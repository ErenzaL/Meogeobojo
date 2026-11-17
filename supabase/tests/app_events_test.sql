\set ON_ERROR_STOP on
\pset pager off
-- 사용 지표 (migration 20261122000100, applied twice by run_local.sh): guests and users can only add events of the
-- four shapes, nobody reads rows, and only the 분석 page's roles (moderator and up) get the aggregates.

insert into auth.users (id, email) values
  ('ae000000-0000-4000-8000-0000000000a1', 'ae-user@example.org'),
  ('ae000000-0000-4000-8000-0000000000b1', 'ae-mod@example.org'),
  ('ae000000-0000-4000-8000-0000000000c1', 'ae-admin@example.org');
insert into public.admin_roles (user_id, role) values
  ('ae000000-0000-4000-8000-0000000000b1', 'moderator'),
  ('ae000000-0000-4000-8000-0000000000c1', 'admin');

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  insert into public.app_events (event, client_id) values ('app_open', 'ae000000-0000-4000-8000-00000000c001');
  insert into public.app_events (event, client_id, restaurant_id) values ('restaurant_view', 'ae000000-0000-4000-8000-00000000c001', 'k1');
  insert into public.app_events (event, client_id, restaurant_id) values ('directions_click', 'ae000000-0000-4000-8000-00000000c001', 'k1');
  insert into public.app_events (event, client_id, query) values ('search', 'ae000000-0000-4000-8000-00000000c001', '국밥');
  begin insert into public.app_events (event, client_id) values ('restaurant_view', 'ae000000-0000-4000-8000-00000000c001'); raise exception 'accepted#view-without-place'; exception when check_violation then null; end;
  begin insert into public.app_events (event, client_id, query) values ('app_open', 'ae000000-0000-4000-8000-00000000c001', 'x'); raise exception 'accepted#open-with-query'; exception when check_violation then null; end;
  begin insert into public.app_events (event, client_id, query) values ('search', 'ae000000-0000-4000-8000-00000000c001', repeat('a', 101)); raise exception 'accepted#long-query'; exception when check_violation then null; end;
  begin insert into public.app_events (event, client_id) values ('purchase', 'ae000000-0000-4000-8000-00000000c001'); raise exception 'accepted#kind'; exception when check_violation then null; end;
  begin insert into public.app_events (event, client_id, created_at) values ('app_open', 'ae000000-0000-4000-8000-00000000c001', now() - interval '3 days'); raise exception 'accepted#forged-time'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.app_events; raise exception 'accepted#read'; exception when insufficient_privilege then null; end;
  begin perform public.admin_event_stats(7); raise exception 'accepted#stats'; exception when insufficient_privilege then null; end;
  raise notice 'OK guest: records the four event shapes only, cannot forge the time, read rows or aggregates';
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"ae000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  insert into public.app_events (event, client_id, query) values ('search', 'ae000000-0000-4000-8000-00000000c002', '국밥');
  insert into public.app_events (event, client_id, query) values ('search', 'ae000000-0000-4000-8000-00000000c002', '라멘');
  begin perform 1 from public.app_events; raise exception 'accepted#read'; exception when insufficient_privilege then null; end;
  begin perform public.admin_top_search_queries(7, 10); raise exception 'accepted#top'; exception when insufficient_privilege then null; end;
  raise notice 'OK user: records events, cannot read rows or aggregates';
end $$;
reset role;

-- The first visitor also came back two days earlier (written as the owner, as only the clock can do).
insert into public.app_events (created_at, event, client_id) values (now() - interval '2 days', 'app_open', 'ae000000-0000-4000-8000-00000000c001');
-- An event older than the period is left out.
insert into public.app_events (created_at, event, client_id) values (now() - interval '40 days', 'app_open', 'ae000000-0000-4000-8000-00000000c003');

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"ae000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ declare s record; t record; begin
  select * into s from public.admin_event_stats(7);
  assert s.visitors = 2, format('two visitors in 7 days, got %s', s.visitors);
  assert s.returning_visitors = 1, format('one returning visitor, got %s', s.returning_visitors);
  assert s.app_opens = 2 and s.restaurant_views = 1 and s.directions_clicks = 1 and s.searches = 3, format('counts %s', s);
  assert (select count(*) from public.admin_event_daily(7)) = 2, 'two days with events';
  select * into t from public.admin_top_search_queries(7, 10) limit 1;
  assert t.term = '국밥' and t.searches = 2, format('top term %s', t);
  assert (select visitors from public.admin_event_stats(60)) = 3, 'a longer period includes the old visit';
  raise notice 'OK admin: visitors, returning visitors, counts, daily rows and top search words are right';
end $$;
select set_config('request.jwt.claims', '{"sub":"ae000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  assert (select visitors from public.admin_event_stats(7)) = 2, 'a moderator reads the same totals';
  raise notice 'OK moderator: reads the aggregates (the 분석 menu is open to moderators)';
end $$;
reset role;

-- 실사용 선택 시간 (migration 20261125000100): app_open → first 길찾기 within the same visit and 30 minutes.
-- So far c001 has two visits in 7 days (opened and clicked in the same instant: 0 s; two days ago: no click).
insert into public.app_events (created_at, event, client_id, restaurant_id) values
  -- c004 visit 1: first click after 90 s counts, the second click does not
  (now() - interval '3 hours',                      'app_open',         'ae000000-0000-4000-8000-00000000c004', null),
  (now() - interval '3 hours' + interval '90 seconds',  'directions_click', 'ae000000-0000-4000-8000-00000000c004', 'k1'),
  (now() - interval '3 hours' + interval '200 seconds', 'directions_click', 'ae000000-0000-4000-8000-00000000c004', 'k2'),
  -- c004 visit 2: the click comes after 40 minutes, so the visit made no choice
  (now() - interval '2 hours',                      'app_open',         'ae000000-0000-4000-8000-00000000c004', null),
  (now() - interval '2 hours' + interval '40 minutes',  'directions_click', 'ae000000-0000-4000-8000-00000000c004', 'k1'),
  -- c004 visits 3 and 4: a reload after 60 s starts a new visit, which owns the click 30 s later
  (now() - interval '1 hour',                       'app_open',         'ae000000-0000-4000-8000-00000000c004', null),
  (now() - interval '1 hour' + interval '60 seconds',   'app_open',         'ae000000-0000-4000-8000-00000000c004', null),
  (now() - interval '1 hour' + interval '90 seconds',   'directions_click', 'ae000000-0000-4000-8000-00000000c004', 'k3'),
  -- c005: a click before any open is ignored; its visit chooses after 300 s
  (now() - interval '5 hours',                      'directions_click', 'ae000000-0000-4000-8000-00000000c005', 'k1'),
  (now() - interval '4 hours',                      'app_open',         'ae000000-0000-4000-8000-00000000c005', null),
  (now() - interval '4 hours' + interval '300 seconds', 'directions_click', 'ae000000-0000-4000-8000-00000000c005', 'k4');

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin perform public.admin_choice_time(7); raise exception 'accepted#choice-time-guest'; exception when insufficient_privilege then null; end;
  raise notice 'OK guest: cannot read the choice time';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"ae000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  begin perform public.admin_choice_time(7); raise exception 'accepted#choice-time-user'; exception when insufficient_privilege then null; end;
  raise notice 'OK user: cannot read the choice time';
end $$;
select set_config('request.jwt.claims', '{"sub":"ae000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ declare c record; begin
  select * into c from public.admin_choice_time(7);
  -- visits: c001 ×2, c004 ×4, c005 ×1; chosen in 0, 30, 90 and 300 s
  assert c.visits = 7 and c.decided_visits = 4, format('visits %s', c);
  assert c.median_seconds = 60.0 and c.p75_seconds = 142.5, format('median / p75 %s', c);
  raise notice 'OK moderator: choice time counts a visit''s first 길찾기 within 30 minutes (median 60 s, p75 142.5 s)';
end $$;
reset role;
