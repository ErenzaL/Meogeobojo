\set ON_ERROR_STOP on
\pset pager off
-- Imported reviews (migration 20261128000100, applied twice by run_local.sh): the same student_reviews table, no author,
-- written only through admin_import_reviews(). Proves the permissions, that re-importing is a no-op that keeps moderation,
-- that students' own reviews are unchanged, and that the app_active_users analytic ignores authorless rows.

insert into auth.users (id, email) values
  ('5e1e0000-0000-4000-8000-0000000000a1', 'ri-student@example.org'),
  ('5e1e0000-0000-4000-8000-0000000000b1', 'ri-admin@example.org'),
  ('5e1e0000-0000-4000-8000-0000000000c1', 'ri-mod@example.org');
insert into public.admin_roles (user_id, role) values
  ('5e1e0000-0000-4000-8000-0000000000b1', 'admin'),
  ('5e1e0000-0000-4000-8000-0000000000c1', 'moderator');

-- a student writes a review the normal way
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"5e1e0000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  insert into public.student_reviews (kakao_place_id, rating, body) values ('P1', 4, '학생 리뷰');
  assert (select source from public.student_reviews where kakao_place_id = 'P1') = 'app', 'a student review is source app';
  assert (select user_id from public.student_reviews where kakao_place_id = 'P1') = '5e1e0000-0000-4000-8000-0000000000a1', 'with its author';
  begin insert into public.student_reviews (kakao_place_id, rating, body, source) values ('P1b', 3, 'x', 'naver'); raise exception 'accepted#source';
  exception when insufficient_privilege then null; end;
  begin insert into public.student_reviews (kakao_place_id, rating, body, import_key) values ('P1c', 3, 'x', 'k'); raise exception 'accepted#key';
  exception when insufficient_privilege then null; end;
  begin insert into public.student_reviews (kakao_place_id, rating, body) values ('P1d', null, 'no stars'); raise exception 'accepted#norating';
  exception when check_violation then null; end;
  begin perform public.admin_import_reviews('[{"kakao_place_id":"P1","source":"naver","rating":5}]'::jsonb, true); raise exception 'accepted#rpc';
  exception when insufficient_privilege then null; end;
  raise notice 'OK student: writes as before; cannot set source / import_key, cannot skip the rating, cannot import';
end $$;
reset role;

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin perform public.admin_import_reviews('[{"kakao_place_id":"P1","source":"naver","rating":5}]'::jsonb, true); raise exception 'accepted#anon';
  exception when insufficient_privilege then null; end;
  raise notice 'OK guest: cannot import';
end $$;
reset role;

-- a moderator is not enough
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"5e1e0000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ begin
  begin perform public.admin_import_reviews('[{"kakao_place_id":"P1","source":"naver","rating":5}]'::jsonb, true); raise exception 'accepted#mod';
  exception when insufficient_privilege then null; end;
  raise notice 'OK moderator: cannot import (admin only)';
end $$;
reset role;

-- the admin
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"5e1e0000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$
declare r jsonb; rows_ jsonb := '[
  {"line":2,"kakao_place_id":"P1","source":"kakao","source_review_id":"900","rating":"1","body":"불친절","reviewed_at":"2026-06-13T14:15:00+09:00"},
  {"line":3,"kakao_place_id":"P1","source":"naver","rating":"4.5","body":"좋아요","reviewed_at":"2025-12-08T00:00:00+09:00"},
  {"line":4,"kakao_place_id":"P1","source":"naver","rating":"","body":"별점 없는 글","reviewed_at":""},
  {"line":5,"kakao_place_id":"P1","source":"naver","rating":"3.5","body":"","reviewed_at":"2026-01-02T00:00:00+09:00"},
  {"line":6,"kakao_place_id":"P1","source":"naver","rating":"","body":"","reviewed_at":""},
  {"line":7,"kakao_place_id":"P1","source":"kakao","source_review_id":"900","rating":"1","body":"불친절","reviewed_at":"2026-06-13T14:15:00+09:00"},
  {"line":8,"kakao_place_id":"P1","source":"naver","rating":"7","body":"x"},
  {"line":9,"kakao_place_id":"P1","source":"app","rating":"5","body":"x"},
  {"line":10,"kakao_place_id":"bad id!","source":"naver","rating":"5"},
  {"line":11,"kakao_place_id":"P2","source":"lemong","platform":"BAEMIN","rating":"5","body":"배달 맛있어요","reviewed_at":"2026-07-05T12:27:00+09:00"}]'::jsonb;
begin
  r := public.admin_import_reviews(rows_, true);
  assert (r ->> 'dry_run')::boolean and (r ->> 'new')::int = 5 and (r ->> 'duplicate')::int = 1 and (r ->> 'empty')::int = 1 and (r ->> 'failed')::int = 3, 'dry run: ' || r::text;
  assert (select count(*) from public.student_reviews where source <> 'app') = 0, 'a dry run writes nothing';
  r := public.admin_import_reviews(rows_, false);
  assert (r ->> 'new')::int = 5 and (r ->> 'failed')::int = 3 and (r ->> 'undated')::int = 1, 'real run: ' || r::text;
  assert (r -> 'errors' -> 0 ->> 'line')::int = 8, 'the error names the file line';
  assert (select count(*) from public.student_reviews where source <> 'app') = 5, 'five imported rows';
  assert (select rating from public.student_reviews where body = '좋아요') = 5 and (select source_rating from public.student_reviews where body = '좋아요') = 4.5, '4.5 stars: rounded up for the app, original kept';
  assert (select rating from public.student_reviews where body is null and source = 'naver') = 4, '3.5 stars star-only row rounds to 4';
  assert (select rating is null and user_id is null from public.student_reviews where body = '별점 없는 글'), 'a text-only review has no rating and no author';
  assert (select created_at from public.student_reviews where source_review_id = '900') = timestamptz '2026-06-13T14:15:00+09:00', 'created_at is the review date';
  assert (select platform from public.student_reviews where source = 'lemong') = 'BAEMIN', 'platform kept';
  assert (select count(*) from public.audit_log where action = 'import_reviews') = 1, 'audited once (the dry run is not)';
  raise notice 'OK admin: dry run writes nothing; import counts, rounding, text-only rows, dates, errors by line, audit';
end $$;

-- hide one imported review, then import the same file again
do $$
declare v uuid; r jsonb;
begin
  select id into v from public.student_reviews where body = '좋아요';
  perform public.admin_moderate_review(v, 'hidden', '테스트');
  r := public.admin_import_reviews('[
    {"line":3,"kakao_place_id":"P1","source":"naver","rating":"4.5","body":"좋아요","reviewed_at":"2025-12-08T00:00:00+09:00"},
    {"line":4,"kakao_place_id":"P1","source":"naver","rating":"","body":"별점 없는 글","reviewed_at":""},
    {"line":12,"kakao_place_id":"P1","source":"kakao","source_review_id":"901","rating":"5","body":"새 글","reviewed_at":"2026-06-14T10:00:00+09:00"}]'::jsonb, false);
  assert (r ->> 'new')::int = 1 and (r ->> 'existing')::int = 2, 're-import: ' || r::text;
  assert (select moderation_status from public.student_reviews where id = v) = 'hidden', 're-importing keeps a hidden review hidden';
  assert (select count(*) from public.student_reviews where source <> 'app') = 6, 'no duplicates';
  raise notice 'OK re-import: identical rows are "existing", moderation untouched, only the new row is added';
end $$;
reset role;

-- what the public sees: visible imported reviews, not the hidden one
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.student_reviews where kakao_place_id = 'P1') = 5, 'guest sees 4 imported + 1 student review of P1 (one hidden)';
  assert not exists (select 1 from public.student_reviews where body = '좋아요'), 'hidden imported review is not public';
  raise notice 'OK public: imported reviews are read like any review; a hidden one is not';
end $$;
reset role;

-- the active-user analytic does not count authorless rows as a user (expected value computed with full access)
select set_config('t.active', (select count(*) from (select user_id from public.favorites union select user_id from public.activity_events
                                                    union select user_id from public.student_reviews) a where user_id is not null)::text, false);
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"5e1e0000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  assert (public.admin_mission_stats(36500) -> 'engagement' ->> 'app_active_users')::int = current_setting('t.active')::int, 'authorless reviews are not an active user';
  raise notice 'OK analytics: imported reviews are not counted as an active user';
end $$;
