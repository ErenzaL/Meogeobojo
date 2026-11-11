\set ON_ERROR_STOP on
\pset pager off
-- CSV menu import = the Admin saving DRAFTS through the EXISTING cms_save_draft('restaurant_menus', ...) (merged onto what the
-- editor shows) and, optionally, publishing them through the existing cms_publish. No new database function. This suite runs
-- exactly that sequence with imported-style data and proves: drafts never touch what is live, restaurants are not touched,
-- publishing puts the menus on the RIGHT restaurant (and its Kakao place id, which the app reads by), unknown prices stay
-- NULL, existing menus survive, a menu id of another restaurant is refused, and only admins can do any of it.

insert into auth.users (id, email) values
  ('f6000000-0000-4000-8000-0000000000a1', 'mi-admin@example.org'),
  ('f6000000-0000-4000-8000-0000000000b1', 'mi-mod@example.org'),
  ('f6000000-0000-4000-8000-0000000000c1', 'mi-user@example.org');
insert into public.admin_roles (user_id, role) values
  ('f6000000-0000-4000-8000-0000000000a1', 'admin'),
  ('f6000000-0000-4000-8000-0000000000b1', 'moderator');
-- r1 is published and already has a published menu; r2 is a draft restaurant without menus
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, visibility) values
  ('e6000000-0000-4000-8000-000000000001', 'mi-1001', '어굿플레이스', 'published'),
  ('e6000000-0000-4000-8000-000000000002', 'mi-1002', '라멘집', 'draft');
insert into public.restaurant_menus (id, restaurant_id, kakao_place_id, name_ko, price_krw, category, price_verified_on, representative, sort_order, source)
  values ('a6000000-0000-4000-8000-0000000000a1', 'e6000000-0000-4000-8000-000000000001', 'mi-1001', '제육 정식', 8000, '식사', '2026-10-01', true, 1, 'admin');

create table public._mi_snap (k text primary key, v jsonb);
insert into public._mi_snap select 'rest', jsonb_agg(to_jsonb(o) order by o.id) from public.restaurant_overrides o where o.kakao_place_id like 'mi-%';
insert into public._mi_snap select 'menus', jsonb_agg(to_jsonb(m) order by m.id) from public.restaurant_menus m;

-- ===== A: the import saves drafts: merged lists, unknown prices NULL; nothing live changes =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare s jsonb; items jsonb; r jsonb; begin
  -- r1: what the editor shows (live, no draft yet) + two imported menus (one with an unknown price)
  s := public.cms_state('restaurant_menus', 'e6000000-0000-4000-8000-000000000001');
  assert (s -> 'draft') = 'null'::jsonb and (s ->> 'live_version')::int = 0, 'no draft yet';
  items := (s -> 'live' -> 'items') || jsonb_build_array(
    jsonb_build_object('id', 'a6000000-0000-4000-8000-0000000000b1', 'name_ko', '우동', 'description_ko', '따뜻한 국물', 'price_krw', 6000, 'category', '면류', 'price_verified_on', null, 'available', true, 'representative', false, 'recommended', false, 'status', 'active', 'sort_order', 2, 'image_url', null),
    jsonb_build_object('id', 'a6000000-0000-4000-8000-0000000000b2', 'name_ko', '김치찌개', 'description_ko', null, 'price_krw', null, 'category', '식사', 'price_verified_on', null, 'available', true, 'representative', false, 'recommended', false, 'status', 'active', 'sort_order', 3, 'image_url', null));
  r := public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000001', jsonb_build_object('items', items), 0);
  assert (r ->> 'revision')::int = 1, 'first draft is revision 1';
  -- r2: only new menus
  r := public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('id', 'a6000000-0000-4000-8000-0000000000c1', 'name_ko', '돈코츠', 'description_ko', '진한 국물, 차슈', 'price_krw', 9000, 'category', '면류', 'price_verified_on', null, 'available', true, 'representative', false, 'recommended', false, 'status', 'active', 'sort_order', 1, 'image_url', null))), 0);
end $$;
reset role;
do $$ begin
  assert (select jsonb_agg(to_jsonb(m) order by m.id) from public.restaurant_menus m) = (select v from public._mi_snap where k = 'menus'), 'saving drafts changes NO live menu row (any restaurant)';
  assert (select jsonb_agg(to_jsonb(o) order by o.id) from public.restaurant_overrides o where o.kakao_place_id like 'mi-%') = (select v from public._mi_snap where k = 'rest'), 'saving drafts does not touch any restaurant (visibility, name ...)';
  assert (select count(*) from public.content_versions where entity_type = 'restaurant_menus' and entity_id::text in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002')) = 0, 'a draft is not a published version';
  assert (select count(*) from public.content_drafts where entity_type = 'restaurant_menus' and entity_id::text in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002')) = 2, 'one draft per restaurant';
  raise notice 'OK import = drafts: live menus and restaurants untouched, one draft per restaurant';
end $$;

-- the public still sees only what was published
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.restaurant_menus where kakao_place_id = 'mi-1001') = 1, 'the public sees only the published menu of r1';
  assert (select count(*) from public.restaurant_menus where kakao_place_id = 'mi-1002') = 0, 'nothing of the imported draft is visible';
  raise notice 'OK public read: imported drafts are invisible until published';
end $$;
reset role;

-- ===== B: an id of ANOTHER restaurant, bad values, stale revision: refused; the draft is unchanged =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare it jsonb := '{"name_ko":"x","description_ko":null,"price_krw":1,"category":null,"price_verified_on":null,"available":true,"representative":false,"recommended":false,"status":"active","sort_order":1,"image_url":null}'; rev int; begin
  select revision into rev from public.content_drafts where entity_id = 'e6000000-0000-4000-8000-000000000002';
  -- the published menu of r1 offered as a menu of r2
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', jsonb_build_object('items', jsonb_build_array(it || '{"id":"a6000000-0000-4000-8000-0000000000a1"}')), rev); raise exception 'accepted#otherrestaurant'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', jsonb_build_object('items', jsonb_build_array(it || '{"id":"a6000000-0000-4000-8000-0000000000d1","price_krw":-5}')), rev); raise exception 'accepted#negative'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', jsonb_build_object('items', jsonb_build_array(it || '{"id":"a6000000-0000-4000-8000-0000000000d1","name_ko":"  "}')), rev); raise exception 'accepted#noname'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', jsonb_build_object('items', jsonb_build_array(it || '{"id":"a6000000-0000-4000-8000-0000000000d1","price_krw":null,"price_verified_on":"2026-11-01"}')), rev); raise exception 'accepted#verifiedwithoutprice'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', jsonb_build_object('items', jsonb_build_array(it || '{"id":"a6000000-0000-4000-8000-0000000000d1"}', it || '{"id":"a6000000-0000-4000-8000-0000000000d1"}')), rev); raise exception 'accepted#duplicateid'; exception when invalid_parameter_value then null; end;
  -- an unknown restaurant
  begin perform public.cms_save_draft('restaurant_menus', '00000000-0000-4000-8000-0000000000ff', '{"items":[]}'::jsonb, 0); raise exception 'accepted#norestaurant'; exception when no_data_found then null; end;
  -- someone else saved first (stale revision)
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', '{"items":[]}'::jsonb, rev + 5); raise exception 'accepted#stale'; exception when serialization_failure then null; end;
  assert (select revision from public.content_drafts where entity_id = 'e6000000-0000-4000-8000-000000000002') = rev, 'refused saves left the draft as it was';
  raise notice 'OK a menu id of another restaurant, negative prices, blank names, orphan verification dates, duplicate ids, unknown restaurants and stale revisions are refused';
end $$;
reset role;

-- ===== C: publishing (optional step of the import) puts the menus on the RIGHT restaurant =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare v1 int; v2 int; begin
  v1 := public.cms_publish('restaurant_menus', 'e6000000-0000-4000-8000-000000000001', 1, '메뉴 CSV 가져오기');
  v2 := public.cms_publish('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', 1, '메뉴 CSV 가져오기');
  assert v1 = 1 and v2 = 1, 'first versions';
end $$;
reset role;
do $$ begin
  assert (select count(*) from public.restaurant_menus where restaurant_id = 'e6000000-0000-4000-8000-000000000001' and status = 'active') = 3, 'r1 has its old menu plus the two imported ones, all active';
  assert (select count(*) from public.restaurant_menus where restaurant_id = 'e6000000-0000-4000-8000-000000000002' and status = 'active') = 1, 'r2 has its imported menu';
  assert (select count(*) from public.restaurant_menus where status = 'archived' and restaurant_id::text in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002')) = 0, 'nothing was archived or deleted by the import';
  -- the app reads menus by the restaurant's Kakao place id: it was filled from the right restaurant
  assert (select kakao_place_id from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000b1') = 'mi-1001', 'imported menu of r1 carries r1''s Kakao place id';
  assert (select kakao_place_id from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000c1') = 'mi-1002', 'imported menu of r2 carries r2''s Kakao place id';
  assert not exists (select 1 from public.restaurant_menus where kakao_place_id = 'mi-1001' and restaurant_id <> 'e6000000-0000-4000-8000-000000000001'), 'no menu points at the wrong restaurant';
  -- unknown prices are NULL, not 0; nothing was marked verified
  assert (select price_krw from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000b2') is null, 'an unknown price stays NULL (not 0)';
  assert (select count(*) from public.restaurant_menus where price_krw = 0 and restaurant_id::text in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002')) = 0, 'no price became 0';
  assert (select price_verified_on from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000b1') is null and (select price_verified_on from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000b2') is null, 'imported menus are not marked price-verified';
  -- the existing menu is exactly as it was
  -- publishing upserts the whole menu set, so an existing line is rewritten with the same values: only its updated_at moves
  assert (select to_jsonb(m) - 'updated_at' from public.restaurant_menus m where m.id = 'a6000000-0000-4000-8000-0000000000a1') = (select e - 'updated_at' from public._mi_snap s, jsonb_array_elements(s.v) e where s.k = 'menus' and e ->> 'id' = 'a6000000-0000-4000-8000-0000000000a1'), 'the existing menu keeps every value (price, verification date, flags, order, photo)';
  -- restaurants: visibility and everything else unchanged
  assert (select jsonb_agg(to_jsonb(o) order by o.id) from public.restaurant_overrides o where o.kakao_place_id like 'mi-%') = (select v from public._mi_snap where k = 'rest'), 'publishing menus did not change any restaurant (still published / still a draft)';
  assert (select visibility from public.restaurant_overrides where kakao_place_id = 'mi-1002') = 'draft', 'a draft restaurant stays a draft';
  assert (select count(*) from public.content_versions where entity_type = 'restaurant_menus' and reason = '메뉴 CSV 가져오기' and entity_id::text in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002')) = 2, 'one version per restaurant, with the reason';
  assert (select count(*) from public.audit_log where action = 'cms_publish' and table_name = 'restaurant_menus' and row_id in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002')) = 2, 'publishing is audited (one entry per restaurant)';
  assert (select count(*) from public.content_drafts where entity_type = 'restaurant_menus' and entity_id::text in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002')) = 0, 'the published drafts are gone';
  raise notice 'OK publish: right restaurant + Kakao place id, NULL prices kept, nothing archived, existing menu and restaurants untouched, versions + audit';
end $$;

-- ===== D: what the app and the website read after publishing =====
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.restaurant_menus where kakao_place_id = 'mi-1001' and status = 'active') = 3, 'the app reads r1''s 3 menus by its Kakao place id';
  assert (select string_agg(name_ko, ',' order by sort_order) from public.restaurant_menus where kakao_place_id = 'mi-1001' and status = 'active') = '제육 정식,우동,김치찌개', 'in the admin-chosen order';
  assert (select price_krw from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000b2') is null, 'the app receives NULL for an unknown price (it shows "가격 미정")';
  assert (select count(*) from public.restaurant_menus where kakao_place_id = 'mi-1002' and status = 'active') = 1, 'r2''s menu is readable by its place id (shown once the restaurant is published)';
  raise notice 'OK public read after publishing: menus by Kakao place id, in order, NULL price preserved';
end $$;
reset role;

-- ===== E: a later import (update) only changes the lines it names; the rest stays =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare s jsonb; items jsonb; begin
  s := public.cms_state('restaurant_menus', 'e6000000-0000-4000-8000-000000000001');
  -- update mode: 우동's price changes (its verification date, if any, is cleared by the Admin), the other two stay as they are
  items := (select jsonb_agg(case when i ->> 'id' = 'a6000000-0000-4000-8000-0000000000b1' then i || '{"price_krw":6500}' else i end order by (i ->> 'sort_order')::int) from jsonb_array_elements(s -> 'live' -> 'items') i);
  perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000001', jsonb_build_object('items', items), 0);
  assert (select price_krw from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000b1') = 6000, 'the live price is still the old one until published';
  perform public.cms_publish('restaurant_menus', 'e6000000-0000-4000-8000-000000000001', 1, '가격 갱신');
end $$;
reset role;
do $$ begin
  assert (select price_krw from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000b1') = 6500, '우동 changed';
  assert (select price_krw from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000a1') = 8000 and (select representative from public.restaurant_menus where id = 'a6000000-0000-4000-8000-0000000000a1'), 'the others kept their price and flags';
  assert (select count(*) from public.restaurant_menus where restaurant_id = 'e6000000-0000-4000-8000-000000000001' and status = 'active') = 3, 'still 3 menus, none archived';
  assert (select count(*) from public.restaurant_menus where name_ko = '우동' and restaurant_id = 'e6000000-0000-4000-8000-000000000001') = 1, 'a re-import by id does not create a second copy';
  raise notice 'OK update by menu id: only the named line changed, no copy, nothing archived';
end $$;

-- ===== F: authorization: only admins =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', '{"items":[]}'::jsonb, 0); raise exception 'accepted#moderator'; exception when insufficient_privilege then null; end;
  begin perform public.cms_publish('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', 1, 'x'); raise exception 'accepted#moderator-publish'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', '{"items":[]}'::jsonb, 0); raise exception 'accepted#user'; exception when insufficient_privilege then null; end;
  -- direct table writes are refused too: live menus change only by publishing
  begin insert into public.restaurant_menus (restaurant_id, name_ko, source) values ('e6000000-0000-4000-8000-000000000002', '직접 쓰기', 'admin'); raise exception 'accepted#direct-user'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin perform public.cms_save_draft('restaurant_menus', 'e6000000-0000-4000-8000-000000000002', '{"items":[]}'::jsonb, 0); raise exception 'accepted#anon'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  begin insert into public.restaurant_menus (restaurant_id, name_ko, source) values ('e6000000-0000-4000-8000-000000000002', '관리자도 직접은 안 돼요', 'admin'); raise exception 'accepted#direct-admin'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert not exists (select 1 from public.restaurant_menus where name_ko in ('직접 쓰기', '관리자도 직접은 안 돼요')), 'refused writes left nothing behind';
  raise notice 'OK only admins can save or publish menu drafts; nobody (not even an admin) can write live menus directly';
end $$;
drop table public._mi_snap;
