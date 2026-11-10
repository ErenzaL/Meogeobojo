# Controlled publishing (draft → preview → publish / schedule → live)

Status: **foundation + restaurants + cafeteria meals (학식) built and tested locally; not applied to production.**
Other sections are listed under "Rollout" and still publish immediately.

Entity types so far: `restaurant`, `cafeteria_meal` (one meal = one date × meal × corner) and
`restaurant_menus` (a restaurant's whole menu list; entity id = the restaurant id) and
`restaurant_photos` (its cover + gallery, published together).
The engine is generic (`_cms_keys / _cms_snapshot / _cms_validate / _cms_apply /
_cms_unpublished`); a new type is one more branch plus its admin form.

### Cafeteria meals (학식)
* A new meal is inserted as a **draft row** (`status = 'draft'`, invisible to students; the
  guard refuses any API insert/update that would make a live meal visible or change one).
  It is then edited in the editor (`초안 저장`, `미리보기`, `지금 게시`, `예약 게시`,
  `예약 취소`, `게시 중단`, `게시 이력` with restore).
* Quick actions on the card (`바로 공개` / `비공개로`) call `cms_set_visibility`
  (versioned + audited, reason required). Only a draft meal can be deleted.
* The photo is part of the draft snapshot (`extra.photo_url/path`). Saving or replacing a
  photo never deletes the published file (a rollback needs it). **Limitation:** the file is
  uploaded to the public bucket, so its URL is reachable if guessed even while unpublished
  (see Rollout 2: a private staging bucket).
* Verified-source rules are kept (천원의 아침밥 needs an official source and breakfast).
* Flutter keeps reading only `cafeteria_meals.status = 'published'` of active cafeterias.

### Menus and prices (`restaurant_menus`)
* The menu list of one restaurant is ONE publishable set: the snapshot is `{items: [...]}` with
  every line (id, name, price, category, price-verified date, flags, status, order, photo).
  Price and menu changes therefore go live together, atomically, and roll back together.
* `restaurant_menus` rows are the live rows the app already reads (by `kakao_place_id`, archived
  lines are filtered out by Flutter). A trigger refuses any API insert/update/delete of them;
  only `cms_publish` / the scheduler / rollback write them.
* A line missing from a published set is **archived, never deleted**; rollback restores it.
  "게시 중단" archives every line (nothing is deleted). Unknown prices stay `null`, never 0.
* Photos are staged in the draft; a published photo file is never deleted (same public-bucket
  limitation as meals).

### Photos (`restaurant_photos`)
* Cover + gallery of one restaurant are one set. Uploading a file only adds it to the draft;
  `restaurant_photos` rows are live rows (RLS shows students only `published` ones of
  published restaurants), written only by publishing. The cover mirror into
  `restaurant_overrides.image_url` (existing trigger) follows the publish; at most one live cover.
* A photo left out of a published set is **archived** (row and file kept); rollback restores it.
  Files are never deleted by publishing or by the admin UI, except an upload no draft references yet.
* Hidden (`archived`) rows are staging rows and may still be written through the API: an approved
  student photo from 기여 검토 is staged hidden, then published from 사진 관리.
* **Unpublished files are not discoverable**: the migration replaces the public LIST policy on the
  `restaurant-images` bucket with an admin-only one. Files are still served by their random URL
  (the bucket stays public, which the app needs), so a file that is in no published row is
  reachable only by someone who already has its 122-bit random URL. A private staging bucket
  would remove even that, but cannot be copied to public by a scheduled SQL job.

### Admin database compatibility (`campus_cafeterias.status` does not exist)
**Root cause:** the Admin expects `campus_cafeterias.status` / `operating_note`, added by
migration `20261113000100_cafeteria_management.sql`, which is **not applied in production**
(`scripts/verify_production.py` reports it PENDING). The fix is that migration (additive;
existing cafeterias become `active`, nothing is deleted or rewritten). Until it is applied
the Admin 학식 page does not crash: on that exact error it re-reads the list without those
columns, treats every cafeteria as active, hides the status controls and shows a banner
naming the missing migration. Applying the migration removes the banner without a redeploy.

## 1. Audit: which Admin pages write public data directly (before this work)

| Page | Writes to | Live immediately? | Existing draft/publish rule | Flutter reads |
|---|---|---|---|---|
| 식당 (edit) | `restaurant_overrides` (+ campus links) | yes | `visibility` draft/published/hidden/archived (a *state*, not a staging area) | `restaurant_override_repository`, merged repo |
| 식당 (list hide/publish) | `restaurant_overrides.visibility` | yes | same | same |
| 카카오 식당 불러오기 | `admin_register_kakao_places` → new **draft** rows | no (drafts) | draft rows hidden by RLS | n/a |
| 메뉴·가격 | `restaurant_menus` | yes (active/archived flag) | `status` active/archived | `menus()` |
| 사진 관리 | `restaurant_photos` + public bucket | yes (`status`) | published/archived | `photos()`, cover mirror |
| 학식 | `campus_cafeterias`, `cafeteria_meals` | yes | cafeteria active/inactive/archived; meal draft/published (RLS hides drafts) | `campus_meal_repository` |
| 미션 관리 | RPCs → `missions`, `monthly_campaigns` | yes | mission status; campaign draft/published | `sync_my_missions` |
| 앱 콘텐츠 | `app_content` | yes (`active` + start/end window) | active flag, optional window | `appContentProvider` |
| 대학교 | `universities` | yes | `is_active` | `universityListProvider` |
| 추천 | read-only stats | n/a | n/a | n/a |

Findings: only meals, cafeterias, campaigns and app content have any staging notion
(and it is a status flag on the live row, with no history, no scheduling and no
conflict detection); restaurants, menus, photos, universities were edited live.

## 2. Architecture (no second source of truth)

```
 Admin form ──cms_save_draft──▶ content_drafts      (one per entity, admins only)
                                   │  Preview = this saved draft vs live (diff)
        ┌──────────────────────────┤
        │ cms_publish (now)        │ cms_schedule (frozen snapshot, one per entity)
        ▼                          ▼
   _cms_commit  ◀── cms_run_due_jobs ◀── pg_cron, every minute, inside the database
        │  validate → apply to the LIVE row → append content_versions
        ▼
 restaurant_overrides  (the live row the app already reads; unchanged schema)
```

* **Live** = the existing row. Students read it exactly as before: **no Flutter
  change was needed** (a test pins that the app never reads the publishing tables).
* **Draft** (`content_drafts`): separate, `revision` bumped on every save, remembers
  the live `base_version` it started from. Invisible to students (admin-only RLS).
* **Versions** (`content_versions`): immutable (a trigger refuses update/delete, even
  for the superuser). Version N holds exactly what became live. Rollback = publish an
  old snapshot as a **new** version (`kind = rollback`, `rolled_back_from`).
* **Jobs** (`publication_jobs`): a scheduled publish holds a **frozen snapshot**; later
  edits to the draft never change it. An optional end time creates a linked
  *unpublish* job. One scheduled publish per entity (partial unique index).
* **Atomic**: validate → apply → record version in one transaction; any error leaves
  live untouched. Scheduler errors are caught per job (sub-transaction) and recorded
  (`failed`, `last_error`, audit `cms_job_failed`).
* **Guard**: a trigger on `restaurant_overrides` refuses API edits of live content
  (and inserts that are not drafts); only the publishing functions (and the SQL editor
  / service role) can change it. Photos still mirror `image_url`, Kakao registration
  still adds draft rows.
* **Concurrency**: saving with a stale `revision`, publishing/scheduling when live moved
  since the draft started, discarding someone else's newer draft → SQLSTATE 40001, shown
  as a conflict with a choice (load latest / overwrite knowingly / rebase). Nothing is
  silently overwritten. A scheduled job whose live version changed refuses to run.
* **Permissions**: every `cms_*` function checks the **admin** role in the database;
  moderators, students and anon are refused. At run time the scheduler re-checks that
  the person who scheduled it still has the admin role, and re-validates the snapshot.
* **Non-destructive**: "게시 중단" = new version with `visibility = hidden`; nothing is
  deleted (not the row, the links, the menus, the photos, the favorites or reviews).
* **Times**: the UI uses Asia/Seoul (UTC+9, no DST) and sends UTC; the database stores UTC.

### What the toolbar shows (restaurant page)
Live status + version, pending changes ("게시되지 않은 변경 N건"), last saved (when/who),
last published (when/who/kind), scheduled time (and end), conflicts, failed jobs;
buttons: 초안 저장, 미리보기, 지금 게시, 예약 게시, 예약 취소, 게시 중단,
게시 이력 (versions with 이 버전으로 복원; jobs with 시간 변경 / 다시 시도 / 취소).
The restaurant list has a 게시 column and a filter: 초안 / 예약됨 / 게시됨 / 보관·숨김 / 실패.

## 3. Migration `20261115000100_cms_publishing.sql` (not applied)

Additive and idempotent. New: `content_drafts`, `content_versions`, `publication_jobs`,
the `cms_*` functions, the guard trigger, and a `pg_cron` job `cms-run-due-jobs`
(every minute) when the extension is available.

**Before it is applied** the old Admin Web still edits live directly; **after** it is
applied that no longer works (by design), so **apply the migration and deploy the new
Admin Web together** (the new Admin needs the migration to open a restaurant).

**pg_cron**: enable it in the Supabase dashboard (Database → Extensions → pg_cron), then
run the migration (or re-run it). If it cannot be enabled, scheduled publications will
not run: `select * from cron.job where jobname = 'cms-run-due-jobs'` must return a row.
The runner `cms_run_due_jobs()` is **not** callable through the API; it needs no browser,
Flutter app or laptop.

## 4. Tests (all local)

* `supabase/tests/cms_publishing_test.sql` (scratch PostgreSQL): A draft never changes
  live · concurrency conflicts · validation · the guard · B publish creates version 1,
  audited · scheduling rules · frozen snapshot · runner not callable via API · C/H runner
  publishes once and is idempotent · automatic end hides without deleting · failure is
  atomic and recorded · retry publishes exactly once · scheduler who lost the role cannot
  publish · a stale scheduled snapshot never overwrites newer live · D cancel/reschedule ·
  F unpublish/rollback are new versions · versions immutable · G moderators, students and
  anon refused.
* Admin (vitest): status panel, publish with a change summary, dirty-form gating, conflicts,
  stale-draft rebase, schedule (Seoul → UTC), validation, cancel, unpublish with reason,
  history + rollback, failed-job surfacing + retry, preview + diff, list filters, the
  versioned visibility change; plus unit tests for KST conversion and the diff.
* Flutter: the app never reads the publishing tables or writes restaurant content.

Mapping to your scenarios: A, B, D, F, G, H are covered by the SQL suite and the admin
tests; C (7 AM KST) is covered as "a due job published by the runner without any client";
the actual wall-clock firing by **pg_cron in production is not verified** until it is enabled.
E (missions) is not implemented yet. The cafeteria meal flow (draft invisible → publish → schedule → cancel → rollback → unpublish, guard, non-admin refusal) is covered by the same SQL suite (`cafeteria_meal` section) and by `CafeteriaPage.test.tsx` / `CafeteriaManagement.test.tsx`.

## 5. Rollout (safe order; not done)

1. ~~Menus + prices~~ done (`restaurant_menus`).
2. ~~Photos~~ done (`restaurant_photos`; unlistable, random URLs; see above).
3. ~~Cafeteria meals~~ done (single meal). A whole week as one publication is still open.
4. **App content** (banners/announcements: schedule start + automatic expiry; the live
   window already exists, this adds drafts and history).
5. **Missions/campaigns**: publish versions without touching progress, points or badges
   (the existing mission versioning already preserves them; draft/schedule goes on top).
6. **Universities / recommendation settings**: only student-facing configuration, separate
   from operational changes.

Each step = one more branch in `_cms_keys / _cms_snapshot / _cms_validate / _cms_apply /
_cms_unpublished` plus its admin form. Account suspension, role changes and fraud
moderation stay immediate, confirmed and audited; they never go through publishing.
