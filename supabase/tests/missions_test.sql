\set ON_ERROR_STOP on
\pset pager off
-- Mission system: RLS, server-side validation, idempotent rewards, periods,
-- versioning, admin authorization and audit. Every "cannot" is a NEGATIVE test.

-- ===== fixtures (superuser, like the SQL editor) =====
insert into auth.users (id, email) values
  ('f1000000-0000-4000-8000-000000000001', 'm-user1@example.org'),
  ('f1000000-0000-4000-8000-000000000002', 'm-user2@example.org'),
  ('f1000000-0000-4000-8000-00000000000a', 'm-admin@example.org'),
  ('f1000000-0000-4000-8000-00000000000b', 'm-mod@example.org');
insert into public.admin_roles (user_id, role) values
  ('f1000000-0000-4000-8000-00000000000a', 'admin'),
  ('f1000000-0000-4000-8000-00000000000b', 'moderator');
insert into public.profiles (id, selected_university_id) values
  ('f1000000-0000-4000-8000-000000000001', '5c0a8f3e-0001-4a6e-9b1d-000000000001'),
  ('f1000000-0000-4000-8000-000000000002', '5c0a8f3e-0001-4a6e-9b1d-000000000001'),
  ('f1000000-0000-4000-8000-00000000000a', null),
  ('f1000000-0000-4000-8000-00000000000b', null) on conflict (id) do update set selected_university_id = excluded.selected_university_id;

-- a campaign that started a day ago (so it is the "current" one), published
insert into public.monthly_campaigns (id, slug, title, starts_at, ends_at, publish_state) values
  ('a1000000-0000-4000-8000-000000000001', 'test-run', '테스트 미션', now() - interval '1 day', now() + interval '30 days', 'published'),
  ('a1000000-0000-4000-8000-000000000002', 'test-draft', '초안 캠페인', now() - interval '1 day', now() + interval '30 days', 'draft'),
  ('a1000000-0000-4000-8000-000000000003', 'test-old', '지난 캠페인', now() - interval '60 days', now() - interval '31 days', 'published');

insert into public.missions (id, lineage_id, campaign_id, slug, kind, title, reward_points, rule_type, rule_params, target_count, recurrence, status, sort_order, reward_badge_key, reward_badge_name, reward_badge_mascot) values
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 't-fav', 'monthly', '찜 2곳', 10, 'favorite_distinct', '{}', 2, 'none', 'active', 1, null, null, null),
  ('b1000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 't-cheap', 'monthly', '가성비', 20, 'favorite_cheap', '{"max_price_krw":10000}', 2, 'none', 'active', 2, null, null, null),
  ('b1000000-0000-4000-8000-000000000003', 'b1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000001', 't-days', 'monthly', '추천 2일', 5, 'activity_days', '{"event":"recommendation_view"}', 2, 'none', 'active', 3, null, null, null),
  ('b1000000-0000-4000-8000-000000000004', 'b1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000001', 't-cat', 'monthly', '카테고리 2개', 7, 'activity_refs', '{"event":"category_explore","exclude":["all"]}', 2, 'none', 'active', 4, null, null, null),
  ('b1000000-0000-4000-8000-000000000005', 'b1000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000001', 't-review', 'monthly', '리뷰', 30, 'review_valid', '{"min_chars":10}', 1, 'none', 'active', 5, null, null, null),
  ('b1000000-0000-4000-8000-000000000006', 'b1000000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-000000000001', 't-photo', 'monthly', '사진', 30, 'contribution_approved', '{"kind":"menu_photo"}', 1, 'none', 'active', 6, null, null, null),
  ('b1000000-0000-4000-8000-000000000007', 'b1000000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-000000000001', 't-master', 'monthly', '마스터', 0, 'missions_completed', '{}', 3, 'none', 'active', 9, 'tc_master', '테스트 마스터', 'cheer'),
  ('b1000000-0000-4000-8000-000000000008', 'b1000000-0000-4000-8000-000000000008', null, 't-daily', 'daily', '데일리', 3, 'activity_days', '{"event":"recommendation_view"}', 1, 'daily', 'active', 1, null, null, null),
  ('b1000000-0000-4000-8000-000000000009', 'b1000000-0000-4000-8000-000000000009', null, 't-weekly', 'weekly', '주간', 4, 'favorite_distinct', '{}', 99, 'weekly', 'active', 1, null, null, null),
  ('b1000000-0000-4000-8000-00000000000a', 'b1000000-0000-4000-8000-00000000000a', 'a1000000-0000-4000-8000-000000000002', 't-in-draft-campaign', 'monthly', '초안 캠페인 미션', 99, 'favorite_distinct', '{}', 1, 'none', 'active', 1, null, null, null),
  ('b1000000-0000-4000-8000-00000000000b', 'b1000000-0000-4000-8000-00000000000b', 'a1000000-0000-4000-8000-000000000001', 't-draft-mission', 'monthly', '초안 미션', 99, 'favorite_distinct', '{}', 1, 'none', 'draft', 1, null, null, null),
  ('b1000000-0000-4000-8000-00000000000c', 'b1000000-0000-4000-8000-00000000000c', 'a1000000-0000-4000-8000-000000000003', 't-expired', 'monthly', '지난 미션', 99, 'favorite_distinct', '{}', 1, 'none', 'active', 1, null, null, null);
insert into public.missions (id, lineage_id, campaign_id, slug, kind, title, reward_points, rule_type, rule_params, target_count, status, university_id)
select 'b1000000-0000-4000-8000-00000000000d', 'b1000000-0000-4000-8000-00000000000d', null, 't-other-campus', 'achievement', '다른 캠퍼스', 99, 'favorite_distinct', '{}', 1, 'active', u.id
  from public.universities u where u.id <> '5c0a8f3e-0001-4a6e-9b1d-000000000001' limit 1;

insert into public.restaurant_overrides (kakao_place_id, name_ko, visibility, price_min_krw) values
  ('p2', '싼집', 'published', 8000),
  ('p3', '비싼집', 'published', 12000),
  ('p4', '초안싼집', 'draft', 5000),
  ('p5', '싼집2', 'published', 9999);
-- the seeded production missions would also react to these fixtures: park them
update public.missions set status = 'archived' where slug not like 't-%';
update public.monthly_campaigns set publish_state = 'draft' where slug = '2026-11';
delete from public.audit_log;

-- ===== anonymous =====
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin perform 1 from public.missions; raise exception 'accepted#1'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.user_mission_progress; raise exception 'accepted#2'; exception when insufficient_privilege then null; end;
  begin perform public.sync_my_missions(); raise exception 'accepted#3'; exception when insufficient_privilege then null; end;
  begin perform public.log_activity('recommendation_view'); raise exception 'accepted#4'; exception when insufficient_privilege then null; end;
  raise notice 'OK anon: no mission tables, no mission functions';
end $$;
reset role;

-- ===== a normal user: cannot write anything directly =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}', false);
do $$ begin
  begin insert into public.user_mission_progress (user_id, mission_id, lineage_id, period_key, progress, target)
    values (auth.uid(), 'b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'once', 99, 1);
    raise exception 'accepted#10'; exception when insufficient_privilege then null; end;
  begin insert into public.point_transactions (user_id, points, kind, mission_id, lineage_id, period_key)
    values (auth.uid(), 999, 'mission_reward', 'b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'once');
    raise exception 'accepted#11'; exception when insufficient_privilege then null; end;
  begin insert into public.user_badges (user_id, badge_key) values (auth.uid(), 'hax'); raise exception 'accepted#12'; exception when insufficient_privilege then null; end;
  begin insert into public.activity_events (user_id, event_type, local_date) values (auth.uid(), 'recommendation_view', current_date); raise exception 'accepted#13'; exception when insufficient_privilege then null; end;
  begin update public.missions set reward_points = 9999; raise exception 'accepted#14'; exception when insufficient_privilege then null; end;
  begin insert into public.monthly_campaigns (slug, title, starts_at, ends_at) values ('hax-camp', 'x', now(), now() + interval '1 day'); raise exception 'accepted#15'; exception when insufficient_privilege then null; end;
  begin insert into public.user_contributions (kind, kakao_place_id) values ('menu_photo', 'p1'); raise exception 'accepted#16'; exception when insufficient_privilege then null; end;
  begin perform public.admin_save_mission('{"slug":"hax","kind":"daily","title":"x","rule_type":"favorite_distinct","target_count":1}'::jsonb); raise exception 'accepted#17'; exception when insufficient_privilege then null; end;
  begin perform public.admin_revoke_reward(1, 'x'); raise exception 'accepted#18'; exception when insufficient_privilege then null; end;
  begin perform public.admin_mission_stats(7); raise exception 'accepted#19'; exception when insufficient_privilege then null; end;
  begin perform public.log_activity('hack_event'); raise exception 'accepted#20'; exception when invalid_parameter_value then null; end;
  assert (select count(*) from public.monthly_campaigns where slug = 'test-draft') = 0, 'users do not see draft campaigns';
  assert (select count(*) from public.missions where slug = 't-draft-mission') = 0, 'users do not see draft missions';
  assert (select count(*) from public.missions where slug = 't-fav') = 1, 'users see active missions of a published campaign';
  assert (select count(*) from public.missions where slug = 't-in-draft-campaign') = 0, 'missions of a draft campaign stay hidden';
  raise notice 'OK user: read-only on mission data; admin functions and forged events refused';
end $$;

-- ===== progress comes from real, de-duplicated actions =====
do $$ declare r jsonb; m jsonb; begin
  -- nothing done yet: honest zeros
  r := public.sync_my_missions();
  assert r -> 'campaign' ->> 'slug' = 'test-run', 'current campaign is the newest started one';
  assert (select count(*) from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-draft-mission') = 0, 'draft mission not offered';
  assert (select count(*) from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-other-campus') = 0, 'another campus''s mission not offered';
  assert (select count(*) from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-in-draft-campaign') = 0, 'draft campaign mission not offered';
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-fav') = 0, 'zero progress at start';
  assert (r ->> 'points_total')::int = 0, 'no points at start';

  -- saving places
  insert into public.favorites (kakao_place_id) values ('p1');
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-fav') = 1, 'one saved place = 1/2';
  insert into public.favorites (kakao_place_id) values ('p2');
  r := public.sync_my_missions();
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-fav'), 't-fav completed at 2';
  assert jsonb_array_length(r -> 'newly_completed') = 1 and r -> 'newly_completed' -> 0 ->> 'slug' = 't-fav', 'completion reported once';
  assert (r ->> 'points_total')::int = 10, 'reward paid';
  -- again: nothing new, no second payment
  r := public.sync_my_missions();
  assert jsonb_array_length(r -> 'newly_completed') = 0 and (r ->> 'points_total')::int = 10, 'idempotent';
  begin insert into public.favorites (kakao_place_id) values ('p2'); exception when unique_violation then null; end;
  raise notice 'OK saving places: counts distinct places, pays once';
end $$;

do $$ declare r jsonb; begin
  -- price rule: only PUBLISHED admin prices <= 10,000 count (p2 8000; p3 12000; p4 is draft)
  insert into public.favorites (kakao_place_id) values ('p3'), ('p4');
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-cheap') = 1,
    'only the published cheap place counts (not 12,000, not a draft price, not unknown)';
  assert not (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-cheap'), 'not complete at 1/2';
  insert into public.favorites (kakao_place_id) values ('p5');
  r := public.sync_my_missions();
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-cheap'), 'complete at 2/2';
  assert (r ->> 'points_total')::int = 30, 'both paid: 10 + 20';
  raise notice 'OK price rule: verified (published) prices only';
end $$;

do $$ declare r jsonb; begin
  -- repeated taps on the same day do not add up
  perform public.log_activity('recommendation_view');
  perform public.log_activity('recommendation_view');
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-days') = 1, 'two taps, one day = 1';
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-daily'), 'daily mission completed today';
  assert (r ->> 'points_total')::int = 33, 'daily reward 3';
  -- categories: "all" never counts; same category twice counts once
  perform public.log_activity('category_explore', 'all');
  perform public.log_activity('category_explore', 'korean');
  perform public.log_activity('category_explore', 'korean');
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-cat') = 1, 'distinct categories only, "all" excluded';
  begin perform public.log_activity('category_explore', ''); raise exception 'accepted'; exception when invalid_parameter_value then null; end;
  perform public.log_activity('category_explore', 'cafe');
  r := public.sync_my_missions();
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-cat'), 'two categories complete it';
  assert (r ->> 'points_total')::int = 40, 'category reward 7';
  raise notice 'OK activity: de-duplicated per day, categories distinct, all excluded';
end $$;

-- ===== reviews and contributions =====
do $$ declare r jsonb; begin
  insert into public.student_reviews (kakao_place_id, rating, body) values ('p1', 5, 'short');
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-review') = 0, 'a too-short review is not a valid review';
  update public.student_reviews set body = 'A genuinely useful review of this place.' where kakao_place_id = 'p1';
  r := public.sync_my_missions();
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-review'), 'a valid review completes it';
  assert (r ->> 'points_total')::int = 70, 'review reward 30';
  -- contributions wait for approval, and duplicates are refused
  insert into storage.objects (bucket_id, name) values ('contribution-photos', 'f1000000-0000-4000-8000-000000000001/a.jpg');
  perform public.submit_contribution('menu_photo', 'p1', '{"path":"f1000000-0000-4000-8000-000000000001/a.jpg","consent":true}');
  begin perform public.submit_contribution('menu_photo', 'p1', '{"path":"f1000000-0000-4000-8000-000000000001/a.jpg","consent":true}'); raise exception 'accepted'; exception when unique_violation then null; end;
  begin perform public.submit_contribution('badkind', 'p1'); raise exception 'accepted'; exception when invalid_parameter_value then null; end;
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-photo') = 0, 'a pending photo does not count';
  raise notice 'OK reviews and contributions: valid reviews only; pending uploads do not count; duplicates refused';
end $$;
reset role;

-- ===== one user cannot see another's progress =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}', false);
do $$ declare r jsonb; begin
  assert (select count(*) from public.user_mission_progress) = 0, 'user2 sees none of user1''s progress';
  assert (select count(*) from public.point_transactions) = 0, 'user2 sees none of user1''s points';
  assert (select count(*) from public.user_badges) = 0, 'user2 sees none of user1''s badges';
  assert (select count(*) from public.user_contributions) = 0, 'user2 sees none of user1''s contributions';
  -- favorites made BEFORE the window do not count
  r := public.sync_my_missions();
  assert (r ->> 'points_total')::int = 0, 'fresh user: nothing earned';
  raise notice 'OK isolation: users only ever see their own progress, points, badges and contributions';
end $$;
reset role;
insert into public.favorites (user_id, kakao_place_id, created_at) values
  ('f1000000-0000-4000-8000-000000000002', 'old1', now() - interval '90 days'),
  ('f1000000-0000-4000-8000-000000000002', 'old2', now() - interval '90 days');
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}', false);
do $$ declare r jsonb; begin
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-fav') = 0,
    'actions before the campaign window are not counted';
  assert (r ->> 'points_total')::int = 0, 'no reward for old actions';
  assert (select count(*) from public.user_mission_progress p join public.missions m on m.id = p.mission_id where m.slug = 't-expired') = 0,
    'an ended campaign''s mission is never evaluated';
  raise notice 'OK windows: old actions and ended campaigns earn nothing';
end $$;
reset role;

-- ===== daily / weekly periods reset on Asia/Seoul boundaries =====
do $$ declare m public.missions; a record; b record; c record; begin
  select * into m from public.missions where slug = 't-daily';
  select * into a from public._mission_period(m, timestamptz '2026-11-10 14:59:59+00');   -- 23:59:59 KST, Nov 10
  select * into b from public._mission_period(m, timestamptz '2026-11-10 15:00:00+00');   -- 00:00:00 KST, Nov 11
  assert a.period_key = '2026-11-10' and b.period_key = '2026-11-11', 'daily key changes at Seoul midnight, not UTC midnight';
  assert a.win_end = b.win_start, 'daily windows are contiguous';
  select * into m from public.missions where slug = 't-weekly';
  select * into a from public._mission_period(m, timestamptz '2026-11-08 14:59:59+00');   -- Sun 23:59:59 KST
  select * into b from public._mission_period(m, timestamptz '2026-11-08 15:00:00+00');   -- Mon 00:00 KST
  assert a.period_key <> b.period_key, 'weekly key changes Monday 00:00 Seoul';
  assert b.win_end - b.win_start = interval '7 days', 'a week is 7 days';
  select * into m from public.missions where slug = 't-fav';
  select * into c from public._mission_period(m, now());
  assert c.period_key = 'once', 'a campaign mission has one period';
  raise notice 'OK periods: daily and weekly reset at Asia/Seoul boundaries';
end $$;

-- yesterday's tap counts for the 2-day mission but cannot complete today's daily again
insert into public.activity_events (user_id, event_type, ref_key, local_date, created_at) values
  ('f1000000-0000-4000-8000-000000000001', 'recommendation_view', '', public.seoul_date(now()) - 1, now() - interval '1 day');
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}', false);
do $$ declare r jsonb; begin
  r := public.sync_my_missions();
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-days'), 'two different days complete t-days';
  assert (r ->> 'points_total')::int = 75, 't-days paid 5: 70 + 5';
  -- 3 of the campaign's missions are now complete (fav, cheap, days, cat, review = 5): the master badge
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-master'), 'master completes at 3 of the campaign missions';
  assert (select count(*) from jsonb_array_elements(r -> 'badges') b where b ->> 'badge_key' = 'tc_master') = 1, 'badge unlocked once';
  assert (r ->> 'points_total')::int = 75, 'master pays no points';
  -- nothing more changes however often it runs
  perform public.sync_my_missions(); perform public.sync_my_missions();
  assert (select count(*) from public.point_transactions) = 6, 'six rewards, never more';
  assert (select count(*) from public.user_badges) = 1, 'one badge';
  raise notice 'OK master mission: unlocks the badge exactly once';
end $$;
reset role;

-- the database itself refuses a second reward for the same lineage + period
do $$ begin
  begin
    insert into public.point_transactions (user_id, points, kind, mission_id, lineage_id, period_key)
    values ('f1000000-0000-4000-8000-000000000001', 10, 'mission_reward',
            'b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'once');
    raise exception 'accepted';
  exception when unique_violation then null; end;
  raise notice 'OK unique index: a duplicate reward is impossible, even for the superuser';
end $$;

-- ===== contributions: moderators approve, rejected ones never count =====
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-00000000000b","role":"authenticated"}', false);
set role authenticated;
do $$ declare v_id uuid; r jsonb; begin
  select id into v_id from public.user_contributions where user_id = 'f1000000-0000-4000-8000-000000000001' limit 1;
  assert v_id is not null and (select count(*) from public.user_contributions) >= 1, 'moderators can read contributions';
  begin perform public.admin_review_contribution(v_id, 'rejected', ''); raise exception 'accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_mission('{}'::jsonb); raise exception 'accepted'; exception when insufficient_privilege then null; end;
  begin perform public.admin_mission_stats(7); raise exception 'accepted'; exception when insufficient_privilege then null; end;
  perform public.admin_review_contribution(v_id, 'rejected', 'blurry');
  begin perform public.admin_review_contribution(v_id, 'approved', null); raise exception 'accepted'; exception when no_data_found then null; end;
  raise notice 'OK moderator: can review contributions (reason required to reject), nothing else';
end $$;
reset role;
do $$ declare r jsonb; begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  r := public.sync_my_missions();
  assert (select (x ->> 'progress')::int from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-photo') = 0, 'a rejected photo never counts';
  insert into storage.objects (bucket_id, name) values ('contribution-photos', 'f1000000-0000-4000-8000-000000000001/b.jpg');
  perform public.submit_contribution('menu_photo', 'p1', '{"path":"f1000000-0000-4000-8000-000000000001/b.jpg","consent":true}');
  reset role;
  raise notice 'OK rejected contributions do not count';
end $$;
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-00000000000b","role":"authenticated"}', false);
set role authenticated;
do $$ declare v_id uuid; begin
  select id into v_id from public.user_contributions where status = 'pending' and user_id = 'f1000000-0000-4000-8000-000000000001' limit 1;
  perform public.admin_review_contribution(v_id, 'approved', null);
end $$;
reset role;
do $$ declare r jsonb; begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  r := public.sync_my_missions();
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-photo'), 'an approved photo completes t-photo at once';
  assert (r ->> 'points_total')::int = 105, 'photo reward 30';
  reset role;
  raise notice 'OK approval: an approved contribution updates progress and pays immediately';
end $$;

-- ===== admin: versioning, status, revoke, audit =====
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-00000000000a","role":"authenticated"}', false);
set role authenticated;
do $$ declare v1 uuid := 'b1000000-0000-4000-8000-000000000001'; v2 uuid; s jsonb; n integer; begin
  -- title-only edit: in place
  perform public.admin_save_mission(jsonb_build_object('id', v1, 'title', '찜 두 곳'));
  assert (select title from public.missions where id = v1) = '찜 두 곳' and (select count(*) from public.missions where slug = 't-fav') = 1, 'a title edit is in place';
  -- a material edit on a mission with progress: new version, old archived
  v2 := public.admin_save_mission(jsonb_build_object('id', v1, 'target_count', 3, 'reward_points', 50));
  assert v2 <> v1, 'new version row';
  assert (select status from public.missions where id = v1) = 'archived', 'old version archived';
  assert (select version from public.missions where id = v2) = 2 and (select lineage_id from public.missions where id = v2) = v1, 'same lineage, version 2';
  assert (select reward_points from public.missions where id = v1) = 10, 'the old row is untouched';
  -- editing an archived mission is refused
  begin perform public.admin_save_mission(jsonb_build_object('id', v1, 'title', 'x')); raise exception 'accepted'; exception when object_not_in_prerequisite_state then null; end;
  -- a new mission, then duplicate
  v2 := public.admin_save_mission('{"slug":"t-created","kind":"daily","title":"새 미션","rule_type":"favorite_distinct","target_count":1,"recurrence":"daily","reward_points":2}'::jsonb);
  assert (select status from public.missions where id = v2) = 'draft', 'new missions start as drafts';
  assert public.admin_duplicate_mission(v2) is not null, 'duplicate works';
  begin perform public.admin_set_mission_status(v2, 'active', ''); raise exception 'accepted'; exception when invalid_parameter_value then null; end;
  perform public.admin_set_mission_status(v2, 'active', 'launch');
  s := public.admin_mission_stats(30);
  assert (s ->> 'points_awarded')::int >= 105, 'analytics reads real ledger data';
  raise notice 'OK admin: versioned edits keep history; status changes need a reason';
end $$;
do $$ declare r jsonb; begin
  -- the version bump must not pay user1 again, and keeps their completed state
  reset role;
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  r := public.sync_my_missions();
  assert (select count(*) from public.point_transactions where lineage_id = 'b1000000-0000-4000-8000-000000000001' and kind = 'mission_reward') = 1, 'a new version does not pay the mission a second time';
  assert (r ->> 'points_total')::int = 107, 'only the brand-new daily mission (2) paid: 105 + 2';
  assert (select (x ->> 'completed')::boolean from jsonb_array_elements(r -> 'missions') x where x ->> 'slug' = 't-fav'), 'earlier completion survives the new version';
  reset role;
  raise notice 'OK versioning: earned rewards are neither deleted nor paid twice';
end $$;

select set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-00000000000a","role":"authenticated"}', false);
set role authenticated;
do $$ declare tx bigint; r jsonb; begin
  select id into tx from public.point_transactions where user_id = 'f1000000-0000-4000-8000-000000000001' and kind = 'mission_reward' and points = 20;
  begin perform public.admin_revoke_reward(tx, ''); raise exception 'accepted'; exception when invalid_parameter_value then null; end;
  perform public.admin_revoke_reward(tx, 'fraud: scripted saves');
  begin perform public.admin_revoke_reward(tx, 'again'); raise exception 'accepted'; exception when unique_violation then null; end;
  assert (select sum(points) from public.point_transactions where user_id = 'f1000000-0000-4000-8000-000000000001') = 87, 'balance reduced by the revocation (107 - 20)';
  assert (select count(*) from public.point_transactions where kind = 'revocation' and ref_id = tx) = 1, 'a visible negative row, nothing deleted';
  assert (select count(*) from public.point_transactions where id = tx) = 1, 'the original reward row remains';
  assert public.admin_user_missions('f1000000-0000-4000-8000-000000000001') ->> 'balance' = '87', 'support view shows the balance';
  perform public.admin_revoke_badge('f1000000-0000-4000-8000-000000000001', 'tc_master', 'fraud');
  perform * from public.admin_suspicious_mission_activity(24);
  raise notice 'OK revoke: auditable negative ledger row, once only; badge revocable';
end $$;
reset role;
do $$ declare r jsonb; begin
  -- the revoked period is never paid again
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  r := public.sync_my_missions(); perform public.sync_my_missions();
  assert (select sum(points) from public.point_transactions) = 87, 'revoked rewards are not re-earned';
  assert (select count(*) from public.user_badges where revoked_at is null) = 0, 'a revoked badge stays revoked';
  assert (select count(*) from jsonb_array_elements(r -> 'badges')) = 0, 'and is not shown';
  reset role;
  raise notice 'OK revoked rewards and badges cannot be re-earned';
end $$;

do $$ begin
  assert (select count(*) from public.audit_log where action in ('set_mission_status', 'revoke_reward', 'revoke_badge', 'review_contribution', 'mission_new_version', 'duplicate_mission')) >= 6,
    'admin actions are audited';
  assert (select count(*) from public.audit_log where table_name = 'missions' and action in ('insert', 'update')) >= 3, 'mission row changes are audited by trigger';
  assert (select count(*) from public.audit_log where actor_id = 'f1000000-0000-4000-8000-00000000000a') >= 6, 'with the acting admin recorded';
  raise notice 'OK audit log: every admin change is recorded with its actor';
end $$;
