-- Live-update signal for the apps.
--
-- WHY: Supabase Realtime only delivers a change to a subscriber if that subscriber could SELECT the row
-- (row-level security). Taking something down - an announcement switched off, a restaurant hidden, a photo
-- archived, a mission paused - is an UPDATE after which the row is no longer visible to students, so
-- Realtime stays silent and a running app keeps showing it until restarted.
--
-- WHAT: a tiny append-only log, `content_sync`, that anyone may read and nobody may write through the API.
-- A statement-level trigger on each synced table appends ONE row (just the table's name and a timestamp)
-- on ANY insert / update / delete, including take-downs, from any writer (Admin, the publishing functions,
-- the scheduler, the SQL editor). The new row is always visible, so Realtime always delivers it, and the app
-- re-reads the named table. It holds no content.
--
-- Append-only on purpose: inserts never lock each other, so two publishes running at once cannot deadlock
-- (a counter row updated by every statement would hold a lock until commit). Old rows are pruned now and
-- then; the app listens to INSERT events only, so pruning triggers no refresh.
--
-- Additive and idempotent. Requires 20261112000100 (the realtime publication) and the content tables.
-- Changes no existing data. The app works without it too (it re-reads on resume, on a timer and on
-- pull-to-refresh); this makes the update immediate.

do $$ begin
  if to_regclass('public.app_content') is null or to_regclass('public.restaurant_overrides') is null then
    raise exception 'Apply 20261109000100 first.';
  end if;
end $$;

create table if not exists public.content_sync (
  id         bigint generated always as identity primary key,
  source     text not null check (source ~ '^[a-z_]+$'),
  changed_at timestamptz not null default now()
);
create index if not exists content_sync_changed_idx on public.content_sync (changed_at);
alter table public.content_sync enable row level security;
revoke all on public.content_sync from anon, authenticated;
grant select on public.content_sync to anon, authenticated;
drop policy if exists "content_sync: public read" on public.content_sync;
create policy "content_sync: public read" on public.content_sync for select to anon, authenticated using (true);

create or replace function public.content_sync_bump() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.content_sync (source) values (tg_argv[0]);
  -- keep the log small: now and then drop what is older than two days (nobody needs it: apps only react to new rows)
  if random() < 0.02 then
    delete from public.content_sync where changed_at < now() - interval '2 days';
  end if;
  return null;
end $$;
revoke all on function public.content_sync_bump() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['restaurant_overrides', 'restaurant_menus', 'restaurant_photos', 'cafeteria_meals', 'campus_cafeterias',
                           'missions', 'monthly_campaigns', 'app_content', 'universities'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists content_sync_bump on public.%I', t);
      execute format('create trigger content_sync_bump after insert or update or delete on public.%I
                      for each statement execute function public.content_sync_bump(%L)', t, t);
    end if;
  end loop;
end $$;

-- Deliver it to the apps.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'content_sync') then
    alter publication supabase_realtime add table public.content_sync;
  end if;
end $$;
