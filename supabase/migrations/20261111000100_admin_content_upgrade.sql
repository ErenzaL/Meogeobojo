-- Admin content upgrade: restaurant photos (cover + gallery), richer menus,
-- featured placement, and a menu -> Kakao-place sync fix.
--
-- Additive and idempotent. Nothing is dropped; existing rows keep their data.
-- Requires 20261109000100_admin_foundation.sql (has_role, audit_row_change,
-- restaurant_overrides, restaurant_menus, the 'restaurant-images' bucket).
--
-- Security model
--   * Photos and menus are written ONLY by admins (RLS via has_role). The
--     browser uses the publishable key; the database decides.
--   * The public (anon) can read only PUBLISHED photos of PUBLISHED places.
--   * Kakao source data is never stored here; photos are first-party uploads
--     that carry their own source / credit so ownership stays visible.

do $$ begin
  if to_regclass('public.restaurant_overrides') is null
     or to_regclass('public.restaurant_menus') is null
     or to_regprocedure('public.has_role(text)') is null
     or to_regprocedure('public._audit(text, text, text, text, jsonb)') is null then
    raise exception 'Apply 20261109000100_admin_foundation.sql and 20261110000100_missions.sql first.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Featured placement and verification on the existing override row.
-- (Tags such as 혼밥 / 단체석 / 카공 reuse the existing dining_purposes column.)
-- ---------------------------------------------------------------------------
alter table public.restaurant_overrides
  add column if not exists featured      boolean not null default false,
  add column if not exists display_order integer,
  add column if not exists verified_at   timestamptz,
  -- When an admin registered this Kakao place for management. Kakao's own
  -- response data (address, phone, coordinates, category path, ...) is NOT
  -- stored: Kakao's operating policy restricts caching of Local API results,
  -- so only the place ID, its name as a management label, and OUR data live here.
  add column if not exists kakao_registered_at timestamptz;
create index if not exists restaurant_overrides_featured_idx
  on public.restaurant_overrides (featured, display_order) where featured;

-- ---------------------------------------------------------------------------
-- Menus: category, recommended flag, price verification date, archiving.
-- ---------------------------------------------------------------------------
alter table public.restaurant_menus
  add column if not exists category          text check (category is null or char_length(category) <= 30),
  add column if not exists recommended       boolean not null default false,
  add column if not exists price_verified_on date,
  add column if not exists status            text not null default 'active';
alter table public.restaurant_menus drop constraint if exists restaurant_menus_status_check;
alter table public.restaurant_menus add constraint restaurant_menus_status_check
  check (status in ('active', 'archived'));

-- THE SYNC FIX: the app reads menus by kakao_place_id, but the dashboard
-- stores them by restaurant_id. Keep kakao_place_id filled from the restaurant
-- so a menu an admin adds really shows up in the app.
create or replace function public.restaurant_menus_fill_place() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if new.restaurant_id is not null
     and (new.kakao_place_id is null or tg_op = 'INSERT') then
    select o.kakao_place_id into new.kakao_place_id
      from public.restaurant_overrides o where o.id = new.restaurant_id;
  end if;
  return new;
end $$;
drop trigger if exists restaurant_menus_fill_place on public.restaurant_menus;
create trigger restaurant_menus_fill_place
  before insert or update of restaurant_id, kakao_place_id on public.restaurant_menus
  for each row execute function public.restaurant_menus_fill_place();
-- Repair menus already saved by the dashboard.
update public.restaurant_menus m set kakao_place_id = o.kakao_place_id
  from public.restaurant_overrides o
 where m.restaurant_id = o.id and m.kakao_place_id is null and o.kakao_place_id is not null;

-- ---------------------------------------------------------------------------
-- restaurant_photos: one live cover + a gallery per restaurant.
-- The file lives in Storage ('restaurant-images'); this row is its record.
-- ---------------------------------------------------------------------------
create table if not exists public.restaurant_photos (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_overrides (id) on delete cascade,
  kind          text not null check (kind in ('cover', 'gallery')),
  storage_path  text not null unique check (btrim(storage_path) <> ''),
  url           text not null check (url ~ '^https://'),
  caption       text check (caption is null or char_length(caption) <= 200),
  sort_order    integer not null default 0,
  status        text not null default 'published' check (status in ('published', 'archived')),
  -- ownership / licence: 'admin' (the team's own photo) or 'student' (approved
  -- contribution; credit says who agreed to be named).
  source        text not null default 'admin' check (source in ('admin', 'student')),
  credit        text check (credit is null or char_length(credit) <= 100),
  width         integer check (width is null or width > 0),
  height        integer check (height is null or height > 0),
  bytes         integer check (bytes is null or bytes > 0),
  uploaded_by   uuid default auth.uid() references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists restaurant_photos_restaurant_idx
  on public.restaurant_photos (restaurant_id, status, kind, sort_order);
-- At most one live cover per restaurant.
create unique index if not exists restaurant_photos_one_cover
  on public.restaurant_photos (restaurant_id) where kind = 'cover' and status = 'published';
drop trigger if exists restaurant_photos_set_updated_at on public.restaurant_photos;
create trigger restaurant_photos_set_updated_at before update on public.restaurant_photos
  for each row execute function public.set_updated_at();

alter table public.restaurant_photos enable row level security;
revoke all on public.restaurant_photos from anon, authenticated;
grant select on public.restaurant_photos to anon, authenticated;
grant insert, update, delete on public.restaurant_photos to authenticated;

drop policy if exists "restaurant_photos: public read published" on public.restaurant_photos;
create policy "restaurant_photos: public read published" on public.restaurant_photos
  for select to anon, authenticated using (
    status = 'published' and exists (
      select 1 from public.restaurant_overrides o
       where o.id = restaurant_id and o.visibility = 'published'));
drop policy if exists "restaurant_photos: moderators read all" on public.restaurant_photos;
create policy "restaurant_photos: moderators read all" on public.restaurant_photos
  for select to authenticated using ((select public.has_role('moderator')));
drop policy if exists "restaurant_photos: admin write" on public.restaurant_photos;
create policy "restaurant_photos: admin write" on public.restaurant_photos
  for all to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));

drop trigger if exists restaurant_photos_audit on public.restaurant_photos;
create trigger restaurant_photos_audit after insert or update or delete on public.restaurant_photos
  for each row execute function public.audit_row_change();

-- The app's cards already read restaurant_overrides.image_url, so the live
-- cover is mirrored there: one source of truth, no second code path.
create or replace function public.restaurant_photos_sync_cover() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_rid uuid := coalesce(new.restaurant_id, old.restaurant_id);
  v_url text;
begin
  select p.url into v_url from public.restaurant_photos p
   where p.restaurant_id = v_rid and p.kind = 'cover' and p.status = 'published' limit 1;
  if v_url is not null then
    update public.restaurant_overrides set image_url = v_url where id = v_rid;
  else
    -- no live cover: clear the mirror only if it points at one of OUR files, so
    -- a link an admin typed by hand is never wiped.
    update public.restaurant_overrides set image_url = null
     where id = v_rid and image_url like '%/storage/v1/object/public/restaurant-images/%';
  end if;
  return null;
end $$;
revoke all on function public.restaurant_photos_sync_cover() from public, anon, authenticated;
drop trigger if exists restaurant_photos_sync_cover on public.restaurant_photos;
create trigger restaurant_photos_sync_cover after insert or update or delete on public.restaurant_photos
  for each row execute function public.restaurant_photos_sync_cover();

-- Storage: unchanged bucket, but record the same limits here for clarity.
-- (5 MB, JPEG / PNG / WebP, admin-only writes: see 20261109000100.)

-- ---------------------------------------------------------------------------
-- Registering Kakao places for management (the shared catalog)
--
-- The app discovers places live through the deployed `search_restaurants` Edge
-- Function and keeps them only in memory. This function lets an administrator
-- REGISTER chosen places, keyed by the stable kakao_place_id, so they can be
-- managed, published and enriched.
--
-- Only identity / management metadata is stored: kakao_place_id and the
-- place's name as a label (editable by the admin), plus our own fields. The
-- rest of the Kakao document is validated here and then DISCARDED; address,
-- phone, coordinates and category are fetched live when they are needed.
--
--   * NEW place   -> one restaurant_overrides row (draft) + a campus link.
--   * KNOWN place -> nothing is overwritten; only the campus link is added.
--   * Re-running the same registration changes nothing.
-- The caller must be an admin; the call is validated here and audited.
-- ---------------------------------------------------------------------------
create or replace function public.admin_register_kakao_places(p_university uuid, p_places jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  d        jsonb;
  v_id     text;
  v_name   text;
  v_lat    double precision;
  v_lng    double precision;
  v_group  text;
  v_rid    uuid;
  v_new    boolean;
  v_added  integer := 0;
  v_known  integer := 0;
  v_skip   integer := 0;
begin
  perform public._require_role('admin');
  if not exists (select 1 from public.universities where id = p_university) then
    raise exception 'unknown university' using errcode = 'P0002';
  end if;
  if p_places is null or jsonb_typeof(p_places) <> 'array' then
    raise exception 'places must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_places) > 500 then
    raise exception 'too many places in one registration (max 500)' using errcode = '22023';
  end if;

  for d in select * from jsonb_array_elements(p_places) loop
    v_id    := nullif(btrim(d ->> 'id'), '');
    v_name  := nullif(btrim(d ->> 'place_name'), '');
    v_group := d ->> 'category_group_code';
    -- Kakao: x = longitude, y = latitude (as text). Validated, never stored.
    begin
      v_lng := (d ->> 'x')::double precision;
      v_lat := (d ->> 'y')::double precision;
    exception when others then v_lng := null; v_lat := null;
    end;
    if v_id is null or char_length(v_id) > 40 or v_name is null
       or v_group is null or v_group not in ('FD6', 'CE7')
       or v_lat is null or v_lng is null
       or v_lat not between 33 and 39 or v_lng not between 124 and 132 then
      v_skip := v_skip + 1;
      continue;
    end if;

    insert into public.restaurant_overrides as o
      (kakao_place_id, name_ko, visibility, kakao_registered_at)
    values (v_id, left(v_name, 120), 'draft', now())
    on conflict (kakao_place_id) do update set kakao_registered_at = coalesce(o.kakao_registered_at, now())
    returning o.id, (xmax = 0) into v_rid, v_new;

    insert into public.restaurant_university_links (restaurant_id, university_id)
    values (v_rid, p_university) on conflict do nothing;

    if v_new then v_added := v_added + 1; else v_known := v_known + 1; end if;
  end loop;

  perform public._audit('register_kakao_places', 'restaurant_overrides', p_university::text, null,
    jsonb_build_object('added', v_added, 'already_managed', v_known, 'skipped', v_skip));
  return jsonb_build_object('added', v_added, 'already_managed', v_known, 'skipped', v_skip);
end $$;
revoke all on function public.admin_register_kakao_places(uuid, jsonb) from public, anon;
grant execute on function public.admin_register_kakao_places(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Cafeteria meals: a DRAFT state, invisible to the public until published.
-- (Meal photos and notices live in the existing `extra` jsonb:
--  extra.photo_url / extra.photo_path / extra.notice.)
-- ---------------------------------------------------------------------------
alter table public.cafeteria_meals drop constraint if exists cafeteria_meals_status_check;
alter table public.cafeteria_meals add constraint cafeteria_meals_status_check
  check (status in ('draft', 'published', 'closed', 'no_menu'));
drop policy if exists "cafeteria_meals: public read" on public.cafeteria_meals;
create policy "cafeteria_meals: public read" on public.cafeteria_meals
  for select to anon, authenticated using (status <> 'draft');
drop policy if exists "cafeteria_meals: staff read all" on public.cafeteria_meals;
create policy "cafeteria_meals: staff read all" on public.cafeteria_meals
  for select to authenticated using ((select public.has_role('moderator')));
