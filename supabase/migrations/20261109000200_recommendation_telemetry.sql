-- Recommendation API telemetry. Stores ONLY operational metadata (no user ids,
-- no preferences, no restaurant lists). Rows are written by a trusted server
-- (Edge Function / the recommendation service with the service role); clients
-- cannot insert. Admins read aggregates through admin_recommendation_stats().
-- Requires 20261109000100_admin_foundation.sql (has_role).

do $$ begin
  if to_regprocedure('public.has_role(text)') is null then
    raise exception 'Apply 20261109000100_admin_foundation.sql first.';
  end if;
end $$;

create table if not exists public.recommendation_requests (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  model_version text not null check (btrim(model_version) <> ''),
  -- true for the documented test mock: it must never be mistaken for a model.
  is_mock       boolean not null default false,
  status        text not null check (status in ('ok', 'error', 'timeout', 'fallback')),
  latency_ms    integer check (latency_ms is null or latency_ms >= 0),
  error_code    text,
  university_id uuid references public.universities (id) on delete set null
);
create index if not exists recommendation_requests_created_idx
  on public.recommendation_requests (created_at desc);

alter table public.recommendation_requests enable row level security;
revoke all on public.recommendation_requests from anon, authenticated;
grant select on public.recommendation_requests to authenticated;
drop policy if exists "recommendation_requests: admins read" on public.recommendation_requests;
create policy "recommendation_requests: admins read" on public.recommendation_requests
  for select to authenticated using ((select public.has_role('admin')));
-- No insert/update/delete policy or grant: only the service role writes.

-- Aggregates over the last [p_days] days. Real telemetry only: with no rows
-- every figure is null / 0 and the dashboard says so.
create or replace function public.admin_recommendation_stats(p_days integer default 7)
returns table (
  total bigint, errors bigint, mock_requests bigint,
  avg_latency_ms numeric, last_success_at timestamptz, latest_model_version text, latest_is_mock boolean
) language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  return query
    select count(*)::bigint,
           count(*) filter (where status in ('error', 'timeout'))::bigint,
           count(*) filter (where is_mock)::bigint,
           round(avg(latency_ms) filter (where status = 'ok'), 1),
           max(created_at) filter (where status = 'ok'),
           (select r.model_version from public.recommendation_requests r order by r.created_at desc limit 1),
           (select r.is_mock from public.recommendation_requests r order by r.created_at desc limit 1)
      from public.recommendation_requests
     where created_at >= now() - make_interval(days => greatest(p_days, 1));
end $$;
revoke all on function public.admin_recommendation_stats(integer) from public, anon;
grant execute on function public.admin_recommendation_stats(integer) to authenticated;
