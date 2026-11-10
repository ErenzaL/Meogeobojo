\set ON_ERROR_STOP on
\pset pager off
-- Admin content upgrade: photos (RLS, one live cover, cover mirror), menu ->
-- Kakao-place sync, featured placement. Every "cannot" is a NEGATIVE test.

insert into auth.users (id, email) values
  ('f2000000-0000-4000-8000-00000000000a', 'c-admin@example.org'),
  ('f2000000-0000-4000-8000-00000000000b', 'c-mod@example.org'),
  ('f2000000-0000-4000-8000-000000000001', 'c-user@example.org');
insert into public.admin_roles (user_id, role) values
  ('f2000000-0000-4000-8000-00000000000a', 'admin'),
  ('f2000000-0000-4000-8000-00000000000b', 'moderator');
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, visibility) values
  ('e2000000-0000-4000-8000-000000000001', 'kp-pub', '공개식당', 'published'),
  ('e2000000-0000-4000-8000-000000000002', 'kp-draft', '초안식당', 'draft');

-- ===== admin: photos, menus =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f2000000-0000-4000-8000-00000000000a","role":"authenticated"}', false);
do $$ declare mid uuid; v text; begin
  insert into public.restaurant_photos (restaurant_id, kind, storage_path, url, caption)
  values ('e2000000-0000-4000-8000-000000000001', 'cover', 'restaurants/a/cover1.webp',
          'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/a/cover1.webp', '입구');
  select image_url into v from public.restaurant_overrides where id = 'e2000000-0000-4000-8000-000000000001';
  assert v like '%cover1.webp', 'the live cover is mirrored to restaurant_overrides.image_url';

  -- a second LIVE cover is refused (one per restaurant)
  begin
    insert into public.restaurant_photos (restaurant_id, kind, storage_path, url)
    values ('e2000000-0000-4000-8000-000000000001', 'cover', 'restaurants/a/cover2.webp', 'https://x/y.webp');
    raise exception 'accepted#1';
  exception when unique_violation then null; end;
  -- archiving the old cover then adding a new one works, and the mirror follows
  update public.restaurant_photos set status = 'archived' where storage_path = 'restaurants/a/cover1.webp';
  insert into public.restaurant_photos (restaurant_id, kind, storage_path, url)
  values ('e2000000-0000-4000-8000-000000000001', 'cover', 'restaurants/a/cover2.webp',
          'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/a/cover2.webp');
  select image_url into v from public.restaurant_overrides where id = 'e2000000-0000-4000-8000-000000000001';
  assert v like '%cover2.webp', 'the mirror follows the new cover';
  -- removing the only live cover clears OUR mirrored link
  delete from public.restaurant_photos where storage_path = 'restaurants/a/cover2.webp';
  select image_url into v from public.restaurant_overrides where id = 'e2000000-0000-4000-8000-000000000001';
  assert v is null, 'no live cover: the mirror is cleared';
  -- ... but a link typed by hand is never wiped
  update public.restaurant_overrides set image_url = 'https://example.org/hand.jpg' where id = 'e2000000-0000-4000-8000-000000000001';
  insert into public.restaurant_photos (restaurant_id, kind, storage_path, url)
  values ('e2000000-0000-4000-8000-000000000001', 'gallery', 'restaurants/a/g1.webp', 'https://x/g1.webp');
  delete from public.restaurant_photos where storage_path = 'restaurants/a/g1.webp';
  select image_url into v from public.restaurant_overrides where id = 'e2000000-0000-4000-8000-000000000001';
  assert v = 'https://example.org/hand.jpg', 'a hand-typed image link survives';
  -- bad rows are refused by constraints
  begin insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values ('e2000000-0000-4000-8000-000000000001', 'gallery', 'p/h.webp', 'http://insecure'); raise exception 'accepted#2'; exception when check_violation then null; end;
  begin insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values ('e2000000-0000-4000-8000-000000000001', 'banner', 'p/b.webp', 'https://x/b'); raise exception 'accepted#3'; exception when check_violation then null; end;
  raise notice 'OK photos: one live cover, mirror, hand link kept, constraints';

  -- menu added by restaurant_id gets the Kakao id the app reads by
  insert into public.restaurant_menus (restaurant_id, name_ko, price_krw, source, category, recommended)
  values ('e2000000-0000-4000-8000-000000000001', '제육 정식', 8000, 'admin', '식사', true) returning id into mid;
  assert (select kakao_place_id from public.restaurant_menus where id = mid) = 'kp-pub', 'menu kakao_place_id filled from the restaurant';
  assert (select status from public.restaurant_menus where id = mid) = 'active', 'menus default to active';
  begin update public.restaurant_menus set status = 'gone' where id = mid; raise exception 'accepted#4'; exception when check_violation then null; end;
  raise notice 'OK menus: kakao_place_id sync, status check';
end $$;
reset role;

-- ===== anon: sees only published photos of published places =====
insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values
  ('e2000000-0000-4000-8000-000000000001', 'gallery', 'restaurants/a/pub.webp', 'https://x/pub.webp'),
  ('e2000000-0000-4000-8000-000000000002', 'gallery', 'restaurants/b/draftplace.webp', 'https://x/dp.webp');
insert into public.restaurant_photos (restaurant_id, kind, storage_path, url, status) values
  ('e2000000-0000-4000-8000-000000000001', 'gallery', 'restaurants/a/old.webp', 'https://x/old.webp', 'archived');
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare n int; begin
  select count(*) into n from public.restaurant_photos;
  assert n = 1, 'anon sees only the published photo of the published restaurant (got ' || n || ')';
  begin insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values ('e2000000-0000-4000-8000-000000000001', 'gallery', 'z.webp', 'https://x/z'); raise exception 'accepted#5'; exception when insufficient_privilege then null; end;
  raise notice 'OK anon: published photos only, no writes';
end $$;
reset role;

-- ===== ordinary user and moderator =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f2000000-0000-4000-8000-000000000001","role":"authenticated"}', false);
do $$ declare n int; begin
  select count(*) into n from public.restaurant_photos; assert n = 1, 'user sees only published';
  insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values ('e2000000-0000-4000-8000-000000000001', 'gallery', 'u.webp', 'https://x/u');
  raise exception 'accepted#6';
exception when insufficient_privilege or others then
  if sqlerrm = 'accepted#6' then raise; end if;
end $$;
do $$ declare n int; begin
  update public.restaurant_photos set caption = 'hacked'; get diagnostics n = row_count; assert n = 0, 'user update touches 0 rows';
  delete from public.restaurant_photos; get diagnostics n = row_count; assert n = 0, 'user delete touches 0 rows';
  update public.restaurant_overrides set featured = true; get diagnostics n = row_count; assert n = 0, 'user cannot feature';
  raise notice 'OK user: cannot write photos or feature restaurants';
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f2000000-0000-4000-8000-00000000000b","role":"authenticated"}', false);
do $$ declare n int; begin
  select count(*) into n from public.restaurant_photos; assert n = 4, 'moderator reads every photo incl. archived and draft places (got ' || n || ')';
  update public.restaurant_photos set caption = 'mod'; get diagnostics n = row_count; assert n = 0, 'moderator cannot edit photos';
  raise notice 'OK moderator: read all, no edits';
end $$;
reset role;

-- ===== audit: photo changes are recorded =====
do $$ begin
  assert (select count(*) from public.audit_log where table_name = 'restaurant_photos') >= 5, 'photo changes are audited';
  raise notice 'OK audit log records photo changes';
end $$;

-- ===== Kakao registration (identity only) =====
insert into public.universities (id, name_ko, name_en, latitude, longitude) values
  ('5c0a8f3e-0001-4a6e-9b1d-000000000001', '순천향대학교', 'Soonchunhyang', 36.76999, 126.9315)
  on conflict (id) do nothing;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f2000000-0000-4000-8000-00000000000a","role":"authenticated"}', false);
do $$ declare r jsonb; o public.restaurant_overrides; places jsonb; n int; begin
  places := '[
    {"id":"1001","place_name":"어굿플레이스","category_group_code":"FD6","category_name":"음식점 > 한식","address_name":"충남 아산시 신창면 읍내리 646","road_address_name":"충남 아산시 신창면 순천향로 22-25","phone":"041-000-0000","x":"126.931458","y":"36.769988"},
    {"id":"1002","place_name":"카페 A","category_group_code":"CE7","category_name":"음식점 > 카페 > 커피전문점","address_name":"주소 2","x":"126.93","y":"36.77"},
    {"id":"9001","place_name":"편의점","category_group_code":"CS2","category_name":"가정,생활 > 편의점","x":"126.93","y":"36.77"},
    {"id":"9002","place_name":"좌표 이상","category_group_code":"FD6","category_name":"음식점 > 한식","x":"36.77","y":"126.93"},
    {"id":"","place_name":"이름만","category_group_code":"FD6","x":"126.9","y":"36.7"}
  ]'::jsonb;
  r := public.admin_register_kakao_places('5c0a8f3e-0001-4a6e-9b1d-000000000001', places);
  assert (r ->> 'added')::int = 2 and (r ->> 'skipped')::int = 3 and (r ->> 'already_managed')::int = 0, 'first registration: 2 added, 3 skipped (non-food, swapped coordinates, no id): ' || r::text;
  select * into o from public.restaurant_overrides where kakao_place_id = '1001';
  assert o.visibility = 'draft' and o.name_ko = '어굿플레이스' and o.kakao_registered_at is not null, 'new places start as draft with the name as a label';
  -- the Kakao response content is NOT stored
  assert o.address is null and o.phone is null and o.latitude is null and o.longitude is null and o.category is null,
    'address, phone, coordinates and category from Kakao are not stored';
  assert not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'restaurant_overrides' and column_name in ('kakao_source', 'kakao_synced_at')), 'no raw Kakao document column';
  assert (select count(*) from public.restaurant_university_links where restaurant_id = o.id) = 1, 'linked to the campus';

  -- an admin edits; registering again must not overwrite anything
  update public.restaurant_overrides set name_ko = '어굿플레이스 (수정)', category = '백반', visibility = 'published' where kakao_place_id = '1001';
  r := public.admin_register_kakao_places('5c0a8f3e-0001-4a6e-9b1d-000000000001', replace(places::text, '어굿플레이스', '이름이 바뀐 카카오')::jsonb);
  assert (r ->> 'added')::int = 0 and (r ->> 'already_managed')::int = 2, 're-registering adds nothing: ' || r::text;
  select * into o from public.restaurant_overrides where kakao_place_id = '1001';
  assert o.name_ko = '어굿플레이스 (수정)' and o.category = '백반' and o.visibility = 'published', 'admin edits survive';
  select count(*) into n from public.restaurant_overrides where kakao_place_id in ('1001', '1002'); assert n = 2, 'no duplicates';
  select count(*) into n from public.restaurant_university_links l join public.restaurant_overrides x on x.id = l.restaurant_id where x.kakao_place_id in ('1001', '1002'); assert n = 2, 'no duplicate campus links';

  -- a hand-made row for the same Kakao id is reused, not duplicated or changed
  insert into public.restaurant_overrides (kakao_place_id, name_ko, visibility) values ('1003', '손으로 만든', 'published');
  perform public.admin_register_kakao_places('5c0a8f3e-0001-4a6e-9b1d-000000000001',
    '[{"id":"1003","place_name":"카카오 이름","category_group_code":"FD6","x":"126.9","y":"36.7"}]');
  select * into o from public.restaurant_overrides where kakao_place_id = '1003';
  assert o.name_ko = '손으로 만든' and o.visibility = 'published', 'existing row untouched';
  select count(*) into n from public.restaurant_overrides where kakao_place_id = '1003'; assert n = 1, 'still one row';

  begin perform public.admin_register_kakao_places('5c0a8f3e-0001-4a6e-9b1d-000000000001', '{"a":1}'); raise exception 'accepted#7'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_register_kakao_places('00000000-0000-4000-8000-000000000000', '[]'); raise exception 'accepted#8'; exception when no_data_found then null; end;
  assert (select count(*) from public.audit_log where action = 'register_kakao_places') = 3, 'registrations are audited';
  raise notice 'OK kakao registration: identity only, validated, deduplicated, edits kept, audited';
end $$;
reset role;

-- not for moderators, users or anon
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f2000000-0000-4000-8000-00000000000b","role":"authenticated"}', false);
do $$ begin
  begin perform public.admin_register_kakao_places('5c0a8f3e-0001-4a6e-9b1d-000000000001', '[]'); raise exception 'accepted#9'; exception when insufficient_privilege then null; end;
  raise notice 'OK kakao registration: moderators refused';
end $$;
select set_config('request.jwt.claims', '{"sub":"f2000000-0000-4000-8000-000000000001","role":"authenticated"}', false);
do $$ begin
  begin perform public.admin_register_kakao_places('5c0a8f3e-0001-4a6e-9b1d-000000000001', '[]'); raise exception 'accepted#10'; exception when insufficient_privilege then null; end;
  raise notice 'OK kakao registration: ordinary users refused';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin perform public.admin_register_kakao_places('5c0a8f3e-0001-4a6e-9b1d-000000000001', '[]'); raise exception 'accepted#11'; exception when insufficient_privilege then null; end;
  raise notice 'OK kakao registration: anon refused';
end $$;
reset role;

-- ===== cafeteria drafts =====
insert into public.campus_cafeterias (id, university_id, kind) values
  ('c2000000-0000-4000-8000-000000000001', '5c0a8f3e-0001-4a6e-9b1d-000000000001', 'student')
  on conflict (id) do nothing;
insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, option_name, menu_items, status, verified_at, extra) values
  ('c2000000-0000-4000-8000-000000000001', '2026-11-16', 'lunch', '', '[{"name_ko":"김치찌개"}]', 'draft', now(), '{"photo_url":"https://x/m.webp","notice":"공지"}'),
  ('c2000000-0000-4000-8000-000000000001', '2026-11-17', 'lunch', '', '[{"name_ko":"돈까스"}]', 'published', now(), '{}');
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'c2000000-0000-4000-8000-000000000001') = 1, 'anon sees only the published meal';
  raise notice 'OK cafeteria: drafts are invisible to the public';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f2000000-0000-4000-8000-00000000000a","role":"authenticated"}', false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'c2000000-0000-4000-8000-000000000001') = 2, 'admin sees drafts too';
  update public.cafeteria_meals set status = 'published' where meal_date = '2026-11-16' and cafeteria_id = 'c2000000-0000-4000-8000-000000000001';
  raise notice 'OK cafeteria: admin reads and publishes a draft';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'c2000000-0000-4000-8000-000000000001') = 2, 'published draft is now public';
  raise notice 'OK cafeteria: publishing makes it appear';
end $$;
reset role;
-- leave no cafeteria fixtures behind for the CSV end-to-end checks that follow
delete from public.campus_cafeterias where id = 'c2000000-0000-4000-8000-000000000001';
