\set ON_ERROR_STOP on
\pset pager off
-- Deleting a restaurant from the Admin = a plain DELETE on restaurant_overrides by a SUPER ADMIN (the existing row-level
-- policy; no new function). This suite proves what that does in the real schema: who can do it, what is removed with it
-- (campus links, menus, photos), what is kept (publishing history, other restaurants), that it is audited, and what the
-- public sees afterwards.

insert into auth.users (id, email) values
  ('fa000000-0000-4000-8000-0000000000a1', 'del-super@example.org'),
  ('fa000000-0000-4000-8000-0000000000b1', 'del-admin@example.org'),
  ('fa000000-0000-4000-8000-0000000000c1', 'del-mod@example.org'),
  ('fa000000-0000-4000-8000-0000000000d1', 'del-user@example.org');
insert into public.admin_roles (user_id, role) values
  ('fa000000-0000-4000-8000-0000000000a1', 'super_admin'),
  ('fa000000-0000-4000-8000-0000000000b1', 'admin'),
  ('fa000000-0000-4000-8000-0000000000c1', 'moderator');
insert into public.universities (id, name_ko, name_en, latitude, longitude) values
  ('5c0a8f3e-0001-4a6e-9b1d-000000000001', '순천향대학교', 'Soonchunhyang', 36.76999, 126.9315) on conflict (id) do nothing;

-- r1: a draft with campus link, a live menu, a photo, a saved draft edit and a publishing history; r2: untouched neighbour; r3: hidden
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, visibility) values
  ('ea000000-0000-4000-8000-000000000001', 'dl-1001', '지울 식당', 'draft'),
  ('ea000000-0000-4000-8000-000000000002', 'dl-1002', '남을 식당', 'draft'),
  ('ea000000-0000-4000-8000-000000000003', 'dl-1003', '숨긴 식당', 'hidden'),
  ('ea000000-0000-4000-8000-000000000004', 'dl-1004', '관리자가 못 지우는 식당', 'draft'),
  ('ea000000-0000-4000-8000-000000000005', 'dl-1005', '다른 사람이 못 지우는 식당', 'draft');
insert into public.restaurant_university_links select id, '5c0a8f3e-0001-4a6e-9b1d-000000000001' from public.restaurant_overrides where kakao_place_id like 'dl-%';
insert into public.restaurant_menus (id, restaurant_id, kakao_place_id, name_ko, price_krw, status, source) values
  ('aa000000-0000-4000-8000-000000000001', 'ea000000-0000-4000-8000-000000000001', 'dl-1001', '국수', 5000, 'active', 'admin'),
  ('aa000000-0000-4000-8000-000000000002', 'ea000000-0000-4000-8000-000000000002', 'dl-1002', '우동', 6000, 'active', 'admin');
insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values
  ('ea000000-0000-4000-8000-000000000001', 'cover', 'restaurants/dl/cover1.webp', 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/dl/cover1.webp'),
  ('ea000000-0000-4000-8000-000000000002', 'cover', 'restaurants/dl/cover2.webp', 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/dl/cover2.webp');

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare s jsonb; begin
  s := public.cms_state('restaurant', 'ea000000-0000-4000-8000-000000000001');
  perform public.cms_save_draft('restaurant', 'ea000000-0000-4000-8000-000000000001', jsonb_set(s -> 'live', '{description}', '"작업 중인 설명"'), 0);
  perform public.cms_set_visibility('restaurant', 'ea000000-0000-4000-8000-000000000001', 'hidden', '테스트 이력');
  perform public.cms_set_visibility('restaurant', 'ea000000-0000-4000-8000-000000000001', 'draft', '테스트 이력 2');
end $$;
reset role;

-- ===== A: only a super admin can delete (the others delete nothing, with no error: row-level security filters the rows) =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ declare n int; begin
  delete from public.restaurant_overrides where id = 'ea000000-0000-4000-8000-000000000004'; get diagnostics n = row_count; assert n = 0, 'an admin deletes nothing';
end $$;
select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ declare n int; begin
  delete from public.restaurant_overrides where id = 'ea000000-0000-4000-8000-000000000004'; get diagnostics n = row_count; assert n = 0, 'a moderator deletes nothing';
end $$;
select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-0000000000d1","role":"authenticated"}', false);
do $$ declare n int; begin
  delete from public.restaurant_overrides where id = 'ea000000-0000-4000-8000-000000000004'; get diagnostics n = row_count; assert n = 0, 'an ordinary user deletes nothing';
end $$;
reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin delete from public.restaurant_overrides where id = 'ea000000-0000-4000-8000-000000000005'; raise exception 'accepted#anon'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert (select count(*) from public.restaurant_overrides where kakao_place_id like 'dl-%') = 5, 'refused callers removed nothing';
  raise notice 'OK only a super admin can delete a restaurant (admin, moderator, user: nothing deleted; anonymous: refused)';
end $$;

-- ===== B: a super admin deletes: the restaurant and what belongs to it go, nothing else =====
create table public._dl_snap (k text primary key, v jsonb);
insert into public._dl_snap select 'neighbour', jsonb_build_object('r', (select to_jsonb(o) from public.restaurant_overrides o where o.id = 'ea000000-0000-4000-8000-000000000002'),
  'menu', (select to_jsonb(m) from public.restaurant_menus m where m.id = 'aa000000-0000-4000-8000-000000000002'),
  'photo', (select to_jsonb(p) - 'id' from public.restaurant_photos p where p.restaurant_id = 'ea000000-0000-4000-8000-000000000002'));
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare n int; begin
  delete from public.restaurant_overrides where id = 'ea000000-0000-4000-8000-000000000001'; get diagnostics n = row_count;
  assert n = 1, 'the super admin deleted exactly one restaurant';
end $$;
reset role;
do $$ begin
  assert not exists (select 1 from public.restaurant_overrides where id = 'ea000000-0000-4000-8000-000000000001'), 'the restaurant is gone';
  assert not exists (select 1 from public.restaurant_university_links where restaurant_id = 'ea000000-0000-4000-8000-000000000001'), 'its campus links went with it';
  assert not exists (select 1 from public.restaurant_menus where restaurant_id = 'ea000000-0000-4000-8000-000000000001'), 'its menus went with it (the live-menu guard does not block the cascade)';
  assert not exists (select 1 from public.restaurant_photos where restaurant_id = 'ea000000-0000-4000-8000-000000000001'), 'its photo rows went with it';
  assert (select count(*) from public.restaurant_overrides where kakao_place_id like 'dl-%') = 4, 'the other four restaurants are all still there';
  assert (select jsonb_build_object('r', (select to_jsonb(o) from public.restaurant_overrides o where o.id = 'ea000000-0000-4000-8000-000000000002'),
            'menu', (select to_jsonb(m) from public.restaurant_menus m where m.id = 'aa000000-0000-4000-8000-000000000002'),
            'photo', (select to_jsonb(p) - 'id' from public.restaurant_photos p where p.restaurant_id = 'ea000000-0000-4000-8000-000000000002'))) = (select v from public._dl_snap where k = 'neighbour'), 'a neighbouring restaurant, its menu and photo are byte-for-byte unchanged';
  raise notice 'OK delete: the restaurant with its campus links, menus and photo rows; every other restaurant untouched';
end $$;

-- ===== C: audited; history kept =====
do $$ begin
  assert (select count(*) from public.audit_log where action = 'delete' and table_name = 'restaurant_overrides' and row_id = 'ea000000-0000-4000-8000-000000000001') = 1, 'the deletion is audited';
  assert (select details -> 'old' ->> 'name_ko' from public.audit_log where action = 'delete' and table_name = 'restaurant_overrides' and row_id = 'ea000000-0000-4000-8000-000000000001') = '지울 식당', 'with the deleted row, so it can be reconstructed';
  assert (select actor_id from public.audit_log where action = 'delete' and table_name = 'restaurant_overrides' and row_id = 'ea000000-0000-4000-8000-000000000001') = 'fa000000-0000-4000-8000-0000000000a1', 'and who did it';
  assert (select count(*) from public.audit_log where action = 'delete' and table_name = 'restaurant_menus' and row_id = 'aa000000-0000-4000-8000-000000000001') = 1, 'its menu removal is audited too';
  assert (select count(*) from public.content_versions where entity_type = 'restaurant' and entity_id = 'ea000000-0000-4000-8000-000000000001') = 2, 'the immutable publishing history is kept';
  raise notice 'OK delete is audited (who, and the whole deleted row); publishing history is kept';
end $$;

-- ===== D: what the public sees =====
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert not exists (select 1 from public.restaurant_overrides where kakao_place_id = 'dl-1001'), 'the public no longer sees it';
  assert not exists (select 1 from public.restaurant_menus where kakao_place_id = 'dl-1001'), 'nor its menus';
  assert not exists (select 1 from public.restaurant_photos where restaurant_id = 'ea000000-0000-4000-8000-000000000001'), 'nor its photos';
  raise notice 'OK public read: nothing of a deleted restaurant remains';
end $$;
reset role;

-- ===== E: what a delete does NOT clean up (documented, harmless) =====
do $$ begin
  assert exists (select 1 from public.content_drafts where entity_type = 'restaurant' and entity_id = 'ea000000-0000-4000-8000-000000000001'), 'a saved draft stays behind as an orphan (admin-only, unreachable from any list)';
  -- the admin list reads by existing restaurants only, so an orphan draft can never be opened; a later restaurant with a new id does not clash
  raise notice 'OK known leftovers: an orphan draft row (admin-only) and the publishing history; nothing the app can read';
end $$;
drop table public._dl_snap;
