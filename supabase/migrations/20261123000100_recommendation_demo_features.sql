-- =============================================================================
-- DEVELOPMENT / DEMO ONLY: simulated hours and amenities for the recommendation demo.
--
-- `recommendation_demo_features` holds SYNTHETIC values (opening / last-order time, break time, parking, takeout, ...)
-- keyed by Kakao place id, so the recommendation can be demonstrated before real data exists. It is NOT restaurant
-- information:
--   * nothing in restaurant_overrides / restaurant_menus / restaurant_photos or any publication state is read or written;
--   * the app reads it only while the in-app demo mode is ON (off by default, and the switch exists only in demo
--     builds) and then labels everything that rests on it as demo data;
--   * an administrator-entered value always wins over a row here;
--   * prices come from the published menus and positions from Kakao's live coordinates, so neither is stored here.
-- demo_data must be true on every row (a CHECK), so a row can never pass for real data.
--
-- Additive and idempotent. Requires 20261109000100 (has_role). NOT applied by the repository.
-- To remove the demo completely:  drop table public.recommendation_demo_features;
-- =============================================================================
do $$ begin
  if to_regprocedure('public.has_role(text)') is null then
    raise exception 'Apply 20261109000100_admin_foundation.sql first.';
  end if;
end $$;

create table if not exists public.recommendation_demo_features (
  kakao_place_id  text primary key check (kakao_place_id ~ '^[0-9]{1,20}$'),
  name_ko         text,
  category_demo   text,
  open_time       time,
  last_order_time time,
  break_time      text check (break_time is null or char_length(break_time) <= 30),
  no_break_time   boolean,
  parking         boolean,
  local_currency  boolean,
  fast_turnover   boolean,
  takeout         boolean,
  open_late       boolean,
  demo_data       boolean not null default true check (demo_data),
  source          text not null default 'synthetic demo dataset',
  imported_at     timestamptz not null default now(),
  imported_by     uuid default auth.uid() references auth.users (id) on delete set null
);
comment on table public.recommendation_demo_features is
  'DEVELOPMENT ONLY. Simulated hours/amenities for the recommendation demo. Never verified restaurant information.';

alter table public.recommendation_demo_features enable row level security;
revoke all on public.recommendation_demo_features from anon, authenticated;
grant select on public.recommendation_demo_features to anon, authenticated;
grant insert, update, delete on public.recommendation_demo_features to authenticated;

drop policy if exists "recommendation_demo_features: read" on public.recommendation_demo_features;
create policy "recommendation_demo_features: read" on public.recommendation_demo_features
  for select to anon, authenticated using (true);
drop policy if exists "recommendation_demo_features: admin write" on public.recommendation_demo_features;
create policy "recommendation_demo_features: admin write" on public.recommendation_demo_features
  for all to authenticated using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));
