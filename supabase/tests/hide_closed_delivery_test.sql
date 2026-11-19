\set ON_ERROR_STOP on
\pset pager off
-- 20261128000800: the closed and delivery-only places become hidden through the versioned publishing path; nothing else changes.

insert into public.universities (id, name_ko, name_en, latitude, longitude) values
  ('5c0a8f3e-0001-4a6e-9b1d-000000000001', '순천향대학교', 'Soonchunhyang', 36.76999, 126.9315) on conflict (id) do nothing;
delete from public.restaurant_overrides where kakao_place_id in ('1776574319', '18105730', 'hc-neighbour');
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, category, latitude, longitude, visibility) values
  ('ec000000-0000-4000-8000-000000000001', '1776574319', '대학자장 (학생회관)', '음식점 > 중식', 36.769988, 126.931458, 'published'),
  ('ec000000-0000-4000-8000-000000000002', '18105730', '토마토도시락 순천향대점', null, null, null, 'published'),
  ('ec000000-0000-4000-8000-000000000003', 'hc-neighbour', '남을 식당', null, null, null, 'published');
insert into public.restaurant_university_links select id, '5c0a8f3e-0001-4a6e-9b1d-000000000001' from public.restaurant_overrides
  where id::text like 'ec000000-%';

\ir ../migrations/20261128000800_hide_closed_and_delivery_only.sql
\ir ../migrations/20261128000800_hide_closed_and_delivery_only.sql

do $$ begin
  assert (select visibility from public.restaurant_overrides where kakao_place_id = '1776574319') = 'hidden', 'closed place hidden';
  assert (select visibility from public.restaurant_overrides where kakao_place_id = '18105730') = 'hidden', 'delivery-only place hidden';
  assert (select visibility from public.restaurant_overrides where kakao_place_id = 'hc-neighbour') = 'published', 'neighbour untouched';
  assert (select name_ko from public.restaurant_overrides where kakao_place_id = '1776574319') = '대학자장 (학생회관)', 'other fields kept';
  assert exists (select 1 from public.restaurant_university_links where restaurant_id = 'ec000000-0000-4000-8000-000000000001'), 'campus link kept';
  raise notice 'OK hide closed / delivery-only: both hidden, neighbour and fields untouched';
end $$;

do $$ begin
  assert (select count(*) from public.content_versions where entity_type = 'restaurant'
            and entity_id in ('ec000000-0000-4000-8000-000000000001', 'ec000000-0000-4000-8000-000000000002')) = 2,
         'one version each, even after running twice';
  assert (select reason from public.content_versions where entity_id = 'ec000000-0000-4000-8000-000000000002') like '배달 전문%', 'reason recorded';
  assert (select kind from public.content_versions where entity_id = 'ec000000-0000-4000-8000-000000000001') = 'visibility', 'versioned as a visibility change';
  assert exists (select 1 from public.audit_log where action = 'cms_visibility' and row_id = 'ec000000-0000-4000-8000-000000000001'), 'audited';
  raise notice 'OK hide closed / delivery-only: versioned with its reason, audited, idempotent';
end $$;

set role anon;
do $$ begin
  assert not exists (select 1 from public.restaurant_overrides where kakao_place_id in ('1776574319', '18105730') and visibility = 'published'),
         'the app (visibility = published) no longer lists them';
  raise notice 'OK hide closed / delivery-only: the public published list no longer has them';
end $$;
reset role;
