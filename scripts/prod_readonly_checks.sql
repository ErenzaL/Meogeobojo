-- READ-ONLY production verification for the publishing release. Paste the whole file into the Supabase
-- SQL editor and run it once. It only SELECTs from catalogs and counts rows; the only object it creates is a
-- session-local TEMP table that disappears when the session ends. It changes no data and no schema.
--
-- Result: one row per check, with status PASS / FAIL / INFO.
--   FAIL  = fix before releasing (the 'hint' column says how)
--   INFO  = informational (for example things that only exist after migration 20261116000100)
-- Run it again after the release and compare the 'baseline' rows: they must not drop.

create temp table _chk (n serial, section text, item text, expected text, actual text, status text, hint text) on commit preserve rows;

do $$
declare
  r record; t text; v text; n bigint; ok boolean; exp text; act text;
  tables_pub constant text[] := array['content_drafts', 'content_versions', 'publication_jobs'];
  fns_api constant text[] := array['cms_state', 'cms_save_draft', 'cms_discard_draft', 'cms_rebase_draft', 'cms_publish', 'cms_schedule', 'cms_reschedule',
                                   'cms_cancel_job', 'cms_retry_job', 'cms_unpublish', 'cms_rollback', 'cms_set_visibility', 'cms_overview',
                                   'admin_save_mission', 'admin_save_campaign', 'admin_set_mission_status', 'admin_set_campaign_publish'];
  fns_internal constant text[] := array['cms_run_due_jobs', '_cms_commit', '_cms_apply', '_cms_snapshot', '_cms_validate', '_cms_unpublished', '_cms_keys', '_mission_save', '_campaign_save'];
  guards constant text[] := array['restaurant_overrides_guard_live', 'cafeteria_meals_guard_live', 'restaurant_menus_guard_live', 'restaurant_photos_guard_live', 'app_content_guard_live', 'universities_guard_live'];
  types constant text[] := array['restaurant', 'cafeteria_meal', 'restaurant_menus', 'restaurant_photos', 'mission', 'campaign', 'app_content', 'university'];
  live_pub constant text[] := array['restaurant_overrides', 'restaurant_menus', 'restaurant_photos', 'cafeteria_meals', 'campus_cafeterias', 'missions', 'monthly_campaigns', 'app_content'];
  jid bigint; cnt_ok int; cnt_bad int; last_run timestamptz;
  procedure_exists boolean;
begin
  -- 1. migration history (informational: a migration run by pasting SQL is not recorded here)
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    for r in select v2 from unnest(array['20261112000100', '20261113000100', '20261114000100', '20261115000100', '20261116000100']) v2 loop
      execute 'select exists (select 1 from supabase_migrations.schema_migrations where version = $1)' into ok using r.v2;
      insert into _chk (section, item, expected, actual, status, hint) values ('1 migration history', 'recorded: ' || r.v2, 'recorded or applied by hand', case when ok then 'recorded' else 'not recorded' end, 'INFO', 'Not recording is normal when the SQL was pasted into the editor. Rely on the object checks below.');
    end loop;
  else
    insert into _chk (section, item, expected, actual, status) values ('1 migration history', 'supabase_migrations.schema_migrations', 'n/a', 'table not present', 'INFO');
  end if;

  -- 2. columns the migrations add
  for r in select * from (values ('campus_cafeterias', 'status', '20261113000100'), ('campus_cafeterias', 'operating_note', '20261113000100'), ('universities', 'is_active', '20261109000100'),
                                 ('universities', 'search_radius_m', '20261109000100'), ('restaurant_menus', 'status', '20261111000100'), ('cafeteria_meals', 'extra', '20261110000100')) x(tb, col, mig) loop
    select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = r.tb and column_name = r.col) into ok;
    insert into _chk (section, item, expected, actual, status, hint) values ('2 schema', r.tb || '.' || r.col, 'present', case when ok then 'present' else 'MISSING' end, case when ok then 'PASS' else 'FAIL' end, 'apply migration ' || r.mig);
  end loop;

  -- 3. publishing tables: exist, RLS on, entity_type check accepts every content type
  foreach t in array tables_pub loop
    select c.relrowsecurity into ok from pg_class c where c.oid = to_regclass('public.' || t);
    insert into _chk (section, item, expected, actual, status, hint) values ('3 publishing tables', t || ' exists with RLS on', 'yes', case when ok is null then 'MISSING' when ok then 'yes' else 'RLS OFF' end, case when ok then 'PASS' else 'FAIL' end, 'apply 20261115000100');
    if to_regclass('public.' || t) is not null then
      select string_agg(pg_get_constraintdef(oid), ' ') into v from pg_constraint where conrelid = ('public.' || t)::regclass and contype = 'c' and pg_get_constraintdef(oid) ~ '^CHECK \(\(entity_type = ';
      select string_agg(x, ', ') into act from unnest(types) x where coalesce(v, '') not like '%''' || x || '''%';
      insert into _chk (section, item, expected, actual, status, hint) values ('3 publishing tables', t || ': entity_type check accepts all 8 types', 'all 8', coalesce('missing: ' || act, 'all 8'), case when act is null then 'PASS' else 'FAIL' end,
        'migration 20261116000100 widens an older, shorter check (safe to apply)');
    end if;
  end loop;

  -- 4. functions: exist, SECURITY DEFINER, and the right callers
  foreach t in array fns_api loop
    select p.oid into jid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = t limit 1;
    if jid is null then
      insert into _chk (section, item, expected, actual, status, hint) values ('4 functions', t, 'exists', 'MISSING', 'FAIL', 'apply 20261115000100 (or earlier mission/campaign migrations)');
    else
      select prosecdef and has_function_privilege('authenticated', jid, 'execute') and not has_function_privilege('anon', jid, 'execute') into ok from pg_proc where oid = jid;
      insert into _chk (section, item, expected, actual, status, hint) values ('4 functions', t || ' (security definer; signed-in yes, anonymous no)', 'yes', case when ok then 'yes' else 'WRONG' end, case when ok then 'PASS' else 'FAIL' end, 'GRANT/REVOKE or security definer is off');
    end if;
  end loop;
  foreach t in array fns_internal loop
    select p.oid into jid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = t limit 1;
    if jid is null then
      insert into _chk (section, item, expected, actual, status, hint) values ('4 functions', t || ' (internal)', 'exists', 'MISSING', 'FAIL', 'apply 20261115000100');
    else
      ok := not has_function_privilege('authenticated', jid, 'execute') and not has_function_privilege('anon', jid, 'execute');
      insert into _chk (section, item, expected, actual, status, hint) values ('4 functions', t || ' (internal: not callable from the API)', 'not callable', case when ok then 'not callable' else 'CALLABLE BY API ROLES' end, case when ok then 'PASS' else 'FAIL' end, 'revoke execute from anon, authenticated');
    end if;
  end loop;
  select exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'cms_health') into ok;
  insert into _chk (section, item, expected, actual, status, hint) values ('4 functions', 'cms_health (migration 20261116000100)', 'absent before the release, present after', case when ok then 'present' else 'absent' end, 'INFO', 'Apply 20261116000100 in step 3 of the release.');

  -- 5. guards that keep live content changing only by publishing
  foreach t in array guards loop
    select tgenabled into v from pg_trigger where tgname = t and not tgisinternal limit 1;
    insert into _chk (section, item, expected, actual, status, hint) values ('5 guards', t, 'enabled', coalesce(case v when 'O' then 'enabled' when 'D' then 'DISABLED' else v end, 'MISSING'), case when v = 'O' then 'PASS' else 'FAIL' end, 'apply 20261115000100; a disabled guard lets old Admin builds write live content');
  end loop;
  select exists (select 1 from pg_trigger where tgname = 'content_versions_no_update' and tgenabled = 'O') into ok;
  insert into _chk (section, item, expected, actual, status, hint) values ('5 guards', 'content_versions are immutable (trigger)', 'enabled', case when ok then 'enabled' else 'MISSING/DISABLED' end, case when ok then 'PASS' else 'FAIL' end, 'apply 20261115000100');
  select exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'publication_jobs_one_scheduled') into ok;
  insert into _chk (section, item, expected, actual, status, hint) values ('5 guards', 'one scheduled publish per item (unique index)', 'present', case when ok then 'present' else 'MISSING' end, case when ok then 'PASS' else 'FAIL' end, 'apply 20261115000100');

  -- 6. scheduler
  select exists (select 1 from pg_extension where extname = 'pg_cron') into ok;
  insert into _chk (section, item, expected, actual, status, hint) values ('6 scheduler', 'pg_cron extension installed', 'yes', case when ok then 'yes' else 'NO' end, case when ok then 'PASS' else 'FAIL' end, 'Dashboard > Database > Extensions > enable pg_cron');
  if ok and to_regclass('cron.job') is not null then
    execute 'select jobid, schedule, active, command from cron.job where jobname = $1' into jid, v, ok, act using 'cms-run-due-jobs';
    insert into _chk (section, item, expected, actual, status, hint) values ('6 scheduler', 'job cms-run-due-jobs registered and active', 'every minute, active', coalesce(v || ', active=' || ok::text, 'NOT REGISTERED'),
      case when jid is not null and v = '* * * * *' and ok then 'PASS' else 'FAIL' end,
      $h$select cron.schedule('cms-run-due-jobs', '* * * * *', 'select public.cms_run_due_jobs()');$h$);
    if jid is not null then
      insert into _chk (section, item, expected, actual, status) values ('6 scheduler', 'job command', 'select public.cms_run_due_jobs()', act, case when act ilike '%cms_run_due_jobs%' then 'PASS' else 'FAIL' end);
      if to_regclass('cron.job_run_details') is not null then
        execute 'select count(*) filter (where status = ''succeeded''), count(*) filter (where status = ''failed''), max(start_time) from (select * from cron.job_run_details where jobid = $1 order by start_time desc limit 10) q' into cnt_ok, cnt_bad, last_run using jid;
        insert into _chk (section, item, expected, actual, status, hint) values ('6 scheduler', 'last 10 runs', 'recent, no failures', cnt_ok || ' succeeded, ' || cnt_bad || ' failed, last ' || coalesce(last_run::text, 'never'),
          case when last_run is not null and last_run > now() - interval '5 minutes' and cnt_bad = 0 then 'PASS' else 'FAIL' end, 'no recent run = the scheduler is not firing; see cron.job_run_details.return_message');
      end if;
    end if;
  elsif to_regclass('cron.job') is null then
    insert into _chk (section, item, expected, actual, status, hint) values ('6 scheduler', 'cron.job table', 'present', 'absent', 'FAIL', 'enable pg_cron');
  end if;
  if to_regclass('public.publication_jobs') is not null then
    select count(*) into n from public.publication_jobs where status = 'scheduled' and run_at < now() - interval '3 minutes';
    insert into _chk (section, item, expected, actual, status, hint) values ('6 scheduler', 'overdue scheduled jobs', '0', n::text, case when n = 0 then 'PASS' else 'FAIL' end, 'the scheduler is stalled');
    select count(*) into n from public.publication_jobs where status = 'failed';
    insert into _chk (section, item, expected, actual, status) values ('6 scheduler', 'failed jobs', '0 (or known)', n::text, case when n = 0 then 'PASS' else 'INFO' end);
  end if;

  -- 7. live-update channel the app listens on
  foreach t in array live_pub loop
    select exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) into ok;
    insert into _chk (section, item, expected, actual, status, hint) values ('7 live updates', 'realtime: ' || t, 'on the channel', case when ok then 'yes' else 'NO' end, case when ok then 'PASS' else 'FAIL' end, 'apply 20261112000100');
  end loop;
  select exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'universities') into ok;
  insert into _chk (section, item, expected, actual, status, hint) values ('7 live updates', 'realtime: universities', 'added by 20261116000100', case when ok then 'yes' else 'not yet' end, 'INFO', 'The app still refreshes campuses on resume and pull-to-refresh.');

  -- 7b. the live-update signal (20261117000100): Realtime cannot announce a take-down, this log does
  select exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'content_sync') into ok;
  select count(*) into n from pg_trigger where tgname = 'content_sync_bump' and not tgisinternal;
  insert into _chk (section, item, expected, actual, status, hint) values ('7 live updates', 'content_sync signal (migration 20261117000100)', '9 triggers + on the channel after the migration',
    n || ' triggers, ' || case when ok then 'on the channel' else 'not on the channel' end, case when n = 9 and ok then 'PASS' else 'INFO' end,
    'Without it a running app learns about a take-down only on resume, on its 60 s refresh or on pull-to-refresh.');

  -- 7c. weekly cafeterias (20261118000100)
  select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'campus_cafeterias' and column_name = 'meal_periods') into ok;
  insert into _chk (section, item, expected, actual, status, hint) values ('7 live updates', 'weekly cafeteria columns (migration 20261118000100)', 'present after the migration', case when ok then 'present' else 'absent' end, 'INFO', 'Apply 20261118000100 to use weekly editing, selected-day publishing and the CSV import.');

  -- 8. storage
  if to_regclass('storage.objects') is not null then
    select exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'restaurant-images: public read') into ok;
    insert into _chk (section, item, expected, actual, status, hint) values ('8 storage', 'public LIST policy on restaurant-images removed', 'absent', case when ok then 'PRESENT' else 'absent' end, case when ok then 'FAIL' else 'PASS' end, 'apply 20261115000100 (unpublished files must not be listable)');
    select exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'restaurant-images: admin read') into ok;
    insert into _chk (section, item, expected, actual, status, hint) values ('8 storage', 'admin-only read policy on restaurant-images', 'present', case when ok then 'present' else 'MISSING' end, case when ok then 'PASS' else 'FAIL' end, 'apply 20261115000100');
    for r in select id, public from storage.buckets where id in ('restaurant-images', 'contribution-photos') loop
      insert into _chk (section, item, expected, actual, status, hint) values ('8 storage', 'bucket ' || r.id || ' public flag', case r.id when 'restaurant-images' then 'public (files are served by URL)' else 'private' end, case when r.public then 'public' else 'private' end,
        case when (r.id = 'restaurant-images') = r.public then 'PASS' else 'FAIL' end, 'fix the bucket visibility');
    end loop;
  end if;

  -- 9. who can publish
  select count(*) into n from public.admin_roles where role in ('admin', 'super_admin');
  insert into _chk (section, item, expected, actual, status, hint) values ('9 access', 'admins who can publish', '>= 1', n::text, case when n >= 1 then 'PASS' else 'FAIL' end, 'grant an admin role');

  -- 10. BASELINE row counts: run again after the release; nothing here may go down
  for r in select x from unnest(array['restaurant_overrides', 'restaurant_menus', 'restaurant_photos', 'restaurant_university_links', 'universities', 'campus_cafeterias', 'cafeteria_meals', 'app_content',
                                      'monthly_campaigns', 'missions', 'user_mission_progress', 'point_transactions', 'user_badges', 'activity_events', 'user_contributions', 'student_reviews', 'food_records',
                                      'favorites', 'profiles', 'user_preferences', 'content_versions', 'content_drafts', 'publication_jobs', 'audit_log']) x loop
    if to_regclass('public.' || r.x) is not null then
      execute format('select count(*) from public.%I', r.x) into n;
      insert into _chk (section, item, expected, actual, status) values ('10 baseline counts', r.x, 'unchanged by the release', n::text, 'INFO');
    end if;
  end loop;
  select count(*) into n from auth.users;
  insert into _chk (section, item, expected, actual, status) values ('10 baseline counts', 'auth.users', 'unchanged by the release', n::text, 'INFO');
  for r in select 'restaurant_overrides by visibility' lbl, visibility k, count(*) c from public.restaurant_overrides group by visibility
           union all select 'restaurant_menus by status', status, count(*) from public.restaurant_menus group by status
           union all select 'restaurant_photos by status', status, count(*) from public.restaurant_photos group by status
           union all select 'missions by status', status, count(*) from public.missions group by status loop
    insert into _chk (section, item, expected, actual, status) values ('10 baseline counts', r.lbl || ': ' || r.k, 'unchanged by the release', r.c::text, 'INFO');
  end loop;
  select coalesce(sum(points), 0) into n from public.point_transactions;
  insert into _chk (section, item, expected, actual, status) values ('10 baseline counts', 'sum of all points (ledger)', 'unchanged by the release', n::text, 'INFO');
end $$;

select n, section, item, expected, actual, status, hint from _chk order by n;
