-- Imported reviews (kakao / naver / delivery-app reviews collected in a CSV) live in the SAME table as the reviews
-- students write in the app: public.student_reviews. The app, the website and the admin page therefore always show the
-- same rows; there is no second review table to keep in sync.
--
-- What changes:
--   * user_id may be NULL: an imported review has no app account behind it.
--   * rating may be NULL: many Naver reviews are text only. A student's own review still needs a rating (see the check).
--   * source ('app' for what students write, otherwise 'kakao' | 'naver' | 'lemong' ...), platform, source_review_id,
--     source_rating (the original, possibly half-star, rating; `rating` is the same value rounded to 1..5, which is what
--     the app and the ranking use) and import_key (makes re-importing the same file a no-op).
--   * public.admin_import_reviews(): the ONLY way imported rows get in (admin role, audited). Students keep the column
--     grants they had, so they can never set source / import_key and can never write a review "as" a source.
--   * admin_mission_stats(): active users no longer count the NULL author of imported reviews as a user.
-- Moderation (hide / remove / show again) works on imported rows exactly as on student reviews, and re-importing never
-- changes a row's moderation state.
-- Safe to run twice.

alter table public.student_reviews
  alter column user_id drop not null,
  alter column rating drop not null,
  add column if not exists source text not null default 'app',
  add column if not exists platform text,
  add column if not exists source_review_id text,
  add column if not exists source_rating numeric(2, 1),
  add column if not exists import_key text;

alter table public.student_reviews drop constraint if exists student_reviews_source_check;
alter table public.student_reviews add constraint student_reviews_source_check
  check (source ~ '^[a-z0-9_]{2,20}$');
alter table public.student_reviews drop constraint if exists student_reviews_source_rating_check;
alter table public.student_reviews add constraint student_reviews_source_rating_check
  check (source_rating is null or (source_rating between 0.5 and 5));
-- a student's review has an author and a rating; an imported one has no author and needs a rating or some text
alter table public.student_reviews drop constraint if exists student_reviews_shape_check;
alter table public.student_reviews add constraint student_reviews_shape_check check (
  case when source = 'app'
       then user_id is not null and rating is not null
       else user_id is null and import_key is not null
            and (rating is not null or nullif(btrim(coalesce(body, '')), '') is not null)
  end);

create unique index if not exists student_reviews_import_key_idx on public.student_reviews (import_key);
create index if not exists student_reviews_source_idx on public.student_reviews (source, created_at desc);

-- ---------------------------------------------------------------------------
-- Import (the browser parses and previews; the server validates and writes)
-- ---------------------------------------------------------------------------
-- p_rows: [{line, kakao_place_id, source, platform, source_review_id, rating, body, reviewed_at}]  (at most 1000 per call)
--   rating       1..5 in half steps, or empty. Stored as the nearest whole star (.5 rounds up) in `rating`; the original stays
--                in `source_rating`.
--   reviewed_at  ISO 8601 with offset (the browser resolves Korean local times); empty = unknown, the import time is used.
-- A row is skipped when it has neither a rating nor text. A review already in the table (same import_key) is left exactly
-- as it is: its text, rating AND moderation state are never overwritten.
-- Returns {total, new, existing, duplicate, empty, failed, undated, errors:[{line, error}] (first 50)}.
create or replace function public.admin_import_reviews(p_rows jsonb, p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  e jsonb; ord int;
  place text; src text; plat text; sid text; txt text; at_raw text; key text; msg text;
  rat numeric; at_ timestamptz;
  seen text[] := '{}';
  c_new int := 0; c_existing int := 0; c_dup int := 0; c_empty int := 0; c_failed int := 0; c_undated int := 0; ins int;
  errs jsonb := '[]'::jsonb;
begin
  perform public._require_role('admin');
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'rows must be an array' using errcode = '22023'; end if;
  if jsonb_array_length(p_rows) = 0 then raise exception 'no rows' using errcode = '22023'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception '한 번에 1000개까지 가져올 수 있어요' using errcode = '22023'; end if;

  for e, ord in select x, o::int from jsonb_array_elements(p_rows) with ordinality as t(x, o) loop
    msg := null; rat := null; at_ := null; key := null;
    begin
      if jsonb_typeof(e) <> 'object' then raise exception '행 형식이 올바르지 않아요'; end if;
      place := btrim(coalesce(e ->> 'kakao_place_id', ''));
      src := lower(btrim(coalesce(e ->> 'source', '')));
      plat := nullif(btrim(coalesce(e ->> 'platform', '')), '');
      sid := nullif(btrim(coalesce(e ->> 'source_review_id', '')), '');
      txt := nullif(btrim(coalesce(e ->> 'body', '')), '');
      at_raw := nullif(btrim(coalesce(e ->> 'reviewed_at', '')), '');

      if place !~ '^[A-Za-z0-9_-]{1,40}$' then raise exception '장소 ID가 올바르지 않아요: %', place; end if;
      if src !~ '^[a-z0-9_]{2,20}$' then raise exception '출처(source)가 올바르지 않아요: %', src; end if;
      if src = 'app' then raise exception '출처 app은 학생이 앱에서 쓴 리뷰 전용이에요'; end if;
      if plat is not null and char_length(plat) > 30 then raise exception '플랫폼 이름이 너무 길어요'; end if;
      if sid is not null and char_length(sid) > 80 then raise exception '출처 리뷰 ID가 너무 길어요'; end if;
      if txt is not null and char_length(txt) > 2000 then raise exception '리뷰 내용은 2000자 이하여야 해요 (% 자)', char_length(txt); end if;

      begin rat := nullif(btrim(coalesce(e ->> 'rating', '')), '')::numeric;
      exception when others then raise exception '별점이 올바르지 않아요: %', e ->> 'rating'; end;
      if rat is not null and (rat < 0.5 or rat > 5 or rat * 2 <> trunc(rat * 2)) then
        raise exception '별점은 0.5 단위로 0.5~5 사이여야 해요: %', rat;
      end if;

      if rat is null and txt is null then
        c_empty := c_empty + 1; continue;   -- nothing to show: skipped, not an error
      end if;

      if at_raw is not null then
        begin at_ := at_raw::timestamptz;
        exception when others then raise exception '날짜가 올바르지 않아요: %', at_raw; end;
        if at_ < timestamptz '2000-01-01' or at_ > now() + interval '1 day' then raise exception '날짜가 범위를 벗어났어요: %', at_raw; end if;
      else
        c_undated := c_undated + 1;
      end if;

      key := case when sid is not null
                  then md5(src || '|' || place || '|' || sid)
                  else md5(src || '|' || coalesce(plat, '') || '|' || place || '|' || coalesce(at_raw, '') || '|' || coalesce(rat::text, '') || '|' || coalesce(txt, '')) end;
      if key = any (seen) then c_dup := c_dup + 1; continue; end if;
      seen := array_append(seen, key);

      if p_dry_run then
        if exists (select 1 from public.student_reviews where import_key = key) then c_existing := c_existing + 1; else c_new := c_new + 1; end if;
      else
        insert into public.student_reviews (user_id, kakao_place_id, university_id, rating, body, created_at,
                                            source, platform, source_review_id, source_rating, import_key)
        values (null, place, null, case when rat is null then null else least(5, greatest(1, round(rat)))::smallint end, txt,
                coalesce(at_, now()), src, plat, sid, rat, key)
        on conflict (import_key) do nothing;
        get diagnostics ins = row_count;
        if ins = 1 then c_new := c_new + 1; else c_existing := c_existing + 1; end if;
      end if;
    exception when others then
      c_failed := c_failed + 1;
      get stacked diagnostics msg = message_text;
      if jsonb_array_length(errs) < 50 then
        errs := errs || jsonb_build_array(jsonb_build_object('line', coalesce((e ->> 'line')::int, ord), 'error', msg));
      end if;
    end;
  end loop;

  if not p_dry_run and c_new > 0 then
    insert into public.audit_log (actor_id, action, table_name, row_id, reason, details)
    values (auth.uid(), 'import_reviews', 'student_reviews', null, 'CSV 가져오기',
            jsonb_build_object('new', c_new, 'existing', c_existing, 'duplicate', c_dup, 'empty', c_empty, 'failed', c_failed));
  end if;
  return jsonb_build_object('total', jsonb_array_length(p_rows), 'new', c_new, 'existing', c_existing, 'duplicate', c_dup,
                            'empty', c_empty, 'failed', c_failed, 'undated', c_undated, 'errors', errs, 'dry_run', p_dry_run);
end $$;
revoke all on function public.admin_import_reviews(jsonb, boolean) from public, anon;
grant execute on function public.admin_import_reviews(jsonb, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_mission_stats: same as 20261110000100, except that reviews without an author are not an "active user".
-- ---------------------------------------------------------------------------
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
          union select user_id from public.student_reviews where created_at >= v_from and user_id is not null) a)),
    'pending_contributions', (select count(*) from public.user_contributions where status = 'pending')
  ) into v_result;
  return v_result;
end $$;
