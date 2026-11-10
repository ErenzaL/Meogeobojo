-- Live updates for the app: publish the tables an admin edits to Supabase
-- Realtime, so a published change reaches a running app or browser tab
-- without a restart (the app also refreshes on resume and by pull-to-refresh).
--
-- Safe: it only adds tables to the existing `supabase_realtime` publication, is
-- idempotent, and does nothing where that publication does not exist (a plain
-- PostgreSQL). Realtime delivers a row only to a client whose RLS policies let
-- it READ that row, so drafts and private rows never reach ordinary users.
-- Nothing here changes RLS, grants or data.

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime publication not found: nothing to do';
    return;
  end if;
  foreach t in array array[
    'restaurant_overrides', 'restaurant_menus', 'restaurant_photos',
    'cafeteria_meals', 'campus_cafeterias', 'missions', 'monthly_campaigns', 'app_content']
  loop
    if to_regclass('public.' || t) is not null
       and not exists (select 1 from pg_publication_tables
                        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
