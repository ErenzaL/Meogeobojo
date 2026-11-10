-- Monthly mission system: campaigns, missions, per-user progress, points,
-- badges, activity events and user contributions, plus the server-side
-- functions that validate progress and award rewards.
--
-- Additive and idempotent (safe to re-run). Nothing existing is altered or
-- dropped. Requires 20261109000100_admin_foundation.sql (has_role, audit_log,
-- audit_row_change, _require_role) and the favorites / student_reviews /
-- restaurant_overrides / profiles tables it builds on.
--
-- Security model
--   * Clients can READ their own progress, points and badges. They can NOT
--     write any of those tables: progress and rewards are produced only by
--     SECURITY DEFINER functions that recompute everything from real data
--     (favorites, reviews, approved contributions, de-duplicated activity).
--   * Rewards are idempotent: a unique index allows ONE mission_reward per
--     (user, mission lineage, period), so re-running or racing the evaluator,
--     or editing a mission into a new version, can never pay twice.
--   * Mission periods are calendar periods in Asia/Seoul; every timestamp is
--     stored in UTC (timestamptz).
--   * Admin operations check the caller's role in the database, record a
--     reason where it matters and write public.audit_log. No function lets an
--     admin edit progress or a point balance directly: a fraudulent reward is
--     reversed with an auditable negative transaction.

do $$ begin
  if to_regprocedure('public.has_role(text)') is null
     or to_regprocedure('public._require_role(text)') is null
     or to_regclass('public.favorites') is null
     or to_regclass('public.student_reviews') is null
     or to_regclass('public.restaurant_overrides') is null
     or to_regclass('public.profiles') is null then
    raise exception 'Apply 20261109000100_admin_foundation.sql (and its prerequisites) first.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Time helpers (periods are Asia/Seoul calendar periods)
-- ---------------------------------------------------------------------------
create or replace function public.seoul_date(p_ts timestamptz default now())
returns date language sql stable as $$
  select (p_ts at time zone 'Asia/Seoul')::date
$$;

-- draft | scheduled | active | ended, derived from the dates.
create or replace function public.campaign_state(p_publish text, p_start timestamptz, p_end timestamptz)
returns text language sql stable as $$
  select case
    when p_publish <> 'published' then 'draft'
    when now() < p_start then 'scheduled'
    when now() < p_end then 'active'
    else 'ended'
  end
$$;

-- ---------------------------------------------------------------------------
-- monthly_campaigns
-- ---------------------------------------------------------------------------
create table if not exists public.monthly_campaigns (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique check (slug ~ '^[a-z0-9][a-z0-9_-]{1,40}$'),
  title         text not null check (btrim(title) <> '' and char_length(title) <= 60),
  subtitle      text check (subtitle is null or char_length(subtitle) <= 120),
  description   text check (description is null or char_length(description) <= 1000),
  theme_color   text not null default '#E85D04' check (theme_color ~ '^#[0-9A-Fa-f]{6}$'),
  -- Keys of the EXISTING mascot artwork (assets/images/mascot); no new art.
  banner_mascot text not null default 'cheer'
    check (banner_mascot in ('standing','wink','cheer','sparkle','burger','boba','searching','sleeping','confused','running')),
  -- Exclusive end: a campaign for November ends at 2026-12-01 00:00 Seoul.
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  publish_state text not null default 'draft' check (publish_state in ('draft', 'published')),
  created_by    uuid default auth.uid() references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint monthly_campaigns_window check (ends_at > starts_at)
);
drop trigger if exists monthly_campaigns_set_updated_at on public.monthly_campaigns;
create trigger monthly_campaigns_set_updated_at before update on public.monthly_campaigns
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- missions
--   kind        monthly (belongs to a campaign) | daily | weekly | achievement
--   recurrence  none | daily | weekly  (daily / weekly missions reset on their
--               Asia/Seoul period boundary; one reward per period)
--   rule_type   what is counted, always from real data:
--                 favorite_distinct   distinct saved places in the window
--                 favorite_cheap      distinct saved places whose PUBLISHED
--                                     admin price is <= max_price_krw
--                 activity_days       distinct Seoul days with params.event
--                 activity_refs       distinct params.event refs (minus params.exclude)
--                 review_valid        visible reviews with >= min_chars of text
--                 contribution_approved  approved contributions of params.kind
--                 missions_completed  other missions of the campaign completed
--   Editing a mission that already has progress creates a NEW VERSION
--   (version + 1, same lineage_id): the old row is archived, so completed
--   missions and paid rewards are never rewritten, and the lineage-level
--   unique index stops a second reward.
-- ---------------------------------------------------------------------------
create table if not exists public.missions (
  id            uuid primary key default gen_random_uuid(),
  lineage_id    uuid not null default gen_random_uuid(),
  version       integer not null default 1 check (version >= 1),
  supersedes_id uuid references public.missions (id) on delete set null,
  campaign_id   uuid references public.monthly_campaigns (id) on delete restrict,
  slug          text not null check (slug ~ '^[a-z0-9][a-z0-9_-]{1,60}$'),
  kind          text not null check (kind in ('monthly', 'daily', 'weekly', 'achievement')),
  title         text not null check (btrim(title) <> '' and char_length(title) <= 60),
  description   text check (description is null or char_length(description) <= 300),
  category      text check (category is null or char_length(category) <= 30),
  icon          text not null default 'star' check (char_length(icon) between 1 and 30),
  reward_points integer not null default 0 check (reward_points between 0 and 10000),
  rule_type     text not null check (rule_type in (
                  'favorite_distinct', 'favorite_cheap', 'activity_days', 'activity_refs',
                  'review_valid', 'contribution_approved', 'missions_completed')),
  rule_params   jsonb not null default '{}'::jsonb check (jsonb_typeof(rule_params) = 'object'),
  target_count  integer not null check (target_count between 1 and 1000),
  recurrence    text not null default 'none' check (recurrence in ('none', 'daily', 'weekly')),
  -- null = every campus
  university_id uuid references public.universities (id) on delete set null,
  -- null = use the campaign's window; both null and no campaign = always on
  starts_at     timestamptz,
  ends_at       timestamptz,
  -- where the app's action button leads (a closed list the app understands)
  action_key    text not null default 'none'
                  check (action_key in ('none', 'recommend', 'map', 'favorites', 'review', 'photo', 'correct', 'categories')),
  sort_order    integer not null default 0,
  reward_badge_key    text check (reward_badge_key is null or reward_badge_key ~ '^[a-z0-9][a-z0-9_]{1,60}$'),
  reward_badge_name   text check (reward_badge_name is null or char_length(reward_badge_name) <= 60),
  reward_badge_mascot text check (reward_badge_mascot is null or reward_badge_mascot in
                  ('standing','wink','cheer','sparkle','burger','boba','searching','sleeping','confused','running')),
  status        text not null default 'draft' check (status in ('draft', 'active', 'paused', 'archived')),
  created_by    uuid default auth.uid() references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint missions_slug_version_key unique (slug, version),
  constraint missions_window check (starts_at is null or ends_at is null or ends_at > starts_at),
  constraint missions_monthly_has_campaign check (kind <> 'monthly' or campaign_id is not null)
);
create index if not exists missions_campaign_idx on public.missions (campaign_id, sort_order);
create index if not exists missions_status_idx on public.missions (status, kind);
drop trigger if exists missions_set_updated_at on public.missions;
create trigger missions_set_updated_at before update on public.missions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Per-user progress (written ONLY by the evaluator)
-- ---------------------------------------------------------------------------
create table if not exists public.user_mission_progress (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  mission_id   uuid not null references public.missions (id) on delete restrict,
  lineage_id   uuid not null,
  -- 'once' (campaign / dated window), 'all' (lifetime), 'YYYY-MM-DD' (daily),
  -- 'YYYY-"W"IW' (weekly, Seoul Monday start)
  period_key   text not null,
  progress     integer not null default 0 check (progress >= 0),
  target       integer not null check (target >= 1),
  completed_at timestamptz,
  revoked_at   timestamptz,
  updated_at   timestamptz not null default now(),
  constraint user_mission_progress_key unique (user_id, mission_id, period_key)
);
create index if not exists user_mission_progress_user_idx on public.user_mission_progress (user_id);
create index if not exists user_mission_progress_lineage_idx
  on public.user_mission_progress (user_id, lineage_id, period_key);

-- ---------------------------------------------------------------------------
-- Points ledger (append-only). Balance = sum(points).
-- ---------------------------------------------------------------------------
create table if not exists public.point_transactions (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  points      integer not null check (points <> 0),
  kind        text not null check (kind in ('mission_reward', 'revocation')),
  mission_id  uuid references public.missions (id) on delete restrict,
  lineage_id  uuid,
  period_key  text,
  ref_id      bigint references public.point_transactions (id) on delete restrict,
  reason      text,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  constraint point_transactions_sign check (
    (kind = 'mission_reward' and points > 0 and mission_id is not null
       and lineage_id is not null and period_key is not null)
    or (kind = 'revocation' and points < 0 and ref_id is not null))
);
create index if not exists point_transactions_user_idx on public.point_transactions (user_id, created_at desc);
-- THE duplicate-reward guard: one reward per user, mission lineage and period.
create unique index if not exists point_transactions_one_reward
  on public.point_transactions (user_id, lineage_id, period_key) where kind = 'mission_reward';
-- A reward can be reversed at most once.
create unique index if not exists point_transactions_one_revocation
  on public.point_transactions (ref_id) where kind = 'revocation';

-- ---------------------------------------------------------------------------
-- Badges
-- ---------------------------------------------------------------------------
create table if not exists public.user_badges (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  badge_key   text not null,
  badge_name  text,
  mascot_key  text,
  mission_id  uuid references public.missions (id) on delete set null,
  campaign_id uuid references public.monthly_campaigns (id) on delete set null,
  awarded_at  timestamptz not null default now(),
  revoked_at  timestamptz,
  constraint user_badges_user_badge_key unique (user_id, badge_key)
);
create index if not exists user_badges_user_idx on public.user_badges (user_id);

-- ---------------------------------------------------------------------------
-- activity_events: de-duplicated user actions that have no table of their own
-- (checking recommendations, exploring a category). One row per user, event,
-- ref and Seoul day, so repeated taps change nothing.
-- ---------------------------------------------------------------------------
create table if not exists public.activity_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  event_type text not null check (event_type in ('recommendation_view', 'category_explore')),
  ref_key    text not null default '' check (char_length(ref_key) <= 40),
  local_date date not null,
  created_at timestamptz not null default now(),
  constraint activity_events_once_per_day unique (user_id, event_type, ref_key, local_date)
);
create index if not exists activity_events_user_idx on public.activity_events (user_id, event_type, created_at);
create index if not exists activity_events_created_idx on public.activity_events (created_at desc);

-- ---------------------------------------------------------------------------
-- user_contributions: menu photos and menu / price corrections, reviewed by an
-- admin before they count for a mission.
-- ---------------------------------------------------------------------------
create table if not exists public.user_contributions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind           text not null check (kind in ('menu_photo', 'info_correction')),
  kakao_place_id text not null check (char_length(kakao_place_id) between 1 and 64),
  payload        jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  status         text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by    uuid references auth.users (id) on delete set null,
  reviewed_at    timestamptz,
  review_note    text,
  created_at     timestamptz not null default now()
);
create index if not exists user_contributions_user_idx on public.user_contributions (user_id, kind, status);
create index if not exists user_contributions_status_idx on public.user_contributions (status, created_at);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.monthly_campaigns     enable row level security;
alter table public.missions              enable row level security;
alter table public.user_mission_progress enable row level security;
alter table public.point_transactions    enable row level security;
alter table public.user_badges           enable row level security;
alter table public.activity_events       enable row level security;
alter table public.user_contributions    enable row level security;

revoke all on public.monthly_campaigns, public.missions, public.user_mission_progress,
  public.point_transactions, public.user_badges, public.activity_events,
  public.user_contributions from anon, authenticated;
-- Reads only. Every write goes through the functions below.
grant select on public.monthly_campaigns, public.missions, public.user_mission_progress,
  public.point_transactions, public.user_badges, public.activity_events,
  public.user_contributions to authenticated;

drop policy if exists "monthly_campaigns: read published" on public.monthly_campaigns;
create policy "monthly_campaigns: read published" on public.monthly_campaigns
  for select to authenticated using (publish_state = 'published' or (select public.has_role('admin')));

drop policy if exists "missions: read active or own history" on public.missions;
create policy "missions: read active or own history" on public.missions
  for select to authenticated using (
    (select public.has_role('admin'))
    or (status = 'active' and (campaign_id is null or exists (
          select 1 from public.monthly_campaigns c where c.id = campaign_id and c.publish_state = 'published')))
    or exists (select 1 from public.user_mission_progress p
                where p.mission_id = missions.id and p.user_id = (select auth.uid())));

drop policy if exists "user_mission_progress: own or admin" on public.user_mission_progress;
create policy "user_mission_progress: own or admin" on public.user_mission_progress
  for select to authenticated using (user_id = (select auth.uid()) or (select public.has_role('admin')));

drop policy if exists "point_transactions: own or admin" on public.point_transactions;
create policy "point_transactions: own or admin" on public.point_transactions
  for select to authenticated using (user_id = (select auth.uid()) or (select public.has_role('admin')));

drop policy if exists "user_badges: own or admin" on public.user_badges;
create policy "user_badges: own or admin" on public.user_badges
  for select to authenticated using (user_id = (select auth.uid()) or (select public.has_role('admin')));

drop policy if exists "activity_events: admin read" on public.activity_events;
create policy "activity_events: admin read" on public.activity_events
  for select to authenticated using ((select public.has_role('admin')));

drop policy if exists "user_contributions: own or moderator" on public.user_contributions;
create policy "user_contributions: own or moderator" on public.user_contributions
  for select to authenticated using (user_id = (select auth.uid()) or (select public.has_role('moderator')));

-- Row-level audit of configuration changes (who changed what, old and new).
drop trigger if exists monthly_campaigns_audit on public.monthly_campaigns;
create trigger monthly_campaigns_audit after insert or update or delete on public.monthly_campaigns
  for each row execute function public.audit_row_change();
drop trigger if exists missions_audit on public.missions;
create trigger missions_audit after insert or update or delete on public.missions
  for each row execute function public.audit_row_change();

-- ---------------------------------------------------------------------------
-- Period of a mission around [p_at]
-- ---------------------------------------------------------------------------
create or replace function public._mission_period(p_m public.missions, p_at timestamptz default now())
returns table (period_key text, win_start timestamptz, win_end timestamptz)
language plpgsql stable set search_path = public, pg_temp as $$
declare
  v_c public.monthly_campaigns;
  v_start timestamptz;
  v_end timestamptz;
  v_day date := public.seoul_date(p_at);
begin
  if p_m.campaign_id is not null then
    select * into v_c from public.monthly_campaigns where id = p_m.campaign_id;
  end if;
  v_start := coalesce(p_m.starts_at, v_c.starts_at);
  v_end   := coalesce(p_m.ends_at, v_c.ends_at);

  if p_m.recurrence = 'daily' then
    period_key := to_char(v_day, 'YYYY-MM-DD');
    win_start  := v_day::timestamp at time zone 'Asia/Seoul';
    win_end    := (v_day + 1)::timestamp at time zone 'Asia/Seoul';
  elsif p_m.recurrence = 'weekly' then
    v_day      := date_trunc('week', v_day::timestamp)::date;          -- Monday
    period_key := to_char(v_day, 'IYYY-"W"IW');
    win_start  := v_day::timestamp at time zone 'Asia/Seoul';
    win_end    := (v_day + 7)::timestamp at time zone 'Asia/Seoul';
  else
    period_key := case when v_start is null and v_end is null then 'all' else 'once' end;
    win_start  := v_start;
    win_end    := v_end;
  end if;
  if p_m.recurrence in ('daily', 'weekly') then
    -- recurring missions are also bounded by their own schedule
    win_start := greatest(win_start, coalesce(v_start, win_start));
    win_end   := least(win_end, coalesce(v_end, win_end));
  end if;
  return next;
end $$;

-- ---------------------------------------------------------------------------
-- What a user has really done inside [p_from, p_to)
-- ---------------------------------------------------------------------------
create or replace function public._mission_count(
  p_user uuid, p_m public.missions, p_from timestamptz, p_to timestamptz)
returns integer language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_from timestamptz := coalesce(p_from, '-infinity'::timestamptz);
  v_to   timestamptz := coalesce(p_to, 'infinity'::timestamptz);
  v_n    integer := 0;
begin
  case p_m.rule_type
    when 'favorite_distinct' then
      select count(distinct f.kakao_place_id) into v_n from public.favorites f
       where f.user_id = p_user and f.created_at >= v_from and f.created_at < v_to;

    when 'favorite_cheap' then
      -- "verified price": a PUBLISHED admin price. Unknown prices never count.
      select count(distinct f.kakao_place_id) into v_n
        from public.favorites f
        join public.restaurant_overrides o on o.kakao_place_id = f.kakao_place_id
       where f.user_id = p_user and f.created_at >= v_from and f.created_at < v_to
         and o.visibility = 'published'
         and o.price_min_krw is not null
         and o.price_min_krw <= coalesce((p_m.rule_params ->> 'max_price_krw')::integer, 10000);

    when 'activity_days' then
      select count(distinct e.local_date) into v_n from public.activity_events e
       where e.user_id = p_user and e.event_type = p_m.rule_params ->> 'event'
         and e.created_at >= v_from and e.created_at < v_to;

    when 'activity_refs' then
      select count(distinct e.ref_key) into v_n from public.activity_events e
       where e.user_id = p_user and e.event_type = p_m.rule_params ->> 'event'
         and e.ref_key <> ''
         and e.created_at >= v_from and e.created_at < v_to
         and not (e.ref_key = any (array(
               select jsonb_array_elements_text(coalesce(p_m.rule_params -> 'exclude', '[]'::jsonb)))));

    when 'review_valid' then
      select count(*) into v_n from public.student_reviews r
       where r.user_id = p_user and r.moderation_status = 'visible'
         and r.created_at >= v_from and r.created_at < v_to
         and char_length(btrim(coalesce(r.body, ''))) >= coalesce((p_m.rule_params ->> 'min_chars')::integer, 10);

    when 'contribution_approved' then
      select count(*) into v_n from public.user_contributions c
       where c.user_id = p_user and c.kind = p_m.rule_params ->> 'kind'
         and c.status = 'approved'
         and c.reviewed_at >= v_from and c.reviewed_at < v_to;

    when 'missions_completed' then
      select count(*) into v_n
        from public.user_mission_progress p
        join public.missions mm on mm.id = p.mission_id
       where p.user_id = p_user and p.completed_at is not null and p.revoked_at is null
         and mm.campaign_id is not distinct from p_m.campaign_id
         and mm.kind = 'monthly' and mm.rule_type <> 'missions_completed'
         and mm.lineage_id <> p_m.lineage_id;
  end case;
  return coalesce(v_n, 0);
end $$;
revoke all on function public._mission_count(uuid, public.missions, timestamptz, timestamptz)
  from public, anon, authenticated;
revoke all on function public._mission_period(public.missions, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The evaluator. Recomputes progress for every ACTIVE mission in its current
-- period from real data and awards each completion exactly once. Returns the
-- missions completed by THIS call (for the app's completion animation).
-- ---------------------------------------------------------------------------
create or replace function public._evaluate_user(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  m           public.missions;
  per         record;
  prog        public.user_mission_progress;
  v_uni       uuid;
  v_new       jsonb := '[]'::jsonb;
  v_cnt       integer;
  v_rewarded  integer;
begin
  -- One evaluation per user at a time; concurrent calls queue here.
  perform pg_advisory_xact_lock(hashtextextended('missions:' || p_user::text, 0));
  select selected_university_id into v_uni from public.profiles where id = p_user;

  for m in
    select ms.* from public.missions ms
     where ms.status = 'active'
       and (ms.university_id is null or ms.university_id = v_uni)
       and (ms.campaign_id is null or exists (
              select 1 from public.monthly_campaigns c
               where c.id = ms.campaign_id and c.publish_state = 'published'))
     order by (ms.rule_type = 'missions_completed'), ms.sort_order, ms.created_at
  loop
    select * into per from public._mission_period(m, now());
    -- outside the mission's window: nothing is counted or awarded
    continue when per.win_start is not null and now() < per.win_start;
    continue when per.win_end is not null and now() >= per.win_end;
    -- already completed in this lineage + period (any version): keep as is
    continue when exists (
      select 1 from public.user_mission_progress x
       where x.user_id = p_user and x.lineage_id = m.lineage_id
         and x.period_key = per.period_key and x.completed_at is not null);

    v_cnt := public._mission_count(p_user, m, per.win_start, per.win_end);

    insert into public.user_mission_progress (user_id, mission_id, lineage_id, period_key, progress, target)
    values (p_user, m.id, m.lineage_id, per.period_key, v_cnt, m.target_count)
    on conflict (user_id, mission_id, period_key) do update
      set progress = greatest(public.user_mission_progress.progress, excluded.progress),
          target = excluded.target, updated_at = now()
    returning * into prog;

    if prog.completed_at is null and prog.progress >= m.target_count then
      update public.user_mission_progress set completed_at = now(), updated_at = now() where id = prog.id;
      if m.reward_points > 0 then
        insert into public.point_transactions (user_id, points, kind, mission_id, lineage_id, period_key, reason)
        values (p_user, m.reward_points, 'mission_reward', m.id, m.lineage_id, per.period_key, m.title)
        on conflict (user_id, lineage_id, period_key) where kind = 'mission_reward' do nothing;
        get diagnostics v_rewarded = row_count;
      else
        v_rewarded := 0;
      end if;
      if m.reward_badge_key is not null then
        insert into public.user_badges (user_id, badge_key, badge_name, mascot_key, mission_id, campaign_id)
        values (p_user, m.reward_badge_key, coalesce(m.reward_badge_name, m.title),
                m.reward_badge_mascot, m.id, m.campaign_id)
        on conflict (user_id, badge_key) do nothing;
      end if;
      v_new := v_new || jsonb_build_object(
        'mission_id', m.id, 'slug', m.slug, 'title', m.title,
        'points', case when v_rewarded > 0 then m.reward_points else 0 end,
        'badge_key', m.reward_badge_key);
    end if;
  end loop;
  return v_new;
end $$;
revoke all on function public._evaluate_user(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Payload for the app: the current campaign + every active mission with the
-- caller's real progress. Read-only.
-- ---------------------------------------------------------------------------
create or replace function public._my_missions_payload(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uni      uuid;
  v_camp     public.monthly_campaigns;
  v_missions jsonb;
  v_badges   jsonb;
  v_total    integer;
  v_month    integer;
begin
  select selected_university_id into v_uni from public.profiles where id = p_user;

  select * into v_camp from public.monthly_campaigns c
   where c.publish_state = 'published' and c.starts_at <= now()
   order by (now() < c.ends_at) desc, c.starts_at desc limit 1;

  select coalesce(jsonb_agg(item order by (item ->> 'sort_order')::int, item ->> 'title'), '[]'::jsonb)
    into v_missions
  from (
    select jsonb_build_object(
      'id', m.id, 'slug', m.slug, 'kind', m.kind, 'title', m.title, 'description', m.description,
      'category', m.category, 'icon', m.icon, 'reward_points', m.reward_points,
      'rule_type', m.rule_type, 'target', m.target_count, 'action_key', m.action_key,
      'sort_order', m.sort_order, 'recurrence', m.recurrence, 'version', m.version,
      'badge_key', m.reward_badge_key, 'badge_name', m.reward_badge_name,
      'badge_mascot', m.reward_badge_mascot,
      'period_key', per.period_key, 'starts_at', per.win_start, 'ends_at', per.win_end,
      'progress', least(coalesce(pr.progress, 0), m.target_count),
      'completed', pr.completed_at is not null and pr.revoked_at is null,
      'completed_at', pr.completed_at,
      'state', case
        when pr.completed_at is not null and pr.revoked_at is null then 'completed'
        when per.win_end is not null and now() >= per.win_end then 'expired'
        when per.win_start is not null and now() < per.win_start then 'upcoming'
        else 'active' end) as item
    from public.missions m
    cross join lateral public._mission_period(m, now()) per
    left join lateral (
      select max(x.progress) as progress,
             max(x.completed_at) as completed_at,
             case when bool_and(x.revoked_at is not null) then max(x.revoked_at) end as revoked_at
        from public.user_mission_progress x
       where x.user_id = p_user and x.lineage_id = m.lineage_id and x.period_key = per.period_key
    ) pr on true
    where m.status = 'active'
      and (m.university_id is null or m.university_id = v_uni)
      and ((m.kind = 'monthly' and m.campaign_id = v_camp.id)
           or (m.kind <> 'monthly'
               and (m.campaign_id is null or exists (
                      select 1 from public.monthly_campaigns c
                       where c.id = m.campaign_id and c.publish_state = 'published'))))
  ) q;

  select coalesce(sum(points), 0) into v_total from public.point_transactions where user_id = p_user;
  select coalesce(sum(points), 0) into v_month from public.point_transactions
   where user_id = p_user and v_camp.id is not null
     and created_at >= v_camp.starts_at and created_at < v_camp.ends_at;

  select coalesce(jsonb_agg(jsonb_build_object(
           'badge_key', b.badge_key, 'name', b.badge_name, 'mascot', b.mascot_key,
           'awarded_at', b.awarded_at, 'campaign_id', b.campaign_id) order by b.awarded_at desc), '[]'::jsonb)
    into v_badges
    from public.user_badges b where b.user_id = p_user and b.revoked_at is null;

  return jsonb_build_object(
    'campaign', case when v_camp.id is null then null else jsonb_build_object(
      'id', v_camp.id, 'slug', v_camp.slug, 'title', v_camp.title, 'subtitle', v_camp.subtitle,
      'description', v_camp.description, 'theme_color', v_camp.theme_color,
      'banner_mascot', v_camp.banner_mascot, 'starts_at', v_camp.starts_at, 'ends_at', v_camp.ends_at,
      'state', public.campaign_state(v_camp.publish_state, v_camp.starts_at, v_camp.ends_at)) end,
    'missions', v_missions,
    'points_total', v_total,
    'points_campaign', v_month,
    'badges', v_badges,
    'server_time', now());
end $$;
revoke all on function public._my_missions_payload(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- App-facing functions (always act on auth.uid(); no user id is accepted)
-- ---------------------------------------------------------------------------
-- Recompute and return the dashboard. `newly_completed` lists what this call
-- completed, so the app can celebrate once.
create or replace function public.sync_my_missions()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_new  jsonb;
begin
  if v_user is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  v_new := public._evaluate_user(v_user);
  return public._my_missions_payload(v_user) || jsonb_build_object('newly_completed', v_new);
end $$;

-- Records one of the few actions that have no table of their own, then
-- re-evaluates. Unknown events are rejected; repeats on the same Seoul day
-- are ignored by the unique constraint.
create or replace function public.log_activity(p_event text, p_ref text default '')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_ref  text := left(btrim(coalesce(p_ref, '')), 40);
begin
  if v_user is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if p_event not in ('recommendation_view', 'category_explore') then
    raise exception 'unknown event' using errcode = '22023';
  end if;
  if p_event = 'category_explore' and v_ref = '' then
    raise exception 'category is required' using errcode = '22023';
  end if;
  if p_event = 'recommendation_view' then v_ref := ''; end if;
  insert into public.activity_events (user_id, event_type, ref_key, local_date)
  values (v_user, p_event, v_ref, public.seoul_date(now()))
  on conflict (user_id, event_type, ref_key, local_date) do nothing;
  return public._evaluate_user(v_user);
end $$;

-- A user's photo / correction, waiting for an admin. Counts only once approved.
create or replace function public.submit_contribution(p_kind text, p_place text, p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_id   uuid;
begin
  if v_user is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if p_kind not in ('menu_photo', 'info_correction') then
    raise exception 'unknown contribution kind' using errcode = '22023';
  end if;
  if p_place is null or btrim(p_place) = '' then
    raise exception 'place is required' using errcode = '22023';
  end if;
  if (select count(*) from public.user_contributions where user_id = v_user and status = 'pending') >= 20 then
    raise exception 'too many pending contributions' using errcode = '54000';
  end if;
  -- identical submissions (same kind, place and content) are duplicates
  if exists (select 1 from public.user_contributions c
              where c.user_id = v_user and c.kind = p_kind and c.kakao_place_id = btrim(p_place)
                and c.payload = coalesce(p_payload, '{}'::jsonb) and c.status <> 'rejected') then
    raise exception 'duplicate contribution' using errcode = '23505';
  end if;
  insert into public.user_contributions (user_id, kind, kakao_place_id, payload)
  values (v_user, p_kind, btrim(p_place), coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Admin functions
-- ---------------------------------------------------------------------------
create or replace function public._audit(p_action text, p_table text, p_row text, p_reason text, p_details jsonb)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
  values (auth.uid(), p_action, p_table, p_row, p_reason, coalesce(p_details, '{}'::jsonb))
$$;
revoke all on function public._audit(text, text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.admin_save_campaign(p jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  perform public._require_role('admin');
  if v_id is null then
    insert into public.monthly_campaigns
      (slug, title, subtitle, description, theme_color, banner_mascot, starts_at, ends_at)
    values (p ->> 'slug', p ->> 'title', p ->> 'subtitle', p ->> 'description',
            coalesce(p ->> 'theme_color', '#E85D04'), coalesce(p ->> 'banner_mascot', 'cheer'),
            (p ->> 'starts_at')::timestamptz, (p ->> 'ends_at')::timestamptz)
    returning id into v_id;
  else
    update public.monthly_campaigns set
      title = coalesce(p ->> 'title', title),
      subtitle = case when p ? 'subtitle' then p ->> 'subtitle' else subtitle end,
      description = case when p ? 'description' then p ->> 'description' else description end,
      theme_color = coalesce(p ->> 'theme_color', theme_color),
      banner_mascot = coalesce(p ->> 'banner_mascot', banner_mascot),
      starts_at = coalesce((p ->> 'starts_at')::timestamptz, starts_at),
      ends_at = coalesce((p ->> 'ends_at')::timestamptz, ends_at)
    where id = v_id;
    if not found then raise exception 'no such campaign' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.admin_set_campaign_publish(p_id uuid, p_state text, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  if p_state not in ('draft', 'published') then raise exception 'unknown state' using errcode = '22023'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update public.monthly_campaigns set publish_state = p_state where id = p_id;
  if not found then raise exception 'no such campaign' using errcode = 'P0002'; end if;
  perform public._audit('set_campaign_publish', 'monthly_campaigns', p_id::text, p_reason,
                        jsonb_build_object('state', p_state));
end $$;

-- Create or edit a mission. Editing a mission that already has progress, in a
-- way that changes what counts or what it pays, creates a NEW VERSION instead
-- (the old row is archived and untouched, so earned rewards stay valid).
create or replace function public.admin_save_mission(p jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id   uuid := nullif(p ->> 'id', '')::uuid;
  old    public.missions;
  v_new  uuid;
  v_material boolean;
begin
  perform public._require_role('admin');
  if v_id is null then
    insert into public.missions
      (campaign_id, slug, kind, title, description, category, icon, reward_points, rule_type, rule_params,
       target_count, recurrence, university_id, starts_at, ends_at, action_key, sort_order,
       reward_badge_key, reward_badge_name, reward_badge_mascot, status)
    values (nullif(p ->> 'campaign_id', '')::uuid, p ->> 'slug', p ->> 'kind', p ->> 'title',
            p ->> 'description', p ->> 'category', coalesce(p ->> 'icon', 'star'),
            coalesce((p ->> 'reward_points')::integer, 0), p ->> 'rule_type',
            coalesce(p -> 'rule_params', '{}'::jsonb), (p ->> 'target_count')::integer,
            coalesce(p ->> 'recurrence', 'none'), nullif(p ->> 'university_id', '')::uuid,
            (p ->> 'starts_at')::timestamptz, (p ->> 'ends_at')::timestamptz,
            coalesce(p ->> 'action_key', 'none'), coalesce((p ->> 'sort_order')::integer, 0),
            nullif(p ->> 'reward_badge_key', ''), nullif(p ->> 'reward_badge_name', ''),
            nullif(p ->> 'reward_badge_mascot', ''), coalesce(p ->> 'status', 'draft'))
    returning id into v_id;
    return v_id;
  end if;

  select * into old from public.missions where id = v_id for update;
  if not found then raise exception 'no such mission' using errcode = 'P0002'; end if;
  if old.status = 'archived' then raise exception 'archived missions cannot be edited' using errcode = '55000'; end if;

  v_material :=
       coalesce((p ->> 'target_count')::integer, old.target_count) is distinct from old.target_count
    or coalesce((p ->> 'reward_points')::integer, old.reward_points) is distinct from old.reward_points
    or coalesce(p ->> 'rule_type', old.rule_type) is distinct from old.rule_type
    or coalesce(p -> 'rule_params', old.rule_params) is distinct from old.rule_params
    or coalesce(p ->> 'recurrence', old.recurrence) is distinct from old.recurrence
    or (case when p ? 'university_id' then nullif(p ->> 'university_id', '')::uuid else old.university_id end)
         is distinct from old.university_id
    or (case when p ? 'starts_at' then (p ->> 'starts_at')::timestamptz else old.starts_at end)
         is distinct from old.starts_at
    or (case when p ? 'ends_at' then (p ->> 'ends_at')::timestamptz else old.ends_at end)
         is distinct from old.ends_at;

  if v_material and exists (select 1 from public.user_mission_progress where mission_id = old.id) then
    insert into public.missions
      (lineage_id, version, supersedes_id, campaign_id, slug, kind, title, description, category, icon,
       reward_points, rule_type, rule_params, target_count, recurrence, university_id, starts_at, ends_at,
       action_key, sort_order, reward_badge_key, reward_badge_name, reward_badge_mascot, status)
    values (old.lineage_id, old.version + 1, old.id, old.campaign_id, old.slug, old.kind,
            coalesce(p ->> 'title', old.title),
            case when p ? 'description' then p ->> 'description' else old.description end,
            case when p ? 'category' then p ->> 'category' else old.category end,
            coalesce(p ->> 'icon', old.icon),
            coalesce((p ->> 'reward_points')::integer, old.reward_points),
            coalesce(p ->> 'rule_type', old.rule_type),
            coalesce(p -> 'rule_params', old.rule_params),
            coalesce((p ->> 'target_count')::integer, old.target_count),
            coalesce(p ->> 'recurrence', old.recurrence),
            case when p ? 'university_id' then nullif(p ->> 'university_id', '')::uuid else old.university_id end,
            case when p ? 'starts_at' then (p ->> 'starts_at')::timestamptz else old.starts_at end,
            case when p ? 'ends_at' then (p ->> 'ends_at')::timestamptz else old.ends_at end,
            coalesce(p ->> 'action_key', old.action_key),
            coalesce((p ->> 'sort_order')::integer, old.sort_order),
            case when p ? 'reward_badge_key' then nullif(p ->> 'reward_badge_key', '') else old.reward_badge_key end,
            case when p ? 'reward_badge_name' then nullif(p ->> 'reward_badge_name', '') else old.reward_badge_name end,
            case when p ? 'reward_badge_mascot' then nullif(p ->> 'reward_badge_mascot', '') else old.reward_badge_mascot end,
            coalesce(p ->> 'status', old.status))
    returning id into v_new;
    update public.missions set status = 'archived' where id = old.id;
    perform public._audit('mission_new_version', 'missions', v_new::text, 'versioned edit',
                          jsonb_build_object('previous', old.id, 'version', old.version + 1));
    return v_new;
  end if;

  update public.missions set
    campaign_id = case when p ? 'campaign_id' then nullif(p ->> 'campaign_id', '')::uuid else campaign_id end,
    title = coalesce(p ->> 'title', title),
    description = case when p ? 'description' then p ->> 'description' else description end,
    category = case when p ? 'category' then p ->> 'category' else category end,
    icon = coalesce(p ->> 'icon', icon),
    reward_points = coalesce((p ->> 'reward_points')::integer, reward_points),
    rule_type = coalesce(p ->> 'rule_type', rule_type),
    rule_params = coalesce(p -> 'rule_params', rule_params),
    target_count = coalesce((p ->> 'target_count')::integer, target_count),
    recurrence = coalesce(p ->> 'recurrence', recurrence),
    university_id = case when p ? 'university_id' then nullif(p ->> 'university_id', '')::uuid else university_id end,
    starts_at = case when p ? 'starts_at' then (p ->> 'starts_at')::timestamptz else starts_at end,
    ends_at = case when p ? 'ends_at' then (p ->> 'ends_at')::timestamptz else ends_at end,
    action_key = coalesce(p ->> 'action_key', action_key),
    sort_order = coalesce((p ->> 'sort_order')::integer, sort_order),
    reward_badge_key = case when p ? 'reward_badge_key' then nullif(p ->> 'reward_badge_key', '') else reward_badge_key end,
    reward_badge_name = case when p ? 'reward_badge_name' then nullif(p ->> 'reward_badge_name', '') else reward_badge_name end,
    reward_badge_mascot = case when p ? 'reward_badge_mascot' then nullif(p ->> 'reward_badge_mascot', '') else reward_badge_mascot end,
    status = coalesce(p ->> 'status', status)
  where id = v_id;
  return v_id;
end $$;

create or replace function public.admin_set_mission_status(p_id uuid, p_status text, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  if p_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'unknown status' using errcode = '22023';
  end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update public.missions set status = p_status where id = p_id;
  if not found then raise exception 'no such mission' using errcode = 'P0002'; end if;
  perform public._audit('set_mission_status', 'missions', p_id::text, p_reason,
                        jsonb_build_object('status', p_status));
end $$;

create or replace function public.admin_duplicate_mission(p_id uuid, p_campaign uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  src public.missions;
  v_id uuid;
  v_slug text;
  n integer := 1;
begin
  perform public._require_role('admin');
  select * into src from public.missions where id = p_id;
  if not found then raise exception 'no such mission' using errcode = 'P0002'; end if;
  loop
    v_slug := left(src.slug, 50) || '-copy' || case when n > 1 then n::text else '' end;
    exit when not exists (select 1 from public.missions where slug = v_slug);
    n := n + 1;
  end loop;
  insert into public.missions
    (campaign_id, slug, kind, title, description, category, icon, reward_points, rule_type, rule_params,
     target_count, recurrence, university_id, starts_at, ends_at, action_key, sort_order,
     reward_badge_key, reward_badge_name, reward_badge_mascot, status)
  values (coalesce(p_campaign, src.campaign_id), v_slug, src.kind, src.title, src.description, src.category,
          src.icon, src.reward_points, src.rule_type, src.rule_params, src.target_count, src.recurrence,
          src.university_id, src.starts_at, src.ends_at, src.action_key, src.sort_order,
          null, null, null, 'draft')   -- a badge key is unique per user: never copy it
  returning id into v_id;
  perform public._audit('duplicate_mission', 'missions', v_id::text, null, jsonb_build_object('from', p_id));
  return v_id;
end $$;

-- Approve / reject a user's photo or correction. Approving re-evaluates the
-- contributor so progress and the reward update at once.
create or replace function public.admin_review_contribution(p_id uuid, p_status text, p_note text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid;
begin
  perform public._require_role('moderator');
  if p_status not in ('approved', 'rejected') then raise exception 'unknown status' using errcode = '22023'; end if;
  if p_status = 'rejected' and (p_note is null or btrim(p_note) = '') then
    raise exception 'a note is required to reject' using errcode = '22023';
  end if;
  update public.user_contributions
     set status = p_status, reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_note
   where id = p_id and status = 'pending'
  returning user_id into v_user;
  if v_user is null then raise exception 'no pending contribution' using errcode = 'P0002'; end if;
  perform public._audit('review_contribution', 'user_contributions', p_id::text, p_note,
                        jsonb_build_object('status', p_status));
  if p_status = 'approved' then perform public._evaluate_user(v_user); end if;
end $$;

-- Reverse a reward with a negative ledger row. The original row stays, so the
-- same period can never be paid again.
create or replace function public.admin_revoke_reward(p_tx bigint, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  t public.point_transactions;
begin
  perform public._require_role('admin');
  if p_reason is null or btrim(p_reason) = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into t from public.point_transactions where id = p_tx and kind = 'mission_reward' for update;
  if not found then raise exception 'no such reward' using errcode = 'P0002'; end if;
  if exists (select 1 from public.point_transactions where ref_id = p_tx) then
    raise exception 'already revoked' using errcode = '23505';
  end if;
  insert into public.point_transactions (user_id, points, kind, mission_id, lineage_id, period_key, ref_id, reason, created_by)
  values (t.user_id, -t.points, 'revocation', t.mission_id, t.lineage_id, t.period_key, t.id, p_reason, auth.uid());
  update public.user_mission_progress set revoked_at = now()
   where user_id = t.user_id and lineage_id = t.lineage_id and period_key = t.period_key;
  perform public._audit('revoke_reward', 'point_transactions', p_tx::text, p_reason,
                        jsonb_build_object('user', t.user_id, 'points', t.points));
end $$;

create or replace function public.admin_revoke_badge(p_user uuid, p_badge text, p_reason text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  if p_reason is null or btrim(p_reason) = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update public.user_badges set revoked_at = now()
   where user_id = p_user and badge_key = p_badge and revoked_at is null;
  if not found then raise exception 'no such badge' using errcode = 'P0002'; end if;
  perform public._audit('revoke_badge', 'user_badges', p_user::text || ':' || p_badge, p_reason, '{}'::jsonb);
end $$;

-- One user's mission history, for support and fraud review.
create or replace function public.admin_user_missions(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  return jsonb_build_object(
    'progress', coalesce((select jsonb_agg(jsonb_build_object(
        'mission_id', p.mission_id, 'title', m.title, 'kind', m.kind, 'period_key', p.period_key,
        'progress', p.progress, 'target', p.target, 'completed_at', p.completed_at,
        'revoked_at', p.revoked_at, 'version', m.version) order by p.updated_at desc)
      from public.user_mission_progress p join public.missions m on m.id = p.mission_id
      where p.user_id = p_user), '[]'::jsonb),
    'transactions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'points', t.points, 'kind', t.kind, 'reason', t.reason, 'period_key', t.period_key,
        'ref_id', t.ref_id, 'created_at', t.created_at) order by t.created_at desc)
      from public.point_transactions t where t.user_id = p_user), '[]'::jsonb),
    'badges', coalesce((select jsonb_agg(jsonb_build_object(
        'badge_key', b.badge_key, 'name', b.badge_name, 'awarded_at', b.awarded_at, 'revoked_at', b.revoked_at))
      from public.user_badges b where b.user_id = p_user), '[]'::jsonb),
    'contributions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'kind', c.kind, 'place', c.kakao_place_id, 'status', c.status, 'created_at', c.created_at)
        order by c.created_at desc)
      from public.user_contributions c where c.user_id = p_user), '[]'::jsonb),
    'balance', coalesce((select sum(points) from public.point_transactions where user_id = p_user), 0));
end $$;

-- Accounts whose mission activity looks automated or fraudulent. A lead for a
-- human to look at, not an automatic verdict.
create or replace function public.admin_suspicious_mission_activity(p_hours integer default 24)
returns table (user_id uuid, reason text, detail text, last_seen timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_role('admin');
  return query
    select e.user_id, 'many_events'::text,
           count(*)::text || ' activity events in one hour', max(e.created_at)
      from public.activity_events e
     where e.created_at >= now() - make_interval(hours => greatest(p_hours, 1))
     group by e.user_id, date_trunc('hour', e.created_at)
    having count(*) >= 30
    union all
    select p.user_id, 'rapid_completions'::text,
           count(*)::text || ' missions completed within 10 minutes', max(p.completed_at)
      from public.user_mission_progress p
     where p.completed_at >= now() - make_interval(hours => greatest(p_hours, 1))
     group by p.user_id, floor(extract(epoch from p.completed_at) / 600)
    having count(*) >= 4
    union all
    select c.user_id, 'many_pending'::text,
           count(*)::text || ' contributions waiting for review', max(c.created_at)
      from public.user_contributions c
     where c.status = 'pending'
     group by c.user_id
    having count(*) >= 10;
end $$;

-- Analytics over real data. [p_days] looks back from now.
create or replace function public.admin_mission_stats(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_from timestamptz := now() - make_interval(days => greatest(p_days, 1));
  v_result jsonb;
begin
  perform public._require_role('admin');
  select jsonb_build_object(
    'participants', (select count(distinct user_id) from public.user_mission_progress
                      where updated_at >= v_from and progress > 0),
    'completers', (select count(distinct user_id) from public.user_mission_progress
                    where completed_at >= v_from),
    'completions', (select count(*) from public.user_mission_progress where completed_at >= v_from),
    'points_awarded', coalesce((select sum(points) from public.point_transactions
                                 where kind = 'mission_reward' and created_at >= v_from), 0),
    'points_revoked', coalesce((select -sum(points) from public.point_transactions
                                 where kind = 'revocation' and created_at >= v_from), 0),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'title', m.title, 'kind', m.kind, 'status', m.status, 'version', m.version,
        'participants', s.participants, 'completions', s.completions,
        'points', s.points) order by s.participants desc)
      from public.missions m
      left join lateral (
        select count(distinct p.user_id) filter (where p.progress > 0) as participants,
               count(*) filter (where p.completed_at is not null) as completions,
               coalesce((select sum(t.points) from public.point_transactions t
                          where t.lineage_id = m.lineage_id and t.kind = 'mission_reward'
                            and t.created_at >= v_from), 0) as points
          from public.user_mission_progress p
         where p.lineage_id = m.lineage_id and p.updated_at >= v_from) s on true
      where m.status <> 'draft'), '[]'::jsonb),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', d.day, 'participants', d.participants, 'completions', d.completions)
                       order by d.day)
      from (
        select public.seoul_date(updated_at) as day,
               count(distinct user_id) filter (where progress > 0) as participants,
               count(*) filter (where completed_at is not null and public.seoul_date(completed_at) = public.seoul_date(updated_at)) as completions
          from public.user_mission_progress where updated_at >= v_from group by 1) d), '[]'::jsonb),
    'weekly', coalesce((
      select jsonb_agg(jsonb_build_object('week', w.wk, 'participants', w.participants, 'completions', w.completions)
                       order by w.wk)
      from (
        select to_char(date_trunc('week', (updated_at at time zone 'Asia/Seoul')), 'IYYY-"W"IW') as wk,
               count(distinct user_id) filter (where progress > 0) as participants,
               count(*) filter (where completed_at is not null) as completions
          from public.user_mission_progress where updated_at >= v_from group by 1) w), '[]'::jsonb),
    'by_university', coalesce((
      select jsonb_agg(jsonb_build_object('university', u.name_ko, 'participants', x.participants,
                                          'completions', x.completions) order by x.participants desc)
      from (
        select pr.selected_university_id as uid,
               count(distinct p.user_id) filter (where p.progress > 0) as participants,
               count(*) filter (where p.completed_at is not null) as completions
          from public.user_mission_progress p
          join public.profiles pr on pr.id = p.user_id
         where p.updated_at >= v_from group by 1) x
      join public.universities u on u.id = x.uid), '[]'::jsonb),
    'engagement', jsonb_build_object(
      'mission_users', (select count(distinct user_id) from public.user_mission_progress
                         where updated_at >= v_from and progress > 0),
      'app_active_users', (select count(*) from (
          select user_id from public.favorites where created_at >= v_from
          union select user_id from public.activity_events where created_at >= v_from
          union select user_id from public.student_reviews where created_at >= v_from) a)),
    'pending_contributions', (select count(*) from public.user_contributions where status = 'pending')
  ) into v_result;
  return v_result;
end $$;

-- Function privileges: signed-in users (app) or admins only; never anon.
revoke all on function
  public.sync_my_missions(), public.log_activity(text, text), public.submit_contribution(text, text, jsonb),
  public.admin_save_campaign(jsonb), public.admin_set_campaign_publish(uuid, text, text),
  public.admin_save_mission(jsonb), public.admin_set_mission_status(uuid, text, text),
  public.admin_duplicate_mission(uuid, uuid), public.admin_review_contribution(uuid, text, text),
  public.admin_revoke_reward(bigint, text), public.admin_revoke_badge(uuid, text, text),
  public.admin_user_missions(uuid), public.admin_suspicious_mission_activity(integer),
  public.admin_mission_stats(integer), public.seoul_date(timestamptz),
  public.campaign_state(text, timestamptz, timestamptz)
  from public, anon;
grant execute on function
  public.sync_my_missions(), public.log_activity(text, text), public.submit_contribution(text, text, jsonb),
  public.admin_save_campaign(jsonb), public.admin_set_campaign_publish(uuid, text, text),
  public.admin_save_mission(jsonb), public.admin_set_mission_status(uuid, text, text),
  public.admin_duplicate_mission(uuid, uuid), public.admin_review_contribution(uuid, text, text),
  public.admin_revoke_reward(bigint, text), public.admin_revoke_badge(uuid, text, text),
  public.admin_user_missions(uuid), public.admin_suspicious_mission_activity(integer),
  public.admin_mission_stats(integer), public.seoul_date(timestamptz),
  public.campaign_state(text, timestamptz, timestamptz)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Seed: the 11월 미션 campaign and the missions from the product brief, plus
-- one daily, one weekly and two achievement missions to show the reusable
-- configuration. These are DEFINITIONS only; nobody's progress is seeded.
-- Everything here can be edited from the admin dashboard.
-- ---------------------------------------------------------------------------
insert into public.monthly_campaigns
  (slug, title, subtitle, description, theme_color, banner_mascot, starts_at, ends_at, publish_state)
values ('2026-11', '11월 미션', '가을엔, 맛집 탐험하기 🍁',
        '11월 한 달 동안 캠퍼스 맛집을 탐험하고 포인트와 한정 뱃지를 모아보세요.',
        '#E85D04', 'cheer',
        timestamp '2026-11-01 00:00' at time zone 'Asia/Seoul',
        timestamp '2026-12-01 00:00' at time zone 'Asia/Seoul', 'published')
on conflict (slug) do nothing;

insert into public.missions
  (campaign_id, slug, kind, title, description, category, icon, reward_points, rule_type, rule_params,
   target_count, action_key, sort_order, reward_badge_key, reward_badge_name, reward_badge_mascot, status)
select c.id, v.slug, 'monthly', v.title, v.descr, v.cat, v.icon, v.pts, v.rule, v.params::jsonb,
       v.target, v.action, v.ord, v.badge_key, v.badge_name, v.badge_mascot, 'active'
from public.monthly_campaigns c,
(values
  ('nov-whats-for-lunch', '오늘 뭐 먹지?', '서로 다른 3일 동안 오늘의 추천을 확인해요.', 'explore', 'sparkle', 15,
     'activity_days', '{"event":"recommendation_view"}', 3, 'recommend', 10, null, null, null),
  ('nov-save-places', '맛집 찜하기', '서로 다른 맛집 5곳을 저장해요.', 'save', 'favorite', 20,
     'favorite_distinct', '{}', 5, 'map', 20, null, null, null),
  ('nov-first-review', '첫 리뷰 도전', '식당 리뷰를 1개 남겨요. (10자 이상, 숨김 처리되지 않은 리뷰)', 'review', 'review', 30,
     'review_valid', '{"min_chars":10}', 1, 'review', 30, null, null, null),
  ('nov-menu-photos', '메뉴 사진 수집가', '메뉴 사진 3장이 승인되면 완료돼요.', 'photo', 'photo', 30,
     'contribution_approved', '{"kind":"menu_photo"}', 3, 'photo', 40, null, null, null),
  ('nov-category-explorer', '캠퍼스 맛집 탐험가', '서로 다른 음식 카테고리 4개를 둘러봐요.', 'explore', 'category', 25,
     'activity_refs', '{"event":"category_explore","exclude":["all"]}', 4, 'categories', 50, null, null, null),
  ('nov-value-hunter', '가성비 헌터', '확인된 가격이 10,000원 이하인 맛집 3곳을 저장해요.', 'save', 'value', 20,
     'favorite_cheap', '{"max_price_krw":10000}', 3, 'favorites', 60, null, null, null),
  ('nov-info-solver', '정보 해결사', '메뉴·가격 정보 수정 제안 2건이 관리자 승인을 받으면 완료돼요.', 'info', 'fix', 40,
     'contribution_approved', '{"kind":"info_correction"}', 2, 'correct', 70, null, null, null),
  ('nov-master', '11월 미션 마스터', '이번 달 미션 7개 중 5개를 완료하면 한정 뱃지를 받아요.', 'master', 'trophy', 0,
     'missions_completed', '{}', 5, 'none', 100, 'nov_2026_master', '11월 미션 마스터', 'cheer')
) as v(slug, title, descr, cat, icon, pts, rule, params, target, action, ord, badge_key, badge_name, badge_mascot)
where c.slug = '2026-11'
on conflict (slug, version) do nothing;

insert into public.missions
  (slug, kind, title, description, category, icon, reward_points, rule_type, rule_params,
   target_count, recurrence, action_key, sort_order, status)
values
  ('daily-check-recommendation', 'daily', '오늘의 추천 확인', '오늘의 추천을 한 번 확인해요.', 'explore', 'sparkle', 5,
     'activity_days', '{"event":"recommendation_view"}', 1, 'daily', 'recommend', 10, 'active'),
  ('weekly-save-two', 'weekly', '이번 주 맛집 2곳 찜하기', '이번 주에 새로운 맛집 2곳을 저장해요.', 'save', 'favorite', 10,
     'favorite_distinct', '{}', 2, 'weekly', 'map', 10, 'active'),
  ('ach-first-save', 'achievement', '첫 찜', '처음으로 맛집을 저장해요.', 'save', 'favorite', 10,
     'favorite_distinct', '{}', 1, 'none', 'map', 10, 'active'),
  ('ach-save-20', 'achievement', '찜 수집가', '맛집 20곳을 저장해요.', 'save', 'favorite', 50,
     'favorite_distinct', '{}', 20, 'none', 'map', 20, 'active')
on conflict (slug, version) do nothing;
