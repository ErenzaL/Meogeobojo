\set ON_ERROR_STOP on
\pset pager off
-- Bulk publish / hide = the Admin calling the EXISTING cms_set_visibility once per restaurant (no new database function).
-- This suite runs that exact sequence for incomplete restaurants and proves: only the selected ones change, nothing else is
-- written (menus, photos, descriptions, drafts, "verified" markers), versions + audit entries are made, the public sees
-- the right rows, and the authorization / validation of the single button still applies per restaurant.

insert into auth.users (id, email) values
  ('f5000000-0000-4000-8000-0000000000a1', 'bp-admin@example.org'),
  ('f5000000-0000-4000-8000-0000000000b1', 'bp-mod@example.org'),
  ('f5000000-0000-4000-8000-0000000000c1', 'bp-user@example.org');
insert into public.admin_roles (user_id, role) values
  ('f5000000-0000-4000-8000-0000000000a1', 'admin'),
  ('f5000000-0000-4000-8000-0000000000b1', 'moderator');
insert into public.universities (id, name_ko, name_en, latitude, longitude) values
  ('5c0a8f3e-0001-4a6e-9b1d-000000000001', '순천향대학교', 'Soonchunhyang', 36.76999, 126.9315) on conflict (id) do nothing;

-- 12 imported-style restaurants: 1..10 drafts with NO description / photo / menu, 11 a draft left out of the selection, 12 archived.
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, visibility, kakao_registered_at)
select ('e5000000-0000-4000-8000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'bp-' || lpad(g::text, 2, '0'), '일괄식당' || g,
       case when g = 12 then 'archived' else 'draft' end, now()
  from generate_series(1, 12) g;
insert into public.restaurant_university_links select id, '5c0a8f3e-0001-4a6e-9b1d-000000000001' from public.restaurant_overrides where kakao_place_id like 'bp-%';
-- restaurant 1 has a menu and a photo (published content that bulk publishing must not disturb)
insert into public.restaurant_menus (kakao_place_id, name_ko, price_krw, source) values ('bp-01', '국수', 7000, 'admin');
insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values ('e5000000-0000-4000-8000-000000000001', 'cover', 'restaurants/bp/cover.webp', 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/bp/cover.webp');

-- restaurant 2 has a pending DRAFT edit (an admin's unpublished work)
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare s jsonb; begin
  s := public.cms_state('restaurant', 'e5000000-0000-4000-8000-000000000002');
  perform public.cms_save_draft('restaurant', 'e5000000-0000-4000-8000-000000000002', jsonb_set(s -> 'live', '{description}', '"작업 중인 설명"'), 0);
end $$;
reset role;

-- snapshot everything that must stay as it is
create table public._bp_snap (k text primary key, v jsonb);
insert into public._bp_snap select 'rows', jsonb_agg(to_jsonb(o) - 'visibility' - 'updated_at' order by o.id) from public.restaurant_overrides o where o.kakao_place_id like 'bp-%';
insert into public._bp_snap select 'menus', coalesce(jsonb_agg(to_jsonb(m) order by m.id), '[]') from public.restaurant_menus m;
insert into public._bp_snap select 'photos', coalesce(jsonb_agg(to_jsonb(p) order by p.id), '[]') from public.restaurant_photos p;
insert into public._bp_snap select 'drafts', coalesce(jsonb_agg(to_jsonb(d) order by d.entity_id), '[]') from public.content_drafts d;
insert into public._bp_snap select 'links', coalesce(jsonb_agg(to_jsonb(l) order by l.restaurant_id), '[]') from public.restaurant_university_links l;

-- ===== A: publish 1..10 exactly as the Admin does (one call each, tagged reason) =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare g int; v int; begin
  for g in 1..10 loop
    v := public.cms_set_visibility('restaurant', ('e5000000-0000-4000-8000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'published', '일괄 공개 [ab12cd34]: 개강 시즌');
    assert v = 1, 'first publish is version 1';
  end loop;
end $$;
reset role;
do $$ declare n int; begin
  assert (select count(*) from public.restaurant_overrides where kakao_place_id like 'bp-%' and visibility = 'published') = 10, 'the 10 selected are published';
  assert (select visibility from public.restaurant_overrides where kakao_place_id = 'bp-11') = 'draft', 'a restaurant outside the selection stays a draft';
  assert (select visibility from public.restaurant_overrides where kakao_place_id = 'bp-12') = 'archived', 'an archived restaurant stays archived';
  -- incomplete restaurants publish: photos, menus and descriptions are NOT required
  assert (select count(*) from public.restaurant_overrides where kakao_place_id like 'bp-%' and visibility = 'published' and description is null and image_url is null) >= 9, 'incomplete restaurants were published (no new requirements)';
  -- nothing but visibility (and the row timestamp) changed on any restaurant
  assert (select jsonb_agg(to_jsonb(o) - 'visibility' - 'updated_at' order by o.id) from public.restaurant_overrides o where o.kakao_place_id like 'bp-%') = (select v from public._bp_snap where k = 'rows'),
    'every other column of every restaurant is unchanged (name, description, prices, hours, kakao_registered_at ...)';
  assert (select coalesce(jsonb_agg(to_jsonb(m) order by m.id), '[]') from public.restaurant_menus m) = (select v from public._bp_snap where k = 'menus'), 'menus untouched';
  assert (select coalesce(jsonb_agg(to_jsonb(p) order by p.id), '[]') from public.restaurant_photos p) = (select v from public._bp_snap where k = 'photos'), 'photos untouched';
  assert (select coalesce(jsonb_agg(to_jsonb(l) order by l.restaurant_id), '[]') from public.restaurant_university_links l) = (select v from public._bp_snap where k = 'links'), 'campus links untouched';
  assert (select coalesce(jsonb_agg(to_jsonb(d) order by d.entity_id), '[]') from public.content_drafts d) = (select v from public._bp_snap where k = 'drafts'), 'a pending draft of an admin is untouched';
  assert (select data ->> 'description' from public.content_drafts where entity_id = 'e5000000-0000-4000-8000-000000000002') = '작업 중인 설명', 'the draft text survived publishing';
  -- history and audit, per restaurant
  select count(*) into n from public.content_versions where entity_type = 'restaurant' and entity_id::text like 'e5000000-%' and kind = 'visibility' and reason = '일괄 공개 [ab12cd34]: 개강 시즌' and version = 1; assert n = 10, 'one version per published restaurant';
  assert not exists (select 1 from public.content_versions where entity_id in ('e5000000-0000-4000-8000-000000000011', 'e5000000-0000-4000-8000-000000000012')), 'no version for restaurants outside the selection';
  select count(*) into n from public.audit_log where action = 'cms_visibility' and reason like '일괄 공개 [ab12cd34]%'; assert n = 10, 'one audit entry per restaurant, carrying the batch tag';
  assert (select count(*) from public.audit_log where actor_id = 'f5000000-0000-4000-8000-0000000000a1' and action = 'cms_visibility') = 10, 'attributed to the admin who did it';
  raise notice 'OK bulk publish: only the selected restaurants, nothing else written, versions + audit per restaurant, drafts kept';
end $$;

-- ===== B: what the public (the app and the website) can read =====
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.restaurant_overrides where kakao_place_id like 'bp-%' and visibility = 'published') = 10, 'the public reads the 10 published restaurants';
  assert not exists (select 1 from public.restaurant_overrides where kakao_place_id = 'bp-11'), 'a draft stays invisible to the public (RLS)';
  raise notice 'OK public read: published restaurants visible, drafts not';
end $$;
reset role;

-- ===== C: the database does NOT deduplicate: that is why the Admin skips restaurants that are already published =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare v int; begin
  v := public.cms_set_visibility('restaurant', 'e5000000-0000-4000-8000-000000000003', 'published', 'again');
  assert v = 2, 'publishing an already-published restaurant writes version 2 (and an audit entry): the Admin must not send those';
end $$;
reset role;
do $$ begin raise notice 'OK repeat call is a new version (documented: bulk skips already-published ones client-side after re-reading the status)'; end $$;

-- ===== D: bulk hide =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare g int; begin
  for g in 4..6 loop perform public.cms_set_visibility('restaurant', ('e5000000-0000-4000-8000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'hidden', '일괄 숨김 [00000001]: 점검'); end loop;
end $$;
reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.restaurant_overrides where kakao_place_id like 'bp-%' and visibility = 'published') = 7, 'after hiding 3, the public sees 7 published';
  raise notice 'OK bulk hide: hidden restaurants are no longer published';
end $$;
reset role;

-- ===== E: authorization is the database's, per call =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_set_visibility('restaurant', 'e5000000-0000-4000-8000-000000000011', 'published', 'x'); raise exception 'accepted#moderator'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_set_visibility('restaurant', 'e5000000-0000-4000-8000-000000000011', 'published', 'x'); raise exception 'accepted#user'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin perform public.cms_set_visibility('restaurant', 'e5000000-0000-4000-8000-000000000011', 'published', 'x'); raise exception 'accepted#anon'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert (select visibility from public.restaurant_overrides where kakao_place_id = 'bp-11') = 'draft', 'refused callers changed nothing';
  raise notice 'OK moderators, ordinary users and anonymous callers cannot publish (SQLSTATE 42501)';
end $$;

-- ===== F: the single-restaurant validation still applies to every restaurant of a bulk run =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_set_visibility('restaurant', 'e5000000-0000-4000-8000-000000000011', 'published', ''); raise exception 'accepted#noreason'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_set_visibility('restaurant', 'e5000000-0000-4000-8000-000000000011', 'live', 'x'); raise exception 'accepted#badstatus'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_set_visibility('restaurant', '00000000-0000-4000-8000-0000000000ff', 'published', 'x'); raise exception 'accepted#missing'; exception when no_data_found then null; end;
  raise notice 'OK a reason is required, the status must be valid, a missing restaurant is refused';
end $$;
reset role;
-- a restaurant whose data would fail the publication rules (inverted price range): refused, stays a draft, others unaffected
do $$ declare ok boolean := true; begin
  begin
    insert into public.restaurant_overrides (id, kakao_place_id, name_ko, visibility, price_min_krw, price_max_krw) values ('e5000000-0000-4000-8000-000000000013', 'bp-13', '가격이상', 'draft', 9000, 1000);
  exception when check_violation then ok := false;
  end;
  if ok then
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"f5000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
    begin perform public.cms_set_visibility('restaurant', 'e5000000-0000-4000-8000-000000000013', 'published', 'x'); raise exception 'accepted#invalid'; exception when invalid_parameter_value then null; end;
    reset role;
    assert (select visibility from public.restaurant_overrides where kakao_place_id = 'bp-13') = 'draft', 'a restaurant that fails validation stays a draft';
    raise notice 'OK a restaurant that fails the publication rules is refused and stays a draft';
  else
    raise notice 'OK (the table itself already refuses an inverted price range)';
  end if;
end $$;
drop table public._bp_snap;
