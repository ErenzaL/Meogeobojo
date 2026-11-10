\set ON_ERROR_STOP on
\pset pager off
-- Production readiness: applying (or re-applying) 20261112 .. 20261116 must not change, hide or delete
-- existing live content, photos, menus, missions, points or user progress, and students must still see
-- exactly what they saw. Runs inside a transaction that is rolled back.
begin;

insert into auth.users (id, email) values ('f9000000-0000-4000-8000-000000000001', 'keep-user@example.org');
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, visibility, description, price_min_krw)
  values ('e9000000-0000-4000-8000-000000000001', 'keep-1', '기존 공개식당', 'published', '기존 설명', 8000),
         ('e9000000-0000-4000-8000-000000000002', 'keep-2', '기존 초안식당', 'draft', null, null);
insert into public.restaurant_menus (id, restaurant_id, name_ko, price_krw, source, category, recommended)
  values ('e9100000-0000-4000-8000-000000000001', 'e9000000-0000-4000-8000-000000000001', '기존 메뉴', 8000, 'admin', '식사', true);
insert into public.restaurant_photos (id, restaurant_id, kind, storage_path, url)
  values ('e9200000-0000-4000-8000-000000000001', 'e9000000-0000-4000-8000-000000000001', 'cover', 'restaurants/keep/c.jpg', 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/keep/c.jpg'),
         ('e9200000-0000-4000-8000-000000000002', 'e9000000-0000-4000-8000-000000000001', 'gallery', 'restaurants/keep/g.jpg', 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/keep/g.jpg');
insert into public.app_content (id, kind, title, active) values ('e9300000-0000-4000-8000-000000000001', 'announcement', '기존 공지', true);
insert into public.campus_cafeterias (id, university_id, kind, name_ko) values ('e9400000-0000-4000-8000-000000000001', '5c0a8f3e-0001-4a6e-9b1d-000000000001', 'student', '기존 학식당');
insert into public.cafeteria_meals (id, cafeteria_id, meal_date, meal_type, menu_items, price_krw, verified_at, status)
  values ('e9500000-0000-4000-8000-000000000001', 'e9400000-0000-4000-8000-000000000001', '2026-11-10', 'lunch', '[{"name_ko":"김치찌개","kind":"main"}]', 5500, now(), 'published');
insert into public.monthly_campaigns (id, slug, title, starts_at, ends_at, publish_state)
  values ('e9600000-0000-4000-8000-000000000001', 'keep-camp', '기존 캠페인', now() - interval '1 day', now() + interval '20 days', 'published');
insert into public.missions (id, lineage_id, campaign_id, slug, kind, title, reward_points, rule_type, target_count, recurrence, status)
  values ('e9700000-0000-4000-8000-000000000001', 'e9700000-0000-4000-8000-000000000001', 'e9600000-0000-4000-8000-000000000001', 'keep-m', 'monthly', '기존 미션', 25, 'favorite_distinct', 3, 'none', 'active');
insert into public.user_mission_progress (user_id, mission_id, lineage_id, period_key, progress, target, completed_at)
  values ('f9000000-0000-4000-8000-000000000001', 'e9700000-0000-4000-8000-000000000001', 'e9700000-0000-4000-8000-000000000001', 'once', 3, 3, now());

create temp table before_sum as
select 'restaurant_overrides' t, md5(string_agg(x::text, '|' order by id)) h, count(*) n from public.restaurant_overrides x where id::text like 'e9000000%'
union all select 'restaurant_menus', md5(string_agg(x::text, '|' order by id)), count(*) from public.restaurant_menus x where id::text like 'e9100000%'
union all select 'restaurant_photos', md5(string_agg(x::text, '|' order by id)), count(*) from public.restaurant_photos x where id::text like 'e9200000%'
union all select 'app_content', md5(string_agg(x::text, '|' order by id)), count(*) from public.app_content x where id::text like 'e9300000%'
union all select 'campus_cafeterias', md5(string_agg(x::text, '|' order by id)), count(*) from public.campus_cafeterias x where id::text like 'e9400000%'
union all select 'cafeteria_meals', md5(string_agg(x::text, '|' order by id)), count(*) from public.cafeteria_meals x where id::text like 'e9500000%'
union all select 'monthly_campaigns', md5(string_agg(x::text, '|' order by id)), count(*) from public.monthly_campaigns x where id::text like 'e9600000%'
union all select 'missions', md5(string_agg(x::text, '|' order by id)), count(*) from public.missions x where id::text like 'e9700000%'
union all select 'user_mission_progress', md5(string_agg(x::text, '|' order by id)), count(*) from public.user_mission_progress x where user_id::text like 'f9000000%'
union all select 'universities', md5(string_agg(x::text, '|' order by id)), count(*) from public.universities x;

-- what a student (anon) sees
set local role anon;
create temp table before_anon as
select (select count(*) from public.restaurant_overrides where id::text like 'e9000000%') r,
       (select count(*) from public.restaurant_menus where id::text like 'e9100000%') m,
       (select count(*) from public.restaurant_photos where id::text like 'e9200000%') p,
       (select count(*) from public.app_content where id::text like 'e9300000%') a,
       (select count(*) from public.cafeteria_meals where id::text like 'e9500000%') meals,
       (select count(*) from public.universities) u;
reset role;

\ir ../migrations/20261112000100_realtime_content.sql
\ir ../migrations/20261113000100_cafeteria_management.sql
\ir ../migrations/20261114000100_student_contributions.sql
\ir ../migrations/20261115000100_cms_publishing.sql
\ir ../migrations/20261116000100_cms_health.sql
\ir ../migrations/20261117000100_content_sync_signal.sql

create temp table after_sum as
select 'restaurant_overrides' t, md5(string_agg(x::text, '|' order by id)) h, count(*) n from public.restaurant_overrides x where id::text like 'e9000000%'
union all select 'restaurant_menus', md5(string_agg(x::text, '|' order by id)), count(*) from public.restaurant_menus x where id::text like 'e9100000%'
union all select 'restaurant_photos', md5(string_agg(x::text, '|' order by id)), count(*) from public.restaurant_photos x where id::text like 'e9200000%'
union all select 'app_content', md5(string_agg(x::text, '|' order by id)), count(*) from public.app_content x where id::text like 'e9300000%'
union all select 'campus_cafeterias', md5(string_agg(x::text, '|' order by id)), count(*) from public.campus_cafeterias x where id::text like 'e9400000%'
union all select 'cafeteria_meals', md5(string_agg(x::text, '|' order by id)), count(*) from public.cafeteria_meals x where id::text like 'e9500000%'
union all select 'monthly_campaigns', md5(string_agg(x::text, '|' order by id)), count(*) from public.monthly_campaigns x where id::text like 'e9600000%'
union all select 'missions', md5(string_agg(x::text, '|' order by id)), count(*) from public.missions x where id::text like 'e9700000%'
union all select 'user_mission_progress', md5(string_agg(x::text, '|' order by id)), count(*) from public.user_mission_progress x where user_id::text like 'f9000000%'
union all select 'universities', md5(string_agg(x::text, '|' order by id)), count(*) from public.universities x;

do $$ declare bad text; b record; a record; begin
  select string_agg(t, ', ') into bad from before_sum bs join after_sum af using (t) where bs.h is distinct from af.h or bs.n <> af.n;
  assert bad is null, 'content changed by the migrations: ' || coalesce(bad, '');
  assert (select count(*) from before_sum) = (select count(*) from after_sum), 'same tables compared';
  assert (select n from after_sum where t = 'user_mission_progress') = 1 and (select n from after_sum where t = 'missions') = 1, 'progress and missions are there';
  raise notice 'OK preservation: restaurants, menus, photos, announcements, cafeteria data, campaigns, missions, user progress and universities are byte-for-byte unchanged by 20261112..20261117';
end $$;

set local role anon;
do $$ declare b record; a record; begin
  select * into b from before_anon; 
  select (select count(*) from public.restaurant_overrides where id::text like 'e9000000%') r, (select count(*) from public.restaurant_menus where id::text like 'e9100000%') m,
         (select count(*) from public.restaurant_photos where id::text like 'e9200000%') p, (select count(*) from public.app_content where id::text like 'e9300000%') a,
         (select count(*) from public.cafeteria_meals where id::text like 'e9500000%') meals, (select count(*) from public.universities) u into a;
  assert b = a, 'students see the same rows as before: before ' || b::text || ' after ' || a::text;
  assert a.r = 1 and a.a = 1 and a.meals = 1, 'the published restaurant, announcement and meal are visible; the draft restaurant is not: ' || a::text;
  raise notice 'OK preservation: what students can read is identical before and after the migrations';
end $$;
reset role;

-- the migrations are re-runnable on a populated database (a second pass changes nothing)
\ir ../migrations/20261115000100_cms_publishing.sql
\ir ../migrations/20261116000100_cms_health.sql
\ir ../migrations/20261117000100_content_sync_signal.sql
do $$ begin
  assert (select count(*) from public.restaurant_overrides where id::text like 'e9000000%') = 2 and (select count(*) from public.content_versions where entity_id::text like 'e9%') = 0, 'a second pass changes nothing';
  raise notice 'OK preservation: re-running 20261115 and 20261116 on populated data is harmless';
end $$;

rollback;
