-- Controlled publishing for admin-managed content: draft -> preview -> publish
-- now / schedule -> live, with immutable version history, rollback and a
-- server-side scheduler. Entity types: 'restaurant' (restaurant_overrides) and
-- 'cafeteria_meal' (cafeteria_meals) and 'restaurant_menus' (all menu items of one restaurant,
-- published together; entity id = the restaurant id) and 'restaurant_photos' (the cover and
-- gallery of one restaurant, published together). More types = one branch in each adapter below.
--
-- Additive and idempotent. Requires 20261109000100 (roles, audit) and
-- 20261110000100 (_audit). Applying it changes nothing for students: the LIVE
-- data stays exactly where the app already reads it (restaurant_overrides); what
-- changes is HOW admins may change it.
--
-- Model (no duplicate source of truth)
--   live      the existing row (restaurant_overrides). Only publishing changes it.
--   draft     content_drafts: one pending draft per entity, separate from live.
--   versions  content_versions: IMMUTABLE snapshots of what each publish made
--             live (publish / unpublish / rollback / visibility), numbered 1, 2, ...
--   jobs      publication_jobs: scheduled publish/unpublish, with a FROZEN
--             snapshot, run by pg_cron every minute inside the database.
--
-- Safety
--   * A guard trigger refuses API (authenticated/anon) edits of live restaurant
--     content: it can be changed only by the publishing functions below.
--   * Optimistic concurrency: a draft carries a revision (bumped by every save)
--     and the live version it started from. Saving with a stale revision, or
--     publishing when live moved on, is refused as a conflict.
--   * One scheduled publish per entity; later edits never alter a scheduled
--     snapshot; an immediate publish is refused while one is scheduled.
--   * Publishing is one transaction: validate, apply, record the version. A
--     failure leaves live untouched.
--   * The scheduler rechecks that the scheduler-of-record still has the admin
--     role, that live did not change since scheduling, and revalidates the
--     snapshot. Jobs are locked (skip locked) and status-guarded, so a retry or
--     a second run never publishes twice.
--   * Not for urgent operational actions (account suspension, roles, fraud).

do $$ begin
  if to_regclass('public.restaurant_overrides') is null
     or to_regclass('public.restaurant_university_links') is null
     or to_regclass('public.cafeteria_meals') is null
     or to_regclass('public.restaurant_menus') is null
     or to_regclass('public.restaurant_photos') is null
     or to_regclass('public.missions') is null
     or to_regclass('public.app_content') is null
     or to_regclass('public.monthly_campaigns') is null
     or to_regprocedure('public.has_role(text)') is null
     or to_regprocedure('public._audit(text, text, text, text, jsonb)') is null then
    raise exception 'Apply 20261109000100 and 20261110000100 first.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.content_drafts (
  entity_type  text not null check (entity_type in ('restaurant', 'cafeteria_meal', 'restaurant_menus', 'restaurant_photos', 'mission', 'app_content', 'university', 'campaign')),
  entity_id    uuid not null,
  data         jsonb not null check (jsonb_typeof(data) = 'object'),
  base_version integer not null check (base_version >= 0),
  revision     integer not null default 1 check (revision >= 1),
  created_by   uuid references auth.users (id) on delete set null,
  updated_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (entity_type, entity_id)
);

create table if not exists public.content_versions (
  id               bigint generated always as identity primary key,
  entity_type      text not null check (entity_type in ('restaurant', 'cafeteria_meal', 'restaurant_menus', 'restaurant_photos', 'mission', 'app_content', 'university', 'campaign')),
  entity_id        uuid not null,
  version          integer not null check (version >= 1),
  kind             text not null check (kind in ('publish', 'unpublish', 'rollback', 'visibility')),
  data             jsonb not null check (jsonb_typeof(data) = 'object'),
  reason           text,
  rolled_back_from integer,
  published_by     uuid references auth.users (id) on delete set null,
  published_at     timestamptz not null default now(),
  job_id           bigint,
  constraint content_versions_unique unique (entity_type, entity_id, version)
);
create index if not exists content_versions_entity_idx on public.content_versions (entity_type, entity_id, version desc);

create table if not exists public.publication_jobs (
  id               bigint generated always as identity primary key,
  entity_type      text not null check (entity_type in ('restaurant', 'cafeteria_meal', 'restaurant_menus', 'restaurant_photos', 'mission', 'app_content', 'university', 'campaign')),
  entity_id        uuid not null,
  action           text not null default 'publish' check (action in ('publish', 'unpublish')),
  snapshot         jsonb check (snapshot is null or jsonb_typeof(snapshot) = 'object'),
  base_version     integer not null default 0,
  run_at           timestamptz not null,
  unpublish_at     timestamptz,
  status           text not null default 'scheduled'
                     check (status in ('scheduled', 'running', 'published', 'failed', 'cancelled')),
  reason           text,
  created_by       uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  attempts         integer not null default 0,
  last_error       text,
  executed_at      timestamptz,
  published_version integer,
  parent_job_id    bigint references public.publication_jobs (id) on delete set null,
  constraint publication_jobs_publish_has_snapshot check (action <> 'publish' or snapshot is not null),
  constraint publication_jobs_window check (unpublish_at is null or unpublish_at > run_at)
);
create index if not exists publication_jobs_due_idx on public.publication_jobs (run_at) where status = 'scheduled';
create index if not exists publication_jobs_entity_idx on public.publication_jobs (entity_type, entity_id, created_at desc);
-- At most one scheduled job per entity and action: no duplicate schedules.
create unique index if not exists publication_jobs_one_scheduled
  on public.publication_jobs (entity_type, entity_id, action) where status = 'scheduled';

-- Versions are immutable: no update, no delete (not even by mistake).
create or replace function public.content_versions_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'content_versions is append-only' using errcode = '55000';
end $$;
drop trigger if exists content_versions_no_update on public.content_versions;
create trigger content_versions_no_update before update or delete on public.content_versions
  for each row execute function public.content_versions_immutable();

-- RLS: admins read; nobody writes through the API (functions below do).
alter table public.content_drafts   enable row level security;
alter table public.content_versions enable row level security;
alter table public.publication_jobs enable row level security;
revoke all on public.content_drafts, public.content_versions, public.publication_jobs from anon, authenticated;
grant select on public.content_drafts, public.content_versions, public.publication_jobs to authenticated;
drop policy if exists "content_drafts: admin read" on public.content_drafts;
create policy "content_drafts: admin read" on public.content_drafts for select to authenticated using ((select public.has_role('admin')));
drop policy if exists "content_versions: admin read" on public.content_versions;
create policy "content_versions: admin read" on public.content_versions for select to authenticated using ((select public.has_role('admin')));
drop policy if exists "publication_jobs: admin read" on public.publication_jobs;
create policy "publication_jobs: admin read" on public.publication_jobs for select to authenticated using ((select public.has_role('admin')));

-- ---------------------------------------------------------------------------
-- Entity adapters ('restaurant'). Adding a type = one branch in each of these.
-- ---------------------------------------------------------------------------
create or replace function public._cms_keys(p_type text) returns text[]
language sql immutable as $$
  select case p_type when 'restaurant' then array[
    'name_ko', 'name_en', 'category', 'address', 'latitude', 'longitude', 'phone', 'description',
    'opening_hours', 'break_time', 'last_order_time', 'business_status', 'price_min_krw', 'price_max_krw',
    'avg_cost_krw', 'dining_purposes', 'visibility', 'featured', 'display_order', 'university_ids']
  when 'cafeteria_meal' then array[
    'menu_items', 'price_krw', 'start_time', 'end_time', 'status', 'badge', 'source_url', 'verified_at', 'extra']
  when 'restaurant_menus' then array['items']
  when 'restaurant_photos' then array['photos']
  when 'campaign' then array['title', 'subtitle', 'description', 'theme_color', 'banner_mascot', 'starts_at', 'ends_at', 'publish_state']
  when 'university' then array['name_ko', 'name_en', 'city', 'address', 'latitude', 'longitude', 'search_radius_m', 'is_active']
  when 'app_content' then array['title', 'body', 'image_url', 'link_url', 'kakao_place_id', 'university_id', 'active', 'sort_order', 'starts_at', 'ends_at']
  when 'mission' then array[
    'campaign_id', 'title', 'description', 'category', 'icon', 'reward_points', 'rule_type', 'rule_params', 'target_count',
    'recurrence', 'university_id', 'starts_at', 'ends_at', 'action_key', 'sort_order', 'reward_badge_key',
    'reward_badge_name', 'reward_badge_mascot', 'status']
  else null end
$$;

-- The live content of an entity, in snapshot shape.
create or replace function public._cms_snapshot(p_type text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if p_type = 'restaurant' then
    select jsonb_build_object(
      'name_ko', o.name_ko, 'name_en', o.name_en, 'category', o.category, 'address', o.address,
      'latitude', o.latitude, 'longitude', o.longitude, 'phone', o.phone, 'description', o.description,
      'opening_hours', o.opening_hours, 'break_time', o.break_time,
      'last_order_time', to_char(o.last_order_time, 'HH24:MI'), 'business_status', o.business_status,
      'price_min_krw', o.price_min_krw, 'price_max_krw', o.price_max_krw, 'avg_cost_krw', o.avg_cost_krw,
      'dining_purposes', to_jsonb(o.dining_purposes), 'visibility', o.visibility,
      'featured', o.featured, 'display_order', o.display_order,
      'university_ids', coalesce((select jsonb_agg(l.university_id order by l.university_id)
                                    from public.restaurant_university_links l where l.restaurant_id = o.id), '[]'::jsonb))
      into v from public.restaurant_overrides o where o.id = p_id;
  elsif p_type = 'cafeteria_meal' then
    select jsonb_build_object(
      'menu_items', m.menu_items, 'price_krw', m.price_krw,
      'start_time', to_char(m.start_time, 'HH24:MI'), 'end_time', to_char(m.end_time, 'HH24:MI'),
      'status', m.status, 'badge', m.badge, 'source_url', m.source_url, 'verified_at', m.verified_at, 'extra', m.extra)
      into v from public.cafeteria_meals m where m.id = p_id;
  elsif p_type = 'restaurant_menus' then
    if not exists (select 1 from public.restaurant_overrides where id = p_id) then v := null;
    else
      -- every menu of the restaurant, archived ones included (so a rollback restores them)
      select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
          'id', x.id, 'name_ko', x.name_ko, 'description_ko', x.description_ko, 'price_krw', x.price_krw,
          'category', x.category, 'price_verified_on', to_char(x.price_verified_on, 'YYYY-MM-DD'),
          'available', x.available, 'representative', x.representative, 'recommended', x.recommended,
          'status', x.status, 'sort_order', x.sort_order, 'image_url', x.image_url) order by x.sort_order, x.id), '[]'::jsonb))
        into v from public.restaurant_menus x where x.restaurant_id = p_id;
    end if;
  elsif p_type = 'campaign' then
    select jsonb_build_object('title', c.title, 'subtitle', c.subtitle, 'description', c.description, 'theme_color', c.theme_color,
      'banner_mascot', c.banner_mascot, 'starts_at', c.starts_at, 'ends_at', c.ends_at, 'publish_state', c.publish_state)
      into v from public.monthly_campaigns c where c.id = p_id;
  elsif p_type = 'university' then
    select jsonb_build_object('name_ko', u.name_ko, 'name_en', u.name_en, 'city', u.city, 'address', u.address, 'latitude', u.latitude,
      'longitude', u.longitude, 'search_radius_m', u.search_radius_m, 'is_active', u.is_active) into v from public.universities u where u.id = p_id;
  elsif p_type = 'app_content' then
    select jsonb_build_object('title', c.title, 'body', c.body, 'image_url', c.image_url, 'link_url', c.link_url,
      'kakao_place_id', c.kakao_place_id, 'university_id', c.university_id, 'active', c.active, 'sort_order', c.sort_order,
      'starts_at', c.starts_at, 'ends_at', c.ends_at) into v from public.app_content c where c.id = p_id;
  elsif p_type = 'mission' then
    -- the current version of the mission lineage
    select jsonb_build_object(
      'campaign_id', x.campaign_id, 'title', x.title, 'description', x.description, 'category', x.category, 'icon', x.icon,
      'reward_points', x.reward_points, 'rule_type', x.rule_type, 'rule_params', x.rule_params, 'target_count', x.target_count,
      'recurrence', x.recurrence, 'university_id', x.university_id, 'starts_at', x.starts_at, 'ends_at', x.ends_at,
      'action_key', x.action_key, 'sort_order', x.sort_order, 'reward_badge_key', x.reward_badge_key,
      'reward_badge_name', x.reward_badge_name, 'reward_badge_mascot', x.reward_badge_mascot, 'status', x.status)
      into v from public.missions x where x.lineage_id = p_id order by x.version desc limit 1;
  elsif p_type = 'restaurant_photos' then
    if not exists (select 1 from public.restaurant_overrides where id = p_id) then v := null;
    else
      select jsonb_build_object('photos', coalesce(jsonb_agg(jsonb_build_object(
          'id', x.id, 'kind', x.kind, 'storage_path', x.storage_path, 'url', x.url, 'caption', x.caption,
          'sort_order', x.sort_order, 'status', x.status, 'source', x.source, 'credit', x.credit,
          'width', x.width, 'height', x.height, 'bytes', x.bytes) order by x.sort_order, x.id), '[]'::jsonb))
        into v from public.restaurant_photos x where x.restaurant_id = p_id;
    end if;
  else
    raise exception 'unknown entity type' using errcode = '22023';
  end if;
  if v is null then raise exception 'no such %', p_type using errcode = 'P0002'; end if;
  return v;
end $$;

-- Friendly validation (the table's CHECK constraints remain the last line of defence).
create or replace function public._cms_validate(p_type text, p_data jsonb, p_id uuid default null) returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare k text; mt text; it jsonb; ids text[] := '{}'; iid text; pr integer; n integer;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'content must be an object' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_data) loop
    if not (k = any (public._cms_keys(p_type))) then
      raise exception 'unknown field: %', k using errcode = '22023';
    end if;
  end loop;
  if p_type = 'restaurant' then
    if btrim(coalesce(p_data ->> 'name_ko', '')) = '' then raise exception '이름은 비워 둘 수 없어요' using errcode = '22023'; end if;
    if char_length(p_data ->> 'name_ko') > 120 then raise exception '이름이 너무 길어요' using errcode = '22023'; end if;
    if coalesce(p_data ->> 'visibility', '') not in ('draft', 'published', 'hidden', 'archived') then
      raise exception '공개 상태가 올바르지 않아요' using errcode = '22023';
    end if;
    if char_length(coalesce(p_data ->> 'description', '')) > 2000 then raise exception '설명은 2000자 이하여야 해요' using errcode = '22023'; end if;
    begin
      if (p_data ->> 'latitude') is not null and (p_data ->> 'latitude')::double precision not between -90 and 90 then raise exception 'x'; end if;
      if (p_data ->> 'longitude') is not null and (p_data ->> 'longitude')::double precision not between -180 and 180 then raise exception 'x'; end if;
    exception when others then raise exception '좌표가 올바르지 않아요' using errcode = '22023'; end;
    begin
      if (p_data ->> 'price_min_krw') is not null and (p_data ->> 'price_min_krw')::integer < 0 then raise exception 'x'; end if;
      if (p_data ->> 'price_max_krw') is not null and (p_data ->> 'price_max_krw')::integer < 0 then raise exception 'x'; end if;
      if (p_data ->> 'price_min_krw') is not null and (p_data ->> 'price_max_krw') is not null
         and (p_data ->> 'price_min_krw')::integer > (p_data ->> 'price_max_krw')::integer then raise exception 'x'; end if;
    exception when others then raise exception '가격이 올바르지 않아요 (최저 ≤ 최고, 0 이상)' using errcode = '22023'; end;
    if (p_data ->> 'last_order_time') is not null and (p_data ->> 'last_order_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception '주문 마감 시간 형식이 올바르지 않아요' using errcode = '22023';
    end if;
    if (p_data ->> 'business_status') is not null and (p_data ->> 'business_status') not in ('open', 'temporarily_closed', 'closed') then
      raise exception '영업 상태가 올바르지 않아요' using errcode = '22023';
    end if;
    if p_data ? 'university_ids' and jsonb_typeof(p_data -> 'university_ids') <> 'array' then
      raise exception '대학교 목록이 올바르지 않아요' using errcode = '22023';
    end if;
  elsif p_type = 'restaurant_menus' then
    if jsonb_typeof(p_data -> 'items') is distinct from 'array' then raise exception '메뉴 목록이 올바르지 않아요' using errcode = '22023'; end if;
    if jsonb_array_length(p_data -> 'items') > 300 then raise exception '메뉴는 300개까지 둘 수 있어요' using errcode = '22023'; end if;
    for it in select * from jsonb_array_elements(p_data -> 'items') loop
      if jsonb_typeof(it) <> 'object' then raise exception '메뉴 항목이 올바르지 않아요' using errcode = '22023'; end if;
      for k in select jsonb_object_keys(it) loop
        if k <> all (array['id','name_ko','description_ko','price_krw','category','price_verified_on','available','representative','recommended','status','sort_order','image_url']) then
          raise exception '알 수 없는 메뉴 필드: %', k using errcode = '22023';
        end if;
      end loop;
      begin iid := (it ->> 'id')::uuid::text; exception when others then raise exception '메뉴 id가 올바르지 않아요' using errcode = '22023'; end;
      if iid = any (ids) then raise exception '메뉴 id가 겹쳐요' using errcode = '22023'; end if;
      ids := ids || iid;
      if p_id is not null and exists (select 1 from public.restaurant_menus x where x.id = iid::uuid and x.restaurant_id is distinct from p_id) then
        raise exception '다른 식당의 메뉴예요' using errcode = '22023';
      end if;
      if btrim(coalesce(it ->> 'name_ko', '')) = '' then raise exception '메뉴 이름은 비워 둘 수 없어요' using errcode = '22023'; end if;
      if char_length(it ->> 'name_ko') > 120 then raise exception '메뉴 이름이 너무 길어요' using errcode = '22023'; end if;
      if char_length(coalesce(it ->> 'description_ko', '')) > 500 then raise exception '메뉴 설명은 500자 이하여야 해요' using errcode = '22023'; end if;
      if char_length(coalesce(it ->> 'category', '')) > 30 then raise exception '분류가 너무 길어요' using errcode = '22023'; end if;
      if coalesce(it ->> 'status', '') not in ('active', 'archived') then raise exception '메뉴 상태가 올바르지 않아요' using errcode = '22023'; end if;
      begin
        pr := (it ->> 'price_krw')::integer;
        if pr < 0 then raise exception 'x'; end if;
        n := (it ->> 'sort_order')::integer;
        if (it ->> 'available') is not null then perform (it ->> 'available')::boolean; end if;
        if (it ->> 'representative') is not null then perform (it ->> 'representative')::boolean; end if;
        if (it ->> 'recommended') is not null then perform (it ->> 'recommended')::boolean; end if;
      exception when others then raise exception '메뉴 가격·순서 값이 올바르지 않아요 (가격은 0 이상의 정수)' using errcode = '22023'; end;
      if (it ->> 'price_verified_on') is not null then
        begin perform (it ->> 'price_verified_on')::date; exception when others then raise exception '가격 확인일 형식이 올바르지 않아요' using errcode = '22023'; end;
        if pr is null then raise exception '가격이 없으면 확인일을 적을 수 없어요' using errcode = '22023'; end if;
      end if;
      if (it ->> 'image_url') is not null and (it ->> 'image_url') !~ '^https://' then raise exception '메뉴 사진 주소가 올바르지 않아요' using errcode = '22023'; end if;
    end loop;
  elsif p_type = 'campaign' then
    if btrim(coalesce(p_data ->> 'title', '')) = '' then raise exception '캠페인 이름을 입력해 주세요' using errcode = '22023'; end if;
    if char_length(p_data ->> 'title') > 60 then raise exception '이름은 60자 이하여야 해요' using errcode = '22023'; end if;
    if char_length(coalesce(p_data ->> 'subtitle', '')) > 120 then raise exception '부제목은 120자 이하여야 해요' using errcode = '22023'; end if;
    if char_length(coalesce(p_data ->> 'description', '')) > 1000 then raise exception '설명은 1000자 이하여야 해요' using errcode = '22023'; end if;
    if coalesce(p_data ->> 'theme_color', '') !~ '^#[0-9A-Fa-f]{6}$' then raise exception '테마 색상은 #RRGGBB 형식이어야 해요' using errcode = '22023'; end if;
    if coalesce(p_data ->> 'banner_mascot', '') not in ('standing','wink','cheer','sparkle','burger','boba','searching','sleeping','confused','running') then raise exception '배너 마스코트가 올바르지 않아요' using errcode = '22023'; end if;
    if coalesce(p_data ->> 'publish_state', '') not in ('draft', 'published') then raise exception '게시 상태가 올바르지 않아요' using errcode = '22023'; end if;
    begin
      if (p_data ->> 'ends_at')::timestamptz <= (p_data ->> 'starts_at')::timestamptz then raise exception 'x'; end if;
    exception when others then raise exception '종료는 시작보다 늦어야 해요' using errcode = '22023'; end;
  elsif p_type = 'university' then
    if btrim(coalesce(p_data ->> 'name_ko', '')) = '' then raise exception '이름을 입력해 주세요' using errcode = '22023'; end if;
    if char_length(p_data ->> 'name_ko') > 80 then raise exception '이름이 너무 길어요' using errcode = '22023'; end if;
    begin
      if (p_data ->> 'latitude') is not null and (p_data ->> 'latitude')::double precision not between -90 and 90 then raise exception 'x'; end if;
      if (p_data ->> 'longitude') is not null and (p_data ->> 'longitude')::double precision not between -180 and 180 then raise exception 'x'; end if;
    exception when others then raise exception '좌표가 올바르지 않아요' using errcode = '22023'; end;
    begin n := (p_data ->> 'search_radius_m')::integer; if n < 100 or n > 5000 then raise exception 'x'; end if;
    exception when others then raise exception '검색 반경은 100 ~ 5000 m 사이여야 해요' using errcode = '22023'; end;
    if jsonb_typeof(p_data -> 'is_active') is distinct from 'boolean' then raise exception '활성 여부가 올바르지 않아요' using errcode = '22023'; end if;
  elsif p_type = 'app_content' then
    if btrim(coalesce(p_data ->> 'title', '')) = '' then raise exception '제목을 입력해 주세요' using errcode = '22023'; end if;
    if char_length(p_data ->> 'title') > 120 then raise exception '제목이 너무 길어요' using errcode = '22023'; end if;
    if char_length(coalesce(p_data ->> 'body', '')) > 2000 then raise exception '내용은 2000자 이하여야 해요' using errcode = '22023'; end if;
    if (p_data ->> 'image_url') is not null and (p_data ->> 'image_url') !~ '^https://' then raise exception '이미지 주소는 https:// 로 시작해야 해요' using errcode = '22023'; end if;
    if (p_data ->> 'link_url') is not null and (p_data ->> 'link_url') !~ '^https://' then raise exception '링크는 https:// 로 시작해야 해요' using errcode = '22023'; end if;
    if jsonb_typeof(p_data -> 'active') is distinct from 'boolean' then raise exception '노출 여부가 올바르지 않아요' using errcode = '22023'; end if;
    begin n := (p_data ->> 'sort_order')::integer; exception when others then raise exception '정렬 순서가 올바르지 않아요' using errcode = '22023'; end;
    begin
      if (p_data ->> 'starts_at') is not null and (p_data ->> 'ends_at') is not null
         and (p_data ->> 'starts_at')::timestamptz >= (p_data ->> 'ends_at')::timestamptz then raise exception 'x'; end if;
    exception when others then raise exception '노출 종료는 시작보다 늦어야 해요' using errcode = '22023'; end;
    if p_id is not null and (select kind from public.app_content where id = p_id) = 'featured' and btrim(coalesce(p_data ->> 'kakao_place_id', '')) = '' then
      raise exception '추천 식당은 카카오 장소 ID가 필요해요' using errcode = '22023';
    end if;
  elsif p_type = 'mission' then
    if btrim(coalesce(p_data ->> 'title', '')) = '' then raise exception '제목을 입력해 주세요' using errcode = '22023'; end if;
    if char_length(p_data ->> 'title') > 60 then raise exception '제목은 60자 이하여야 해요' using errcode = '22023'; end if;
    if char_length(coalesce(p_data ->> 'description', '')) > 300 then raise exception '설명은 300자 이하여야 해요' using errcode = '22023'; end if;
    begin
      n := (p_data ->> 'reward_points')::integer; if n < 0 or n > 10000 then raise exception 'x'; end if;
    exception when others then raise exception '보상 포인트는 0 ~ 10000 사이 정수여야 해요' using errcode = '22023'; end;
    begin
      n := (p_data ->> 'target_count')::integer; if n < 1 or n > 1000 then raise exception 'x'; end if;
    exception when others then raise exception '목표 횟수는 1 ~ 1000 사이 정수여야 해요' using errcode = '22023'; end;
    if coalesce(p_data ->> 'rule_type', '') not in ('favorite_distinct', 'favorite_cheap', 'activity_days', 'activity_refs', 'review_valid', 'contribution_approved', 'missions_completed') then
      raise exception '완료 조건이 올바르지 않아요' using errcode = '22023';
    end if;
    if jsonb_typeof(p_data -> 'rule_params') is distinct from 'object' then raise exception '완료 조건 값이 올바르지 않아요' using errcode = '22023'; end if;
    if coalesce(p_data ->> 'recurrence', '') not in ('none', 'daily', 'weekly') then raise exception '반복 주기가 올바르지 않아요' using errcode = '22023'; end if;
    if coalesce(p_data ->> 'action_key', '') not in ('none', 'recommend', 'map', 'favorites', 'review', 'photo', 'correct', 'categories') then raise exception '버튼 동작이 올바르지 않아요' using errcode = '22023'; end if;
    if coalesce(p_data ->> 'status', '') not in ('draft', 'active', 'paused', 'archived') then raise exception '미션 상태가 올바르지 않아요' using errcode = '22023'; end if;
    begin
      if (p_data ->> 'starts_at') is not null and (p_data ->> 'ends_at') is not null
         and (p_data ->> 'ends_at')::timestamptz <= (p_data ->> 'starts_at')::timestamptz then raise exception 'x'; end if;
    exception when others then raise exception '종료는 시작보다 늦어야 해요' using errcode = '22023'; end;
    if (p_data ->> 'reward_badge_key') is not null and (p_data ->> 'reward_badge_key') !~ '^[a-z0-9][a-z0-9_]{1,60}$' then raise exception '뱃지 키 형식이 올바르지 않아요' using errcode = '22023'; end if;
    if p_id is not null and (select kind from public.missions where lineage_id = p_id order by version desc limit 1) = 'monthly' and (p_data ->> 'campaign_id') is null then
      raise exception '월간 미션은 캠페인이 필요해요' using errcode = '22023';
    end if;
    if p_id is not null and (select status from public.missions where lineage_id = p_id order by version desc limit 1) = 'archived' then
      raise exception '보관된 미션은 수정할 수 없어요' using errcode = '55000';
    end if;
  elsif p_type = 'restaurant_photos' then
    if jsonb_typeof(p_data -> 'photos') is distinct from 'array' then raise exception '사진 목록이 올바르지 않아요' using errcode = '22023'; end if;
    if jsonb_array_length(p_data -> 'photos') > 200 then raise exception '사진은 200장까지 둘 수 있어요' using errcode = '22023'; end if;
    n := 0;
    for it in select * from jsonb_array_elements(p_data -> 'photos') loop
      if jsonb_typeof(it) <> 'object' then raise exception '사진 항목이 올바르지 않아요' using errcode = '22023'; end if;
      for k in select jsonb_object_keys(it) loop
        if k <> all (array['id','kind','storage_path','url','caption','sort_order','status','source','credit','width','height','bytes']) then
          raise exception '알 수 없는 사진 필드: %', k using errcode = '22023';
        end if;
      end loop;
      begin iid := (it ->> 'id')::uuid::text; exception when others then raise exception '사진 id가 올바르지 않아요' using errcode = '22023'; end;
      if iid = any (ids) then raise exception '사진 id가 겹쳐요' using errcode = '22023'; end if;
      ids := ids || iid;
      if p_id is not null and exists (select 1 from public.restaurant_photos x where (x.id = iid::uuid or x.storage_path = it ->> 'storage_path') and x.restaurant_id is distinct from p_id) then
        raise exception '다른 식당의 사진이에요' using errcode = '22023';
      end if;
      if p_id is not null and exists (select 1 from public.restaurant_photos x where x.storage_path = it ->> 'storage_path' and x.id <> iid::uuid) then
        raise exception '같은 파일을 두 번 쓸 수 없어요' using errcode = '22023';
      end if;
      if coalesce(it ->> 'kind', '') not in ('cover', 'gallery') then raise exception '사진 종류가 올바르지 않아요' using errcode = '22023'; end if;
      if coalesce(it ->> 'status', '') not in ('published', 'archived') then raise exception '사진 상태가 올바르지 않아요' using errcode = '22023'; end if;
      if coalesce(it ->> 'source', 'admin') not in ('admin', 'student') then raise exception '사진 출처가 올바르지 않아요' using errcode = '22023'; end if;
      if btrim(coalesce(it ->> 'storage_path', '')) = '' then raise exception '파일 경로가 필요해요' using errcode = '22023'; end if;
      if coalesce(it ->> 'url', '') !~ '^https://' then raise exception '사진 주소는 https:// 로 시작해야 해요' using errcode = '22023'; end if;
      if char_length(coalesce(it ->> 'caption', '')) > 200 then raise exception '사진 설명은 200자 이하여야 해요' using errcode = '22023'; end if;
      if char_length(coalesce(it ->> 'credit', '')) > 100 then raise exception '사진 제공자는 100자 이하여야 해요' using errcode = '22023'; end if;
      begin
        perform (it ->> 'sort_order')::integer;
        if (it ->> 'width') is not null and (it ->> 'width')::integer <= 0 then raise exception 'x'; end if;
        if (it ->> 'height') is not null and (it ->> 'height')::integer <= 0 then raise exception 'x'; end if;
        if (it ->> 'bytes') is not null and (it ->> 'bytes')::integer <= 0 then raise exception 'x'; end if;
      exception when others then raise exception '사진 크기·순서 값이 올바르지 않아요' using errcode = '22023'; end;
      if it ->> 'kind' = 'cover' and it ->> 'status' = 'published' then n := n + 1; end if;
    end loop;
    if n > 1 then raise exception '대표 사진은 한 장만 공개할 수 있어요' using errcode = '22023'; end if;
  elsif p_type = 'cafeteria_meal' then
    if coalesce(p_data ->> 'status', '') not in ('draft', 'published', 'closed', 'no_menu') then
      raise exception '식단 상태가 올바르지 않아요' using errcode = '22023';
    end if;
    if jsonb_typeof(p_data -> 'menu_items') is distinct from 'array' then
      raise exception '메뉴 목록이 올바르지 않아요' using errcode = '22023';
    end if;
    for it in select * from jsonb_array_elements(p_data -> 'menu_items') loop
      if jsonb_typeof(it) <> 'object' or btrim(coalesce(it ->> 'name_ko', '')) = '' then
        raise exception '메뉴 이름은 비워 둘 수 없어요' using errcode = '22023';
      end if;
    end loop;
    if p_data ->> 'status' = 'published' and jsonb_array_length(p_data -> 'menu_items') = 0 then
      raise exception '공개하려면 메뉴가 한 개 이상 필요해요' using errcode = '22023';
    end if;
    begin
      if (p_data ->> 'price_krw') is not null and (p_data ->> 'price_krw')::integer < 0 then raise exception 'x'; end if;
    exception when others then raise exception '가격이 올바르지 않아요' using errcode = '22023'; end;
    if (p_data ->> 'start_time') is not null and (p_data ->> 'start_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception '시작 시간 형식이 올바르지 않아요' using errcode = '22023'; end if;
    if (p_data ->> 'end_time') is not null and (p_data ->> 'end_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception '종료 시간 형식이 올바르지 않아요' using errcode = '22023'; end if;
    if (p_data ->> 'start_time') is not null and (p_data ->> 'end_time') is not null and (p_data ->> 'start_time') >= (p_data ->> 'end_time') then
      raise exception '종료는 시작보다 늦어야 해요' using errcode = '22023';
    end if;
    if (p_data ->> 'source_url') is not null and (p_data ->> 'source_url') !~ '^https://' then raise exception '출처 주소는 https:// 로 시작해야 해요' using errcode = '22023'; end if;
    if (p_data ->> 'verified_at') is null then raise exception '확인한 날짜가 필요해요' using errcode = '22023'; end if;
    begin perform (p_data ->> 'verified_at')::timestamptz; exception when others then raise exception '확인한 날짜 형식이 올바르지 않아요' using errcode = '22023'; end;
    if p_data ? 'extra' and (jsonb_typeof(p_data -> 'extra') <> 'object' or octet_length((p_data -> 'extra')::text) > 4000) then
      raise exception '추가 정보가 올바르지 않아요' using errcode = '22023';
    end if;
    -- the 천원의 아침밥 label is only for a breakfast with an official source
    if btrim(coalesce(p_data ->> 'badge', '')) = '천원의 아침밥' then
      if btrim(coalesce(p_data ->> 'source_url', '')) = '' then raise exception '천원의 아침밥은 공식 출처 주소가 있어야 해요' using errcode = '22023'; end if;
      if p_id is not null then
        select meal_type into mt from public.cafeteria_meals where id = p_id;
        if mt is distinct from 'breakfast' then raise exception '천원의 아침밥은 조식에만 쓸 수 있어요' using errcode = '22023'; end if;
      end if;
    end if;
  end if;
end $$;

-- What "unpublished" means for a type (non-destructive: nothing is deleted).
create or replace function public._cms_unpublished(p_type text, p_live jsonb) returns jsonb
language sql immutable as $$
  select case p_type when 'restaurant' then p_live || '{"visibility":"hidden"}'::jsonb
                     when 'cafeteria_meal' then p_live || '{"status":"draft"}'::jsonb
                     -- no menu is shown any more; every item is kept (archived), none is deleted
                     when 'restaurant_menus' then jsonb_build_object('items', coalesce(
                       (select jsonb_agg(i || '{"status":"archived"}'::jsonb) from jsonb_array_elements(p_live -> 'items') i), '[]'::jsonb))
                     -- a stopped mission keeps its progress, rewards and badges; students just stop seeing it
                     when 'mission' then p_live || '{"status":"paused"}'::jsonb
                     when 'app_content' then p_live || '{"active":false}'::jsonb
                     when 'university' then p_live || '{"is_active":false}'::jsonb
                     when 'campaign' then p_live || '{"publish_state":"draft"}'::jsonb
                     when 'restaurant_photos' then jsonb_build_object('photos', coalesce(
                       (select jsonb_agg(i || '{"status":"archived"}'::jsonb) from jsonb_array_elements(p_live -> 'photos') i), '[]'::jsonb))
                     else p_live end
$$;

-- Write [p_data] into the live row. Only callable from the publishing functions
-- (they set the flag the guard trigger checks).
create or replace function public._cms_apply(p_type text, p_id uuid, p_data jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform set_config('app.cms_apply', 'on', true);
  if p_type = 'restaurant' then
    update public.restaurant_overrides o set
      name_ko = p_data ->> 'name_ko', name_en = p_data ->> 'name_en', category = p_data ->> 'category',
      address = p_data ->> 'address', latitude = (p_data ->> 'latitude')::double precision,
      longitude = (p_data ->> 'longitude')::double precision, phone = p_data ->> 'phone',
      description = p_data ->> 'description', opening_hours = coalesce(p_data -> 'opening_hours', '{}'::jsonb),
      break_time = p_data ->> 'break_time', last_order_time = nullif(p_data ->> 'last_order_time', '')::time,
      business_status = p_data ->> 'business_status', price_min_krw = (p_data ->> 'price_min_krw')::integer,
      price_max_krw = (p_data ->> 'price_max_krw')::integer, avg_cost_krw = (p_data ->> 'avg_cost_krw')::integer,
      dining_purposes = coalesce(array(select jsonb_array_elements_text(p_data -> 'dining_purposes')), '{}'),
      visibility = p_data ->> 'visibility', featured = coalesce((p_data ->> 'featured')::boolean, false),
      display_order = (p_data ->> 'display_order')::integer
     where o.id = p_id;
    if not found then raise exception 'no such restaurant' using errcode = 'P0002'; end if;
    if p_data ? 'university_ids' then
      delete from public.restaurant_university_links l
       where l.restaurant_id = p_id
         and l.university_id not in (select (jsonb_array_elements_text(p_data -> 'university_ids'))::uuid);
      insert into public.restaurant_university_links (restaurant_id, university_id)
        select p_id, (jsonb_array_elements_text(p_data -> 'university_ids'))::uuid
        on conflict do nothing;
    end if;
  elsif p_type = 'cafeteria_meal' then
    update public.cafeteria_meals m set
      menu_items = coalesce(p_data -> 'menu_items', '[]'::jsonb), price_krw = (p_data ->> 'price_krw')::integer,
      start_time = nullif(p_data ->> 'start_time', '')::time, end_time = nullif(p_data ->> 'end_time', '')::time,
      status = p_data ->> 'status', badge = nullif(btrim(coalesce(p_data ->> 'badge', '')), ''),
      source_url = nullif(p_data ->> 'source_url', ''), verified_at = (p_data ->> 'verified_at')::timestamptz,
      extra = coalesce(p_data -> 'extra', '{}'::jsonb)
     where m.id = p_id;
    if not found then raise exception 'no such meal' using errcode = 'P0002'; end if;
  elsif p_type = 'restaurant_menus' then
    if not exists (select 1 from public.restaurant_overrides where id = p_id) then raise exception 'no such restaurant' using errcode = 'P0002'; end if;
    -- a menu that is no longer in the list is archived, never deleted
    update public.restaurant_menus x set status = 'archived'
     where x.restaurant_id = p_id and x.status <> 'archived'
       and x.id not in (select (i ->> 'id')::uuid from jsonb_array_elements(p_data -> 'items') i);
    insert into public.restaurant_menus as x (id, restaurant_id, name_ko, description_ko, price_krw, category, price_verified_on,
                                              available, representative, recommended, status, sort_order, image_url, source)
    select (i ->> 'id')::uuid, p_id, btrim(i ->> 'name_ko'), nullif(btrim(coalesce(i ->> 'description_ko', '')), ''),
           (i ->> 'price_krw')::integer, nullif(i ->> 'category', ''), (i ->> 'price_verified_on')::date,
           coalesce((i ->> 'available')::boolean, true), coalesce((i ->> 'representative')::boolean, false),
           coalesce((i ->> 'recommended')::boolean, false), i ->> 'status', coalesce((i ->> 'sort_order')::integer, 0),
           i ->> 'image_url', 'admin'
      from jsonb_array_elements(p_data -> 'items') i
    on conflict (id) do update set
      name_ko = excluded.name_ko, description_ko = excluded.description_ko, price_krw = excluded.price_krw,
      category = excluded.category, price_verified_on = excluded.price_verified_on, available = excluded.available,
      representative = excluded.representative, recommended = excluded.recommended, status = excluded.status,
      sort_order = excluded.sort_order, image_url = excluded.image_url
      where x.restaurant_id = p_id;
  elsif p_type = 'campaign' then
    perform public._campaign_save(jsonb_build_object('id', p_id, 'title', p_data ->> 'title', 'subtitle', p_data ->> 'subtitle', 'description', p_data ->> 'description',
      'theme_color', p_data ->> 'theme_color', 'banner_mascot', p_data ->> 'banner_mascot', 'starts_at', p_data ->> 'starts_at', 'ends_at', p_data ->> 'ends_at'));
    update public.monthly_campaigns set publish_state = p_data ->> 'publish_state' where id = p_id;
  elsif p_type = 'university' then
    update public.universities u set
      name_ko = btrim(p_data ->> 'name_ko'), name_en = nullif(btrim(coalesce(p_data ->> 'name_en', '')), ''), city = nullif(btrim(coalesce(p_data ->> 'city', '')), ''),
      address = nullif(btrim(coalesce(p_data ->> 'address', '')), ''), latitude = (p_data ->> 'latitude')::double precision,
      longitude = (p_data ->> 'longitude')::double precision, search_radius_m = (p_data ->> 'search_radius_m')::integer, is_active = (p_data ->> 'is_active')::boolean
     where u.id = p_id;
    if not found then raise exception 'no such university' using errcode = 'P0002'; end if;
  elsif p_type = 'app_content' then
    update public.app_content c set
      title = btrim(p_data ->> 'title'), body = nullif(btrim(coalesce(p_data ->> 'body', '')), ''), image_url = p_data ->> 'image_url',
      link_url = p_data ->> 'link_url', kakao_place_id = nullif(btrim(coalesce(p_data ->> 'kakao_place_id', '')), ''),
      university_id = (p_data ->> 'university_id')::uuid, active = (p_data ->> 'active')::boolean,
      sort_order = coalesce((p_data ->> 'sort_order')::integer, 0), starts_at = (p_data ->> 'starts_at')::timestamptz, ends_at = (p_data ->> 'ends_at')::timestamptz
     where c.id = p_id;
    if not found then raise exception 'no such content' using errcode = 'P0002'; end if;
  elsif p_type = 'mission' then
    -- the existing mission rules decide: a change to goal / reward / rule / audience / period of a
    -- mission that already has progress becomes a NEW VERSION (old row archived, rewards untouched)
    perform public._mission_save(p_data || jsonb_build_object('id', (select x.id from public.missions x where x.lineage_id = p_id order by x.version desc limit 1)));
  elsif p_type = 'restaurant_photos' then
    if not exists (select 1 from public.restaurant_overrides where id = p_id) then raise exception 'no such restaurant' using errcode = 'P0002'; end if;
    -- a photo that is no longer in the set is archived (the file and the row are kept), and
    -- every live cover that will not stay the live cover steps aside first (one live cover at a time)
    update public.restaurant_photos x set status = 'archived'
     where x.restaurant_id = p_id and x.status <> 'archived'
       and (x.id not in (select (i ->> 'id')::uuid from jsonb_array_elements(p_data -> 'photos') i)
            or (x.kind = 'cover' and x.id not in (select (i ->> 'id')::uuid from jsonb_array_elements(p_data -> 'photos') i
                                                   where i ->> 'kind' = 'cover' and i ->> 'status' = 'published')));
    insert into public.restaurant_photos as x (id, restaurant_id, kind, storage_path, url, caption, sort_order, status, source, credit, width, height, bytes)
    select (i ->> 'id')::uuid, p_id, i ->> 'kind', i ->> 'storage_path', i ->> 'url', nullif(btrim(coalesce(i ->> 'caption', '')), ''),
           coalesce((i ->> 'sort_order')::integer, 0), i ->> 'status', coalesce(i ->> 'source', 'admin'), nullif(btrim(coalesce(i ->> 'credit', '')), ''),
           (i ->> 'width')::integer, (i ->> 'height')::integer, (i ->> 'bytes')::integer
      from jsonb_array_elements(p_data -> 'photos') i
    on conflict (id) do update set
      kind = excluded.kind, storage_path = excluded.storage_path, url = excluded.url, caption = excluded.caption,
      sort_order = excluded.sort_order, status = excluded.status, source = excluded.source, credit = excluded.credit,
      width = excluded.width, height = excluded.height, bytes = excluded.bytes
      where x.restaurant_id = p_id;
  else
    raise exception 'unknown entity type' using errcode = '22023';
  end if;
  perform set_config('app.cms_apply', 'off', true);
end $$;
revoke all on function public._cms_apply(text, uuid, jsonb), public._cms_snapshot(text, uuid),
  public._cms_validate(text, jsonb, uuid), public._cms_unpublished(text, jsonb), public._cms_keys(text)
  from public, anon, authenticated;

-- Guard: live restaurant content cannot be changed through the API.
create or replace function public.restaurant_overrides_guard_live() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  -- API callers run as authenticated / anon. The publishing functions (SECURITY
  -- DEFINER), the SQL editor and the service role are not subject to this.
  if current_user not in ('authenticated', 'anon') or coalesce(current_setting('app.cms_apply', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.visibility <> 'draft' then
      raise exception 'new restaurants start as drafts; publish them from the publishing toolbar' using errcode = '42501';
    end if;
    return new;
  end if;
  if (new.name_ko, new.name_en, new.category, new.address, new.latitude, new.longitude, new.phone, new.description,
      new.opening_hours, new.break_time, new.last_order_time, new.business_status, new.price_min_krw, new.price_max_krw,
      new.avg_cost_krw, new.dining_purposes, new.visibility, new.featured, new.display_order)
     is distinct from
     (old.name_ko, old.name_en, old.category, old.address, old.latitude, old.longitude, old.phone, old.description,
      old.opening_hours, old.break_time, old.last_order_time, old.business_status, old.price_min_krw, old.price_max_krw,
      old.avg_cost_krw, old.dining_purposes, old.visibility, old.featured, old.display_order) then
    raise exception 'live content is changed only by publishing (save a draft, then publish)' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists restaurant_overrides_guard_live on public.restaurant_overrides;
create trigger restaurant_overrides_guard_live before insert or update on public.restaurant_overrides
  for each row execute function public.restaurant_overrides_guard_live();

-- ---------------------------------------------------------------------------
-- Missions. admin_save_mission (20261110) keeps its versioning rules; its body moves to
-- _mission_save() (no role check, not callable from the API) so that publishing - including the
-- scheduler, which has no logged-in user - can reuse it. The API function now refuses to make a
-- mission visible or to edit a visible one: that is what publishing is for.
-- ---------------------------------------------------------------------------
create or replace function public._mission_save(p jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id   uuid := nullif(p ->> 'id', '')::uuid;
  old    public.missions;
  v_new  uuid;
  v_material boolean;
begin
  if v_id is null then
    insert into public.missions
      (campaign_id, slug, kind, title, description, category, icon, reward_points, rule_type, rule_params,
       target_count, recurrence, university_id, starts_at, ends_at, action_key, sort_order,
       reward_badge_key, reward_badge_name, reward_badge_mascot, status)
    values (nullif(p ->> 'campaign_id', '')::uuid, p ->> 'slug', p ->> 'kind', p ->> 'title',
            p ->> 'description', p ->> 'category', coalesce(p ->> 'icon', 'star'),
            coalesce((p ->> 'reward_points')::integer, 0), p ->> 'rule_type',
            coalesce(p -> 'rule_params', '{}'::jsonb), (p ->> 'target_count')::integer,
            coalesce(p ->> 'recurrence', 'none'), nullif(p ->> 'university_id', '')::uuid,
            (p ->> 'starts_at')::timestamptz, (p ->> 'ends_at')::timestamptz,
            coalesce(p ->> 'action_key', 'none'), coalesce((p ->> 'sort_order')::integer, 0),
            nullif(p ->> 'reward_badge_key', ''), nullif(p ->> 'reward_badge_name', ''),
            nullif(p ->> 'reward_badge_mascot', ''), coalesce(p ->> 'status', 'draft'))
    returning id into v_id;
    return v_id;
  end if;

  select * into old from public.missions where id = v_id for update;
  if not found then raise exception 'no such mission' using errcode = 'P0002'; end if;
  if old.status = 'archived' then raise exception 'archived missions cannot be edited' using errcode = '55000'; end if;

  v_material :=
       coalesce((p ->> 'target_count')::integer, old.target_count) is distinct from old.target_count
    or coalesce((p ->> 'reward_points')::integer, old.reward_points) is distinct from old.reward_points
    or coalesce(p ->> 'rule_type', old.rule_type) is distinct from old.rule_type
    or coalesce(p -> 'rule_params', old.rule_params) is distinct from old.rule_params
    or coalesce(p ->> 'recurrence', old.recurrence) is distinct from old.recurrence
    or (case when p ? 'university_id' then nullif(p ->> 'university_id', '')::uuid else old.university_id end)
         is distinct from old.university_id
    or (case when p ? 'starts_at' then (p ->> 'starts_at')::timestamptz else old.starts_at end)
         is distinct from old.starts_at
    or (case when p ? 'ends_at' then (p ->> 'ends_at')::timestamptz else old.ends_at end)
         is distinct from old.ends_at;

  if v_material and exists (select 1 from public.user_mission_progress where mission_id = old.id) then
    insert into public.missions
      (lineage_id, version, supersedes_id, campaign_id, slug, kind, title, description, category, icon,
       reward_points, rule_type, rule_params, target_count, recurrence, university_id, starts_at, ends_at,
       action_key, sort_order, reward_badge_key, reward_badge_name, reward_badge_mascot, status)
    values (old.lineage_id, old.version + 1, old.id, old.campaign_id, old.slug, old.kind,
            coalesce(p ->> 'title', old.title),
            case when p ? 'description' then p ->> 'description' else old.description end,
            case when p ? 'category' then p ->> 'category' else old.category end,
            coalesce(p ->> 'icon', old.icon),
            coalesce((p ->> 'reward_points')::integer, old.reward_points),
            coalesce(p ->> 'rule_type', old.rule_type),
            coalesce(p -> 'rule_params', old.rule_params),
            coalesce((p ->> 'target_count')::integer, old.target_count),
            coalesce(p ->> 'recurrence', old.recurrence),
            case when p ? 'university_id' then nullif(p ->> 'university_id', '')::uuid else old.university_id end,
            case when p ? 'starts_at' then (p ->> 'starts_at')::timestamptz else old.starts_at end,
            case when p ? 'ends_at' then (p ->> 'ends_at')::timestamptz else old.ends_at end,
            coalesce(p ->> 'action_key', old.action_key),
            coalesce((p ->> 'sort_order')::integer, old.sort_order),
            case when p ? 'reward_badge_key' then nullif(p ->> 'reward_badge_key', '') else old.reward_badge_key end,
            case when p ? 'reward_badge_name' then nullif(p ->> 'reward_badge_name', '') else old.reward_badge_name end,
            case when p ? 'reward_badge_mascot' then nullif(p ->> 'reward_badge_mascot', '') else old.reward_badge_mascot end,
            coalesce(p ->> 'status', old.status))
    returning id into v_new;
    update public.missions set status = 'archived' where id = old.id;
    perform public._audit('mission_new_version', 'missions', v_new::text, 'versioned edit',
                          jsonb_build_object('previous', old.id, 'version', old.version + 1));
    return v_new;
  end if;

  update public.missions set
    campaign_id = case when p ? 'campaign_id' then nullif(p ->> 'campaign_id', '')::uuid else campaign_id end,
    title = coalesce(p ->> 'title', title),
    description = case when p ? 'description' then p ->> 'description' else description end,
    category = case when p ? 'category' then p ->> 'category' else category end,
    icon = coalesce(p ->> 'icon', icon),
    reward_points = coalesce((p ->> 'reward_points')::integer, reward_points),
    rule_type = coalesce(p ->> 'rule_type', rule_type),
    rule_params = coalesce(p -> 'rule_params', rule_params),
    target_count = coalesce((p ->> 'target_count')::integer, target_count),
    recurrence = coalesce(p ->> 'recurrence', recurrence),
    university_id = case when p ? 'university_id' then nullif(p ->> 'university_id', '')::uuid else university_id end,
    starts_at = case when p ? 'starts_at' then (p ->> 'starts_at')::timestamptz else starts_at end,
    ends_at = case when p ? 'ends_at' then (p ->> 'ends_at')::timestamptz else ends_at end,
    action_key = coalesce(p ->> 'action_key', action_key),
    sort_order = coalesce((p ->> 'sort_order')::integer, sort_order),
    reward_badge_key = case when p ? 'reward_badge_key' then nullif(p ->> 'reward_badge_key', '') else reward_badge_key end,
    reward_badge_name = case when p ? 'reward_badge_name' then nullif(p ->> 'reward_badge_name', '') else reward_badge_name end,
    reward_badge_mascot = case when p ? 'reward_badge_mascot' then nullif(p ->> 'reward_badge_mascot', '') else reward_badge_mascot end,
    status = coalesce(p ->> 'status', status)
  where id = v_id;
  return v_id;
end $$;
revoke all on function public._mission_save(jsonb) from public, anon, authenticated;

create or replace function public.admin_save_mission(p jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; old_status text;
begin
  perform public._require_role('admin');
  if coalesce(current_setting('app.cms_apply', true), '') <> 'on' then
    if v_id is not null then select status into old_status from public.missions where id = v_id; end if;
    if coalesce(old_status, 'draft') <> 'draft' or coalesce(p ->> 'status', coalesce(old_status, 'draft')) <> 'draft' then
      raise exception 'a visible mission is changed only by publishing (save a draft, then publish)' using errcode = '42501';
    end if;
  end if;
  return public._mission_save(p);
end $$;

-- Pausing / archiving stays an immediate, audited operation; the FIRST activation is a publication.
create or replace function public.admin_set_mission_status(p_id uuid, p_status text, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare old_status text;
begin
  perform public._require_role('admin');
  if p_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'unknown status' using errcode = '22023';
  end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select status into old_status from public.missions where id = p_id;
  if not found then raise exception 'no such mission' using errcode = 'P0002'; end if;
  if p_status = 'active' and old_status = 'draft' then
    raise exception 'a draft mission goes live by publishing it' using errcode = '42501';
  end if;
  update public.missions set status = p_status where id = p_id;
  perform public._audit('set_mission_status', 'missions', p_id::text, p_reason, jsonb_build_object('status', p_status));
end $$;

-- ---------------------------------------------------------------------------
-- Campaigns. The body of admin_save_campaign moves to _campaign_save() (no role check, not callable
-- from the API) for publishing. The API function refuses to edit a published campaign, and a
-- campaign goes published only through publishing; taking it back to draft stays an audited call.
-- ---------------------------------------------------------------------------
create or replace function public._campaign_save(p jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if v_id is null then
    insert into public.monthly_campaigns
      (slug, title, subtitle, description, theme_color, banner_mascot, starts_at, ends_at)
    values (p ->> 'slug', p ->> 'title', p ->> 'subtitle', p ->> 'description',
            coalesce(p ->> 'theme_color', '#E85D04'), coalesce(p ->> 'banner_mascot', 'cheer'),
            (p ->> 'starts_at')::timestamptz, (p ->> 'ends_at')::timestamptz)
    returning id into v_id;
  else
    update public.monthly_campaigns set
      title = coalesce(p ->> 'title', title),
      subtitle = case when p ? 'subtitle' then p ->> 'subtitle' else subtitle end,
      description = case when p ? 'description' then p ->> 'description' else description end,
      theme_color = coalesce(p ->> 'theme_color', theme_color),
      banner_mascot = coalesce(p ->> 'banner_mascot', banner_mascot),
      starts_at = coalesce((p ->> 'starts_at')::timestamptz, starts_at),
      ends_at = coalesce((p ->> 'ends_at')::timestamptz, ends_at)
    where id = v_id;
    if not found then raise exception 'no such campaign' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end $$;
revoke all on function public._campaign_save(jsonb) from public, anon, authenticated;

create or replace function public.admin_save_campaign(p jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  if coalesce(current_setting('app.cms_apply', true), '') <> 'on'
     and nullif(p ->> 'id', '') is not null
     and exists (select 1 from public.monthly_campaigns where id = (p ->> 'id')::uuid and publish_state = 'published') then
    raise exception 'a published campaign is changed only by publishing (save a draft, then publish)' using errcode = '42501';
  end if;
  return public._campaign_save(p);
end $$;

create or replace function public.admin_set_campaign_publish(p_id uuid, p_state text, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  if p_state not in ('draft', 'published') then raise exception 'unknown state' using errcode = '22023'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p_state = 'published' and coalesce(current_setting('app.cms_apply', true), '') <> 'on' then
    raise exception 'a campaign goes live by publishing it' using errcode = '42501';
  end if;
  update public.monthly_campaigns set publish_state = p_state where id = p_id;
  if not found then raise exception 'no such campaign' using errcode = 'P0002'; end if;
  perform public._audit('set_campaign_publish', 'monthly_campaigns', p_id::text, p_reason, jsonb_build_object('state', p_state));
end $$;

-- Guard: a university's live fields change only by publishing. A new campus starts switched off.
create or replace function public.universities_guard_live() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if current_user not in ('authenticated', 'anon') or coalesce(current_setting('app.cms_apply', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op = 'INSERT' then
    if new.is_active then raise exception 'new universities start switched off; publish them from the publishing toolbar' using errcode = '42501'; end if;
    return new;
  end if;
  if (new.name_ko, new.name_en, new.city, new.address, new.latitude, new.longitude, new.search_radius_m, new.is_active)
     is distinct from
     (old.name_ko, old.name_en, old.city, old.address, old.latitude, old.longitude, old.search_radius_m, old.is_active) then
    raise exception 'a university is changed only by publishing (save a draft, then publish)' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists universities_guard_live on public.universities;
create trigger universities_guard_live before insert or update on public.universities
  for each row execute function public.universities_guard_live();

-- Guard: LIVE app content (an active announcement / banner / featured restaurant) changes only by
-- publishing. A switched-off row is a staging row and may be created, edited and removed freely.
create or replace function public.app_content_guard_live() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if current_user not in ('authenticated', 'anon') or coalesce(current_setting('app.cms_apply', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op = 'INSERT' then
    if new.active then raise exception 'new content starts switched off; publish it from the publishing toolbar' using errcode = '42501'; end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.active then raise exception 'live content cannot be deleted: unpublish it first' using errcode = '42501'; end if;
    return old;
  end if;
  if not old.active and not new.active then return new; end if;
  raise exception 'live content is changed only by publishing (save a draft, then publish)' using errcode = '42501';
end $$;
drop trigger if exists app_content_guard_live on public.app_content;
create trigger app_content_guard_live before insert or update or delete on public.app_content
  for each row execute function public.app_content_guard_live();

-- Guard: LIVE cafeteria meals change only by publishing. A meal that is a draft
-- (status 'draft', hidden from students) may be created and removed freely.
create or replace function public.cafeteria_meals_guard_live() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if current_user not in ('authenticated', 'anon') or coalesce(current_setting('app.cms_apply', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'new meals start as drafts; publish them from the publishing toolbar' using errcode = '42501';
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'a published meal cannot be deleted: unpublish it first' using errcode = '42501';
    end if;
    return old;
  end if;
  if old.status = 'draft' and new.status = 'draft' then return new; end if;
  if (new.menu_items, new.price_krw, new.start_time, new.end_time, new.status, new.badge, new.source_url, new.verified_at, new.extra, new.option_order)
     is distinct from
     (old.menu_items, old.price_krw, old.start_time, old.end_time, old.status, old.badge, old.source_url, old.verified_at, old.extra, old.option_order) then
    raise exception 'live meals are changed only by publishing (save a draft, then publish)' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists cafeteria_meals_guard_live on public.cafeteria_meals;
create trigger cafeteria_meals_guard_live before insert or update or delete on public.cafeteria_meals
  for each row execute function public.cafeteria_meals_guard_live();

-- Guard: live menus change only by publishing (a restaurant's menu list is published as one set).
create or replace function public.restaurant_menus_guard_live() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if current_user not in ('authenticated', 'anon') or coalesce(current_setting('app.cms_apply', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  raise exception 'live menus are changed only by publishing (save a draft, then publish)' using errcode = '42501';
end $$;
drop trigger if exists restaurant_menus_guard_live on public.restaurant_menus;
create trigger restaurant_menus_guard_live before insert or update or delete on public.restaurant_menus
  for each row execute function public.restaurant_menus_guard_live();

-- Guard: LIVE photos change only by publishing. A hidden (archived) photo is a staging row:
-- it may be added (for instance an approved student photo), captioned and removed freely.
create or replace function public.restaurant_photos_guard_live() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if current_user not in ('authenticated', 'anon') or coalesce(current_setting('app.cms_apply', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'archived' then
      raise exception 'new photos start hidden; publish them from the publishing toolbar' using errcode = '42501';
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.status <> 'archived' then raise exception 'a published photo cannot be deleted: unpublish it first' using errcode = '42501'; end if;
    return old;
  end if;
  if old.status = 'archived' and new.status = 'archived' then return new; end if;
  raise exception 'live photos are changed only by publishing (save a draft, then publish)' using errcode = '42501';
end $$;
drop trigger if exists restaurant_photos_guard_live on public.restaurant_photos;
create trigger restaurant_photos_guard_live before insert or update or delete on public.restaurant_photos
  for each row execute function public.restaurant_photos_guard_live();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public._cms_lock(p_type text, p_id uuid) returns void
language sql as $$ select pg_advisory_xact_lock(hashtextextended('cms:' || p_type || ':' || p_id::text, 0)) $$;

create or replace function public._cms_live_version(p_type text, p_id uuid) returns integer
language sql stable as $$
  select coalesce(max(version), 0) from public.content_versions where entity_type = p_type and entity_id = p_id
$$;

create or replace function public._cms_admin_check() returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
end $$;

create or replace function public._cms_conflict(p_msg text) returns void
language plpgsql as $$
begin
  raise exception '%', p_msg using errcode = '40001';   -- serialization_failure: "somebody else changed it"
end $$;

-- Validate, apply and record one new live version. Atomic: any error rolls the
-- caller's transaction (or sub-transaction) back, leaving live untouched.
create or replace function public._cms_commit(
  p_type text, p_id uuid, p_data jsonb, p_kind text, p_reason text, p_actor uuid,
  p_job bigint default null, p_rolled_back_from integer default null)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v integer; applied jsonb;
begin
  perform public._cms_validate(p_type, p_data, p_id);
  perform public._cms_apply(p_type, p_id, p_data);
  v := public._cms_live_version(p_type, p_id) + 1;
  applied := public._cms_snapshot(p_type, p_id);          -- exactly what is live now
  insert into public.content_versions (entity_type, entity_id, version, kind, data, reason, rolled_back_from, published_by, job_id)
  values (p_type, p_id, v, p_kind, applied, p_reason, p_rolled_back_from, p_actor, p_job);
  insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
  values (p_actor, 'cms_' || p_kind, p_type, p_id::text, p_reason,
          jsonb_build_object('version', v, 'job', p_job, 'rolled_back_from', p_rolled_back_from));
  return v;
end $$;
revoke all on function public._cms_commit(text, uuid, jsonb, text, text, uuid, bigint, integer),
  public._cms_lock(text, uuid), public._cms_live_version(text, uuid), public._cms_admin_check(), public._cms_conflict(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Admin API (all re-check the admin role in the database)
-- ---------------------------------------------------------------------------
-- Everything the toolbar needs about one entity.
create or replace function public.cms_state(p_type text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare live jsonb; d public.content_drafts; lv integer; last_v public.content_versions; jobs jsonb; draft jsonb := null;
begin
  perform public._cms_admin_check();
  live := public._cms_snapshot(p_type, p_id);
  lv := public._cms_live_version(p_type, p_id);
  select * into last_v from public.content_versions where entity_type = p_type and entity_id = p_id order by version desc limit 1;
  select * into d from public.content_drafts where entity_type = p_type and entity_id = p_id;
  if found then
    draft := jsonb_build_object('data', d.data, 'revision', d.revision, 'base_version', d.base_version,
      'created_by', d.created_by, 'updated_by', d.updated_by, 'created_at', d.created_at, 'updated_at', d.updated_at,
      'stale', d.base_version <> lv, 'has_changes', d.data is distinct from live);
  end if;
  select coalesce(jsonb_agg(to_jsonb(j) - 'snapshot' order by j.created_at desc), '[]'::jsonb) into jobs
    from (select * from public.publication_jobs where entity_type = p_type and entity_id = p_id
           and (status in ('scheduled', 'running', 'failed') or executed_at > now() - interval '7 days')
           order by created_at desc limit 20) j;
  return jsonb_build_object('live', live, 'live_version', lv,
    'last_published', case when last_v.id is null then null else jsonb_build_object(
      'version', last_v.version, 'kind', last_v.kind, 'at', last_v.published_at, 'by', last_v.published_by, 'reason', last_v.reason) end,
    'draft', draft, 'jobs', jobs);
end $$;

create or replace function public.cms_save_draft(p_type text, p_id uuid, p_data jsonb, p_expected_revision integer default 0)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.content_drafts; lv integer;
begin
  perform public._cms_admin_check();
  perform public._cms_validate(p_type, p_data, p_id);
  perform public._cms_lock(p_type, p_id);
  perform public._cms_snapshot(p_type, p_id);               -- the entity must exist
  lv := public._cms_live_version(p_type, p_id);
  select * into d from public.content_drafts where entity_type = p_type and entity_id = p_id for update;
  if found then
    if p_expected_revision is distinct from d.revision then
      perform public._cms_conflict('다른 관리자가 이 초안을 먼저 저장했어요. 새로고침해서 최신 초안을 확인해 주세요.');
    end if;
    update public.content_drafts set data = p_data, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
     where entity_type = p_type and entity_id = p_id returning * into d;
  else
    if coalesce(p_expected_revision, 0) <> 0 then
      perform public._cms_conflict('이 초안은 이미 게시되었거나 삭제되었어요. 새로고침해 주세요.');
    end if;
    insert into public.content_drafts (entity_type, entity_id, data, base_version, created_by, updated_by)
    values (p_type, p_id, p_data, lv, auth.uid(), auth.uid()) returning * into d;
  end if;
  return jsonb_build_object('revision', d.revision, 'base_version', d.base_version, 'updated_at', d.updated_at);
end $$;

create or replace function public.cms_discard_draft(p_type text, p_id uuid, p_expected_revision integer)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.content_drafts;
begin
  perform public._cms_admin_check();
  perform public._cms_lock(p_type, p_id);
  select * into d from public.content_drafts where entity_type = p_type and entity_id = p_id for update;
  if not found then return; end if;
  if p_expected_revision is distinct from d.revision then
    perform public._cms_conflict('다른 관리자가 이 초안을 먼저 저장했어요. 새로고침해 주세요.');
  end if;
  delete from public.content_drafts where entity_type = p_type and entity_id = p_id;
end $$;

-- Keep the draft's content but start it from the CURRENT live version (after
-- someone else published, or after a rollback / unpublish).
create or replace function public.cms_rebase_draft(p_type text, p_id uuid, p_expected_revision integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.content_drafts;
begin
  perform public._cms_admin_check();
  perform public._cms_lock(p_type, p_id);
  select * into d from public.content_drafts where entity_type = p_type and entity_id = p_id for update;
  if not found then raise exception 'no draft' using errcode = 'P0002'; end if;
  if p_expected_revision is distinct from d.revision then
    perform public._cms_conflict('다른 관리자가 이 초안을 먼저 저장했어요. 새로고침해 주세요.');
  end if;
  update public.content_drafts set base_version = public._cms_live_version(p_type, p_id), revision = revision + 1,
         updated_by = auth.uid(), updated_at = now()
   where entity_type = p_type and entity_id = p_id returning * into d;
  return jsonb_build_object('revision', d.revision, 'base_version', d.base_version);
end $$;

create or replace function public.cms_publish(p_type text, p_id uuid, p_expected_revision integer, p_reason text default null)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.content_drafts; v integer;
begin
  perform public._cms_admin_check();
  perform public._cms_lock(p_type, p_id);
  select * into d from public.content_drafts where entity_type = p_type and entity_id = p_id for update;
  if not found then raise exception '게시할 초안이 없어요' using errcode = 'P0002'; end if;
  if p_expected_revision is distinct from d.revision then
    perform public._cms_conflict('다른 관리자가 이 초안을 먼저 저장했어요. 새로고침해서 확인한 뒤 다시 게시해 주세요.');
  end if;
  if d.base_version <> public._cms_live_version(p_type, p_id) then
    perform public._cms_conflict('이 초안을 만든 뒤 라이브 내용이 바뀌었어요. 초안을 최신 라이브 기준으로 다시 맞춘 뒤 게시해 주세요.');
  end if;
  if exists (select 1 from public.publication_jobs where entity_type = p_type and entity_id = p_id and action = 'publish' and status = 'scheduled') then
    raise exception '예약된 게시가 있어요. 예약을 취소한 뒤 지금 게시해 주세요.' using errcode = '55006';
  end if;
  v := public._cms_commit(p_type, p_id, d.data, 'publish', p_reason, auth.uid());
  delete from public.content_drafts where entity_type = p_type and entity_id = p_id;
  return v;
end $$;

create or replace function public.cms_schedule(
  p_type text, p_id uuid, p_expected_revision integer, p_run_at timestamptz,
  p_unpublish_at timestamptz default null, p_reason text default null)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.content_drafts; j bigint;
begin
  perform public._cms_admin_check();
  perform public._cms_lock(p_type, p_id);
  select * into d from public.content_drafts where entity_type = p_type and entity_id = p_id for update;
  if not found then raise exception '예약할 초안이 없어요' using errcode = 'P0002'; end if;
  if p_expected_revision is distinct from d.revision then
    perform public._cms_conflict('다른 관리자가 이 초안을 먼저 저장했어요. 새로고침해 주세요.');
  end if;
  if d.base_version <> public._cms_live_version(p_type, p_id) then
    perform public._cms_conflict('이 초안을 만든 뒤 라이브 내용이 바뀌었어요. 초안을 최신 라이브 기준으로 다시 맞춘 뒤 예약해 주세요.');
  end if;
  if p_run_at is null or p_run_at < now() + interval '1 minute' then
    raise exception '예약 시각은 지금부터 1분 이후여야 해요' using errcode = '22023';
  end if;
  if p_unpublish_at is not null and p_unpublish_at <= p_run_at then
    raise exception '게시 종료 시각은 게시 시각보다 늦어야 해요' using errcode = '22023';
  end if;
  perform public._cms_validate(p_type, d.data, p_id);
  if exists (select 1 from public.publication_jobs where entity_type = p_type and entity_id = p_id and action = 'publish' and status = 'scheduled') then
    raise exception '이미 예약된 게시가 있어요. 예약을 취소하거나 시간을 바꿔 주세요.' using errcode = '55006';
  end if;
  -- The snapshot is FROZEN here: later draft edits never change what runs.
  insert into public.publication_jobs (entity_type, entity_id, action, snapshot, base_version, run_at, unpublish_at, reason, created_by)
  values (p_type, p_id, 'publish', d.data, d.base_version, p_run_at, p_unpublish_at, p_reason, auth.uid())
  returning id into j;
  if p_unpublish_at is not null then
    insert into public.publication_jobs (entity_type, entity_id, action, run_at, reason, created_by, parent_job_id, base_version)
    values (p_type, p_id, 'unpublish', p_unpublish_at, coalesce(p_reason, '예약 종료'), auth.uid(), j, 0);
  end if;
  insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
  values (auth.uid(), 'cms_schedule', p_type, p_id::text, p_reason, jsonb_build_object('job', j, 'run_at', p_run_at, 'unpublish_at', p_unpublish_at));
  return j;
end $$;

create or replace function public.cms_reschedule(p_job bigint, p_run_at timestamptz, p_unpublish_at timestamptz default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare j public.publication_jobs; child public.publication_jobs;
begin
  perform public._cms_admin_check();
  select * into j from public.publication_jobs where id = p_job and action = 'publish' for update;
  if not found or j.status <> 'scheduled' then raise exception '예약 상태의 게시만 시간을 바꿀 수 있어요' using errcode = 'P0002'; end if;
  perform public._cms_lock(j.entity_type, j.entity_id);
  if p_run_at < now() + interval '1 minute' then raise exception '예약 시각은 지금부터 1분 이후여야 해요' using errcode = '22023'; end if;
  if p_unpublish_at is not null and p_unpublish_at <= p_run_at then raise exception '게시 종료 시각은 게시 시각보다 늦어야 해요' using errcode = '22023'; end if;
  update public.publication_jobs set run_at = p_run_at, unpublish_at = p_unpublish_at, updated_at = now() where id = p_job;
  select * into child from public.publication_jobs where parent_job_id = p_job and action = 'unpublish' and status = 'scheduled' for update;
  if found and p_unpublish_at is null then
    update public.publication_jobs set status = 'cancelled', last_error = '종료 예약을 지웠어요', updated_at = now() where id = child.id;
  elsif found then
    update public.publication_jobs set run_at = p_unpublish_at, updated_at = now() where id = child.id;
  elsif p_unpublish_at is not null then
    insert into public.publication_jobs (entity_type, entity_id, action, run_at, reason, created_by, parent_job_id, base_version)
    values (j.entity_type, j.entity_id, 'unpublish', p_unpublish_at, coalesce(j.reason, '예약 종료'), auth.uid(), p_job, 0);
  end if;
  insert into public.audit_log (actor_id, action, table_name, row_id, details)
  values (auth.uid(), 'cms_reschedule', j.entity_type, j.entity_id::text, jsonb_build_object('job', p_job, 'run_at', p_run_at, 'unpublish_at', p_unpublish_at));
end $$;

create or replace function public.cms_cancel_job(p_job bigint, p_reason text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare j public.publication_jobs;
begin
  perform public._cms_admin_check();
  select * into j from public.publication_jobs where id = p_job for update;
  if not found or j.status not in ('scheduled', 'failed') then
    raise exception '예약 중이거나 실패한 게시만 취소할 수 있어요' using errcode = 'P0002';
  end if;
  update public.publication_jobs set status = 'cancelled', last_error = coalesce(p_reason, last_error), updated_at = now()
   where id = p_job or (parent_job_id = p_job and status in ('scheduled', 'failed'));
  insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
  values (auth.uid(), 'cms_cancel', j.entity_type, j.entity_id::text, p_reason, jsonb_build_object('job', p_job));
end $$;

-- A failed job goes back to "scheduled" and runs on the next tick. Safe to
-- repeat: the job is locked and status-guarded when it runs.
create or replace function public.cms_retry_job(p_job bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare j public.publication_jobs;
begin
  perform public._cms_admin_check();
  select * into j from public.publication_jobs where id = p_job for update;
  if not found or j.status <> 'failed' then raise exception '실패한 게시만 다시 시도할 수 있어요' using errcode = 'P0002'; end if;
  update public.publication_jobs set status = 'scheduled', run_at = greatest(run_at, now()), last_error = null, updated_at = now() where id = p_job;
  insert into public.audit_log (actor_id, action, table_name, row_id, details)
  values (auth.uid(), 'cms_retry', j.entity_type, j.entity_id::text, jsonb_build_object('job', p_job));
end $$;

create or replace function public.cms_unpublish(p_type text, p_id uuid, p_reason text)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._cms_admin_check();
  if p_reason is null or btrim(p_reason) = '' then raise exception '사유를 입력해 주세요' using errcode = '22023'; end if;
  perform public._cms_lock(p_type, p_id);
  return public._cms_commit(p_type, p_id, public._cms_unpublished(p_type, public._cms_snapshot(p_type, p_id)), 'unpublish', p_reason, auth.uid());
end $$;

-- Restore an older version by publishing its snapshot as a NEW version.
create or replace function public.cms_rollback(p_type text, p_id uuid, p_version integer, p_reason text)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare old public.content_versions;
begin
  perform public._cms_admin_check();
  if p_reason is null or btrim(p_reason) = '' then raise exception '사유를 입력해 주세요' using errcode = '22023'; end if;
  perform public._cms_lock(p_type, p_id);
  select * into old from public.content_versions where entity_type = p_type and entity_id = p_id and version = p_version;
  if not found then raise exception '그 버전이 없어요' using errcode = 'P0002'; end if;
  return public._cms_commit(p_type, p_id, old.data, 'rollback', p_reason, auth.uid(), null, p_version);
end $$;

-- Quick visibility change from lists (an immediate, versioned publish).
create or replace function public.cms_set_visibility(p_type text, p_id uuid, p_visibility text, p_reason text)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._cms_admin_check();
  if p_type not in ('restaurant', 'cafeteria_meal', 'mission', 'app_content', 'university', 'campaign') then raise exception 'visibility does not apply to %', p_type using errcode = '22023'; end if;
  if p_visibility not in ('draft', 'published', 'hidden', 'archived') then raise exception '공개 상태가 올바르지 않아요' using errcode = '22023'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception '사유를 입력해 주세요' using errcode = '22023'; end if;
  perform public._cms_lock(p_type, p_id);
  -- restaurants carry "visibility"; a meal's visible/hidden is its "status" (published / draft)
  return public._cms_commit(p_type, p_id,
    public._cms_snapshot(p_type, p_id) || case p_type
      when 'cafeteria_meal' then jsonb_build_object('status', case p_visibility when 'published' then 'published' else 'draft' end)
      when 'mission' then jsonb_build_object('status', case p_visibility when 'published' then 'active' when 'hidden' then 'paused' else p_visibility end)
      when 'app_content' then jsonb_build_object('active', p_visibility = 'published')
      when 'university' then jsonb_build_object('is_active', p_visibility = 'published')
      when 'campaign' then jsonb_build_object('publish_state', case when p_visibility = 'published' then 'published' else 'draft' end)
      else jsonb_build_object('visibility', p_visibility) end,
    'visibility', p_reason, auth.uid());
end $$;

-- One row per entity for the list filters: draft / scheduled / failed.
-- [p_parent] limits meals to one cafeteria.
create or replace function public.cms_overview(p_type text, p_parent uuid default null)
returns table (entity_id uuid, has_draft boolean, draft_updated_at timestamptz, scheduled_at timestamptz,
               failed_jobs integer, live_version integer, last_published_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._cms_admin_check();
  return query
    select e.id,
           exists (select 1 from public.content_drafts d where d.entity_type = p_type and d.entity_id = e.id),
           (select d.updated_at from public.content_drafts d where d.entity_type = p_type and d.entity_id = e.id),
           (select min(j.run_at) from public.publication_jobs j where j.entity_type = p_type and j.entity_id = e.id and j.status = 'scheduled' and j.action = 'publish'),
           (select count(*)::integer from public.publication_jobs j where j.entity_type = p_type and j.entity_id = e.id and j.status = 'failed'),
           public._cms_live_version(p_type, e.id),
           (select max(v.published_at) from public.content_versions v where v.entity_type = p_type and v.entity_id = e.id)
      from (select o.id from public.restaurant_overrides o where p_type in ('restaurant', 'restaurant_menus', 'restaurant_photos', 'mission', 'app_content', 'university', 'campaign')
            union all
            select m.id from public.cafeteria_meals m where p_type = 'cafeteria_meal' and (p_parent is null or m.cafeteria_id = p_parent)
            union all
            select c.id from public.monthly_campaigns c where p_type = 'campaign'
            union all
            select u.id from public.universities u where p_type = 'university'
            union all
            select c.id from public.app_content c where p_type = 'app_content'
            union all
            select distinct m.lineage_id from public.missions m where p_type = 'mission' and (p_parent is null or m.campaign_id = p_parent)) e;
end $$;

-- ---------------------------------------------------------------------------
-- The scheduler. NOT callable from the API: pg_cron runs it inside the database.
-- ---------------------------------------------------------------------------
create or replace function public.cms_run_due_jobs() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  j public.publication_jobs; parent public.publication_jobs; v integer; d public.content_drafts;
  n_ok integer := 0; n_failed integer := 0; n_skipped integer := 0;
begin
  for j in
    select * from public.publication_jobs
     where status = 'scheduled' and run_at <= now()
     order by run_at, id
       for update skip locked
  loop
    begin
      -- Re-check under the entity lock; a job another run already handled is skipped.
      perform public._cms_lock(j.entity_type, j.entity_id);
      if (select status from public.publication_jobs where id = j.id) <> 'scheduled' then n_skipped := n_skipped + 1; continue; end if;
      update public.publication_jobs set status = 'running', updated_at = now() where id = j.id;

      -- The person who scheduled it must still be allowed to publish.
      if not exists (select 1 from public.admin_roles r where r.user_id = j.created_by and public.admin_rank(r.role) >= public.admin_rank('admin')) then
        raise exception '예약한 관리자가 더 이상 게시 권한이 없어요';
      end if;

      if j.action = 'publish' then
        if j.base_version <> public._cms_live_version(j.entity_type, j.entity_id) then
          raise exception '예약한 뒤 라이브 내용이 바뀌어서 게시하지 않았어요 (충돌)';
        end if;
        v := public._cms_commit(j.entity_type, j.entity_id, j.snapshot, 'publish', j.reason, j.created_by, j.id);
        -- the draft that was scheduled is now live: drop it if identical, else keep the
        -- later edits and restart them from the new live version
        select * into d from public.content_drafts where entity_type = j.entity_type and entity_id = j.entity_id for update;
        if found then
          if d.data = j.snapshot then
            delete from public.content_drafts where entity_type = j.entity_type and entity_id = j.entity_id;
          else
            update public.content_drafts set base_version = v, revision = revision + 1, updated_at = now()
             where entity_type = j.entity_type and entity_id = j.entity_id;
          end if;
        end if;
      else
        select * into parent from public.publication_jobs where id = j.parent_job_id;
        if j.parent_job_id is not null and (parent.status is distinct from 'published') then
          update public.publication_jobs set status = 'cancelled', last_error = '게시가 실행되지 않아 종료도 취소했어요', executed_at = now(), updated_at = now() where id = j.id;
          n_skipped := n_skipped + 1;
          continue;
        end if;
        v := public._cms_commit(j.entity_type, j.entity_id,
               public._cms_unpublished(j.entity_type, public._cms_snapshot(j.entity_type, j.entity_id)),
               'unpublish', j.reason, j.created_by, j.id);
      end if;
      update public.publication_jobs set status = 'published', published_version = v, attempts = attempts + 1, executed_at = now(), last_error = null, updated_at = now() where id = j.id;
      n_ok := n_ok + 1;
    exception when others then
      -- the sub-transaction above is rolled back: live is untouched
      update public.publication_jobs set status = 'failed', attempts = attempts + 1, last_error = left(sqlerrm, 500), executed_at = now(), updated_at = now() where id = j.id;
      insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
      values (j.created_by, 'cms_job_failed', j.entity_type, j.entity_id::text, left(sqlerrm, 500), jsonb_build_object('job', j.id));
      n_failed := n_failed + 1;
    end;
  end loop;
  return jsonb_build_object('published', n_ok, 'failed', n_failed, 'skipped', n_skipped);
end $$;

-- Function privileges
revoke all on function
  public.cms_state(text, uuid), public.cms_save_draft(text, uuid, jsonb, integer), public.cms_discard_draft(text, uuid, integer),
  public.cms_rebase_draft(text, uuid, integer), public.cms_publish(text, uuid, integer, text),
  public.cms_schedule(text, uuid, integer, timestamptz, timestamptz, text), public.cms_reschedule(bigint, timestamptz, timestamptz),
  public.cms_cancel_job(bigint, text), public.cms_retry_job(bigint), public.cms_unpublish(text, uuid, text),
  public.cms_rollback(text, uuid, integer, text), public.cms_set_visibility(text, uuid, text, text), public.cms_overview(text, uuid),
  public.cms_run_due_jobs()
  from public, anon;
revoke all on function public.cms_run_due_jobs() from authenticated;
grant execute on function
  public.cms_state(text, uuid), public.cms_save_draft(text, uuid, jsonb, integer), public.cms_discard_draft(text, uuid, integer),
  public.cms_rebase_draft(text, uuid, integer), public.cms_publish(text, uuid, integer, text),
  public.cms_schedule(text, uuid, integer, timestamptz, timestamptz, text), public.cms_reschedule(bigint, timestamptz, timestamptz),
  public.cms_cancel_job(bigint, text), public.cms_retry_job(bigint), public.cms_unpublish(text, uuid, text),
  public.cms_rollback(text, uuid, integer, text), public.cms_set_visibility(text, uuid, text, text), public.cms_overview(text, uuid)
  to authenticated;

-- Unpublished photo files must not be discoverable. The bucket stays public (files are served by
-- their unguessable URL, which is all the app and the published rows need), but the API may no
-- longer LIST it: only admins can see the object list. A file that is not in any published
-- row is therefore reachable only by someone who already has its random URL.
do $$ begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "restaurant-images: public read" on storage.objects;
    drop policy if exists "restaurant-images: admin read" on storage.objects;
    create policy "restaurant-images: admin read" on storage.objects
      for select to authenticated using (bucket_id = 'restaurant-images' and (select public.has_role('admin')));
  end if;
end $$;

-- Schedule the runner (every minute) with pg_cron, where it is available.
-- pg_cron must be enabled for the project (Dashboard -> Database -> Extensions).
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be enabled here (%). Enable it in the Supabase dashboard, then run this migration again.', sqlerrm;
  end;
  if to_regnamespace('cron') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'cms-run-due-jobs';
    perform cron.schedule('cms-run-due-jobs', '* * * * *', 'select public.cms_run_due_jobs()');
  else
    raise notice 'pg_cron is not available: scheduled publications will NOT run until it is enabled.';
  end if;
end $$;
