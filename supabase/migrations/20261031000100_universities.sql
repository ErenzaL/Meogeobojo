-- Universities the app can center on. Public read-only reference data.
-- Safe to re-run (idempotent). Nothing here is destructive.

create table if not exists public.universities (
  id          uuid primary key default gen_random_uuid(),
  name_ko     text not null,
  name_en     text,
  city        text,
  latitude    double precision,
  longitude   double precision,
  created_at  timestamptz not null default now(),
  constraint universities_lat_range check (latitude  is null or latitude  between -90  and 90),
  constraint universities_lng_range check (longitude is null or longitude between -180 and 180)
);

create unique index if not exists universities_name_ko_key on public.universities (name_ko);
create index if not exists universities_city_idx on public.universities (city);

alter table public.universities enable row level security;

-- Anyone (including signed-out visitors) may read; nobody may write via the API.
drop policy if exists "universities are publicly readable" on public.universities;
create policy "universities are publicly readable"
  on public.universities for select
  to anon, authenticated
  using (true);

revoke insert, update, delete on public.universities from anon, authenticated;

-- Seed. Ids are fixed so they match lib/features/university/models/verified_universities.dart
-- (the app's offline fallback), which keeps a stored selection valid either way.
--
-- Coordinates are Kakao Map landmark points inside each campus, cross-checked
-- against results returned by the search_restaurants function on 2026-10-31:
--   순천향대  : "순천향대학교" place
--   호서대    : "호서대학교 학생회관" (아산캠퍼스)
--   선문대    : "선문대학교 아산캠퍼스 본관"
--   단국대(천안): "단국대학교 천안캠퍼스 공학관"
--   백석대    : "백석대학교 인성관"
--   상명대(천안): "상명대학교 천안캠퍼스 계당관"
--   한기대    : "한기대 생협"
-- They are campus-area anchors, not surveyed boundaries. Review before launch.
insert into public.universities (id, name_ko, name_en, city, latitude, longitude) values
  ('5c0a8f3e-0001-4a6e-9b1d-000000000001', '순천향대학교',        'Soonchunhyang University',                      '아산', 36.76999, 126.93150),
  ('5c0a8f3e-0002-4a6e-9b1d-000000000002', '호서대학교',          'Hoseo University',                              '아산', 36.73959, 127.07422),
  ('5c0a8f3e-0003-4a6e-9b1d-000000000003', '선문대학교',          'Sun Moon University',                           '아산', 36.80023, 127.07493),
  ('5c0a8f3e-0004-4a6e-9b1d-000000000004', '단국대학교 천안캠퍼스', 'Dankook University (Cheonan)',                '천안', 36.83849, 127.17021),
  ('5c0a8f3e-0005-4a6e-9b1d-000000000005', '백석대학교',          'Baekseok University',                           '천안', 36.83943, 127.18354),
  ('5c0a8f3e-0006-4a6e-9b1d-000000000006', '상명대학교 천안캠퍼스', 'Sangmyung University (Cheonan)',              '천안', 36.83250, 127.17879),
  ('5c0a8f3e-0007-4a6e-9b1d-000000000007', '한국기술교육대학교',   'Korea University of Technology and Education',  '천안', 36.76303, 127.28127)
on conflict (id) do nothing;
