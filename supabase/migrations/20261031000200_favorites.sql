-- Per-user favorites.
--
-- Only the opaque Kakao place id is stored, NOT Kakao's place data (name,
-- address, coordinates ...). Kakao Local API results may not be permanently
-- stored, and that has not been verified for this project, so the app
-- re-fetches display data from the search_restaurants function. If Kakao's
-- terms are confirmed to allow it, a `restaurants` table can be added later
-- and this column can gain a foreign key.

create table if not exists public.favorites (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid()
                    references auth.users (id) on delete cascade,
  kakao_place_id  text not null,
  created_at      timestamptz not null default now(),
  constraint favorites_place_id_len check (char_length(kakao_place_id) between 1 and 64),
  constraint favorites_user_place_key unique (user_id, kakao_place_id)
);

create index if not exists favorites_user_created_idx
  on public.favorites (user_id, created_at desc);

alter table public.favorites enable row level security;

drop policy if exists "favorites: select own" on public.favorites;
create policy "favorites: select own"
  on public.favorites for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "favorites: insert own" on public.favorites;
create policy "favorites: insert own"
  on public.favorites for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "favorites: delete own" on public.favorites;
create policy "favorites: delete own"
  on public.favorites for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- No anonymous access at all, and favorites are immutable (delete + re-insert).
revoke all on public.favorites from anon;
revoke update on public.favorites from authenticated;
grant select, insert, delete on public.favorites to authenticated;
