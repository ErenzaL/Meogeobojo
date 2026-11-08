-- Phase 2 / onboarding: one row of structured preferences per user.
-- Additive and idempotent. Requires the universities + profiles migrations.

do $$
begin
  -- An earlier OPTIONAL draft (20261031000300) defined a different
  -- user_preferences shape. If that was applied, stop instead of guessing.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'user_preferences'
      and column_name = 'preferred_categories'
  ) then
    raise exception
      'public.user_preferences has the legacy shape (preferred_categories). Migrate or drop it manually, then re-run.';
  end if;
end $$;

create table if not exists public.user_preferences (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  university_id      uuid references public.universities (id) on delete set null,

  -- 'max' = at most budget_amount_krw, 'min' = at least budget_amount_krw
  -- ("12,000원 이상"), 'any' = unrestricted (no amount). KRW per person.
  budget_type        text not null default 'any' check (budget_type in ('max', 'min', 'any')),
  budget_amount_krw  integer check (budget_amount_krw is null or budget_amount_krw > 0),

  travel_mode        text not null default 'any' check (travel_mode in ('walk', 'drive', 'any')),
  max_travel_minutes integer check (max_travel_minutes is null or max_travel_minutes between 1 and 120),

  companion_type     text check (companion_type is null or companion_type in
                       ('solo', 'friends_2_3', 'group_4_plus', 'senior', 'junior', 'professor')),

  preferred_cuisines text[] not null default '{}',
  preferred_tags     text[] not null default '{}',

  -- Stored now; only has an effect once real food records exist.
  prioritize_untried boolean not null default false,

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint user_preferences_budget_shape check (
    (budget_type = 'any' and budget_amount_krw is null)
    or (budget_type in ('max', 'min') and budget_amount_krw is not null)
  ),
  constraint user_preferences_travel_shape check (
    (travel_mode = 'any' and max_travel_minutes is null)
    or (travel_mode in ('walk', 'drive') and max_travel_minutes is not null)
  ),
  constraint user_preferences_cuisines_allowed check (
    preferred_cuisines <@ array['korean','japanese','chinese','snack','cafe','western','salad','any']::text[]
  ),
  -- "상관없음" is exclusive.
  constraint user_preferences_cuisines_any_exclusive check (
    not ('any' = any (preferred_cuisines)) or cardinality(preferred_cuisines) = 1
  ),
  constraint user_preferences_tags_allowed check (
    preferred_tags <@ array['spicy','hearty','value','light']::text[]
  )
);

drop trigger if exists user_preferences_set_updated_at on public.user_preferences;
create trigger user_preferences_set_updated_at
  before update on public.user_preferences
  for each row execute function public.set_updated_at();

alter table public.user_preferences enable row level security;

drop policy if exists "user_preferences: read own"   on public.user_preferences;
drop policy if exists "user_preferences: insert own" on public.user_preferences;
drop policy if exists "user_preferences: update own" on public.user_preferences;

create policy "user_preferences: read own" on public.user_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy "user_preferences: insert own" on public.user_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "user_preferences: update own" on public.user_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke all on public.user_preferences from anon;
revoke all on public.user_preferences from authenticated;
grant select, insert, update on public.user_preferences to authenticated;
