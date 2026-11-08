-- A. App-specific nickname  /  B. Multiple dining companions.
-- Additive except for ONE intentional signature replacement (see part B):
-- the old save_user_preferences(...) is dropped and recreated in the same
-- transaction so PostgREST never sees two overloads. No data is deleted.

-- ============================================================================
-- A. Nickname
-- ============================================================================
-- profiles.nickname keeps holding whatever name we have to display. The new
-- flag records whether the USER chose it for 먹어보조. Names copied from Kakao
-- (signup trigger / first load) stay `false`, so they never count as chosen.
-- Existing rows are intentionally NOT guessed at: every current account
-- starts as `false` and is asked once.
alter table public.profiles
  add column if not exists nickname_is_custom boolean not null default false;

comment on column public.profiles.nickname_is_custom is
  'true only when the user typed this nickname in 먹어보조; provider-supplied names are false.';

-- Backstop for the rules enforced in the app and in set_nickname():
-- 2-15 characters (code points), no outer whitespace, no control or
-- invisible/format characters. Only applies to custom nicknames, so legacy
-- provider names (up to 30 chars, governed by profiles_nickname_check) are
-- unaffected.
alter table public.profiles drop constraint if exists profiles_custom_nickname_rules;
alter table public.profiles add constraint profiles_custom_nickname_rules check (
  not nickname_is_custom
  or (
    nickname is not null
    and char_length(nickname) between 2 and 15
    and nickname = btrim(nickname)
    and nickname !~ '[\u0001-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]'
  )
);

-- Nicknames can now only be changed through set_nickname() (server-side
-- validation + the flag). Clients keep editing their other display fields.
revoke update (nickname) on public.profiles from authenticated;

create or replace function public.set_nickname(p_nickname text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_profile public.profiles;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_nickname is null
     or p_nickname <> btrim(p_nickname)
     or char_length(p_nickname) not between 2 and 15
     or p_nickname ~ '[\u0001-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]'
  then
    raise exception 'invalid nickname' using errcode = '23514';
  end if;

  insert into public.profiles (id) values (v_uid) on conflict (id) do nothing;

  update public.profiles
     set nickname = p_nickname,
         nickname_is_custom = true
   where id = v_uid
  returning * into v_profile;

  return v_profile;
end $$;

revoke all on function public.set_nickname(text) from public, anon;
grant execute on function public.set_nickname(text) to authenticated;

-- ============================================================================
-- B. Companions: companion_type (one value)  ->  companion_types (many)
-- ============================================================================
alter table public.user_preferences
  add column if not exists companion_types text[] not null default '{}';

-- Existing single values become one-element arrays; NULL stays an empty array.
-- Only rows not yet migrated are touched, so re-running is a no-op.
update public.user_preferences
   set companion_types = array[companion_type]
 where companion_type is not null
   and cardinality(companion_types) = 0;

alter table public.user_preferences
  drop constraint if exists user_preferences_companion_types_allowed;
alter table public.user_preferences
  add constraint user_preferences_companion_types_allowed check (
    companion_types <@ array['solo','friends_2_3','group_4_plus','senior','junior','professor']::text[]
  );

-- Kept (not dropped) until every caller has moved over; the RPC below keeps it
-- in sync for a single selection and nulls it otherwise.
comment on column public.user_preferences.companion_type is
  'DEPRECATED: use companion_types. Retire in a later migration.';

-- Replace the RPC. The OLD signature (…, p_companion_type text, …) is dropped
-- in the same transaction so there are never two overloads.
drop function if exists public.save_user_preferences(
  uuid, text, integer, text, integer, text, text[], text[], boolean
);

create or replace function public.save_user_preferences(
  p_university_id       uuid,
  p_budget_type         text,
  p_budget_amount_krw   integer,
  p_travel_mode         text,
  p_max_travel_minutes  integer,
  p_companion_types     text[],
  p_preferred_cuisines  text[],
  p_preferred_tags      text[],
  p_prioritize_untried  boolean
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_univ       uuid := p_university_id;
  v_companions text[];
  v_profile    public.profiles;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if v_univ is not null
     and not exists (select 1 from public.universities where id = v_univ) then
    v_univ := null;
  end if;

  -- De-duplicated and ordered. Allowed values are enforced by the table CHECK
  -- constraint, so an invalid value raises and rolls everything back.
  v_companions := coalesce(
    array(select distinct c from unnest(coalesce(p_companion_types, '{}')) as c order by c),
    '{}'
  );

  insert into public.profiles (id) values (v_uid) on conflict (id) do nothing;

  insert into public.user_preferences (
    user_id, university_id, budget_type, budget_amount_krw, travel_mode,
    max_travel_minutes, companion_types, companion_type, preferred_cuisines,
    preferred_tags, prioritize_untried
  ) values (
    v_uid, v_univ, p_budget_type, p_budget_amount_krw, p_travel_mode,
    p_max_travel_minutes, v_companions,
    case when cardinality(v_companions) = 1 then v_companions[1] else null end,
    coalesce(p_preferred_cuisines, '{}'), coalesce(p_preferred_tags, '{}'),
    coalesce(p_prioritize_untried, false)
  )
  on conflict (user_id) do update set
    university_id      = excluded.university_id,
    budget_type        = excluded.budget_type,
    budget_amount_krw  = excluded.budget_amount_krw,
    travel_mode        = excluded.travel_mode,
    max_travel_minutes = excluded.max_travel_minutes,
    companion_types    = excluded.companion_types,
    companion_type     = excluded.companion_type,
    preferred_cuisines = excluded.preferred_cuisines,
    preferred_tags     = excluded.preferred_tags,
    prioritize_untried = excluded.prioritize_untried;

  update public.profiles
     set onboarding_completed    = true,
         onboarding_completed_at = coalesce(onboarding_completed_at, now()),
         selected_university_id  = coalesce(v_univ, selected_university_id)
   where id = v_uid
  returning * into v_profile;

  return v_profile;
end $$;

revoke all on function public.save_user_preferences(
  uuid, text, integer, text, integer, text[], text[], text[], boolean
) from public, anon;
grant execute on function public.save_user_preferences(
  uuid, text, integer, text, integer, text[], text[], text[], boolean
) to authenticated;
