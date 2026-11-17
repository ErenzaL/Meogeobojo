-- 실사용 선택 시간: how long a real visit takes from opening the app to the first 길찾기 (the moment a place is chosen).
-- Read-only aggregate over public.app_events (20261122000100); no new table, no new client write.
--
-- A visit starts at an app_open and ends at the same device's next app_open. Its choice time is the first
-- directions_click inside the visit, counted only within 30 minutes (a later click is a new decision, not this one).
-- ponytail: a web page reload records a new app_open and so splits a visit; fine for a median, revisit if the app
-- starts recording a dedicated "recommendation requested" event.
create or replace function public.admin_choice_time(p_days integer default 7)
returns table (visits bigint, decided_visits bigint, median_seconds numeric, p75_seconds numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('moderator');
  return query
    with ev as (
      select e.client_id, e.event, e.created_at
        from public.app_events e
       where e.event in ('app_open', 'directions_click')
         and e.created_at >= now() - make_interval(days => greatest(p_days, 1))
    ), opens as (
      select o.client_id, o.created_at as t,
             lead(o.created_at) over (partition by o.client_id order by o.created_at) as next_t
        from ev o
       where o.event = 'app_open'
    ), visit as (
      select (select min(d.created_at) from ev d
               where d.client_id = o.client_id and d.event = 'directions_click'
                 and d.created_at >= o.t
                 and d.created_at < least(coalesce(o.next_t, 'infinity'), o.t + interval '30 minutes')) - o.t as took
        from opens o
    )
    select count(*)::bigint,
           count(v.took)::bigint,
           round((percentile_cont(0.5) within group (order by extract(epoch from v.took)) filter (where v.took is not null))::numeric, 1),
           round((percentile_cont(0.75) within group (order by extract(epoch from v.took)) filter (where v.took is not null))::numeric, 1)
      from visit v;
end $$;

revoke all on function public.admin_choice_time(integer) from public, anon;
grant execute on function public.admin_choice_time(integer) to authenticated;
