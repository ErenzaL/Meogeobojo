-- Atomic onboarding / preference save.
--
-- One function = one transaction: preferences are written AND the profile is
-- marked onboarded, or nothing is. The user is always auth.uid() from the
-- JWT; the client cannot name another user. SECURITY DEFINER is needed only
-- because clients have no UPDATE right on profiles.onboarding_completed*;
-- search_path is pinned and every object is schema-qualified.
--
-- Also used from MY → 나의 취향 설정: re-saving keeps onboarding_completed
-- true and keeps the original onboarding_completed_at.

create or replace function public.save_user_preferences(
  p_university_id       uuid,
  p_budget_type         text,
  p_budget_amount_krw   integer,
  p_travel_mode         text,
  p_max_travel_minutes  integer,
  p_companion_type      text,
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
  v_uid     uuid := auth.uid();
  v_univ    uuid := p_university_id;
  v_profile public.profiles;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- An unknown campus id must not block onboarding.
  if v_univ is not null
     and not exists (select 1 from public.universities where id = v_univ) then
    v_univ := null;
  end if;

  -- Value validation is done by the table CHECK constraints; a violation
  -- raises and rolls the whole call back.
  insert into public.profiles (id) values (v_uid) on conflict (id) do nothing;

  insert into public.user_preferences (
    user_id, university_id, budget_type, budget_amount_krw, travel_mode,
    max_travel_minutes, companion_type, preferred_cuisines, preferred_tags,
    prioritize_untried
  ) values (
    v_uid, v_univ, p_budget_type, p_budget_amount_krw, p_travel_mode,
    p_max_travel_minutes, p_companion_type,
    coalesce(p_preferred_cuisines, '{}'), coalesce(p_preferred_tags, '{}'),
    coalesce(p_prioritize_untried, false)
  )
  on conflict (user_id) do update set
    university_id      = excluded.university_id,
    budget_type        = excluded.budget_type,
    budget_amount_krw  = excluded.budget_amount_krw,
    travel_mode        = excluded.travel_mode,
    max_travel_minutes = excluded.max_travel_minutes,
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
  uuid, text, integer, text, integer, text, text[], text[], boolean
) from public, anon;
grant execute on function public.save_user_preferences(
  uuid, text, integer, text, integer, text, text[], text[], boolean
) to authenticated;
