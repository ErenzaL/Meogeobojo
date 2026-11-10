# Publishing: production state, release sequence, rollback

Two different things get "published"; keep them apart.

| | What | Lives in | Reaches students by | Rebuild needed? |
|---|---|---|---|---|
| **Content publication** | restaurants, menus, photos, meals, missions, campaigns, announcements, universities | Supabase (tables + `cms_*` RPCs) | Admin publishes → rows change → the app re-reads (live channel, app resume, pull-to-refresh) | **No** |
| **Code deployment** | the Admin screens, the Flutter app screens | GitHub `main` → Render (`meogeobojo-admin`, `meogeobojo-web`); app stores for mobile | a new build | **Yes** |

## Where production is (checked read-only on 2026-11-10; nothing was changed)

| Part | State | How it was checked |
|---|---|---|
| GitHub `origin/main` | `21affc9` | `git fetch` |
| Render Admin | serves `main` @ `21affc9` (bundle `index-C0qWIz6m.js`: page toolbars for 학식, 메뉴, 사진, 미션, 캠페인, 앱 콘텐츠, 대학교; **no** `/settings` 게시 관리) | live bundle contains those screens and no `cms_health` |
| Supabase `20261113000100`, `20261114000100` | applied | `scripts/verify_production.py` |
| Supabase `20261115000100` | applied, **final edition** (`_campaign_save`, `_mission_save`, `cms_overview(p_type,p_parent)`) | same, signature probes |
| Supabase `20261112000100` (live-update channel) | **effectively applied**: a real Realtime subscription is accepted for all 8 content tables; `universities` is **not** on the channel yet (a nonexistent table is rejected, so the probe discriminates) | Realtime probe |
| Publishing functions | **23 of 24 exist** with the expected signatures; only `cms_health` is missing (it ships in `20261116`) | RPC signature probe (42501 = exists, PGRST202 = missing) |
| Supabase `20261116000100` | **not applied** | `verify_production.py` → PENDING |
| pg_cron job `cms-run-due-jobs`, guards, CHECK constraints, storage policies, role grants | **cannot be seen with the publishable key** (no SQL / dashboard / Render access from here) → run `scripts/prod_readonly_checks.sql` | see step 1 |
| What students can read today | 7 universities (all active, all with coordinates); **0** published restaurants, menus, photos, cafeterias, meals, announcements, reviews | `scripts/prod_snapshot.py` |
| Release candidate | tip of `feature/cms-publishing` = `main` + 3 commits (`b17e36b` settings center / `cms_health` / campus sync, `86072fb` upgrade-path fix + preservation test + preflight, then docs) | `scripts/preflight.sh` |

## Verification-stage findings (read-only, 2026-11-10)

| # | Finding | Impact |
|---|---|---|
| 1 | The release changes **no applied migration**, **no dependency**, **no Render/build config**; only `20261116000100` is new (+ Admin/Flutter source, tests, scripts, docs) | safe to layer over `21affc9` |
| 2 | Flutter Web builds with Render's own recipe (clean checkout, empty `.env`, `--dart-define`): ✓ builds, shipped `.env` is empty | the Render web build will not fail |
| 3 | Admin build (`npm ci && npm run build`) ✓; tests 223, Flutter 647, SQL suite 156 checks | – |
| 4 | Both sites point at the right Supabase project and embed only the publishable key (`sb_publishable_…`); no service-role / secret key / Gemini key in either bundle (`sb_secret_` hits are the Supabase library's own prefix check) | config OK |
| 5 | **Admin response headers differ from `render.yaml`**: the live Admin has no `X-Frame-Options: DENY` / `Referrer-Policy: no-referrer` (the blueprint declares them) – the service was most likely created by hand, so blueprint headers never applied. HTML is also edge-cached for 5 minutes (`s-maxage=300`) | not a release blocker. Add the two headers in Render → meogeobojo-admin → Settings → Headers (your approval); after a deploy a hard refresh may be needed for up to 5 min |
| 6 | `universities` is not on the live-update channel yet | step 3 adds it; until then the app refreshes campuses on resume / pull-to-refresh |
| 7 | All 7 universities are active with coordinates, so the Flutter `is_active` filter changes nothing visible today | – |
| 8 | Students currently see no published restaurants/menus/photos/meals/announcements (anon fingerprint). Whether unpublished rows exist (drafts) is shown by the SQL baseline | nothing to lose on the student side; the baseline covers admin-only rows |
| 9 | Migration **history cannot be reconciled** from outside: `supabase_migrations.schema_migrations` is not readable with the publishable key, and `20261115000100` was edited several times in the repo before/while being applied. The object probes show the **final** edition's functions are present; its tables/constraints/policies are checked by the SQL script, and `20261116000100` repairs the one known gap (shorter `entity_type` CHECK) | run the SQL script; report FAIL rows |
| 10 | Items I could **not** verify: pg_cron job, guards, grants, constraints, storage policies (SQL access needed); Render env var names/values and auto-deploy settings, Kakao JS key, Auth redirect URLs (dashboard access needed) | covered by the SQL script and the ◻ list below |

## What each migration does (all additive and idempotent; none drops or rewrites content)

| Migration | Effect | Verified locally by |
|---|---|---|
| `20261112000100_realtime_content` | adds the content tables to the `supabase_realtime` publication (app updates without refresh) | applied twice; publication assertion |
| `20261113000100_cafeteria_management` | `campus_cafeterias.status`/`operating_note`, per-university unique name, public read of active cafeterias only; existing rows become `active` | cafeteria suite; **preservation test** |
| `20261114000100_student_contributions` | private contribution-photo bucket, own-pending delete, one open report | contributions tests |
| `20261115000100_cms_publishing` | publishing tables/RPCs, guards on live content, pg_cron job; replaces the public LIST policy on `restaurant-images` with admin-only (files still served by URL) | 100+ CMS checks; preservation test |
| `20261117000100_content_sync_signal` | an append-only log `content_sync` (table name + time, no content) that every synced table's statement-level trigger writes to; readable by students, writable by nobody; on the realtime channel. **Makes take-downs reach running apps immediately** (see below) | content_sync suite (9 checks); preservation test |
| `20261116000100_cms_health` | read-only `cms_health()`, adds `universities` to the live-update channel, **widens an older `entity_type` CHECK** on the publishing tables | health tests; **upgrade-path test** (older shorter constraint → widened) |

Proven on a scratch PostgreSQL by `scripts/preflight.sh` → "sql suite": migrations applied fresh and twice; existing restaurants, menus, photos,
announcements, cafeteria data, campaigns, missions, **user progress** and universities are byte-for-byte unchanged by `20261112..20261116`;
what students (anon) can read is identical before and after; a second pass on populated data changes nothing.

## Why a take-down did not reach a running app (announcement bug) and what fixes it

Found when an announcement taken down in Admin stayed on the Flutter home screen until a full restart. Two independent causes:

1. **App bug (fixed in the Flutter code):** Realtime events reached the shell as the bare table name through a Riverpod
   `StreamProvider<String>`. Riverpod drops a state equal to the previous one, so after the first `app_content` event every later one
   (the unpublish after the publish) never reached the listener (verified: 3 identical events → 1 listener call).
   Events are now distinct objects. The announcement list is also handled correctly: a confirmed empty answer clears the banner, a
   failed read keeps the last answer.
2. **Database/Realtime behaviour (fixed by `20261117000100`):** Realtime only delivers a change the subscriber could read under RLS. Switching an
   announcement off is an UPDATE after which students can no longer read the row, so Realtime says nothing
   ([Supabase: Postgres Changes troubleshooting](https://supabase.com/docs/guides/troubleshooting/realtime-postgres-changes-troubleshooting)).
   The same applies to hiding a restaurant, archiving a photo, pausing a mission, unpublishing a meal. `content_sync` is announced
   instead because its rows are always readable.

Layers, so that nothing depends on a single mechanism: live table events → the `content_sync` signal (needs `20261117`) →
re-read on app resume / campus switch / return to Home → a 60-second foreground refresh of the cheap live content → pull-to-refresh on Home.
Without `20261117` an unpublish reaches a running app within 60 seconds (or sooner on resume / pull-to-refresh); with it, within about a second.
Realtime channels are one per source (a missing publication entry for one table can no longer take all live updates down), re-subscribe with
back-off, announce a full re-read after a reconnect, and are disposed with the app shell.

## Backward compatibility (production DB ⇄ code that is deployed or about to be)

| Combination | Result |
|---|---|
| Admin `21affc9` (deployed) + DB through `20261115` | works (every write goes through publishing) |
| Admin `21affc9` + `20261116` applied | works (only adds functions, a publication entry, a CHECK that accepts more) |
| New Admin (release candidate) + DB **without** `20261116` | works; `/settings` shows a clear "apply 20261116000100" notice with raw counts, publishing itself is unaffected |
| Any Admin **older than `21affc9`** + DB `20261115` | **breaks**: direct edits of menus, photos, missions, campaigns, content, universities, meals are refused by the guards (only restaurants work) |
| Old Flutter builds + new DB | works (the app only reads; guards affect writes; archived menus are filtered in the app as before) |
| New Flutter (release candidate) + DB without `is_active` | falls back to the bundled campus list (column exists in production) |

Therefore: **never roll the Admin back below `21affc9`** without the emergency step in "Rollback".

## Release sequence (each numbered step needs your approval; nothing below has been run)

**0. Preflight** (local, read-only): `scripts/preflight.sh` → must end `PREFLIGHT PASSED`.

**1. Read-only checks in the Supabase SQL editor** (no changes; the file only SELECTs and makes one session-local TEMP table)

Paste the whole of `scripts/prod_readonly_checks.sql` into the SQL editor and run it once. It returns one row per check with PASS / FAIL / INFO:
migration history, columns, the three publishing tables (RLS, entity types), 17 API + 9 internal functions (security definer, who may call them),
the 6 live-content guards, immutability and one-scheduled-job index, **pg_cron + `cms-run-due-jobs` + its last 10 runs + overdue/failed jobs**,
the live-update channel, storage policies and buckets, admin roles, and a **baseline of row counts** (restaurants by visibility, menus, photos, meals,
missions by status, user progress, points ledger, reviews, profiles, `auth.users`, …).

Expected before the release: everything PASS except `cms_health` (INFO: absent), `universities` on the channel (INFO: not yet) and possibly the entity_type
check rows (FAIL → the widening in step 3 fixes them; harmless to the release). **Any other FAIL: stop and send me the rows.**
Keep the result; after the release run it again and compare section "10 baseline counts": nothing may go down.

If the `cms-run-due-jobs` row fails: Dashboard → Database → Extensions → enable `pg_cron`, then
`select cron.schedule('cms-run-due-jobs', '* * * * *', 'select public.cms_run_due_jobs()');` (this only registers the schedule).
If a live-update row fails: run `supabase/migrations/20261112000100_realtime_content.sql` (idempotent).

Also take the **student-visible fingerprint** now (publishable key only, read-only) and compare it after the release:
```bash
python3 scripts/prod_snapshot.py --save before.json      # now
python3 scripts/prod_snapshot.py --compare before.json   # after step 4: must print "identical"
```

**2. Merge the release commits into `main`** (this redeploys BOTH Render sites: Admin and Flutter Web)
```bash
git push origin feature/cms-publishing                 # a branch only; open a PR "feature/cms-publishing -> main" and review it
# after you approve, merge the PR on GitHub (fast-forward). Or locally:
git checkout main && git merge --ff-only feature/cms-publishing && git push origin main
```
Render builds `main`; watch both deploys finish. The Admin works before step 3 (fallback notice on `/settings`).

**3. Apply `supabase/migrations/20261116000100_cms_health.sql`** in the SQL editor (paste the file, run once; running it again is harmless).

**4. Verify** (read-only):
```bash
python3 scripts/verify_production.py            # expect 48/48 and every migration line "OK" including 20261116000100
python3 scripts/prod_snapshot.py --compare before.json   # expect: identical (no student-visible content changed)
```
Re-run `scripts/prod_readonly_checks.sql`: all PASS, `cms_health` present, `universities` on the channel, baseline counts not lower.
Then open `https://meogeobojo-admin.onrender.com/settings` as an admin and check 게시 관리:
- "지금 열려 있는 관리자 코드" = the commit Render shows for the Admin deploy (the release tip).
- 동기화 상태 shows 정상 (or tells you exactly what to fix: scheduler, live-update tables, guards).

**5. Prove it end to end against production** (writes one throw-away "[E2E]" announcement for seconds, then deletes it; needs an admin login):
```bash
ADMIN_EMAIL=… ADMIN_PASSWORD=… python3 scripts/verify_publish_e2e.py --yes-i-approve-production-write --with-schedule
```
It checks: draft invisible to the app's read endpoint → publish makes it appear (no rebuild) → pg_cron publishes a scheduled item with no browser open
→ unpublish hides it → cleanup. Then open the Flutter Web app (and the mobile app) once, pull to refresh.

**6. Mobile**: ship the next app build to get the campus change (hidden campuses disappear; published campus edits arrive live).
Published content itself never needs a mobile build.

## Rollback

| What went wrong | Do |
|---|---|
| Bad **content** was published | the page's 게시 이력 → "이 버전으로 복원" (a new version, nothing deleted), or 게시 중단 |
| A scheduled publication is wrong | `/settings` → 게시 관리 → 예약 취소 |
| New **Admin/Flutter code** misbehaves | Render → service → Deploys → previous deploy → Rollback (or `git revert` the release commits and push). Safe down to `21affc9` |
| `20261116` misbehaves | `drop function if exists public.cms_health(); drop function if exists public._cms_label(text, uuid); alter publication supabase_realtime drop table public.universities;` (the widened CHECK is harmless, keep it) |
| You must run an Admin **older than `21affc9`** | first lift the guards (reversible; the old Admin then edits live content directly, without drafts/versions):<br>`alter table public.restaurant_menus disable trigger restaurant_menus_guard_live;` and the same for `restaurant_photos_guard_live`, `app_content_guard_live`, `universities_guard_live`, `cafeteria_meals_guard_live`, `restaurant_overrides_guard_live`; undo with `enable trigger`. (`admin_save_mission` / `admin_save_campaign` also refuse live edits: re-create them from `20261110000100`.) Not recommended. |
| Student data worry | none of these migrations touch user tables; the preservation test compares them before and after |

## Production configuration (✓ read-only verified, ◻ needs a dashboard look)
- ✓ Admin and Flutter Web are served; the Admin bundle holds only the publishable key; no service-role key anywhere in the repo, Flutter, web or Admin source.
- ✓ Edge function `search_restaurants` answers with CORS; storage bucket `restaurant-images` exists; anonymous reads of private tables are refused.
- ◻ Render env for **both** services: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (Admin); `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `KAKAO_JAVASCRIPT_KEY` (Web). Publishable key only.
- ◻ Supabase: `pg_cron` enabled (queries A/B), Realtime enabled for the project, at least one `super_admin`/`admin` in `admin_roles`, Auth site URL / redirect URLs include the Admin and Web domains, Edge function secrets (Kakao REST key) set.

## Known limits
- `universities.search_radius_m` is stored and editable but **the app does not use it** (the Admin field is labelled "reference only"); relabel when the search function reads it.
- Photos are served from a public bucket by random URL; unpublished files cannot be listed but are reachable by someone who has the URL.
- A campaign and its missions are published separately.
