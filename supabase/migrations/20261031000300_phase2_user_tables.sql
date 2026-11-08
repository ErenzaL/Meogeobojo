-- PHASE 2 (optional): future-ready tables. Not used by the app yet.
-- Apply only when the matching features are built. Same data-retention rule
-- as favorites: places are referenced by kakao_place_id, never copied.

-- Personal food diary (private to the user).
create table if not exists public.food_records (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kakao_place_id  text,
  menu_name       text,
  memo            text,
  my_rating       smallint check (my_rating between 1 and 5),
  eaten_at        timestamptz not null default now(),
  created_at      timestamptz not null default now()
);
create index if not exists food_records_user_eaten_idx on public.food_records (user_id, eaten_at desc);

-- user_preferences moved to 20261101000200_user_preferences.sql (superseded draft removed).

-- Student-written reviews (user generated content, readable by everyone).
create table if not exists public.student_reviews (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kakao_place_id  text not null,
  university_id   uuid references public.universities (id) on delete set null,
  rating          smallint not null check (rating between 1 and 5),
  body            text check (char_length(body) <= 2000),
  created_at      timestamptz not null default now(),
  unique (user_id, kakao_place_id)
);
create index if not exists student_reviews_place_idx on public.student_reviews (kakao_place_id, created_at desc);

-- Menu/price facts. Curated server-side only (service role); each row must say where it came from.
create table if not exists public.restaurant_menus (
  id              uuid primary key default gen_random_uuid(),
  kakao_place_id  text not null,
  -- First-party, authorized menu records only (never Kakao data). Korean is
  -- the source text and the fallback; en/zh are optional and must be written
  -- by a person, never machine-invented. Prices stay in KRW.
  name_ko         text not null,
  name_en         text,
  name_zh         text,
  description_ko  text,
  description_en  text,
  description_zh  text,
  price_krw       integer check (price_krw >= 0),
  source          text not null,
  verified_at     timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists restaurant_menus_place_idx on public.restaurant_menus (kakao_place_id);

-- Interaction log for training/evaluating the recommendation model.
create table if not exists public.recommendation_events (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid default auth.uid() references auth.users (id) on delete set null,
  university_id   uuid references public.universities (id) on delete set null,
  strategy        text not null,                 -- e.g. 'proximity_baseline'
  kakao_place_id  text,
  event_type      text not null check (event_type in ('impression', 'click', 'favorite', 'dismiss')),
  created_at      timestamptz not null default now()
);
create index if not exists recommendation_events_user_idx on public.recommendation_events (user_id, created_at desc);

alter table public.food_records           enable row level security;
alter table public.student_reviews        enable row level security;
alter table public.restaurant_menus       enable row level security;
alter table public.recommendation_events  enable row level security;

-- food_records: owner only.
create policy "food_records: owner all" on public.food_records
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- student_reviews: public read, owner write.
create policy "student_reviews: public read" on public.student_reviews
  for select to anon, authenticated using (true);
create policy "student_reviews: owner insert" on public.student_reviews
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "student_reviews: owner update" on public.student_reviews
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "student_reviews: owner delete" on public.student_reviews
  for delete to authenticated using (user_id = (select auth.uid()));

-- restaurant_menus: public read, no API writes.
create policy "restaurant_menus: public read" on public.restaurant_menus
  for select to anon, authenticated using (true);

-- recommendation_events: insert-only for clients; reading is for the service role.
create policy "recommendation_events: insert own" on public.recommendation_events
  for insert to authenticated
  with check (user_id is not distinct from (select auth.uid()));

revoke all on public.food_records, public.student_reviews,
              public.restaurant_menus, public.recommendation_events from anon;
