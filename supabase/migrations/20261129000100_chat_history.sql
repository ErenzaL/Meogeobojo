-- =============================================================================
-- 챗봇 기록: every question a user asks the AI chat and what the chat answered, for the admin 챗봇 기록 page.
--
-- This stores free text that people typed, so it is deliberately narrow:
--   * Nobody can read rows directly. Only admins (admin and super_admin, NOT moderators) read them, through
--     admin_chat_turns() / admin_chat_stats(), and opening the history is written to audit_log.
--   * Clients cannot INSERT into the table. The app calls log_chat_turn(), which checks and trims everything, takes the
--     account from the session (auth.uid(), never from the request), and never raises: a bad or too-frequent call
--     returns false so the chat itself is never slowed or broken by logging.
--   * The account id is stored for signed-in users (guests: null) plus the same random device id the usage events use.
--     No email, no IP address, no device details.
--   * Rows older than 90 days are deleted (opportunistically, on insert, like content_sync / ai_chat_usage), and a
--     deleted account takes its rows with it (ON DELETE CASCADE).
--
-- "Result" = what the chat showed: the outcome, the interpreted conditions, the restaurants it recommended (id, name and the
-- one-line reason), and the AI-written sentence. The recommendation itself is still made by the app's own engine.
--
-- Additive and idempotent. Requires 20261109000100 (has_role / _require_role / audit_log). NOT applied by the repository.
-- =============================================================================
do $$ begin
  if to_regprocedure('public.has_role(text)') is null then
    raise exception 'Apply 20261109000100_admin_foundation.sql first.';
  end if;
end $$;

create table if not exists public.chat_turns (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  user_id     uuid references auth.users (id) on delete cascade,   -- null = guest
  client_id   uuid not null,                                       -- the device id the usage events use
  language    text not null check (language in ('ko', 'en', 'zh-Hans')),
  question    text not null check (char_length(question) between 1 and 400),
  intent      text check (intent in ('search', 'more', 'different', 'menu', 'compare', 'chitchat', 'clarify')),
  prefs       jsonb check (prefs is null or (jsonb_typeof(prefs) = 'object' and pg_column_size(prefs) <= 4000)),
  outcome     text not null check (outcome in ('answered', 'no_result', 'chitchat', 'clarify', 'error')),
  -- ok = the AI understood the message and worded the answer; busy = it understood but the app had to word the answer;
  -- down = it did not understand (unreachable / over quota) and the app answered with its own engine.
  ai_status   text not null check (ai_status in ('ok', 'busy', 'down')),
  reply       text check (char_length(reply) <= 600),
  restaurants jsonb not null default '[]'::jsonb
              check (jsonb_typeof(restaurants) = 'array' and jsonb_array_length(restaurants) <= 10),
  failure     text check (char_length(failure) <= 40),
  -- The lines the app wrote itself instead of (or next to) the AI sentence, as their kind names: foundCount, aiBusy,
  -- noneRaiseBudget, menuOpened ... The admin page turns them into words.
  notes       text[] not null default '{}' check (cardinality(notes) <= 8)
);
create index if not exists chat_turns_created_idx on public.chat_turns (id desc);
create index if not exists chat_turns_user_idx on public.chat_turns (user_id, created_at desc);
create index if not exists chat_turns_client_idx on public.chat_turns (client_id, created_at desc);

alter table public.chat_turns enable row level security;
revoke all on public.chat_turns from anon, authenticated;
-- No policy and no grant: rows are invisible and unwritable for every client role. Only the SECURITY DEFINER functions
-- below (and the service role / SQL editor) touch the table.

-- ---------------------------------------------------------------------------
-- The app records one finished turn. Never raises.
-- ---------------------------------------------------------------------------
create or replace function public.log_chat_turn(
  p_client_id   uuid,
  p_language    text,
  p_question    text,
  p_intent      text,
  p_prefs       jsonb,
  p_outcome     text,
  p_ai_status   text,
  p_reply       text,
  p_restaurants jsonb,
  p_failure     text,
  p_notes       text[] default null
) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid      uuid := auth.uid();
  v_question text := left(btrim(coalesce(p_question, '')), 400);
  v_reply    text := nullif(left(btrim(coalesce(p_reply, '')), 600), '');
  v_failure  text := nullif(left(btrim(coalesce(p_failure, '')), 40), '');
  v_rest     jsonb;
  v_prefs    jsonb;
  v_notes    text[];
  v_recent   integer;
begin
  if p_client_id is null or v_question = '' then return false; end if;
  if p_language is null or p_language not in ('ko', 'en', 'zh-Hans') then return false; end if;
  if p_outcome is null or p_outcome not in ('answered', 'no_result', 'chitchat', 'clarify', 'error') then return false; end if;
  if p_ai_status is null or p_ai_status not in ('ok', 'busy', 'down') then return false; end if;
  if p_intent is not null and p_intent not in ('search', 'more', 'different', 'menu', 'compare', 'chitchat', 'clarify') then
    return false;
  end if;

  -- At most 60 turns per hour for one account (or, for a guest, one device id): a person does not chat faster, and a
  -- script cannot flood the table. ponytail: a script can still rotate client ids; add a global hourly cap if that happens.
  select count(*) into v_recent
    from public.chat_turns t
   where t.created_at > now() - interval '1 hour'
     and (case when v_uid is not null then t.user_id = v_uid else (t.user_id is null and t.client_id = p_client_id) end);
  if v_recent >= 60 then return false; end if;

  -- Restaurants: keep only id / name / reason of at most 10 entries, each cut to a sane length.
  if p_restaurants is not null and jsonb_typeof(p_restaurants) = 'array' then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'id', left(e.value ->> 'id', 64),
             'name', left(e.value ->> 'name', 80),
             'reason', left(e.value ->> 'reason', 160))) order by e.ord), '[]'::jsonb)
      into v_rest
      from (select x.value, x.ord from jsonb_array_elements(p_restaurants) with ordinality as x(value, ord) limit 10) e
     where jsonb_typeof(e.value) = 'object' and coalesce(e.value ->> 'id', '') <> '';
  end if;
  v_rest := coalesce(v_rest, '[]'::jsonb);

  v_prefs := case when p_prefs is not null and jsonb_typeof(p_prefs) = 'object' and pg_column_size(p_prefs) <= 4000
                  then p_prefs else null end;

  select coalesce(array_agg(left(x.n, 30) order by x.ord), '{}') into v_notes
    from (select n, ord from unnest(coalesce(p_notes, '{}'::text[])) with ordinality as u(n, ord)
           where n is not null and btrim(n) <> '' limit 8) x;

  insert into public.chat_turns (user_id, client_id, language, question, intent, prefs, outcome, ai_status, reply, restaurants, failure, notes)
  values (v_uid, p_client_id, p_language, v_question, p_intent, v_prefs, p_outcome, p_ai_status, v_reply, v_rest, v_failure, v_notes);

  -- 90-day retention, done now and then instead of by a scheduled job.
  if random() < 0.02 then
    delete from public.chat_turns where created_at < now() - interval '90 days';
  end if;
  return true;
exception when others then
  return false;   -- logging must never break the chat
end $$;

revoke all on function public.log_chat_turn(uuid, text, text, text, jsonb, text, text, text, jsonb, text, text[]) from public;
grant execute on function public.log_chat_turn(uuid, text, text, text, jsonb, text, text, text, jsonb, text, text[]) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Admin: the history (newest first, "load more" by id) and its totals.
-- ---------------------------------------------------------------------------
create or replace function public.admin_chat_turns(
  p_limit      integer default 50,
  p_before     bigint  default null,
  p_days       integer default 30,
  p_search     text    default null,
  p_outcome    text    default null,
  p_language   text    default null,
  p_only_users boolean default false
) returns table (
  id bigint, created_at timestamptz, user_id uuid, nickname text, client_id uuid, language text, question text,
  intent text, prefs jsonb, outcome text, ai_status text, reply text, restaurants jsonb, failure text, notes text[]
) language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_like text := case when nullif(btrim(coalesce(p_search, '')), '') is null then null
                      else '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
begin
  perform public._require_role('admin');
  -- Reading people's questions is itself recorded (first page only, so "load more" does not flood the log).
  if p_before is null then
    insert into public.audit_log (actor_id, action, table_name, details)
    values (auth.uid(), 'view_chat_history', 'chat_turns',
            jsonb_build_object('days', p_days, 'search', v_like is not null, 'outcome', p_outcome, 'language', p_language));
  end if;
  return query
    select t.id, t.created_at, t.user_id, p.nickname, t.client_id, t.language, t.question, t.intent, t.prefs,
           t.outcome, t.ai_status, t.reply, t.restaurants, t.failure, t.notes
      from public.chat_turns t
      left join public.profiles p on p.id = t.user_id
     where t.created_at >= now() - make_interval(days => least(greatest(p_days, 1), 90))
       and (p_before is null or t.id < p_before)
       and (v_like is null or t.question ilike v_like escape '\')
       and (p_outcome is null or t.outcome = p_outcome)
       and (p_language is null or t.language = p_language)
       and (not coalesce(p_only_users, false) or t.user_id is not null)
     order by t.id desc
     limit least(greatest(p_limit, 1), 100);
end $$;

create or replace function public.admin_chat_stats(p_days integer default 30)
returns table (
  turns bigint, askers bigint, signed_in_turns bigint, answered bigint, no_result bigint,
  chitchat bigint, errors bigint, ai_issues bigint
) language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  return query
    select count(*)::bigint,
           count(distinct coalesce(t.user_id::text, t.client_id::text))::bigint,
           count(*) filter (where t.user_id is not null)::bigint,
           count(*) filter (where t.outcome = 'answered')::bigint,
           count(*) filter (where t.outcome = 'no_result')::bigint,
           count(*) filter (where t.outcome in ('chitchat', 'clarify'))::bigint,
           count(*) filter (where t.outcome = 'error')::bigint,
           count(*) filter (where t.ai_status <> 'ok')::bigint
      from public.chat_turns t
     where t.created_at >= now() - make_interval(days => least(greatest(p_days, 1), 90));
end $$;

revoke all on function public.admin_chat_turns(integer, bigint, integer, text, text, text, boolean) from public, anon;
revoke all on function public.admin_chat_stats(integer) from public, anon;
grant execute on function public.admin_chat_turns(integer, bigint, integer, text, text, text, boolean) to authenticated;
grant execute on function public.admin_chat_stats(integer) to authenticated;
