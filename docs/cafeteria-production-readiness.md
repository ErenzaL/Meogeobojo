# 학식 weekly cafeteria management: production readiness report

Branch `feature/cafeteria-weekly` / PR #2 (Draft). Written 2026-11-10/11. **Nothing in this document has been run against production
except read-only probes.** Real Admin → Supabase → Flutter Web → Android integration is **not yet verified**.

## 1. Current system status (read-only audit)
| Item | Finding | Evidence |
|---|---|---|
| GitHub | `main` = `c8f2f63`; PR #2 head = the branch (4 commits, fast-forwardable, mergeable, no conflicts) | `git`, GitHub API |
| CI | the repo had **no** workflow; `.github/workflows/ci.yml` is added here (untested on GitHub until its first run) | repo |
| Render Admin / Web | serving `main` @ `c8f2f63`; a push to `main` redeployed **both** sites within ~2 min (observed on the last release) → auto-deploy is ON | live bundle commit, deploy timing |
| Render config files | `render.yaml` (Admin: security headers declared but **not applied** on the live service, see risk R6) | `curl -I` |
| Supabase `20261112…16` | applied (probes: functions, tables, `cms_health`, realtime on all 9 tables) | `verify_production.py`, SQL checks |
| Supabase `20261117000100`, `20261118000100` | **not applied** (PENDING) | `verify_production.py` |
| Production data | 7 universities, **124 restaurants (all draft)**, 12 missions, 0 cafeterias/meals/menus/photos/announcements; unchanged by every step so far | SQL baseline, `prod_snapshot.py --compare` |
| pg_cron | `cms-run-due-jobs` every minute, last 10 runs succeeded | SQL check (rows you sent earlier) |
| Migration history | `schema_migrations` recorded `20261112…15`; `…16` was applied later by SQL editor; **cannot be read with the publishable key** → re-run `prod_readonly_checks.sql` section 1 right before the release | SQL check |
| Android | `release` was signed with the **debug key** and `applicationId = com.example.meogeobojo` (see §6) | `build.gradle.kts` |

## 2. Tests performed (local) and results
| Suite | Result |
|---|---|
| Admin: vitest / `tsc` / eslint / production build | 305 pass, clean |
| Flutter: `dart analyze` / `flutter test` | clean, 712 pass |
| SQL on a scratch PostgreSQL: **every migration** fresh and twice, upgrade path, preservation of live data/progress, weekly + import + signal suites | **195 checks OK**, 0 errors |
| `scripts/staging_apply_migrations.sh` full chain on a fresh DB | 20 files apply cleanly in order |
| Python: weekly E2E script unit tests, Korean CSV importer tests | pass |
| Android `flutter build apk --release` | builds (debug-key fallback) **and** builds signed with a throw-away keystore (verified with `apksigner`); no key file left behind |
| Read-only production probes | 48/48; migrations 17/18 PENDING as expected |

## 3. Migration dependency assessment
```
… 20261115000100 cms_publishing (applied) ── 20261116000100 cms_health (applied)
        │                                          │
        └── 20261117000100 content_sync_signal  (optional: take-downs reach running apps in ~1 s instead of ≤ 60 s)
        └── 20261118000100 cafeteria_weekly      (REQUIRED for weekly editing / selected days / CSV import)
                requires: 20261113000100 (cafeteria management) + 20261115000100 (publishing)
```
* Order: `…17` then `…18` (independent; both only add objects). Both are idempotent; neither alters existing rows or applied migrations.
* `…18` renames the publishing functions to `*_v1` and wraps them: other content types keep their behaviour (all earlier suites pass on top of it).
* **Intermediate states** (each verified by tests; the Admin and the apps degrade with a notice instead of failing):
  | State | Admin (new) | Flutter (new) | Old Admin / old app |
  |---|---|---|---|
  | S1 code merged, DB ≤ `…16` | 학식 page loads; weekly editor and CSV show "apply 20261118000100"; single-week features off | defaults (3 meals, Mon-Fri, no photo) | n/a |
  | S2 migrations applied, old code | n/a | n/a | old Admin's single-meal flow still works (tested); old app ignores the new columns |
  | S3 both | full feature | full feature | – |
  → either order is safe; **recommended: merge first (S1), then migrate (S3)** so the new UI is ready the moment the database is.
* **Gap found and fixed during this audit:** a menu changed outside the weekly editor (older Admin tab, SQL editor, Python importer) after a week draft was saved would have been silently overwritten by publishing that draft. `20261118000100` §3b now records such a change as a new week version → the draft is flagged stale and publishing is refused until it is rebased (tested, including bulk changes and a week never opened in the weekly editor).

## 4. Staging integration
**What was possible here:** a scratch PostgreSQL (the full migration chain, fresh and twice, all SQL suites, the two-university weekly/import scenarios, scheduler runner, RLS and student-visibility checks) and fakes for the Admin and Flutter. **No separate Supabase project exists, and I have no access to create one, so the staging steps that need a real Supabase (Auth, Realtime, pg_cron, Storage, the real Admin and real apps) have NOT been run.** Everything is prepared so you can run them in about an hour:

1. Create a second Supabase project (the Free plan allows two): Dashboard → New project → name `meogeobojo-staging`. Enable the `pg_cron` extension (Database → Extensions).
2. Apply the chain: `STAGING_DATABASE_URL='postgresql://postgres:<pw>@db.<staging-ref>.supabase.co:5432/postgres' scripts/staging_apply_migrations.sh` (it refuses the production ref).
3. Create an admin: Auth → Add user (email + password), then in the staging SQL editor:
   `insert into public.admin_roles (user_id, role) select id, 'admin' from auth.users where email = '<admin email>';`
4. Create a student account the same way (no role). Deploy the two staging services from `render.staging.yaml` (Render → New → Blueprint, pick that file) with the **staging** URL/publishable key as env values.
5. Run the automated end-to-end: `STAGING_SUPABASE_URL=… STAGING_SUPABASE_PUBLISHABLE_KEY=… STAGING_ADMIN_EMAIL=… STAGING_ADMIN_PASSWORD=… python3 scripts/verify_cafeteria_e2e.py --yes-write-to-staging --with-schedule` (add `--manual-check` to pause so you can look at Flutter Web and the Android app).
   It covers: two universities, Mon-Fri × 3 meals as one draft, two lunch options, 천원의 아침밥 on one date, draft invisible, atomic week publish, university separation, selected-day publish, CSV dry-run/draft-only/retry/multi-university confirmation, pg_cron publish with no browser, unpublish (empty answer for students), rollback, cleanup. It reads only `STAGING_*` and refuses the production URL.
6. Isolation guarantee: staging uses its own project, URL, keys and database; the scripts refuse the production ref; production is only ever touched through the steps in §7, each needing your approval.

## 5. Unresolved risks
| # | Risk | Mitigation |
|---|---|---|
| R1 | Real end-to-end (Admin → Supabase → Flutter Web → Android) not verified | §4 staging run + §8 checklist before production |
| R2 | The new CI workflow has never run | first PR run will show; it uses no secrets |
| R3 | Migration history cannot be read from outside | re-run the SQL checks (section 1) immediately before applying |
| R4 | `applicationId` is still `com.example.meogeobojo` and release builds use the debug key unless `key.properties` exists | see §6; changing the id creates a **different** app (no upgrade path for installs), so decide before the first store release |
| R5 | Mobile apps need a new build for the Flutter changes (menus themselves do not) | §6 |
| R6 | Live Admin lacks the `X-Frame-Options` / `Referrer-Policy` headers declared in `render.yaml` | add them in Render → Settings → Headers (your approval) |
| R7 | Old non-idempotent migrations (for example `20261031000300`) cannot be re-run | not needed: they are already applied; use `--from` on staging |
| R8 | `universities.search_radius_m` is stored but unused by the app | labelled "reference only" in Admin |
| R9 | Draft isolation and publishing were verified on scratch Postgres; Realtime/pg_cron/Storage behaviour on the hosted project only via earlier production E2E (announcements) | §4 repeats it for cafeterias on staging |

## 6. Flutter Android release configuration
* `android/app/build.gradle.kts` now signs `release` with `android/key.properties` when present, otherwise with the debug key (unchanged behaviour, **not Play-uploadable**).
* Create the upload key yourself and back it up (loss = you can never update the app): `keytool -genkey -v -keystore ~/meogeobojo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload` (Android Studio's bundled `keytool` works). Copy `android/key.properties.example` → `android/key.properties` and fill it in. Both are git-ignored.
* Build: `flutter build appbundle --release --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_PUBLISHABLE_KEY=… [--dart-define=KAKAO_NATIVE_APP_KEY=…]` (publishable key only). Bump `version:` in `pubspec.yaml` (`1.0.0+1` → `1.0.1+2`; the `+N` build number must increase for every upload).
* Decide the final `applicationId` now (R4). Verify the artifact: `apksigner verify --print-certs app-release.apk` shows YOUR certificate, not "Android Debug".
* iOS is not part of this change (Xcode shows a warning in `flutter doctor`).

## 7. Production deployment (each step needs your explicit approval; **none has been run**)
**0 Pre-checks** (read-only)
```bash
git fetch origin && git log --oneline origin/main..origin/feature/cafeteria-weekly        # the 4 commits
python3 scripts/prod_snapshot.py --save before.json                                        # student-visible fingerprint
python3 scripts/verify_production.py                                                      # 48/48, 17/18 PENDING
```
Supabase SQL editor: paste `scripts/prod_readonly_checks.sql`; keep the result (section 10 = baseline counts; 0 FAIL).
**Backup/snapshot:** Supabase Dashboard → Database → Backups (note the latest backup time; on the Free plan there is no point-in-time recovery, so also run **Database → Backups → download**, or `pg_dump` of `public` (`pg_dump "$PROD_URL" --schema=public --data-only -Fc -f meogeobojo-before-weekly.dump`) before step 2. The migrations are additive, so this is a safety net, not an expected need.
**1 Merge** (redeploys Render Admin + Flutter Web; state S1, safe)
```bash
# on GitHub: mark PR #2 ready for review, review, then "Rebase and merge" or fast-forward locally:
git checkout main && git pull --ff-only && git merge --ff-only origin/feature/cafeteria-weekly && git push origin main
```
Wait until both Render deploys are **Live**; open `/settings` and check "지금 열려 있는 관리자 코드" = the new head.
**2 Migrations** (SQL editor, one file at a time, in this order; each may be re-run)
```
supabase/migrations/20261117000100_content_sync_signal.sql
supabase/migrations/20261118000100_cafeteria_weekly.sql
```
**3 Verify** (read-only)
```bash
python3 scripts/verify_production.py                    # every migration line OK, 48/48
python3 scripts/prod_snapshot.py --compare before.json  # identical (nothing students see changed)
```
Re-run `prod_readonly_checks.sql`: no FAIL, baseline counts not lower, `content_sync` PASS, weekly columns present.
**4 Production E2E** (writes throw-away "[E2E]" data, removes it): follow §8 on production **only after** staging passed; use the Admin UI by hand (the automated script refuses production by design). Delete any leftover "[E2E]" cafeteria.
**5 Mobile**: build and upload the Android bundle (§6), and iOS later; Flutter Web is already live from step 1.

## 8. Final end-to-end verification (Admin → Supabase → Flutter Web → Android)
Automated part (staging): `verify_cafeteria_e2e.py` above. Manual part (staging, then production), with two devices open (Flutter Web in a browser, the Android build) on the **student** account, both showing 학식 for the same university:
1. Admin → 학식 → choose the university → add cafeteria "E2E 학생식당" (starts inactive) → switch it **운영 중**. Students see the cafeteria but no menu ("등록된 식단 정보가 없습니다").
2. Open the weekly editor, fill Mon-Fri × 조식/중식/석식 (a second lunch option on Tuesday, 천원의 아침밥 on Monday breakfast with a source) → **초안 저장** once. **Both apps still show nothing.**
3. 미리보기 shows five days → **지금 게시**. Within ~1 s (or after pull-to-refresh) **both apps show the week with no rebuild or restart**; only Monday breakfast carries the 천원의 아침밥 card; Tuesday lunch lists both options.
4. Change Tuesday lunch + Thursday dinner → 초안 저장 → **선택한 날만 게시** Tuesday → only Tuesday changes in the apps.
5. Switch the app to another university: the cafeteria is not listed. Switch back.
6. Admin → **게시 중단** → both apps clear the menus **without restarting** (an empty answer clears stale data). **이전 버전으로 복원** → they return.
7. 예약 게시 for +2 minutes, close the Admin tab → the week appears by itself (pg_cron).
8. CSV: download the example → 학식 → CSV 일괄 등록 → preview → import → nothing visible in the apps (drafts) → publish. Import again: "변경 없음".
9. Put the Android app in the background for a minute, unpublish in Admin, bring it back: it clears (resume refresh).
10. Disable the cafeteria → it disappears from both apps. Delete the test cafeteria.

## 9. Rollback
| Situation | Action |
|---|---|
| A published week is wrong | Admin → 주간 메뉴 → 게시 이력 → **이 버전으로 복원** (new version, nothing deleted), or **게시 중단**; scheduled → **예약 취소** (also in Settings → 게시 관리) |
| New Admin/Web misbehaves | Render → service → Deploys → previous deploy → **Rollback** (the previous `main` Admin works with the migrated database; never go below `c8f2f63`) |
| `20261118000100` must be undone | The additive objects can stay (unused). To remove them: `drop trigger if exists cafeteria_week_drift_flush on public.cafeteria_week_drift; drop trigger if exists cafeteria_meals_note_drift on public.cafeteria_meals;` then the functions `cms_publish_week_days(uuid,integer,date[],text)`, `cafeteria_import(jsonb,text,boolean,boolean,boolean)`, `cafeteria_week_entity(uuid,date)`; tables `cafeteria_week_drift`, `cafeteria_weeks` (after deleting its `content_*` rows only if you accept losing the week history). **Do not** drop the `*_v1` renames: rename them back instead (`alter function public._cms_snapshot_v1(text,uuid) rename to _cms_snapshot;` … only after dropping the wrappers). Prefer restoring the backup taken in step 0 over hand-editing. |
| `20261117000100` must be undone | `drop trigger content_sync_bump on public.<table>` for the 9 tables; `drop table public.content_sync;` (apps fall back to the 60 s refresh) |
| Data damage (not expected) | restore the step-0 backup; student-visible state can be compared with `prod_snapshot.py --compare before.json` |
