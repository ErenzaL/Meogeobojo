# Publishing: production state and deployment checklist

Two different things get "published"; keep them apart.

| | What | Where it lives | How it reaches students | Needs a rebuild? |
|---|---|---|---|---|
| **Content publication** | restaurants, menus, photos, meals, missions, campaigns, announcements, universities | Supabase (tables + `cms_*` RPCs) | Admin publishes → rows change → the app re-reads (live channel, resume, pull-to-refresh) | **No** |
| **Code deployment** | the Admin screens, the Flutter app screens | GitHub → Render (static sites `meogeobojo-admin`, `meogeobojo-web`), app stores for mobile | a new build is deployed | **Yes** |

The Admin `/settings` page shows the commit of the Admin code that is open, and the publishing status.

## State found on 2026-11-10 (read-only inspection; nothing was changed in production)

* **Render Admin = `main` @ `b5449bd`.** A scratch build of `b5449bd` is byte-identical to the live bundle
  (`index-CS0Gcgy4.js`). That build only has the publishing toolbar on the **식당** page.
* The branch `feature/system-integration` (pushed to origin) contains the rest: toolbars on 학식, 메뉴·가격, 사진 관리,
  미션 관리 (미션 + 캠페인), 앱 콘텐츠, 대학교, and the `/settings` 게시 관리 section. **It is not deployed.**
* **Supabase already has the final `20261115000100`** (probed with the publishable key: `_campaign_save`,
  `_mission_save`, `cms_overview(p_type, p_parent)` exist), plus `20261113000100` and `20261114000100`.
  `20261112000100` (live-update channel) and the pg_cron job cannot be seen without an admin session / SQL access.
* **Consequence while the old Admin is deployed:** the database guards are already active, so the OLD Admin gets a
  "changes only by publishing" error when it edits 메뉴·가격, 사진, 미션, 캠페인, 앱 콘텐츠, 대학교 or 학식 meals,
  and when approving a student photo. Restaurants still work. **Deploy the new Admin to fix this.**

## Checklist (nothing here is done for you; each step needs your approval)

1. **Deploy the Admin code** (this is code, not content)
   - Open a PR `feature/system-integration` → `main` and merge it (or point the Render service at the branch).
   - Render builds `npm ci && npm run build` in `admin/` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (publishable key only).
   - Check: `/settings` → 게시 관리 → "지금 열려 있는 관리자 코드" equals the commit Render shows for the deploy.
2. **Apply `20261116000100_cms_health.sql`** (SQL editor; read-only functions + adds `universities` to the live-update channel).
   - Check: `python3 scripts/verify_production.py` → `OK 20261116000100 …`; `/settings` shows 동기화 상태.
3. **Check the scheduler** (SQL editor, read-only):
   ```sql
   select jobid, schedule, active from cron.job where jobname = 'cms-run-due-jobs';          -- expect 1 row, '* * * * *', active
   select status, start_time, return_message from cron.job_run_details
    where jobid = (select jobid from cron.job where jobname = 'cms-run-due-jobs') order by start_time desc limit 10;  -- expect 'succeeded'
   ```
   If there is no row: enable pg_cron (Dashboard → Database → Extensions), then run `20261115000100_cms_publishing.sql` again (idempotent;
   it only re-registers the job). `/settings` shows the same facts after step 2 and flags overdue jobs.
4. **Check the live-update channel** (read-only):
   ```sql
   select tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;
   ```
   Expect restaurant_overrides, restaurant_menus, restaurant_photos, cafeteria_meals, campus_cafeterias, missions, monthly_campaigns,
   app_content, universities. If some are missing apply `20261112000100` (and step 2 for universities). Without it the app still
   updates on resume and pull-to-refresh.
5. **Flutter code** (this branch also changes the app): hidden campuses are no longer offered and a published campus change reaches a running app.
   - Redeploy Flutter Web (Render `meogeobojo-web`) and ship the next mobile build. Until then a campus the admin hides is still shown in the app.
   - Content published through the Admin needs **no** app rebuild.
6. **End-to-end proof against production** (writes one throw-away "[E2E]" announcement for a few seconds, then deletes it; needs an admin login):
   ```
   ADMIN_EMAIL=… ADMIN_PASSWORD=… python3 scripts/verify_publish_e2e.py --yes-i-approve-production-write --with-schedule
   ```
   Proves: a draft is invisible to the app, publish makes the app's read endpoint return it, the server (pg_cron) publishes a
   scheduled item with no browser open, unpublish hides it. Then open the Flutter app/web once and pull to refresh.
7. **Rollback**: code → redeploy the previous Render deploy; content → 게시 이력 → 이 버전으로 복원 (a new version, nothing deleted);
   migrations are additive (no down-migration needed).

## Known limits
* `universities.search_radius_m` is stored and editable but **the app does not use it** (the search range is decided by the app filters and the deployed `search_restaurants` function). The Admin field says so.
* Photos are served from a public bucket by random URL; unpublished files cannot be listed but are reachable by someone who has the URL.
* A campaign and its missions are published separately.
