-- Publishing health for the Admin /settings page: what is pending, what is scheduled, what ran,
-- whether the scheduler (pg_cron job `cms-run-due-jobs`) is alive, and whether the app's live
-- update channel and the database guards are in place.
--
-- READ-ONLY and admin-only. Additive and idempotent. Requires 20261115000100 (the publishing tables).
-- It changes no content. Besides these two functions its only effect is to add `universities` to the
-- live-update channel (supabase_realtime), so a published campus change reaches a running app.

do $$ begin
  if to_regclass('public.content_drafts') is null or to_regclass('public.publication_jobs') is null
     or to_regclass('public.content_versions') is null or to_regprocedure('public._cms_admin_check()') is null then
    raise exception 'Apply 20261115000100 first.';
  end if;
end $$;

-- A published campus change (or hiding a campus) should reach a running app: add it to the channel
-- the app already listens on for the other content tables (20261112000100). Idempotent.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and to_regclass('public.universities') is not null
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'universities') then
    alter publication supabase_realtime add table public.universities;
  end if;
end $$;

-- A human label for any publishable entity (internal: not callable from the API).
create or replace function public._cms_label(p_type text, p_id uuid) returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v text;
begin
  if p_type = 'restaurant' then select name_ko into v from public.restaurant_overrides where id = p_id;
  elsif p_type = 'restaurant_menus' then select name_ko || ' · 메뉴·가격' into v from public.restaurant_overrides where id = p_id;
  elsif p_type = 'restaurant_photos' then select name_ko || ' · 사진' into v from public.restaurant_overrides where id = p_id;
  elsif p_type = 'cafeteria_meal' then
    select coalesce(c.name_ko, '학식') || ' · ' || m.meal_date::text || ' ' || m.meal_type || case when m.option_name <> '' then ' (' || m.option_name || ')' else '' end
      into v from public.cafeteria_meals m left join public.campus_cafeterias c on c.id = m.cafeteria_id where m.id = p_id;
  elsif p_type = 'mission' then select title into v from public.missions where lineage_id = p_id order by version desc limit 1;
  elsif p_type = 'campaign' then select title into v from public.monthly_campaigns where id = p_id;
  elsif p_type = 'app_content' then select title into v from public.app_content where id = p_id;
  elsif p_type = 'university' then select name_ko into v from public.universities where id = p_id;
  end if;
  return coalesce(v, '(삭제됨)');
end $$;
revoke all on function public._cms_label(text, uuid) from public, anon, authenticated;

create or replace function public.cms_health() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  cron_info jsonb := jsonb_build_object('available', false, 'job_found', false);
  jobid_ bigint; sched text; act boolean; runs jsonb := '[]'::jsonb; last_ok timestamptz;
  expected text[] := array['restaurant_overrides', 'restaurant_menus', 'restaurant_photos', 'cafeteria_meals', 'campus_cafeterias', 'missions', 'monthly_campaigns', 'app_content', 'universities'];
  live_tables text[] := '{}'; pub boolean := false;
  guards text[]; want_guards text[] := array['restaurant_overrides_guard_live', 'cafeteria_meals_guard_live', 'restaurant_menus_guard_live',
    'restaurant_photos_guard_live', 'app_content_guard_live', 'universities_guard_live'];
  jobs_info jsonb; drafts jsonb; sched_list jsonb; failed jsonb; recent jsonb;
begin
  perform public._cms_admin_check();

  -- scheduler: the pg_cron job that runs cms_run_due_jobs() every minute
  if to_regclass('cron.job') is not null then
    cron_info := jsonb_build_object('available', true, 'job_found', false);
    begin
      execute 'select jobid, schedule, active from cron.job where jobname = $1' into jobid_, sched, act using 'cms-run-due-jobs';
      if jobid_ is not null then
        cron_info := cron_info || jsonb_build_object('job_found', true, 'schedule', sched, 'active', act);
        if to_regclass('cron.job_run_details') is not null then
          execute 'select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb) from (select status, start_time, end_time, left(return_message, 200) as message
                     from cron.job_run_details where jobid = $1 order by start_time desc limit 10) r' into runs using jobid_;
          execute 'select max(start_time) from cron.job_run_details where jobid = $1 and status = ''succeeded''' into last_ok using jobid_;
          cron_info := cron_info || jsonb_build_object('recent_runs', runs, 'last_success_at', last_ok);
        end if;
      end if;
    exception when others then
      cron_info := cron_info || jsonb_build_object('error', left(sqlerrm, 200));
    end;
  end if;

  -- queue
  select jsonb_build_object(
    'scheduled', count(*) filter (where status = 'scheduled'),
    'overdue', count(*) filter (where status = 'scheduled' and run_at < now() - interval '3 minutes'),
    'running', count(*) filter (where status = 'running'),
    'stuck', count(*) filter (where status = 'running' and updated_at < now() - interval '10 minutes'),
    'failed', count(*) filter (where status = 'failed'),
    'next_run_at', min(run_at) filter (where status = 'scheduled'),
    'last_executed_at', max(executed_at))
    into jobs_info from public.publication_jobs;

  -- live-update channel the app listens to
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    pub := true;
    select coalesce(array_agg(tablename::text), '{}') into live_tables from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = any (expected);
  end if;

  -- the guards that keep live content changing only by publishing
  select coalesce(array_agg(tgname::text), '{}') into guards from pg_trigger where tgname = any (want_guards) and not tgisinternal;

  select coalesce(jsonb_agg(x order by x ->> 'updated_at' desc), '[]'::jsonb) into drafts from (
    select jsonb_build_object('entity_type', d.entity_type, 'entity_id', d.entity_id, 'label', public._cms_label(d.entity_type, d.entity_id),
             'updated_at', d.updated_at, 'updated_by', d.updated_by, 'stale', d.base_version <> public._cms_live_version(d.entity_type, d.entity_id),
             'has_changes', d.data is distinct from (case when d.entity_type in ('restaurant', 'cafeteria_meal', 'restaurant_menus', 'restaurant_photos', 'mission', 'campaign', 'app_content', 'university')
                                                       then public._cms_snapshot(d.entity_type, d.entity_id) end)) as x
      from public.content_drafts d order by d.updated_at desc limit 100) q;

  select coalesce(jsonb_agg(x order by x ->> 'run_at'), '[]'::jsonb) into sched_list from (
    select jsonb_build_object('id', j.id, 'entity_type', j.entity_type, 'entity_id', j.entity_id, 'label', public._cms_label(j.entity_type, j.entity_id),
             'action', j.action, 'status', j.status, 'run_at', j.run_at, 'unpublish_at', j.unpublish_at, 'created_by', j.created_by, 'reason', j.reason,
             'overdue', j.status = 'scheduled' and j.run_at < now() - interval '3 minutes') as x
      from public.publication_jobs j where j.status in ('scheduled', 'running') order by j.run_at limit 100) q;

  select coalesce(jsonb_agg(x order by x ->> 'executed_at' desc), '[]'::jsonb) into failed from (
    select jsonb_build_object('id', j.id, 'entity_type', j.entity_type, 'entity_id', j.entity_id, 'label', public._cms_label(j.entity_type, j.entity_id),
             'action', j.action, 'run_at', j.run_at, 'executed_at', j.executed_at, 'attempts', j.attempts, 'last_error', j.last_error, 'created_by', j.created_by) as x
      from public.publication_jobs j where j.status = 'failed' order by j.executed_at desc nulls last limit 50) q;

  select coalesce(jsonb_agg(x order by x ->> 'published_at' desc), '[]'::jsonb) into recent from (
    select jsonb_build_object('entity_type', v.entity_type, 'entity_id', v.entity_id, 'label', public._cms_label(v.entity_type, v.entity_id),
             'version', v.version, 'kind', v.kind, 'reason', v.reason, 'published_at', v.published_at, 'published_by', v.published_by, 'job_id', v.job_id) as x
      from public.content_versions v order by v.published_at desc limit 30) q;

  return jsonb_build_object(
    'generated_at', now(),
    'cron', cron_info,
    'jobs', jobs_info,
    'realtime', jsonb_build_object('publication', pub, 'tables', to_jsonb(live_tables), 'missing', to_jsonb(array(select t from unnest(expected) t where t <> all (live_tables)))),
    'guards', jsonb_build_object('present', to_jsonb(guards), 'missing', to_jsonb(array(select g from unnest(want_guards) g where g <> all (guards)))),
    'schema', jsonb_build_object(
      'cafeteria_status', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'campus_cafeterias' and column_name = 'status'),
      'contributions', to_regprocedure('public.delete_my_contribution(uuid)') is not null),
    'drafts', drafts, 'scheduled', sched_list, 'failed', failed, 'recent', recent);
end $$;
revoke all on function public.cms_health() from public, anon;
grant execute on function public.cms_health() to authenticated;
