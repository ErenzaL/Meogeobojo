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
| Supabase `20261112000100` (live-update channel) | **unknown** without SQL access | run query C below |
| Supabase `20261116000100` | **not applied** | `verify_production.py` → PENDING |
| pg_cron job `cms-run-due-jobs` | **unknown** without SQL access | run queries A/B below |
| Release candidate | tip of `feature/cms-publishing` = `main` + 3 commits (`b17e36b` settings center / `cms_health` / campus sync, `86072fb` upgrade-path fix + preservation test + preflight, then docs) | `scripts/preflight.sh` |

## What each migration does (all additive and idempotent; none drops or rewrites content)

| Migration | Effect | Verified locally by |
|---|---|---|
| `20261112000100_realtime_content` | adds the content tables to the `supabase_realtime` publication (app updates without refresh) | applied twice; publication assertion |
| `20261113000100_cafeteria_management` | `campus_cafeterias.status`/`operating_note`, per-university unique name, public read of active cafeterias only; existing rows become `active` | cafeteria suite; **preservation test** |
| `20261114000100_student_contributions` | private contribution-photo bucket, own-pending delete, one open report | contributions tests |
| `20261115000100_cms_publishing` | publishing tables/RPCs, guards on live content, pg_cron job; replaces the public LIST policy on `restaurant-images` with admin-only (files still served by URL) | 100+ CMS checks; preservation test |
| `20261116000100_cms_health` | read-only `cms_health()`, adds `universities` to the live-update channel, **widens an older `entity_type` CHECK** on the publishing tables | health tests; **upgrade-path test** (older shorter constraint → widened) |

Proven on a scratch PostgreSQL by `scripts/preflight.sh` → "sql suite": migrations applied fresh and twice; existing restaurants, menus, photos,
announcements, cafeteria data, campaigns, missions, **user progress** and universities are byte-for-byte unchanged by `20261112..20261116`;
what students (anon) can read is identical before and after; a second pass on populated data changes nothing.

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

**1. Read-only checks in the Supabase SQL editor** (no changes):
```sql
-- A. scheduler registered?   expect 1 row, '* * * * *', active = true
select jobid, schedule, active from cron.job where jobname = 'cms-run-due-jobs';
-- B. is it running?          expect recent rows with status 'succeeded'
select status, start_time, left(return_message, 120) from cron.job_run_details
 where jobid = (select jobid from cron.job where jobname = 'cms-run-due-jobs') order by start_time desc limit 10;
-- C. live-update channel     expect restaurant_overrides, restaurant_menus, restaurant_photos, cafeteria_meals, campus_cafeterias,
--                            missions, monthly_campaigns, app_content (universities appears after step 3)
select tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;
-- D. publishing tables       expect one entity_type check per table; the list may be shorter (step 3 widens it)
select conrelid::regclass, pg_get_constraintdef(oid) from pg_constraint
 where conrelid in ('public.content_drafts'::regclass, 'public.content_versions'::regclass, 'public.publication_jobs'::regclass) and pg_get_constraintdef(oid) like '%entity_type%';
-- E. guards present          expect 6 rows
select tgname from pg_trigger where tgname like '%\_guard\_live' and not tgisinternal order by 1;
```
If **A** returns no row: Dashboard → Database → Extensions → enable `pg_cron`, then run
`select cron.schedule('cms-run-due-jobs', '* * * * *', 'select public.cms_run_due_jobs()');`.
If **C** lacks tables: run `supabase/migrations/20261112000100_realtime_content.sql` (idempotent).

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
```
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
