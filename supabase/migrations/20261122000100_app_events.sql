-- =============================================================================
-- 사용 지표: the app records four anonymous events so the admin 분석 page shows real numbers instead of nothing.
--   app_open          the app (or the website) was opened         → 방문자, 재방문자
--   restaurant_view   a restaurant's page was opened               → 식당 상세 조회
--   directions_click  "길찾기" handed off to Kakao Map              → 길찾기
--   search            a finished search (submitted or a chip)      → 검색 수, 많이 찾은 검색어
--
-- No account id is stored. client_id is a random id the app keeps on the device (shared_preferences / localStorage),
-- enough to count distinct visitors and returning visitors (seen on 2+ different days) without knowing who they are.
-- Guests use the app too, so anon and authenticated may INSERT only, and only the four content columns (created_at
-- and id cannot be forged). Nobody reads rows directly: the admin 분석 page (moderator and up, like its menu item)
-- reads aggregates through admin_event_stats(), admin_event_daily() and admin_top_search_queries().
--
-- Additive and idempotent. Requires 20261109000100 (has_role / _require_role). NOT applied by the repository.
-- =============================================================================
do $$ begin
  if to_regprocedure('public.has_role(text)') is null then
    raise exception 'Apply 20261109000100_admin_foundation.sql first.';
  end if;
end $$;

create table if not exists public.app_events (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  event         text not null check (event in ('app_open', 'restaurant_view', 'directions_click', 'search')),
  client_id     uuid not null,
  restaurant_id text check (char_length(restaurant_id) between 1 and 64),
  query         text check (char_length(query) between 1 and 100 and query = btrim(query)),
  -- A restaurant event names its place, a search carries its words, and nothing else carries either.
  constraint app_events_shape check (
    (event in ('restaurant_view', 'directions_click')) = (restaurant_id is not null)
    and (event = 'search') = (query is not null)
  )
);
create index if not exists app_events_created_idx on public.app_events (created_at desc);

alter table public.app_events enable row level security;
revoke all on public.app_events from anon, authenticated;
grant insert (event, client_id, restaurant_id, query) on public.app_events to anon, authenticated;
drop policy if exists "app_events: anyone records" on public.app_events;
-- ponytail: anyone holding the publishable key can insert, so a script could inflate the counts. If that happens,
-- add a per-client daily cap (a trigger) or move inserts behind an Edge Function with a rate limit.
create policy "app_events: anyone records" on public.app_events
  for insert to anon, authenticated with check (true);
-- No select / update / delete policy or grant: rows are write-only for clients.

-- Totals over the last [p_days] days (Seoul calendar days for "returning").
create or replace function public.admin_event_stats(p_days integer default 7)
returns table (
  visitors bigint, returning_visitors bigint, app_opens bigint,
  restaurant_views bigint, directions_clicks bigint, searches bigint
) language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('moderator');
  return query
    with recent as (
      select e.client_id, e.event, (e.created_at at time zone 'Asia/Seoul')::date as d
        from public.app_events e
       where e.created_at >= now() - make_interval(days => greatest(p_days, 1))
    )
    select count(distinct r.client_id)::bigint,
           (select count(*) from (select r2.client_id from recent r2
                                   group by r2.client_id having count(distinct r2.d) >= 2) x)::bigint,
           count(*) filter (where r.event = 'app_open')::bigint,
           count(*) filter (where r.event = 'restaurant_view')::bigint,
           count(*) filter (where r.event = 'directions_click')::bigint,
           count(*) filter (where r.event = 'search')::bigint
      from recent r;
end $$;

-- One row per Seoul day that has events, newest first.
create or replace function public.admin_event_daily(p_days integer default 7)
returns table (day date, visitors bigint, restaurant_views bigint, directions_clicks bigint, searches bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('moderator');
  return query
    select (e.created_at at time zone 'Asia/Seoul')::date,
           count(distinct e.client_id)::bigint,
           count(*) filter (where e.event = 'restaurant_view')::bigint,
           count(*) filter (where e.event = 'directions_click')::bigint,
           count(*) filter (where e.event = 'search')::bigint
      from public.app_events e
     where e.created_at >= now() - make_interval(days => greatest(p_days, 1))
     group by 1
     order by 1 desc;
end $$;

-- Most searched words (case-insensitive), most first.
create or replace function public.admin_top_search_queries(p_days integer default 7, p_limit integer default 20)
returns table (term text, searches bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('moderator');
  return query
    select lower(e.query), count(*)::bigint
      from public.app_events e
     where e.event = 'search'
       and e.created_at >= now() - make_interval(days => greatest(p_days, 1))
     group by 1
     order by 2 desc, 1
     limit least(greatest(p_limit, 1), 100);
end $$;

revoke all on function public.admin_event_stats(integer) from public, anon;
revoke all on function public.admin_event_daily(integer) from public, anon;
revoke all on function public.admin_top_search_queries(integer, integer) from public, anon;
grant execute on function public.admin_event_stats(integer) to authenticated;
grant execute on function public.admin_event_daily(integer) to authenticated;
grant execute on function public.admin_top_search_queries(integer, integer) to authenticated;
