-- Controlled publishing for admin-managed content: draft -> preview -> publish
-- now / schedule -> live, with immutable version history, rollback and a
-- server-side scheduler. First entity type: 'restaurant' (restaurant_overrides).
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
     or to_regprocedure('public.has_role(text)') is null
     or to_regprocedure('public._audit(text, text, text, text, jsonb)') is null then
    raise exception 'Apply 20261109000100 and 20261110000100 first.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.content_drafts (
  entity_type  text not null check (entity_type in ('restaurant')),
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
  entity_type      text not null check (entity_type in ('restaurant')),
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
  entity_type      text not null check (entity_type in ('restaurant')),
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
  else
    raise exception 'unknown entity type' using errcode = '22023';
  end if;
  if v is null then raise exception 'no such %', p_type using errcode = 'P0002'; end if;
  return v;
end $$;

-- Friendly validation (the table's CHECK constraints remain the last line of defence).
create or replace function public._cms_validate(p_type text, p_data jsonb) returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare k text;
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
  end if;
end $$;

-- What "unpublished" means for a type (non-destructive: nothing is deleted).
create or replace function public._cms_unpublished(p_type text, p_live jsonb) returns jsonb
language sql immutable as $$
  select case p_type when 'restaurant' then p_live || '{"visibility":"hidden"}'::jsonb else p_live end
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
  else
    raise exception 'unknown entity type' using errcode = '22023';
  end if;
  perform set_config('app.cms_apply', 'off', true);
end $$;
revoke all on function public._cms_apply(text, uuid, jsonb), public._cms_snapshot(text, uuid),
  public._cms_validate(text, jsonb), public._cms_unpublished(text, jsonb), public._cms_keys(text)
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
  perform public._cms_validate(p_type, p_data);
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
  perform public._cms_validate(p_type, p_data);
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
  perform public._cms_validate(p_type, d.data);
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
  if p_visibility not in ('draft', 'published', 'hidden', 'archived') then raise exception '공개 상태가 올바르지 않아요' using errcode = '22023'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception '사유를 입력해 주세요' using errcode = '22023'; end if;
  perform public._cms_lock(p_type, p_id);
  return public._cms_commit(p_type, p_id,
    public._cms_snapshot(p_type, p_id) || jsonb_build_object('visibility', p_visibility), 'visibility', p_reason, auth.uid());
end $$;

-- One row per entity for the list filters: draft / scheduled / failed.
create or replace function public.cms_overview(p_type text)
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
      from public.restaurant_overrides e
     where p_type = 'restaurant';
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
  public.cms_rollback(text, uuid, integer, text), public.cms_set_visibility(text, uuid, text, text), public.cms_overview(text),
  public.cms_run_due_jobs()
  from public, anon;
revoke all on function public.cms_run_due_jobs() from authenticated;
grant execute on function
  public.cms_state(text, uuid), public.cms_save_draft(text, uuid, jsonb, integer), public.cms_discard_draft(text, uuid, integer),
  public.cms_rebase_draft(text, uuid, integer), public.cms_publish(text, uuid, integer, text),
  public.cms_schedule(text, uuid, integer, timestamptz, timestamptz, text), public.cms_reschedule(bigint, timestamptz, timestamptz),
  public.cms_cancel_job(bigint, text), public.cms_retry_job(bigint), public.cms_unpublish(text, uuid, text),
  public.cms_rollback(text, uuid, integer, text), public.cms_set_visibility(text, uuid, text, text), public.cms_overview(text)
  to authenticated;

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
