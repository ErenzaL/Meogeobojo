-- Phase 2 / auth: one profile row per Supabase Auth user.
-- Additive and idempotent. Requires 20261031000100_universities.sql first.
-- Never overwrites an existing profile.

do $$
begin
  if to_regclass('public.universities') is null then
    raise exception 'Apply 20261031000100_universities.sql before this migration';
  end if;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end $$;

create table if not exists public.profiles (
  id                      uuid primary key references auth.users (id) on delete cascade,
  nickname                text check (nickname is null or char_length(nickname) between 1 and 30),
  avatar_path             text,
  selected_university_id  uuid references public.universities (id) on delete set null,
  preferred_language      text check (preferred_language is null or preferred_language in ('ko', 'en', 'zh-Hans')),
  onboarding_completed    boolean not null default false,
  onboarding_completed_at timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint profiles_onboarding_ts check (onboarding_completed or onboarding_completed_at is null)
);

create index if not exists profiles_selected_university_idx
  on public.profiles (selected_university_id);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;

drop policy if exists "profiles: read own"   on public.profiles;
drop policy if exists "profiles: insert own" on public.profiles;
drop policy if exists "profiles: update own" on public.profiles;

create policy "profiles: read own" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy "profiles: insert own" on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No anonymous access at all. Clients may edit their display fields only;
-- onboarding_completed* can only be set through save_user_preferences(), so
-- onboarding can never be marked done without preferences being saved.
revoke all on public.profiles from anon;
revoke all on public.profiles from authenticated;
grant select on public.profiles to authenticated;
grant insert (id, nickname, avatar_path, selected_university_id, preferred_language)
  on public.profiles to authenticated;
grant update (nickname, avatar_path, selected_university_id, preferred_language)
  on public.profiles to authenticated;

-- Create the profile when an auth user is created (email sign-up and Kakao).
-- It must never block sign-up: any failure is downgraded to a warning and
-- the app creates the row on first load instead (ON CONFLICT DO NOTHING).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nickname)
  values (
    new.id,
    nullif(left(btrim(coalesce(
      new.raw_user_meta_data ->> 'nickname',
      new.raw_user_meta_data ->> 'name',
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'preferred_username',
      ''
    )), 30), '')
  )
  on conflict (id) do nothing;
  return new;
exception when others then
  raise warning 'handle_new_user failed for %: %', new.id, sqlerrm;
  return new;
end $$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
