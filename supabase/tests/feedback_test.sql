\set ON_ERROR_STOP on
\pset pager off
-- 문의 및 제안 = reports rows of target_type 'feedback' (migration 20261121000100, applied twice by run_local.sh).
-- No new table or function: this suite proves the widened type, that one user may send several, that the
-- one-open-report rule still holds for places, and that the existing policies and admin function cover feedback.

insert into auth.users (id, email) values
  ('fb000000-0000-4000-8000-0000000000a1', 'fb-user@example.org'),
  ('fb000000-0000-4000-8000-0000000000b1', 'fb-other@example.org'),
  ('fb000000-0000-4000-8000-0000000000c1', 'fb-mod@example.org');
insert into public.admin_roles (user_id, role) values ('fb000000-0000-4000-8000-0000000000c1', 'moderator');

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"fb000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  insert into public.reports (target_type, target_id, reason, description) values ('feedback', 'suggestion', '지도 핀', '핀이 작아요');
  insert into public.reports (target_type, target_id, reason, description) values ('feedback', 'suggestion', '다크 모드', '글자가 흐려요');
  assert (select count(*) from public.reports where target_type = 'feedback') = 2, 'two open suggestions from one user are both kept';
  insert into public.reports (target_type, target_id, reason) values ('restaurant', 'fb-k1', 'wrong info');
  begin insert into public.reports (target_type, target_id, reason) values ('restaurant', 'fb-k1', 'again'); raise exception 'accepted#dup'; exception when unique_violation then null; end;
  begin insert into public.reports (target_type, target_id, reason) values ('popup', 'x', 'y'); raise exception 'accepted#kind'; exception when check_violation then null; end;
  raise notice 'OK user: sends several 문의·제안; one open report per place still enforced; unknown types refused';
end $$;
select set_config('request.jwt.claims', '{"sub":"fb000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  assert (select count(*) from public.reports where target_type = 'feedback') = 0, 'another user sees none of them';
  raise notice 'OK privacy: a user reads only their own 문의·제안';
end $$;
reset role;

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin insert into public.reports (target_type, target_id, reason) values ('feedback', 'question', 'x'); raise exception 'accepted#anon'; exception when insufficient_privilege then null; end;
  raise notice 'OK guest: cannot send (sign-in required)';
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"fb000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ declare v uuid; begin
  assert (select count(*) from public.reports where target_type = 'feedback') = 2, 'the moderator reads them';
  select id into v from public.reports where target_type = 'feedback' and reason = '지도 핀';
  perform public.admin_resolve_report(v, 'resolved', '다음 배포에 반영');
  assert (select status from public.reports where id = v) = 'resolved', 'and resolves one with a note';
  raise notice 'OK moderator: reads and resolves 문의·제안 with the existing function';
end $$;
reset role;
