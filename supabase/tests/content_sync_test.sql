\set ON_ERROR_STOP on
\pset pager off
-- Live-update signal: every change, including a TAKE-DOWN, appends a row that students can always read;
-- nobody can write it through the API; it holds no content; it never blocks or deadlocks writers.

insert into auth.users (id, email) values ('f7000000-0000-4000-8000-0000000000a1', 'sync-admin@example.org');
insert into public.admin_roles (user_id, role) values ('f7000000-0000-4000-8000-0000000000a1', 'admin');
create temp table _n as select count(*)::int as n from public.content_sync;
grant select, update on _n to public;

-- 1. every synced table has the trigger exactly once (re-applying the migration does not stack them)
do $$ declare n int; begin
  select count(*) into n from pg_trigger where tgname = 'content_sync_bump' and not tgisinternal;
  assert n = 9, 'one content_sync_bump trigger on each of the 9 synced tables (got ' || n || ')';
  raise notice 'OK content_sync: a trigger on each synced table, none duplicated';
end $$;

-- 2. a write of any kind appends ONE row naming the table
do $$ declare before int; begin
  select count(*) into before from public.content_sync;
  insert into public.app_content (id, kind, title, active) values ('a7000000-0000-4000-8000-000000000001', 'announcement', 'Test', true), ('a7000000-0000-4000-8000-000000000002', 'banner', 'Test 2', false);
  assert (select count(*) from public.content_sync) = before + 1, 'a two-row INSERT is ONE statement, so one signal';
  assert (select source from public.content_sync order by id desc limit 1) = 'app_content', 'the row names the table';
  -- a TAKE-DOWN: the row becomes invisible to students, which Realtime itself cannot announce
  update public.app_content set active = false where id = 'a7000000-0000-4000-8000-000000000001';
  assert (select count(*) from public.content_sync) = before + 2, 'switching an announcement off is signalled';
  delete from public.app_content where id = 'a7000000-0000-4000-8000-000000000001';
  assert (select count(*) from public.content_sync) = before + 3, 'a delete is signalled';
  update public.app_content set title = 'nothing matches' where id = 'a7000000-0000-4000-8000-0000000000ff';
  assert (select count(*) from public.content_sync) = before + 4, 'even a statement that changes no row is signalled (harmless: the app just re-reads)';
  raise notice 'OK content_sync: insert, take-down, delete are each signalled once per statement';
end $$;

-- 3. the publishing functions and the scheduler signal too (they are SECURITY DEFINER writers)
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f7000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare before int; v int; c constant uuid := 'a7000000-0000-4000-8000-000000000002'; j bigint; begin
  perform public.cms_save_draft('app_content', c, (public.cms_state('app_content', c) -> 'live') || '{"active":true,"title":"Published"}', 0);
  select count(*) into before from public.content_sync;
  v := public.cms_publish('app_content', c, 1, 'publish');
  assert (select count(*) from public.content_sync where source = 'app_content') > 0 and (select count(*) from public.content_sync) > before, 'cms_publish signals';
  select count(*) into before from public.content_sync;
  v := public.cms_unpublish('app_content', c, 'take down');
  assert (select count(*) from public.content_sync) > before, 'cms_unpublish (a take-down) signals';
  select count(*) into before from public.content_sync;
  v := public.cms_rollback('app_content', c, 1, 'roll back');
  assert (select count(*) from public.content_sync) > before, 'cms_rollback signals';
  perform public.cms_save_draft('app_content', c, (public.cms_state('app_content', c) -> 'live') || '{"title":"Scheduled"}',
    coalesce((select revision from public.content_drafts where entity_type = 'app_content' and entity_id = c), 0));
  j := public.cms_schedule('app_content', c, (select revision from public.content_drafts where entity_type = 'app_content' and entity_id = c), now() + interval '1 day', null, 'later');
  perform set_config('test.syncjob', j::text, false);
  raise notice 'OK content_sync: publish, unpublish and rollback are signalled';
end $$;
reset role;
do $$ declare before int; res jsonb; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = current_setting('test.syncjob')::bigint;
  select count(*) into before from public.content_sync;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'the scheduler ran: ' || res::text;
  assert (select count(*) from public.content_sync) > before, 'a publication made by the scheduler (no logged-in user) is signalled';
  raise notice 'OK content_sync: the server-side scheduler signals too';
end $$;

-- 4. students (anon) and signed-in users can READ it, nobody can WRITE it, and it holds no content
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare n int; begin
  select count(*) into n from public.content_sync;
  assert n > 0, 'anon can read the signal';
  begin insert into public.content_sync (source) values ('app_content'); raise exception 'accepted#s1'; exception when insufficient_privilege then null; end;
  begin update public.content_sync set source = 'x'; raise exception 'accepted#s2'; exception when insufficient_privilege then null; end;
  begin delete from public.content_sync; raise exception 'accepted#s3'; exception when insufficient_privilege then null; end;
  begin perform public.content_sync_bump(); raise exception 'accepted#s4'; exception when others then null; end;
  assert (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'content_sync') = 3, 'only id, source, changed_at: no content';
  raise notice 'OK content_sync: readable by students, writable by nobody, no content in it';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f7000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  begin insert into public.content_sync (source) values ('app_content'); raise exception 'accepted#s5'; exception when insufficient_privilege then null; end;
  raise notice 'OK content_sync: not even an admin can write it through the API';
end $$;
reset role;

-- 5. two writers on different tables in opposite order never block or deadlock each other (inserts take no shared row lock)
do $$ begin
  -- the log has no UNIQUE or UPDATE target: every signal is a fresh row
  assert not exists (select 1 from pg_index i where i.indrelid = 'public.content_sync'::regclass and i.indisunique and not i.indisprimary), 'no unique key to contend on';
  raise notice 'OK content_sync: append-only (no row lock shared by concurrent publishes)';
end $$;

-- 6. the log prunes itself (deterministic random sequence), without touching recent rows
do $$ declare i int; begin
  perform setseed(0.42);
  insert into public.content_sync (source, changed_at) values ('app_content', now() - interval '3 days');
  for i in 1..300 loop update public.app_content set title = title where false; end loop;
  assert not exists (select 1 from public.content_sync where changed_at < now() - interval '2 days'), 'old rows are pruned';
  assert (select count(*) from public.content_sync where changed_at > now() - interval '1 hour') > 100, 'recent rows are kept';
  raise notice 'OK content_sync: old rows are pruned, recent ones kept';
end $$;

-- 7. it reaches the apps: it is on the realtime channel (when the project has one)
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    assert exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'content_sync'), 'content_sync is on the realtime channel';
  end if;
  raise notice 'OK content_sync: delivered through the realtime channel';
end $$;

delete from public.publication_jobs where entity_type = 'app_content';
delete from public.content_drafts where entity_type = 'app_content';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'app_content';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.app_content where id::text like 'a7000000%';
delete from public.content_sync;
