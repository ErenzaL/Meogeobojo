-- 학식: weekly menu management, atomic weekly publishing and a server-side CSV import.
--
-- Additive and idempotent. Requires 20261113000100 (cafeteria management) and 20261115000100 (publishing).
-- Changes no existing data. Does not touch applied migrations: the publishing functions are WRAPPED
-- (renamed to *_v1, then a function with the same name handles the new type and delegates everything else).
--
--  * campus_cafeterias: which meal periods and weekdays a cafeteria serves (never assumed), and a photo.
--  * cafeteria_weeks:   one row per (cafeteria, Monday). The CMS entity 'cafeteria_week' = ALL menus of that
--                       cafeteria for that week, so draft / preview / publish / schedule / unpublish / rollback
--                       act on the whole week atomically, with the existing versioning, audit and pg_cron runner.
--  * cms_publish_week_days(): publish only the chosen days of a week draft, atomically.
--  * cafeteria_import():  validated, idempotent CSV import that only ever writes DRAFTS.
-- The programme "천원의 아침밥" stays a breakfast option (badge) and needs an official source, as before.

do $$ begin
  if to_regclass('public.campus_cafeterias') is null or to_regclass('public.cafeteria_meals') is null
     or to_regprocedure('public._cms_commit(text, uuid, jsonb, text, text, uuid, bigint, integer)') is null
     or to_regprocedure('public.cms_overview(text, uuid)') is null then
    raise exception 'Apply 20261113000100 and 20261115000100 first.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Cafeteria details
-- ---------------------------------------------------------------------------
alter table public.campus_cafeterias
  add column if not exists meal_periods  text[]     not null default array['breakfast', 'lunch', 'dinner'],
  add column if not exists operating_days smallint[] not null default array[1, 2, 3, 4, 5]::smallint[],
  add column if not exists photo_url     text,
  add column if not exists photo_path    text;
alter table public.campus_cafeterias drop constraint if exists campus_cafeterias_meal_periods_check;
alter table public.campus_cafeterias add constraint campus_cafeterias_meal_periods_check
  check (cardinality(meal_periods) between 1 and 3 and meal_periods <@ array['breakfast', 'lunch', 'dinner']);
alter table public.campus_cafeterias drop constraint if exists campus_cafeterias_operating_days_check;
alter table public.campus_cafeterias add constraint campus_cafeterias_operating_days_check
  check (cardinality(operating_days) between 1 and 7 and operating_days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]);
alter table public.campus_cafeterias drop constraint if exists campus_cafeterias_photo_url_check;
alter table public.campus_cafeterias add constraint campus_cafeterias_photo_url_check
  check (photo_url is null or photo_url ~ '^https://');

-- ---------------------------------------------------------------------------
-- 2. One publishable unit per (cafeteria, week)
-- ---------------------------------------------------------------------------
create table if not exists public.cafeteria_weeks (
  id           uuid primary key default gen_random_uuid(),
  cafeteria_id uuid not null references public.campus_cafeterias (id) on delete cascade,
  week_start   date not null check (extract(isodow from week_start) = 1),   -- always a Monday
  created_at   timestamptz not null default now(),
  unique (cafeteria_id, week_start)
);
alter table public.cafeteria_weeks enable row level security;
revoke all on public.cafeteria_weeks from anon, authenticated;
grant select on public.cafeteria_weeks to authenticated;
drop policy if exists "cafeteria_weeks: admin read" on public.cafeteria_weeks;
create policy "cafeteria_weeks: admin read" on public.cafeteria_weeks for select to authenticated using ((select public.has_role('admin')));

-- the entity id of a week (created on first use); internal, no role check
create or replace function public._cafeteria_week_id(p_cafeteria uuid, p_week date) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare ws date := date_trunc('week', p_week)::date; v uuid;
begin
  select id into v from public.cafeteria_weeks where cafeteria_id = p_cafeteria and week_start = ws;
  if v is null then
    insert into public.cafeteria_weeks (cafeteria_id, week_start) values (p_cafeteria, ws)
      on conflict (cafeteria_id, week_start) do nothing;
    select id into v from public.cafeteria_weeks where cafeteria_id = p_cafeteria and week_start = ws;
  end if;
  return v;
end $$;
revoke all on function public._cafeteria_week_id(uuid, date) from public, anon, authenticated;

create or replace function public.cafeteria_week_entity(p_cafeteria uuid, p_week date) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._cms_admin_check();
  if not exists (select 1 from public.campus_cafeterias where id = p_cafeteria) then
    raise exception 'no such cafeteria' using errcode = 'P0002';
  end if;
  return public._cafeteria_week_id(p_cafeteria, p_week);
end $$;

-- the menus of one cafeteria for one week, in snapshot shape (hidden 'draft' rows are not part of it)
create or replace function public._cafeteria_week_meals(p_cafeteria uuid, p_week date) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'date', to_char(m.meal_date, 'YYYY-MM-DD'), 'meal_type', m.meal_type, 'option_name', m.option_name, 'option_order', m.option_order,
      'menu_items', m.menu_items, 'price_krw', m.price_krw, 'start_time', to_char(m.start_time, 'HH24:MI'), 'end_time', to_char(m.end_time, 'HH24:MI'),
      'status', m.status, 'badge', m.badge, 'source_url', m.source_url, 'verified_at', m.verified_at, 'extra', m.extra)
    order by m.meal_date, case m.meal_type when 'breakfast' then 1 when 'lunch' then 2 else 3 end, m.option_order, m.option_name), '[]'::jsonb)
  from public.cafeteria_meals m
  where m.cafeteria_id = p_cafeteria and m.meal_date between p_week and p_week + 6 and m.status <> 'draft'
$$;
revoke all on function public._cafeteria_week_meals(uuid, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Plug the new type into the publishing engine (wrap, do not copy)
-- ---------------------------------------------------------------------------
do $$ begin
  if to_regprocedure('public._cms_snapshot_v1(text, uuid)') is null then alter function public._cms_snapshot(text, uuid) rename to _cms_snapshot_v1; end if;
  if to_regprocedure('public._cms_validate_v1(text, jsonb, uuid)') is null then alter function public._cms_validate(text, jsonb, uuid) rename to _cms_validate_v1; end if;
  if to_regprocedure('public._cms_apply_v1(text, uuid, jsonb)') is null then alter function public._cms_apply(text, uuid, jsonb) rename to _cms_apply_v1; end if;
  if to_regprocedure('public._cms_unpublished_v1(text, jsonb)') is null then alter function public._cms_unpublished(text, jsonb) rename to _cms_unpublished_v1; end if;
  if to_regprocedure('public.cms_overview_v1(text, uuid)') is null then alter function public.cms_overview(text, uuid) rename to cms_overview_v1; end if;
  if to_regprocedure('public._cms_label_v1(text, uuid)') is null and to_regprocedure('public._cms_label(text, uuid)') is not null then alter function public._cms_label(text, uuid) rename to _cms_label_v1; end if;
end $$;

-- the CHECK on the three publishing tables accepts the new type too (same technique as 20261116000100)
do $$
declare t text; c record;
  types constant text := $l$('restaurant', 'cafeteria_meal', 'restaurant_menus', 'restaurant_photos', 'mission', 'campaign', 'app_content', 'university', 'cafeteria_week')$l$;
begin
  foreach t in array array['content_drafts', 'content_versions', 'publication_jobs'] loop
    for c in select conname from pg_constraint
              where conrelid = ('public.' || t)::regclass and contype = 'c' and pg_get_constraintdef(oid) ~ '^CHECK \(\(entity_type = '
    loop
      execute format('alter table public.%I drop constraint %I', t, c.conname);
    end loop;
    execute format('alter table public.%I add constraint %I check (entity_type in %s)', t, t || '_entity_type_check', types);
  end loop;
end $$;

create or replace function public._cms_snapshot(p_type text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare w public.cafeteria_weeks;
begin
  if p_type <> 'cafeteria_week' then return public._cms_snapshot_v1(p_type, p_id); end if;
  select * into w from public.cafeteria_weeks where id = p_id;
  if not found then raise exception 'no such cafeteria_week' using errcode = 'P0002'; end if;
  return jsonb_build_object('meals', public._cafeteria_week_meals(w.cafeteria_id, w.week_start));
end $$;

-- Friendly validation of one week's menus (the table CHECKs stay the last line of defence).
create or replace function public._cafeteria_week_validate(p_data jsonb, p_week date) returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare m jsonb; k text; seen text[] := '{}'; kk text; it jsonb; pr integer; n integer; ex jsonb;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception '주간 식단이 올바르지 않아요' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_data) loop
    if k <> 'meals' then raise exception 'unknown field: %', k using errcode = '22023'; end if;
  end loop;
  if jsonb_typeof(p_data -> 'meals') is distinct from 'array' then raise exception '식단 목록이 올바르지 않아요' using errcode = '22023'; end if;
  if jsonb_array_length(p_data -> 'meals') > 300 then raise exception '한 주에는 식단을 300개까지 둘 수 있어요' using errcode = '22023'; end if;
  for m in select * from jsonb_array_elements(p_data -> 'meals') loop
    if jsonb_typeof(m) <> 'object' then raise exception '식단 항목이 올바르지 않아요' using errcode = '22023'; end if;
    for k in select jsonb_object_keys(m) loop
      if k <> all (array['date', 'meal_type', 'option_name', 'option_order', 'menu_items', 'price_krw', 'start_time', 'end_time', 'status', 'badge', 'source_url', 'verified_at', 'extra']) then
        raise exception '알 수 없는 식단 필드: %', k using errcode = '22023';
      end if;
    end loop;
    begin perform (m ->> 'date')::date; exception when others then raise exception '날짜가 올바르지 않아요: %', coalesce(m ->> 'date', '(없음)') using errcode = '22023'; end;
    if p_week is not null and ((m ->> 'date')::date < p_week or (m ->> 'date')::date > p_week + 6) then
      raise exception '% 은(는) 이 주(%)에 속하지 않아요', m ->> 'date', p_week using errcode = '22023';
    end if;
    if coalesce(m ->> 'meal_type', '') not in ('breakfast', 'lunch', 'dinner') then raise exception '식사 종류가 올바르지 않아요 (조식·중식·석식)' using errcode = '22023'; end if;
    if char_length(coalesce(m ->> 'option_name', '')) > 40 then raise exception '코너/옵션 이름은 40자 이하여야 해요' using errcode = '22023'; end if;
    kk := (m ->> 'date') || '|' || (m ->> 'meal_type') || '|' || coalesce(m ->> 'option_name', '');
    if kk = any (seen) then raise exception '같은 날짜·식사·옵션이 두 번 있어요: %', replace(kk, '|', ' ') using errcode = '22023'; end if;
    seen := seen || kk;
    begin n := coalesce((m ->> 'option_order')::integer, 0); if n < 0 or n > 50 then raise exception 'x'; end if;
    exception when others then raise exception '옵션 순서가 올바르지 않아요' using errcode = '22023'; end;
    if coalesce(m ->> 'status', '') not in ('published', 'closed', 'no_menu') then raise exception '식단 상태가 올바르지 않아요' using errcode = '22023'; end if;
    if jsonb_typeof(m -> 'menu_items') is distinct from 'array' then raise exception '메뉴 목록이 올바르지 않아요' using errcode = '22023'; end if;
    for it in select * from jsonb_array_elements(m -> 'menu_items') loop
      if jsonb_typeof(it) <> 'object' or btrim(coalesce(it ->> 'name_ko', '')) = '' then raise exception '메뉴 이름은 비워 둘 수 없어요' using errcode = '22023'; end if;
    end loop;
    if m ->> 'status' = 'published' and jsonb_array_length(m -> 'menu_items') = 0 then
      raise exception '공개하려면 메뉴가 한 개 이상 필요해요 (% %)', m ->> 'date', m ->> 'meal_type' using errcode = '22023';
    end if;
    begin pr := (m ->> 'price_krw')::integer; if pr < 0 then raise exception 'x'; end if;
    exception when others then raise exception '가격은 0 이상의 정수여야 해요' using errcode = '22023'; end;
    if (m ->> 'start_time') is not null and (m ->> 'start_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception '시작 시간 형식이 올바르지 않아요 (HH:MM)' using errcode = '22023'; end if;
    if (m ->> 'end_time') is not null and (m ->> 'end_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception '종료 시간 형식이 올바르지 않아요 (HH:MM)' using errcode = '22023'; end if;
    if (m ->> 'start_time') is not null and (m ->> 'end_time') is not null and (m ->> 'start_time') >= (m ->> 'end_time') then
      raise exception '종료는 시작보다 늦어야 해요 (% %)', m ->> 'date', m ->> 'meal_type' using errcode = '22023';
    end if;
    if (m ->> 'source_url') is not null and (m ->> 'source_url') !~ '^https://' then raise exception '출처 주소는 https:// 로 시작해야 해요' using errcode = '22023'; end if;
    if (m ->> 'verified_at') is null then raise exception '확인한 날짜가 필요해요' using errcode = '22023'; end if;
    begin perform (m ->> 'verified_at')::timestamptz; exception when others then raise exception '확인한 날짜 형식이 올바르지 않아요' using errcode = '22023'; end;
    ex := m -> 'extra';
    if ex is not null and (jsonb_typeof(ex) <> 'object' or octet_length(ex::text) > 4000) then raise exception '추가 정보가 올바르지 않아요' using errcode = '22023'; end if;
    -- the 천원의 아침밥 programme: breakfast only, and only with an official source (the existing data policy)
    if btrim(coalesce(m ->> 'badge', '')) = '천원의 아침밥' then
      if m ->> 'meal_type' <> 'breakfast' then raise exception '천원의 아침밥은 조식에만 쓸 수 있어요 (%)', m ->> 'date' using errcode = '22023'; end if;
      if btrim(coalesce(m ->> 'source_url', '')) = '' then raise exception '천원의 아침밥은 공식 출처 주소가 있어야 해요 (%)', m ->> 'date' using errcode = '22023'; end if;
    end if;
  end loop;
end $$;
revoke all on function public._cafeteria_week_validate(jsonb, date) from public, anon, authenticated;

create or replace function public._cms_validate(p_type text, p_data jsonb, p_id uuid default null) returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare ws date;
begin
  if p_type <> 'cafeteria_week' then perform public._cms_validate_v1(p_type, p_data, p_id); return; end if;
  if p_id is not null then select week_start into ws from public.cafeteria_weeks where id = p_id; end if;
  perform public._cafeteria_week_validate(p_data, ws);
end $$;

create or replace function public._cms_apply(p_type text, p_id uuid, p_data jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare w public.cafeteria_weeks;
begin
  if p_type <> 'cafeteria_week' then perform public._cms_apply_v1(p_type, p_id, p_data); return; end if;
  perform set_config('app.cms_apply', 'on', true);
  select * into w from public.cafeteria_weeks where id = p_id;
  if not found then raise exception 'no such cafeteria_week' using errcode = 'P0002'; end if;
  -- a menu that is no longer in the week is hidden (status 'draft'), never deleted; a blank cell changes nothing
  update public.cafeteria_meals x set status = 'draft'
   where x.cafeteria_id = w.cafeteria_id and x.meal_date between w.week_start and w.week_start + 6 and x.status <> 'draft'
     and not exists (select 1 from jsonb_array_elements(p_data -> 'meals') e
                      where (e ->> 'date')::date = x.meal_date and e ->> 'meal_type' = x.meal_type and coalesce(e ->> 'option_name', '') = x.option_name);
  insert into public.cafeteria_meals as x (cafeteria_id, meal_date, meal_type, option_name, option_order, menu_items, price_krw, start_time, end_time,
                                           status, badge, source_url, verified_at, extra)
  select w.cafeteria_id, (e ->> 'date')::date, e ->> 'meal_type', coalesce(e ->> 'option_name', ''), coalesce((e ->> 'option_order')::smallint, 0),
         e -> 'menu_items', (e ->> 'price_krw')::integer, nullif(e ->> 'start_time', '')::time, nullif(e ->> 'end_time', '')::time,
         e ->> 'status', nullif(btrim(coalesce(e ->> 'badge', '')), ''), nullif(e ->> 'source_url', ''), (e ->> 'verified_at')::timestamptz, coalesce(e -> 'extra', '{}'::jsonb)
    from jsonb_array_elements(p_data -> 'meals') e
  on conflict (cafeteria_id, meal_date, meal_type, option_name) do update set
    option_order = excluded.option_order, menu_items = excluded.menu_items, price_krw = excluded.price_krw, start_time = excluded.start_time,
    end_time = excluded.end_time, status = excluded.status, badge = excluded.badge, source_url = excluded.source_url,
    verified_at = excluded.verified_at, extra = excluded.extra;
  perform set_config('app.cms_apply', 'off', true);
end $$;

create or replace function public._cms_unpublished(p_type text, p_live jsonb) returns jsonb
language sql immutable as $$
  select case p_type when 'cafeteria_week' then jsonb_build_object('meals', '[]'::jsonb) else public._cms_unpublished_v1(p_type, p_live) end
$$;

create or replace function public.cms_overview(p_type text, p_parent uuid default null)
returns table (entity_id uuid, has_draft boolean, draft_updated_at timestamptz, scheduled_at timestamptz,
               failed_jobs integer, live_version integer, last_published_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._cms_admin_check();
  if p_type <> 'cafeteria_week' then
    return query select * from public.cms_overview_v1(p_type, p_parent);
    return;
  end if;
  return query
    select e.id,
           exists (select 1 from public.content_drafts d where d.entity_type = p_type and d.entity_id = e.id),
           (select d.updated_at from public.content_drafts d where d.entity_type = p_type and d.entity_id = e.id),
           (select min(j.run_at) from public.publication_jobs j where j.entity_type = p_type and j.entity_id = e.id and j.status = 'scheduled' and j.action = 'publish'),
           (select count(*)::integer from public.publication_jobs j where j.entity_type = p_type and j.entity_id = e.id and j.status = 'failed'),
           public._cms_live_version(p_type, e.id),
           (select max(v.published_at) from public.content_versions v where v.entity_type = p_type and v.entity_id = e.id)
      from public.cafeteria_weeks e where p_parent is null or e.cafeteria_id = p_parent;
end $$;

do $$ begin
  if to_regprocedure('public._cms_label_v1(text, uuid)') is not null then
    execute $f$
      create or replace function public._cms_label(p_type text, p_id uuid) returns text
      language plpgsql stable security definer set search_path = public, pg_temp as $b$
      declare v text;
      begin
        if p_type = 'cafeteria_week' then
          select '학식 · ' || coalesce(c.name_ko, '식당') || ' · ' || to_char(w.week_start, 'YYYY-MM-DD') || ' 주' into v
            from public.cafeteria_weeks w join public.campus_cafeterias c on c.id = w.cafeteria_id where w.id = p_id;
          return coalesce(v, '(삭제됨)');
        end if;
        return public._cms_label_v1(p_type, p_id);
      end $b$ $f$;
  end if;
end $$;

-- the renamed originals and the new wrappers are internal (the public API is cms_* / cafeteria_*)
revoke all on function public._cms_snapshot_v1(text, uuid), public._cms_validate_v1(text, jsonb, uuid), public._cms_apply_v1(text, uuid, jsonb),
  public._cms_unpublished_v1(text, jsonb), public._cms_snapshot(text, uuid), public._cms_validate(text, jsonb, uuid),
  public._cms_apply(text, uuid, jsonb), public._cms_unpublished(text, jsonb) from public, anon, authenticated;
revoke all on function public.cms_overview_v1(text, uuid) from public, anon, authenticated;
revoke all on function public.cms_overview(text, uuid) from public, anon;
grant execute on function public.cms_overview(text, uuid) to authenticated;
do $$ begin
  if to_regprocedure('public._cms_label_v1(text, uuid)') is not null then
    revoke all on function public._cms_label_v1(text, uuid) from public, anon, authenticated;
    revoke all on function public._cms_label(text, uuid) from public, anon, authenticated;
  end if;
end $$;
revoke all on function public.cafeteria_week_entity(uuid, date) from public, anon;
grant execute on function public.cafeteria_week_entity(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Publish only the chosen days of a week draft, atomically
-- ---------------------------------------------------------------------------
-- The live week becomes: its current menus for the OTHER days + the draft's menus for [p_days].
-- The remaining days stay in the draft (rebased on the new live version), so nothing is lost.
create or replace function public.cms_publish_week_days(p_id uuid, p_expected_revision integer, p_days date[], p_reason text default null)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare w public.cafeteria_weeks; d public.content_drafts; live jsonb; merged jsonb; v integer; lv integer; after_live jsonb;
begin
  perform public._cms_admin_check();
  if p_days is null or cardinality(p_days) = 0 then raise exception '게시할 날짜를 골라 주세요' using errcode = '22023'; end if;
  perform public._cms_lock('cafeteria_week', p_id);
  select * into w from public.cafeteria_weeks where id = p_id;
  if not found then raise exception 'no such cafeteria_week' using errcode = 'P0002'; end if;
  if exists (select 1 from unnest(p_days) x where x < w.week_start or x > w.week_start + 6) then
    raise exception '선택한 날짜가 이 주에 속하지 않아요' using errcode = '22023';
  end if;
  select * into d from public.content_drafts where entity_type = 'cafeteria_week' and entity_id = p_id for update;
  if not found then raise exception '게시할 초안이 없어요' using errcode = 'P0002'; end if;
  if p_expected_revision is distinct from d.revision then
    perform public._cms_conflict('다른 관리자가 이 초안을 먼저 저장했어요. 새로고침해서 확인한 뒤 다시 게시해 주세요.');
  end if;
  lv := public._cms_live_version('cafeteria_week', p_id);
  if d.base_version <> lv then
    perform public._cms_conflict('이 초안을 만든 뒤 라이브 내용이 바뀌었어요. 최신 기준으로 맞춘 뒤 게시해 주세요.');
  end if;
  live := public._cms_snapshot('cafeteria_week', p_id);
  select jsonb_build_object('meals', coalesce(jsonb_agg(x order by x ->> 'date', case x ->> 'meal_type' when 'breakfast' then 1 when 'lunch' then 2 else 3 end,
                                                      coalesce((x ->> 'option_order')::int, 0), coalesce(x ->> 'option_name', '')), '[]'::jsonb))
    into merged
    from (select e as x from jsonb_array_elements(live -> 'meals') e where not ((e ->> 'date')::date = any (p_days))
          union all
          select e from jsonb_array_elements(d.data -> 'meals') e where (e ->> 'date')::date = any (p_days)) u;
  v := public._cms_commit('cafeteria_week', p_id, merged, 'publish', p_reason, auth.uid());
  after_live := public._cms_snapshot('cafeteria_week', p_id);
  if d.data = after_live then
    delete from public.content_drafts where entity_type = 'cafeteria_week' and entity_id = p_id;
  else
    update public.content_drafts set base_version = v, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
     where entity_type = 'cafeteria_week' and entity_id = p_id;
  end if;
  return v;
end $$;
revoke all on function public.cms_publish_week_days(uuid, integer, date[], text) from public, anon;
grant execute on function public.cms_publish_week_days(uuid, integer, date[], text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. CSV import (the browser parses and previews; the server validates, resolves and writes DRAFTS)
-- ---------------------------------------------------------------------------
create or replace function public._cafeteria_sort_meals(p_meals jsonb) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(e order by e ->> 'date', case e ->> 'meal_type' when 'breakfast' then 1 when 'lunch' then 2 else 3 end,
                                      coalesce((e ->> 'option_order')::int, 0), coalesce(e ->> 'option_name', '')), '[]'::jsonb)
  from jsonb_array_elements(p_meals) e
$$;
revoke all on function public._cafeteria_sort_meals(jsonb) from public, anon, authenticated;

-- p_rows: [{line, university, university_id, cafeteria_name, cafeteria_id, cafeteria_type, location, date, meal_type, menu_name,
--           price, start_time, end_time, meal_option, program, description, notes, menu_items:[..], source_url}]
-- Modes: 'create_only' (never touches an existing menu), 'update_only' (never creates one), 'upsert'.
-- Nothing is published: every change lands in the week's DRAFT, which an admin then previews and publishes.
-- Retrying the same file changes nothing (identical rows are reported as "unchanged").
create or replace function public.cafeteria_import(
  p_rows jsonb, p_mode text default 'upsert', p_dry_run boolean default true,
  p_create_missing boolean default false, p_allow_multi_university boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  n int; e jsonb; ord int; entries jsonb[] := '{}'; warns text[]; msg text; i int;
  uni uuid; cu uuid; uni_name text; unis uuid[]; uni_names text[] := '{}'; cid uuid; cname text; cids uuid[]; ref text; gkey text; slot text;
  seen jsonb := '{}'; groups jsonb := '{}'; newcafs jsonb := '{}'; cafs_of_new jsonb := '{}';
  d date; ws date; mt text; opt text; price int; st text; en text; prog text; items jsonb; extra jsonb; meal jsonb; existing jsonb; merged jsonb;
  meals jsonb; idx int; j int; kind_ text; src text; base jsonb; wid uuid; dr public.content_drafts; snapshot jsonb; live jsonb; lv int;
  c_created int := 0; c_updated int := 0; c_unchanged int := 0; c_skipped int := 0; c_failed int := 0; cafs_created int := 0; weeks_changed int := 0;
  g text; gv jsonb; k text; multi boolean; row_status text; out_rows jsonb := '[]'; newc jsonb; ent jsonb;
begin
  perform public._cms_admin_check();
  if p_mode not in ('create_only', 'update_only', 'upsert') then raise exception 'unknown import mode' using errcode = '22023'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'rows must be an array' using errcode = '22023'; end if;
  n := jsonb_array_length(p_rows);
  if n = 0 then raise exception 'no rows' using errcode = '22023'; end if;
  if n > 2000 then raise exception '한 번에 2000행까지 가져올 수 있어요' using errcode = '22023'; end if;

  -- ===== pass 1: validate every row, resolve university and cafeteria, build the plan in memory =====
  for e, ord in select x, o::int from jsonb_array_elements(p_rows) with ordinality as t(x, o) loop
    msg := null; warns := '{}'; uni := null; cid := null; cname := null; uni_name := null; ref := null;
    ent := jsonb_build_object('line', coalesce((e ->> 'line')::int, ord));
    begin
      if jsonb_typeof(e) <> 'object' then msg := '행 형식이 올바르지 않아요'; end if;
      -- required text
      if msg is null and btrim(coalesce(e ->> 'cafeteria_name', '')) = '' and nullif(e ->> 'cafeteria_id', '') is null then msg := '식당 이름이 비어 있어요'; end if;
      if msg is null and btrim(coalesce(e ->> 'menu_name', '')) = '' then msg := '메뉴 이름이 비어 있어요'; end if;
      if msg is null and btrim(coalesce(e ->> 'university', '')) = '' and nullif(e ->> 'university_id', '') is null then msg := '대학교가 비어 있어요'; end if;
      -- date / meal / price / time
      if msg is null then
        begin d := (e ->> 'date')::date; if e ->> 'date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'x'; end if;
        exception when others then msg := '날짜가 올바르지 않아요 (YYYY-MM-DD): ' || coalesce(e ->> 'date', '(없음)'); end;
      end if;
      if msg is null then mt := e ->> 'meal_type'; if mt is null or mt not in ('breakfast', 'lunch', 'dinner') then msg := '식사 종류가 올바르지 않아요 (조식·중식·석식): ' || coalesce(mt, '(없음)'); end if; end if;
      if msg is null then
        begin price := nullif(btrim(coalesce(e ->> 'price', '')), '')::int; if price < 0 then raise exception 'x'; end if;
        exception when others then msg := '가격이 올바르지 않아요 (0 이상의 정수): ' || coalesce(e ->> 'price', ''); end;
        if msg is null and price is null then warns := array_append(warns, '가격이 비어 있어요 (가격 미정으로 저장)'); end if;
      end if;
      if msg is null then
        st := nullif(btrim(coalesce(e ->> 'start_time', '')), ''); en := nullif(btrim(coalesce(e ->> 'end_time', '')), '');
        if (st is not null and st !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') or (en is not null and en !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then msg := '이용 시간 형식이 올바르지 않아요 (HH:MM-HH:MM)';
        elsif st is not null and en is not null and st >= en then msg := '종료 시간은 시작보다 늦어야 해요';
        elsif (st is null) <> (en is null) then msg := '시작과 종료 시간을 함께 적어 주세요';
        elsif st is null then warns := array_append(warns, '이용 시간이 비어 있어요'); end if;
      end if;
      if msg is null then
        prog := nullif(btrim(coalesce(e ->> 'program', '')), '');
        src := nullif(btrim(coalesce(e ->> 'source_url', '')), '');
        if prog is not null and prog <> '천원의 아침밥' then msg := '알 수 없는 프로그램이에요: ' || prog;
        elsif prog is not null and mt <> 'breakfast' then msg := '천원의 아침밥은 조식에만 쓸 수 있어요';
        elsif prog is not null and src is null then msg := '천원의 아침밥은 공식 출처 주소(source_url)가 필요해요';
        elsif src is not null and src !~ '^https://' then msg := '출처 주소는 https:// 로 시작해야 해요'; end if;
      end if;
      if msg is null and char_length(coalesce(e ->> 'meal_option', '')) > 40 then msg := '옵션 이름은 40자 이하여야 해요'; end if;
      -- university
      if msg is null then
        if nullif(e ->> 'university_id', '') is not null then
          begin uni := (e ->> 'university_id')::uuid; exception when others then msg := '대학교 ID가 올바르지 않아요'; end;
          if msg is null then select name_ko into uni_name from public.universities where id = uni; if not found then msg := '등록되지 않은 대학교 ID예요'; end if; end if;
        else
          select array_agg(id) into unis from public.universities where lower(btrim(name_ko)) = lower(btrim(e ->> 'university'));
          if unis is null then msg := '등록되지 않은 대학교예요: ' || btrim(e ->> 'university');
          elsif cardinality(unis) > 1 then msg := '이름이 같은 대학교가 여러 곳이에요 (대학교 ID를 써 주세요): ' || btrim(e ->> 'university');
          else uni := unis[1]; select name_ko into uni_name from public.universities where id = uni; end if;
        end if;
      end if;
      -- cafeteria
      if msg is null then
        cname := nullif(btrim(coalesce(e ->> 'cafeteria_name', '')), '');
        if nullif(e ->> 'cafeteria_id', '') is not null then
          begin cid := (e ->> 'cafeteria_id')::uuid; exception when others then msg := '식당 ID가 올바르지 않아요'; end;
          if msg is null then
            select c.university_id, coalesce(c.name_ko, cname) into cu, cname from public.campus_cafeterias c where c.id = cid;
            if not found then msg := '등록되지 않은 식당 ID예요';
            elsif cu <> uni then msg := '이 식당은 다른 대학교 소속이에요'; end if;
          end if;
          ref := cid::text;
        else
          select array_agg(id) into cids from public.campus_cafeterias
           where university_id = uni and lower(btrim(coalesce(name_ko, ''))) = lower(cname) and status <> 'archived';
          if cids is null then
            if p_create_missing then ref := 'new:' || uni::text || '|' || lower(cname);
              if not (newcafs ? ref) then
                kind_ := coalesce(nullif(e ->> 'cafeteria_type', ''), 'other');
                if kind_ not in ('student', 'dormitory', 'staff', 'other') then kind_ := 'other'; end if;
                newcafs := newcafs || jsonb_build_object(ref, jsonb_build_object('university_id', uni, 'university', uni_name, 'name', cname, 'kind', kind_, 'location', nullif(btrim(coalesce(e ->> 'location', '')), '')));
              end if;
            else msg := '등록되지 않은 식당이에요 (새로 만들려면 "없는 식당 만들기"를 켜 주세요): ' || cname; end if;
          elsif cardinality(cids) > 1 then msg := '이름이 같은 식당이 여러 곳이에요 (식당 ID를 써 주세요): ' || cname;
          else cid := cids[1]; ref := cid::text; end if;
        end if;
      end if;
      -- duplicates inside the file
      if msg is null then
        ws := date_trunc('week', d)::date;
        opt := btrim(coalesce(e ->> 'meal_option', ''));
        slot := ref || '|' || d::text || '|' || mt || '|' || opt;
        if seen ? slot then msg := '파일 안에서 같은 식당·날짜·식사·옵션이 겹쳐요 (' || (seen ->> slot) || '행과 같아요)';
        else seen := seen || jsonb_build_object(slot, coalesce((e ->> 'line')::int, ord)); end if;
      end if;
    exception when others then
      msg := coalesce(msg, '행을 읽지 못했어요: ' || left(sqlerrm, 120));
    end;

    if msg is not null then
      entries[ord] := ent || jsonb_build_object('status', 'error', 'message', msg, 'university', uni_name, 'cafeteria', cname);
      continue;
    end if;
    if not (uni_names @> array[uni_name]) then uni_names := uni_names || uni_name; end if;
    unis := coalesce(unis, '{}');

    -- group = one cafeteria x one week
    gkey := ref || '|' || ws::text;
    if not (groups ? gkey) then
      if ref like 'new:%' then base := '[]'::jsonb;
      else
        select data -> 'meals' into base from public.content_drafts
         where entity_type = 'cafeteria_week' and entity_id = (select id from public.cafeteria_weeks where cafeteria_id = cid and week_start = ws);
        if base is null then base := public._cafeteria_week_meals(cid, ws); end if;
      end if;
      groups := groups || jsonb_build_object(gkey, jsonb_build_object('ref', ref, 'cafeteria_id', cid, 'week_start', ws, 'meals', base, 'changed', false, 'rows', '[]'::jsonb, 'cafeteria', cname, 'university', uni_name));
    end if;
    meals := groups -> gkey -> 'meals';
    idx := null;
    for j in 0 .. jsonb_array_length(meals) - 1 loop
      if meals -> j ->> 'date' = d::text and meals -> j ->> 'meal_type' = mt and coalesce(meals -> j ->> 'option_name', '') = opt then idx := j; exit; end if;
    end loop;

    -- the new content of this row
    items := jsonb_build_array(jsonb_build_object('name_ko', btrim(e ->> 'menu_name'), 'kind', 'main'))
             || coalesce((select jsonb_agg(jsonb_build_object('name_ko', btrim(x), 'kind', 'side')) from jsonb_array_elements_text(case when jsonb_typeof(e -> 'menu_items') = 'array' then e -> 'menu_items' else '[]'::jsonb end) x where btrim(x) <> ''), '[]'::jsonb);
    extra := '{}'::jsonb;
    if nullif(btrim(coalesce(e ->> 'description', '')), '') is not null then extra := extra || jsonb_build_object('description', btrim(e ->> 'description')); end if;
    if nullif(btrim(coalesce(e ->> 'notes', '')), '') is not null then extra := extra || jsonb_build_object('notice', btrim(e ->> 'notes')); end if;

    if idx is not null and p_mode = 'create_only' then
      row_status := 'skip'; msg := '이미 있는 식단이라 건너뛰었어요 (생성 전용)';
    elsif idx is null and p_mode = 'update_only' then
      row_status := 'skip'; msg := '없는 식단이라 건너뛰었어요 (수정 전용)';
    elsif idx is null then
      meal := jsonb_build_object('date', d::text, 'meal_type', mt, 'option_name', opt,
        'option_order', (select count(*) from jsonb_array_elements(meals) m where m ->> 'date' = d::text and m ->> 'meal_type' = mt),
        'menu_items', items, 'price_krw', price, 'start_time', st, 'end_time', en, 'status', 'published', 'badge', prog,
        'source_url', src, 'verified_at', to_jsonb(now()) #>> '{}', 'extra', extra);
      groups := jsonb_set(groups, array[gkey, 'meals'], meals || jsonb_build_array(meal));
      groups := jsonb_set(groups, array[gkey, 'changed'], 'true');
      row_status := 'create'; msg := null;
    else
      existing := meals -> idx;
      merged := existing || jsonb_build_object('menu_items', items, 'price_krw', price, 'start_time', st, 'end_time', en, 'status', 'published',
        'badge', coalesce(to_jsonb(prog), existing -> 'badge'), 'source_url', coalesce(to_jsonb(src), existing -> 'source_url'),
        'extra', coalesce(existing -> 'extra', '{}'::jsonb) || extra);
      if merged = existing then
        row_status := 'unchanged'; msg := '이미 같은 내용이에요';
      else
        merged := merged || jsonb_build_object('verified_at', to_jsonb(now()) #>> '{}');
        groups := jsonb_set(groups, array[gkey, 'meals'], jsonb_set(meals, array[idx::text], merged));
        groups := jsonb_set(groups, array[gkey, 'changed'], 'true');
        row_status := 'update'; msg := null;
      end if;
    end if;
    groups := jsonb_set(groups, array[gkey, 'rows'], (groups -> gkey -> 'rows') || to_jsonb(ord));
    entries[ord] := ent || jsonb_build_object('status', row_status, 'message', coalesce(msg, case when cardinality(warns) > 0 then array_to_string(warns, ' · ') end),
                       'warnings', to_jsonb(warns), 'university', uni_name, 'cafeteria', cname, 'date', d::text, 'meal_type', mt, 'option', opt, 'new_cafeteria', ref like 'new:%');
  end loop;

  -- ===== pass 2: validate each resulting week; a week that would be invalid is refused as a whole =====
  for g, gv in select key, value from jsonb_each(groups) loop
    meals := public._cafeteria_sort_meals(gv -> 'meals');
    groups := jsonb_set(groups, array[g, 'meals'], meals);
    begin
      perform public._cafeteria_week_validate(jsonb_build_object('meals', meals), (gv ->> 'week_start')::date);
    exception when others then
      for k in select jsonb_array_elements_text(gv -> 'rows') loop
        entries[k::int] := entries[k::int] || jsonb_build_object('status', 'error', 'message', '이 주의 식단이 올바르지 않아요: ' || sqlerrm);
      end loop;
      groups := jsonb_set(groups, array[g, 'changed'], 'false');
      groups := jsonb_set(groups, array[g, 'refused'], 'true');
    end;
  end loop;

  multi := cardinality(uni_names) > 1;
  if multi and not p_allow_multi_university and not p_dry_run then
    raise exception '여러 대학교를 한 번에 바꾸는 가져오기예요. 확인한 뒤 다시 시도해 주세요: %', array_to_string(uni_names, ', ') using errcode = '22023';
  end if;

  -- ===== apply: drafts only, all or nothing =====
  if not p_dry_run then
    for newc in select value from jsonb_each(newcafs) loop null; end loop;
    for g, gv in select key, value from jsonb_each(groups) loop
      continue when (gv ->> 'changed') <> 'true';
      ref := gv ->> 'ref';
      if ref like 'new:%' then
        if not (cafs_of_new ? ref) then
          newc := newcafs -> ref;
          insert into public.campus_cafeterias (university_id, kind, name_ko, location_description, status)
            values ((newc ->> 'university_id')::uuid, newc ->> 'kind', newc ->> 'name', newc ->> 'location', 'inactive') returning id into cid;
          cafs_of_new := cafs_of_new || jsonb_build_object(ref, cid);
          cafs_created := cafs_created + 1;
        end if;
        cid := (cafs_of_new ->> ref)::uuid;
      else cid := (gv ->> 'cafeteria_id')::uuid; end if;
      ws := (gv ->> 'week_start')::date;
      wid := public._cafeteria_week_id(cid, ws);
      snapshot := jsonb_build_object('meals', gv -> 'meals');
      select * into dr from public.content_drafts where entity_type = 'cafeteria_week' and entity_id = wid for update;
      if found then
        if dr.data is distinct from snapshot then
          update public.content_drafts set data = snapshot, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
           where entity_type = 'cafeteria_week' and entity_id = wid;
          weeks_changed := weeks_changed + 1;
        end if;
      else
        live := jsonb_build_object('meals', public._cafeteria_week_meals(cid, ws));
        if snapshot is distinct from live then
          lv := public._cms_live_version('cafeteria_week', wid);
          insert into public.content_drafts (entity_type, entity_id, data, base_version, created_by, updated_by)
            values ('cafeteria_week', wid, snapshot, lv, auth.uid(), auth.uid());
          weeks_changed := weeks_changed + 1;
        end if;
      end if;
    end loop;
    insert into public.audit_log (actor_id, action, table_name, reason, details)
    values (auth.uid(), 'cafeteria_import', 'cafeteria_weeks', null,
            jsonb_build_object('mode', p_mode, 'rows', n, 'weeks_changed', weeks_changed, 'cafeterias_created', cafs_created, 'universities', to_jsonb(uni_names)));
  end if;

  -- summary
  for i in 1 .. n loop
    ent := entries[i];
    case ent ->> 'status' when 'create' then c_created := c_created + 1; when 'update' then c_updated := c_updated + 1;
      when 'unchanged' then c_unchanged := c_unchanged + 1; when 'skip' then c_skipped := c_skipped + 1; else c_failed := c_failed + 1; end case;
    out_rows := out_rows || ent;
  end loop;
  return jsonb_build_object('dry_run', p_dry_run, 'mode', p_mode,
    'summary', jsonb_build_object('created', c_created, 'updated', c_updated, 'unchanged', c_unchanged, 'skipped', c_skipped, 'failed', c_failed,
                                  'cafeterias_created', case when p_dry_run then (select count(*) from jsonb_object_keys(newcafs)) else cafs_created end,
                                  'weeks_changed', case when p_dry_run then (select count(*) from jsonb_each(groups) where value ->> 'changed' = 'true') else weeks_changed end),
    'multi_university', multi, 'universities', to_jsonb(uni_names),
    'new_cafeterias', coalesce((select jsonb_agg(value - 'university_id') from jsonb_each(newcafs)), '[]'::jsonb), 'rows', out_rows);
end $$;
revoke all on function public.cafeteria_import(jsonb, text, boolean, boolean, boolean) from public, anon;
grant execute on function public.cafeteria_import(jsonb, text, boolean, boolean, boolean) to authenticated;
