\set ON_ERROR_STOP on
\pset pager off
-- Notifications (the bell in the app and on the website) = app_content rows of kind 'notification' (bell only) and
-- 'announcement' (Home card + bell). No new table or function: this suite proves the widened kind constraint
-- (migration 20261120000100, applied twice by run_local.sh) and that the EXISTING pipeline does the right thing for the
-- new kind: admin-only writes, draft -> publish, scheduling windows, unpublish keeps the row, what the public reads.

insert into auth.users (id, email) values
  ('f9000000-0000-4000-8000-0000000000a1', 'nt-admin@example.org'),
  ('f9000000-0000-4000-8000-0000000000b1', 'nt-mod@example.org'),
  ('f9000000-0000-4000-8000-0000000000c1', 'nt-user@example.org');
insert into public.admin_roles (user_id, role) values
  ('f9000000-0000-4000-8000-0000000000a1', 'admin'),
  ('f9000000-0000-4000-8000-0000000000b1', 'moderator');

-- ===== A: the constraint =====
do $$ begin
  assert exists (select 1 from pg_constraint where conname = 'app_content_kind_check' and conrelid = 'public.app_content'::regclass), 'the kind constraint exists under the expected name';
  assert pg_get_constraintdef((select oid from pg_constraint where conname = 'app_content_kind_check' and conrelid = 'public.app_content'::regclass)) like '%notification%', 'and allows notification';
  insert into public.app_content (id, kind, title) values ('a9000000-0000-4000-8000-000000000001', 'notification', '검사용 알림');
  begin insert into public.app_content (kind, title) values ('popup', 'x'); raise exception 'accepted#unknownkind'; exception when check_violation then null; end;
  delete from public.app_content where id = 'a9000000-0000-4000-8000-000000000001';
  raise notice 'OK kind constraint: notification allowed, unknown kinds still refused';
end $$;

-- ===== B: admin creates (always OFF), edits as a draft, publishes through the existing function =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f9000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare s jsonb; r jsonb; begin
  insert into public.app_content (id, kind, title, body, link_url, active) values ('a9000000-0000-4000-8000-000000000010', 'notification', '개강 안내', '학식 운영 시간이 바뀌어요', 'https://example.org/news', false);
  insert into public.app_content (id, kind, title, active) values ('a9000000-0000-4000-8000-000000000011', 'announcement', '공지 하나', false);
  insert into public.app_content (id, kind, title, active) values ('a9000000-0000-4000-8000-000000000012', 'notification', '예약 알림', false);
  insert into public.app_content (id, kind, title, active) values ('a9000000-0000-4000-8000-000000000013', 'notification', '지난 알림', false);
  begin insert into public.app_content (kind, title, active) values ('notification', '바로 켜기', true); raise exception 'accepted#active'; exception when insufficient_privilege then null; end;
  -- a draft edit does not change what is live
  s := public.cms_state('app_content', 'a9000000-0000-4000-8000-000000000010');
  r := public.cms_save_draft('app_content', 'a9000000-0000-4000-8000-000000000010', jsonb_set(s -> 'live', '{body}', '"수정한 내용"'), 0);
  assert (select body from public.app_content where id = 'a9000000-0000-4000-8000-000000000010') = '학식 운영 시간이 바뀌어요', 'a draft is not live';
  perform public.cms_discard_draft('app_content', 'a9000000-0000-4000-8000-000000000010', 1);
  -- publish: one immediately, one with a future start, one already expired, one announcement
  perform public.cms_set_visibility('app_content', 'a9000000-0000-4000-8000-000000000010', 'published', '개강 안내');
  perform public.cms_set_visibility('app_content', 'a9000000-0000-4000-8000-000000000011', 'published', '공지');
  perform public.cms_set_visibility('app_content', 'a9000000-0000-4000-8000-000000000012', 'published', '예약 알림');
  perform public.cms_set_visibility('app_content', 'a9000000-0000-4000-8000-000000000013', 'published', '지난 알림');
end $$;
reset role;
-- the scheduling window is a column the existing guard allows an admin to set only through publishing; set it as the platform would
update public.app_content set starts_at = now() + interval '1 day' where id = 'a9000000-0000-4000-8000-000000000012';
update public.app_content set starts_at = now() - interval '3 days', ends_at = now() - interval '1 day' where id = 'a9000000-0000-4000-8000-000000000013';
do $$ begin
  assert (select active from public.app_content where id = 'a9000000-0000-4000-8000-000000000010'), 'published notification is on';
  assert (select count(*) from public.content_versions where entity_type = 'app_content' and entity_id = 'a9000000-0000-4000-8000-000000000010' and reason = '개강 안내') = 1, 'with a version and its reason';
  assert (select count(*) from public.audit_log where action = 'cms_visibility' and row_id = 'a9000000-0000-4000-8000-000000000010') = 1, 'and an audit entry';
  raise notice 'OK admin: created OFF, drafts are not live, published through the existing function with history + audit';
end $$;

-- ===== C: what the public (the app AND the website) reads =====
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.app_content where id::text like 'a9000000-%') = 2, 'the public reads exactly the live notification and the live announcement';
  assert exists (select 1 from public.app_content where id = 'a9000000-0000-4000-8000-000000000010' and kind = 'notification'), 'the notification is readable';
  assert not exists (select 1 from public.app_content where id = 'a9000000-0000-4000-8000-000000000012'), 'a notification that starts tomorrow is not visible yet';
  assert not exists (select 1 from public.app_content where id = 'a9000000-0000-4000-8000-000000000013'), 'an expired one is gone';
  assert (select count(*) from public.app_content where kind = 'notification' and id::text like 'a9000000-%') = 1, 'one bell-only notification visible';
  begin insert into public.app_content (kind, title) values ('notification', 'anon'); raise exception 'accepted#anon'; exception when insufficient_privilege then null; end;
  raise notice 'OK public read: only live items inside their dates; anonymous visitors cannot write';
end $$;
reset role;

-- ===== D: only admins write =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f9000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin insert into public.app_content (kind, title, active) values ('notification', '조정자', false); raise exception 'accepted#moderator'; exception when insufficient_privilege then null; end;
  begin perform public.cms_set_visibility('app_content', 'a9000000-0000-4000-8000-000000000011', 'hidden', 'x'); raise exception 'accepted#moderator-publish'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"f9000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ begin
  begin insert into public.app_content (kind, title, active) values ('notification', '사용자', false); raise exception 'accepted#user'; exception when insufficient_privilege then null; end;
  begin perform public.cms_set_visibility('app_content', 'a9000000-0000-4000-8000-000000000011', 'hidden', 'x'); raise exception 'accepted#user-publish'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert (select active from public.app_content where id = 'a9000000-0000-4000-8000-000000000011'), 'refused callers changed nothing';
  assert not exists (select 1 from public.app_content where title in ('조정자', '사용자', 'anon')), 'and created nothing';
  raise notice 'OK only admins can create or publish notifications';
end $$;

-- ===== E: unpublish keeps the row; the apps hear about changes =====
do $$ declare before bigint; begin
  select count(*) into before from public.content_sync where source = 'app_content';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"f9000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  perform public.cms_set_visibility('app_content', 'a9000000-0000-4000-8000-000000000010', 'hidden', '내릴게요');
  reset role;
  assert (select count(*) from public.app_content where id = 'a9000000-0000-4000-8000-000000000010' and active = false and body = '학식 운영 시간이 바뀌어요') = 1, 'unpublished: switched off, content kept';
  assert (select count(*) from public.content_sync where source = 'app_content') > before, 'a live-update signal was recorded for the running apps and websites';
  raise notice 'OK unpublish keeps the notification (history intact) and signals running apps/websites';
end $$;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert not exists (select 1 from public.app_content where id = 'a9000000-0000-4000-8000-000000000010'), 'an unpublished notification disappears for the public';
end $$;
reset role;
