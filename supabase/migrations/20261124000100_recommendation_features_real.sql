-- =============================================================================
-- Recommendation features: REAL rows next to the simulated ones.
--
-- `recommendation_demo_features` (opening / last-order time, break time, parking, takeout, ...) could only hold rows
-- marked demo_data = true. This lets it hold REAL, admin-entered rows too:
--   demo_data = true   simulated (read by the app only while its demo mode is on, as before)
--   demo_data = false  real (read by every build, shown without any demo label)
-- One row per Kakao place id: importing a real row for a place replaces its demo row, and an administrator-entered value
-- in restaurant_overrides still wins over either. Nothing else changes: same table, same RLS (public read, admin write).
--
-- Additive and idempotent. NOT applied by the repository.
-- =============================================================================
do $$
declare c record;
begin
  if to_regclass('public.recommendation_demo_features') is null then
    raise exception 'Apply 20261123000100_recommendation_demo_features.sql first.';
  end if;
  -- drop the CHECK that forced demo_data = true (whatever name it got)
  for c in
    select conname from pg_constraint
    where conrelid = 'public.recommendation_demo_features'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%demo_data%'
  loop
    execute format('alter table public.recommendation_demo_features drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.recommendation_demo_features alter column demo_data set default true;
comment on table public.recommendation_demo_features is
  'Recommendation hours/amenities per Kakao place id. demo_data = true: simulated (demo mode only). demo_data = false: real, admin-entered.';
