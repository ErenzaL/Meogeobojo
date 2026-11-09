-- Admin foundation: roles, audit log, restaurant overrides, menus, cafeteria
-- and university administration, review moderation + reports, user status,
-- app content, image storage.
--
-- Additive and idempotent (safe to re-run). Nothing is dropped except the old
-- "student_reviews: public read" policy, which is replaced by a moderation-aware
-- one. Requires, in this order: 20261031000100 (universities), 20261031000300
-- (phase2 tables, now REQUIRED), 20261101000100 (profiles / set_updated_at),
-- 20261101000600 (cafeterias).
--
-- Security model
--   * Roles live in public.admin_roles. Clients can only READ their own row.
--     Nobody can write it through the API: only the SECURITY DEFINER functions
--     below (super_admin only) or the SQL editor can.
--   * Every table gets RLS. Admin access is decided here, in the database, by
--     public.has_role(); the React app's route guard is only a convenience.
--   * Sensitive operations (role changes, account suspension, review
--     moderation, report resolution) are functions that check the caller's
--     role, record a reason, and write the audit log. Clients get no direct
--     UPDATE on those columns.
--   * Never expose the service-role key to any browser or app.

do $$ begin
  if to_regclass('public.universities') is null
     or to_regclass('public.student_reviews') is null
     or to_regclass('public.restaurant_menus') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.campus_cafeterias') is null
     or to_regclass('public.cafeteria_meals') is null then
    raise exception 'Apply 20261031000100, 20261031000300, 20261101000100 and 20261101000600 first.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
create table if not exists public.admin_roles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null check (role in ('super_admin', 'admin', 'moderator')),
  granted_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.admin_roles enable row level security;

create or replace function public.admin_rank(p_role text) returns integer
language sql immutable as $$
  select case p_role when 'moderator' then 1 when 'admin' then 2 when 'super_admin' then 3 else 0 end
$$;

-- SECURITY DEFINER so policies on other tables can consult admin_roles without
-- clients being able to read it. Evaluates the CALLER (auth.uid()).
create or replace function public.current_admin_rank() returns integer
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select public.admin_rank(r.role) from public.admin_roles r where r.user_id = auth.uid()), 0)
$$;

-- True when the caller has at least role [p_min] (moderator < admin < super_admin).
create or replace function public.has_role(p_min text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select public.admin_rank(p_min) > 0 and public.current_admin_rank() >= public.admin_rank(p_min)
$$;

revoke all on function public.admin_rank(text), public.current_admin_rank(), public.has_role(text)
  from public, anon;
grant execute on function public.admin_rank(text), public.current_admin_rank(), public.has_role(text)
  to authenticated;

revoke all on public.admin_roles from anon, authenticated;
grant select on public.admin_roles to authenticated;
drop policy if exists "admin_roles: read own" on public.admin_roles;
create policy "admin_roles: read own" on public.admin_roles
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "admin_roles: super admin reads all" on public.admin_roles;
create policy "admin_roles: super admin reads all" on public.admin_roles
  for select to authenticated using ((select public.has_role('super_admin')));

-- ---------------------------------------------------------------------------
-- Audit log (append-only; written by triggers / functions, readable by admins)
-- ---------------------------------------------------------------------------
create table if not exists public.audit_log (
  id         bigint generated always as identity primary key,
  actor_id   uuid,                      -- null: service role / SQL editor
  action     text not null,
  table_name text,
  row_id     text,
  reason     text,
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_log_created_idx on public.audit_log (created_at desc);
create index if not exists audit_log_actor_idx on public.audit_log (actor_id, created_at desc);
alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;
drop policy if exists "audit_log: admins read" on public.audit_log;
create policy "audit_log: admins read" on public.audit_log
  for select to authenticated using ((select public.has_role('admin')));

create or replace function public.audit_row_change() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  insert into public.audit_log (actor_id, action, table_name, row_id, details)
  values (
    auth.uid(), lower(tg_op), tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'user_id'),
    case tg_op
      when 'UPDATE' then jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new))
      when 'INSERT' then jsonb_build_object('new', to_jsonb(new))
      else jsonb_build_object('old', to_jsonb(old))
    end);
  return null;
end $$;
revoke all on function public.audit_row_change() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Universities: activation, search radius, address; admin-writable
-- ---------------------------------------------------------------------------
alter table public.universities
  add column if not exists address text,
  add column if not exists is_active boolean not null default true,
  add column if not exists search_radius_m integer not null default 1500;
alter table public.universities drop constraint if exists universities_radius_range;
alter table public.universities add constraint universities_radius_range
  check (search_radius_m between 100 and 5000);
-- Kept: public read of every row (the app filters on is_active).
grant select on public.universities to anon, authenticated;
grant insert, update, delete on public.universities to authenticated;
drop policy if exists "universities: admin insert" on public.universities;
create policy "universities: admin insert" on public.universities
  for insert to authenticated with check ((select public.has_role('admin')));
drop policy if exists "universities: admin update" on public.universities;
create policy "universities: admin update" on public.universities
  for update to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));
drop policy if exists "universities: super admin delete" on public.universities;
create policy "universities: super admin delete" on public.universities
  for delete to authenticated using ((select public.has_role('super_admin')));

-- ---------------------------------------------------------------------------
-- Restaurants. Kakao places are NOT stored: this table holds what WE know or
-- override, keyed by kakao_place_id (null for places an admin created by hand).
-- ---------------------------------------------------------------------------
create table if not exists public.restaurant_overrides (
  id              uuid primary key default gen_random_uuid(),
  kakao_place_id  text unique,
  name_ko         text not null check (btrim(name_ko) <> ''),
  name_en         text,
  category        text,
  address         text,
  latitude        double precision check (latitude  is null or latitude  between -90  and 90),
  longitude       double precision check (longitude is null or longitude between -180 and 180),
  phone           text,
  description     text check (description is null or char_length(description) <= 2000),
  opening_hours   jsonb not null default '{}'::jsonb check (jsonb_typeof(opening_hours) = 'object'),
  break_time      text,
  last_order_time time,
  business_status text check (business_status is null
                    or business_status in ('open', 'temporarily_closed', 'closed')),
  price_min_krw   integer check (price_min_krw is null or price_min_krw >= 0),
  price_max_krw   integer check (price_max_krw is null or price_max_krw >= 0),
  avg_cost_krw    integer check (avg_cost_krw is null or avg_cost_krw >= 0),
  dining_purposes text[] not null default '{}',
  image_url       text check (image_url is null or image_url ~ '^https://'),
  -- draft: admin only. published: shown. hidden / archived: the app must hide
  -- the place (the row stays readable so clients know to hide it).
  visibility      text not null default 'draft'
                    check (visibility in ('draft', 'published', 'hidden', 'archived')),
  created_by      uuid default auth.uid() references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint restaurant_overrides_price_order
    check (price_min_krw is null or price_max_krw is null or price_min_krw <= price_max_krw),
  constraint restaurant_overrides_kakao_id_not_blank
    check (kakao_place_id is null or btrim(kakao_place_id) <> '')
);
create index if not exists restaurant_overrides_visibility_idx on public.restaurant_overrides (visibility);
create index if not exists restaurant_overrides_name_idx on public.restaurant_overrides (name_ko);
drop trigger if exists restaurant_overrides_set_updated_at on public.restaurant_overrides;
create trigger restaurant_overrides_set_updated_at
  before update on public.restaurant_overrides
  for each row execute function public.set_updated_at();

-- Many-to-many. Deleting a university removes only the links, never restaurants.
create table if not exists public.restaurant_university_links (
  restaurant_id uuid not null references public.restaurant_overrides (id) on delete cascade,
  university_id uuid not null references public.universities (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (restaurant_id, university_id)
);
create index if not exists restaurant_university_links_uni_idx
  on public.restaurant_university_links (university_id);

alter table public.restaurant_overrides        enable row level security;
alter table public.restaurant_university_links enable row level security;
revoke all on public.restaurant_overrides, public.restaurant_university_links from anon, authenticated;
grant select on public.restaurant_overrides, public.restaurant_university_links to anon, authenticated;
grant insert, update, delete on public.restaurant_overrides, public.restaurant_university_links to authenticated;

drop policy if exists "restaurant_overrides: public read" on public.restaurant_overrides;
create policy "restaurant_overrides: public read" on public.restaurant_overrides
  for select to anon, authenticated using (visibility <> 'draft');
drop policy if exists "restaurant_overrides: admin read all" on public.restaurant_overrides;
create policy "restaurant_overrides: admin read all" on public.restaurant_overrides
  for select to authenticated using ((select public.has_role('moderator')));
drop policy if exists "restaurant_overrides: admin insert" on public.restaurant_overrides;
create policy "restaurant_overrides: admin insert" on public.restaurant_overrides
  for insert to authenticated with check ((select public.has_role('admin')));
drop policy if exists "restaurant_overrides: admin update" on public.restaurant_overrides;
create policy "restaurant_overrides: admin update" on public.restaurant_overrides
  for update to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));
drop policy if exists "restaurant_overrides: super admin delete" on public.restaurant_overrides;
create policy "restaurant_overrides: super admin delete" on public.restaurant_overrides
  for delete to authenticated using ((select public.has_role('super_admin')));

drop policy if exists "restaurant_university_links: public read" on public.restaurant_university_links;
create policy "restaurant_university_links: public read" on public.restaurant_university_links
  for select to anon, authenticated using (true);
drop policy if exists "restaurant_university_links: admin write" on public.restaurant_university_links;
create policy "restaurant_university_links: admin write" on public.restaurant_university_links
  for all to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));

-- ---------------------------------------------------------------------------
-- Menus: usable for Kakao places (kakao_place_id) and hand-made restaurants.
-- ---------------------------------------------------------------------------
alter table public.restaurant_menus
  add column if not exists restaurant_id  uuid references public.restaurant_overrides (id) on delete cascade,
  add column if not exists available      boolean not null default true,
  add column if not exists representative boolean not null default false,
  add column if not exists sort_order     integer not null default 0,
  add column if not exists image_url      text,
  add column if not exists updated_at     timestamptz not null default now();
alter table public.restaurant_menus alter column kakao_place_id drop not null;
alter table public.restaurant_menus drop constraint if exists restaurant_menus_has_owner;
alter table public.restaurant_menus add constraint restaurant_menus_has_owner
  check (kakao_place_id is not null or restaurant_id is not null);
alter table public.restaurant_menus drop constraint if exists restaurant_menus_image_https;
alter table public.restaurant_menus add constraint restaurant_menus_image_https
  check (image_url is null or image_url ~ '^https://');
create index if not exists restaurant_menus_restaurant_idx on public.restaurant_menus (restaurant_id, sort_order);
drop trigger if exists restaurant_menus_set_updated_at on public.restaurant_menus;
create trigger restaurant_menus_set_updated_at
  before update on public.restaurant_menus
  for each row execute function public.set_updated_at();

grant select on public.restaurant_menus to anon, authenticated;
grant insert, update, delete on public.restaurant_menus to authenticated;
drop policy if exists "restaurant_menus: admin write" on public.restaurant_menus;
create policy "restaurant_menus: admin write" on public.restaurant_menus
  for all to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));

-- ---------------------------------------------------------------------------
-- Campus cafeterias / meals: administrators may write (천원의 아침밥, 중식, 석식).
-- `badge` carries a program label such as '천원의 아침밥' ONLY when the source says so.
-- ---------------------------------------------------------------------------
alter table public.cafeteria_meals add column if not exists badge text
  check (badge is null or btrim(badge) <> '');
grant insert, update, delete on public.campus_cafeterias, public.cafeteria_meals to authenticated;
drop policy if exists "campus_cafeterias: admin write" on public.campus_cafeterias;
create policy "campus_cafeterias: admin write" on public.campus_cafeterias
  for all to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));
drop policy if exists "cafeteria_meals: admin write" on public.cafeteria_meals;
create policy "cafeteria_meals: admin write" on public.cafeteria_meals
  for all to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));

-- ---------------------------------------------------------------------------
-- Review moderation
-- ---------------------------------------------------------------------------
alter table public.student_reviews
  add column if not exists moderation_status text not null default 'visible',
  add column if not exists moderation_reason text,
  add column if not exists moderated_by uuid references auth.users (id) on delete set null,
  add column if not exists moderated_at timestamptz;
alter table public.student_reviews drop constraint if exists student_reviews_moderation_status_check;
alter table public.student_reviews add constraint student_reviews_moderation_status_check
  check (moderation_status in ('visible', 'hidden', 'removed'));

drop policy if exists "student_reviews: public read" on public.student_reviews;
drop policy if exists "student_reviews: public read visible" on public.student_reviews;
create policy "student_reviews: public read visible" on public.student_reviews
  for select to anon, authenticated using (moderation_status = 'visible');
drop policy if exists "student_reviews: owner read own" on public.student_reviews;
create policy "student_reviews: owner read own" on public.student_reviews
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "student_reviews: moderators read all" on public.student_reviews;
create policy "student_reviews: moderators read all" on public.student_reviews
  for select to authenticated using ((select public.has_role('moderator')));

-- Owners may write only the content columns; moderation columns change only
-- through public.admin_moderate_review().
revoke all on public.student_reviews from anon, authenticated;
grant select on public.student_reviews to anon, authenticated;
grant insert (kakao_place_id, university_id, rating, body) on public.student_reviews to authenticated;
grant update (rating, body) on public.student_reviews to authenticated;
grant delete on public.student_reviews to authenticated;

-- ---------------------------------------------------------------------------
-- Reports (users file them; moderators resolve them)
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  target_type      text not null check (target_type in ('review', 'restaurant', 'user')),
  target_id        text not null check (btrim(target_id) <> ''),
  reason           text not null check (btrim(reason) <> '' and char_length(reason) <= 200),
  description      text check (description is null or char_length(description) <= 2000),
  status           text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  resolution_notes text,
  resolved_by      uuid references auth.users (id) on delete set null,
  resolved_at      timestamptz,
  created_at       timestamptz not null default now()
);
create index if not exists reports_status_idx on public.reports (status, created_at desc);
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;
grant insert (target_type, target_id, reason, description) on public.reports to authenticated;
drop policy if exists "reports: reporter insert" on public.reports;
create policy "reports: reporter insert" on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()) and status = 'open');
drop policy if exists "reports: reporter read own" on public.reports;
create policy "reports: reporter read own" on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));
drop policy if exists "reports: moderators read all" on public.reports;
create policy "reports: moderators read all" on public.reports
  for select to authenticated using ((select public.has_role('moderator')));

-- ---------------------------------------------------------------------------
-- User accounts: status (admin-changed through a function only)
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists account_status text not null default 'active';
alter table public.profiles drop constraint if exists profiles_account_status_check;
alter table public.profiles add constraint profiles_account_status_check
  check (account_status in ('active', 'suspended'));
drop policy if exists "profiles: admin read" on public.profiles;
create policy "profiles: admin read" on public.profiles
  for select to authenticated using ((select public.has_role('admin')));
-- (No column grant for account_status: users cannot change it.)

-- ---------------------------------------------------------------------------
-- App content: announcements, banners, featured restaurants
-- ---------------------------------------------------------------------------
create table if not exists public.app_content (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null check (kind in ('announcement', 'banner', 'featured')),
  title          text not null check (btrim(title) <> ''),
  body           text,
  image_url      text check (image_url is null or image_url ~ '^https://'),
  link_url       text check (link_url is null or link_url ~ '^https://'),
  kakao_place_id text,
  university_id  uuid references public.universities (id) on delete cascade,
  active         boolean not null default false,
  sort_order     integer not null default 0,
  starts_at      timestamptz,
  ends_at        timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint app_content_window check (starts_at is null or ends_at is null or starts_at < ends_at)
);
create index if not exists app_content_kind_idx on public.app_content (kind, active, sort_order);
drop trigger if exists app_content_set_updated_at on public.app_content;
create trigger app_content_set_updated_at
  before update on public.app_content
  for each row execute function public.set_updated_at();
alter table public.app_content enable row level security;
revoke all on public.app_content from anon, authenticated;
grant select on public.app_content to anon, authenticated;
grant insert, update, delete on public.app_content to authenticated;
drop policy if exists "app_content: public read live" on public.app_content;
create policy "app_content: public read live" on public.app_content
  for select to anon, authenticated
  using (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
drop policy if exists "app_content: admin read all" on public.app_content;
create policy "app_content: admin read all" on public.app_content
  for select to authenticated using ((select public.has_role('moderator')));
drop policy if exists "app_content: admin write" on public.app_content;
create policy "app_content: admin write" on public.app_content
  for all to authenticated
  using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));

-- ---------------------------------------------------------------------------
-- Privileged operations (checked in the database, audited with a reason)
-- ---------------------------------------------------------------------------
create or replace function public._require_role(p_min text) returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.has_role(p_min) then
    raise exception 'insufficient privileges' using errcode = '42501';
  end if;
end $$;
revoke all on function public._require_role(text) from public, anon, authenticated;

create or replace function public.admin_grant_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('super_admin');
  if p_role not in ('super_admin', 'admin', 'moderator') then
    raise exception 'unknown role' using errcode = '22023';
  end if;
  insert into public.admin_roles (user_id, role, granted_by)
  values (p_user, p_role, auth.uid())
  on conflict (user_id) do update set role = excluded.role, granted_by = excluded.granted_by;
end $$;

create or replace function public.admin_revoke_role(p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('super_admin');
  if (select role from public.admin_roles where user_id = p_user) = 'super_admin'
     and (select count(*) from public.admin_roles where role = 'super_admin') <= 1 then
    raise exception 'cannot remove the last super_admin' using errcode = '23514';
  end if;
  delete from public.admin_roles where user_id = p_user;
end $$;

create or replace function public.admin_set_account_status(p_user uuid, p_status text, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  if p_status not in ('active', 'suspended') then
    raise exception 'unknown status' using errcode = '22023';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  -- Admins cannot act on other staff; only a super_admin can.
  if exists (select 1 from public.admin_roles where user_id = p_user)
     and not public.has_role('super_admin') then
    raise exception 'insufficient privileges' using errcode = '42501';
  end if;
  update public.profiles set account_status = p_status where id = p_user;
  if not found then raise exception 'no such profile' using errcode = 'P0002'; end if;
  insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
  values (auth.uid(), 'set_account_status', 'profiles', p_user::text, p_reason,
          jsonb_build_object('status', p_status));
end $$;

create or replace function public.admin_moderate_review(p_review uuid, p_status text, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('moderator');
  if p_status not in ('visible', 'hidden', 'removed') then
    raise exception 'unknown status' using errcode = '22023';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  update public.student_reviews
     set moderation_status = p_status, moderation_reason = p_reason,
         moderated_by = auth.uid(), moderated_at = now()
   where id = p_review;
  if not found then raise exception 'no such review' using errcode = 'P0002'; end if;
  insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
  values (auth.uid(), 'moderate_review', 'student_reviews', p_review::text, p_reason,
          jsonb_build_object('status', p_status));
end $$;

create or replace function public.admin_resolve_report(p_report uuid, p_status text, p_notes text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('moderator');
  if p_status not in ('open', 'resolved', 'dismissed') then
    raise exception 'unknown status' using errcode = '22023';
  end if;
  if p_status <> 'open' and (p_notes is null or btrim(p_notes) = '') then
    raise exception 'resolution notes are required' using errcode = '22023';
  end if;
  update public.reports
     set status = p_status, resolution_notes = p_notes,
         resolved_by = case when p_status = 'open' then null else auth.uid() end,
         resolved_at = case when p_status = 'open' then null else now() end
   where id = p_report;
  if not found then raise exception 'no such report' using errcode = 'P0002'; end if;
  insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
  values (auth.uid(), 'resolve_report', 'reports', p_report::text, p_notes,
          jsonb_build_object('status', p_status));
end $$;

revoke all on function public.admin_grant_role(uuid, text), public.admin_revoke_role(uuid),
  public.admin_set_account_status(uuid, text, text), public.admin_moderate_review(uuid, text, text),
  public.admin_resolve_report(uuid, text, text) from public, anon;
grant execute on function public.admin_grant_role(uuid, text), public.admin_revoke_role(uuid),
  public.admin_set_account_status(uuid, text, text), public.admin_moderate_review(uuid, text, text),
  public.admin_resolve_report(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Audit triggers on every admin-writable table
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['restaurant_overrides', 'restaurant_university_links', 'restaurant_menus',
                           'campus_cafeterias', 'cafeteria_meals', 'universities', 'app_content', 'admin_roles']
  loop
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.audit_row_change()', t || '_audit', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Storage: public-read bucket for restaurant / menu / content images, written
-- only by admins. Applied only where Supabase Storage exists.
-- ---------------------------------------------------------------------------
do $$ begin
  if to_regclass('storage.objects') is not null and to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('restaurant-images', 'restaurant-images', true, 5242880,
            array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update
      set public = true, file_size_limit = 5242880,
          allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

    drop policy if exists "restaurant-images: public read" on storage.objects;
    create policy "restaurant-images: public read" on storage.objects
      for select to anon, authenticated using (bucket_id = 'restaurant-images');
    drop policy if exists "restaurant-images: admin insert" on storage.objects;
    create policy "restaurant-images: admin insert" on storage.objects
      for insert to authenticated
      with check (bucket_id = 'restaurant-images' and (select public.has_role('admin')));
    drop policy if exists "restaurant-images: admin update" on storage.objects;
    create policy "restaurant-images: admin update" on storage.objects
      for update to authenticated
      using (bucket_id = 'restaurant-images' and (select public.has_role('admin')))
      with check (bucket_id = 'restaurant-images' and (select public.has_role('admin')));
    drop policy if exists "restaurant-images: admin delete" on storage.objects;
    create policy "restaurant-images: admin delete" on storage.objects
      for delete to authenticated
      using (bucket_id = 'restaurant-images' and (select public.has_role('admin')));
  end if;
end $$;
