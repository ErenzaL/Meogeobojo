-- 학식: university cafeterias and their weekly meals.
-- Additive and idempotent. Requires 20261031000100_universities.sql.
--
-- DATA POLICY: no cafeteria or menu rows are seeded. Every row must come from
-- a verified, permitted source and carry verified_at (and source_url when one
-- exists). Rows are written only by administrators (SQL Editor / CLI, see
-- supabase/cafeteria/); clients can only read.

do $$
begin
  if to_regclass('public.universities') is null then
    raise exception 'Apply 20261031000100_universities.sql before this migration';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Cafeterias. `kind` is a category, not a confirmed name: names are optional
-- and only filled in when an official source gives them (never invented).
-- ---------------------------------------------------------------------------
create table if not exists public.campus_cafeterias (
  id                    uuid primary key default gen_random_uuid(),
  university_id         uuid not null references public.universities (id) on delete cascade,
  kind                  text not null default 'other'
                          check (kind in ('student', 'dormitory', 'staff', 'other')),
  name_ko               text check (name_ko is null or btrim(name_ko) <> ''),
  name_en               text check (name_en is null or btrim(name_en) <> ''),
  name_zh               text check (name_zh is null or btrim(name_zh) <> ''),
  location_description  text,
  sort_order            smallint not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists campus_cafeterias_university_idx
  on public.campus_cafeterias (university_id, sort_order);

-- ---------------------------------------------------------------------------
-- Meals. One row per (cafeteria, date, meal type, option). Cafeterias that
-- serve several choices in one meal period (e.g. "A코너"/"B코너") use
-- option_name; '' is the single/default option, so a second option never
-- overwrites the first.
-- ---------------------------------------------------------------------------
create table if not exists public.cafeteria_meals (
  id            uuid primary key default gen_random_uuid(),
  cafeteria_id  uuid not null references public.campus_cafeterias (id) on delete cascade,
  meal_date     date not null,
  meal_type     text not null check (meal_type in ('breakfast', 'lunch', 'dinner')),
  option_name   text not null default '',
  option_order  smallint not null default 0,

  -- [{"name_ko": "...", "name_en": null, "name_zh": null, "kind": "main"}, ...]
  -- kind: main | side | soup | rice | other. Translations only when verified.
  menu_items    jsonb not null default '[]'::jsonb
                  check (jsonb_typeof(menu_items) = 'array'),

  price_krw     integer check (price_krw is null or price_krw >= 0),
  start_time    time,
  end_time      time,

  -- published: a menu is listed. closed: the source states the cafeteria does
  -- not serve this meal. no_menu: the source states no menu is published.
  -- A MISSING row means "not collected yet" and is never shown as closed.
  status        text not null default 'published'
                  check (status in ('published', 'closed', 'no_menu')),

  source_url    text check (source_url is null or source_url ~ '^https://'),
  verified_at   timestamptz not null,

  -- Room for later features without schema churn: photos, nutrition,
  -- calories, allergens, ratings ...
  extra         jsonb not null default '{}'::jsonb
                  check (jsonb_typeof(extra) = 'object'),

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint cafeteria_meals_one_per_option
    unique (cafeteria_id, meal_date, meal_type, option_name),
  constraint cafeteria_meals_published_has_items
    check (status <> 'published' or jsonb_array_length(menu_items) > 0),
  constraint cafeteria_meals_time_order
    check (start_time is null or end_time is null or start_time < end_time)
);

create index if not exists cafeteria_meals_week_idx
  on public.cafeteria_meals (cafeteria_id, meal_date);

drop trigger if exists campus_cafeterias_set_updated_at on public.campus_cafeterias;
create trigger campus_cafeterias_set_updated_at
  before update on public.campus_cafeterias
  for each row execute function public.set_updated_at();

drop trigger if exists cafeteria_meals_set_updated_at on public.cafeteria_meals;
create trigger cafeteria_meals_set_updated_at
  before update on public.cafeteria_meals
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Security: world-readable, administrator-writable only. There are NO insert /
-- update / delete policies and no such grants for anon or authenticated, so
-- no app user (signed in or not) can change a menu through the API.
-- Administrators write with the SQL editor / `supabase db query`.
-- ---------------------------------------------------------------------------
alter table public.campus_cafeterias enable row level security;
alter table public.cafeteria_meals   enable row level security;

drop policy if exists "campus_cafeterias: public read" on public.campus_cafeterias;
create policy "campus_cafeterias: public read" on public.campus_cafeterias
  for select to anon, authenticated using (true);

drop policy if exists "cafeteria_meals: public read" on public.cafeteria_meals;
create policy "cafeteria_meals: public read" on public.cafeteria_meals
  for select to anon, authenticated using (true);

-- Hosted Supabase grants nothing to client roles by default: be explicit.
revoke all on public.campus_cafeterias, public.cafeteria_meals from anon, authenticated;
grant select on public.campus_cafeterias, public.cafeteria_meals to anon, authenticated;
