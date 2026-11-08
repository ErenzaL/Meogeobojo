-- Corrective grants found by auditing the HOSTED project (2026-11-01).
--
-- Hosted Supabase no longer auto-grants SELECT/INSERT/UPDATE/DELETE on new
-- public tables to anon/authenticated (default privileges are only
-- TRUNCATE, REFERENCES, TRIGGER, MAINTAIN). Row Level Security policies are
-- therefore not enough on their own:
--
--  1. public.universities has an "anyone can read" policy but no SELECT
--     grant, so signed-out visitors get 42501 "permission denied".
--  2. Those leftover TRUNCATE/REFERENCES/TRIGGER/MAINTAIN privileges are not
--     governed by RLS (TRUNCATE in particular) and are not needed by any
--     client role. Remove them.
--
-- Additive for reads, and only removes privileges nothing uses. Idempotent.

-- 1. Public, read-only reference data.
grant select on public.universities to anon, authenticated;

-- 2. Hardening: client roles never need these on any public table.
revoke truncate, references, trigger, maintain
  on all tables in schema public
  from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke truncate, references, trigger, maintain on tables from anon, authenticated;

-- NOTE: the optional phase-2 tables (food_records, student_reviews,
-- restaurant_menus, recommendation_events) have RLS policies but still no
-- table grants, so they are unusable from the API. That is intentional until
-- those features exist; add grants together with the feature.
