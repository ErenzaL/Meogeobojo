\set ON_ERROR_STOP on
\pset pager off
-- Collected reviews (migration 20261128000100, applied twice by run_local.sh): the import (as the owner) writes, everyone
-- reads, nobody writes through the API, the checks keep rows in shape, and the stats view gives the totals per platform.

insert into auth.users (id, email) values ('ce000000-0000-4000-8000-0000000000a1', 'cr-user@example.org');

do $$ begin
  insert into public.collected_reviews (kakao_place_id, platform, rating, body, reviewed_on) values
    ('900001', 'naver', null, '양이 많아요', '2026-10-01'),
    ('900001', 'naver', 4.5, null, '2026-09-01'),
    ('900001', 'kakao', 3, '보통', null),
    ('900001', 'baemin', 5, '빨라요', '2026-08-01'),
    ('900002', 'yogiyo', 1, '식었어요', '2026-07-01');
  begin insert into public.collected_reviews (kakao_place_id, platform) values ('900001', 'google'); raise exception 'accepted#platform'; exception when check_violation then null; end;
  begin insert into public.collected_reviews (kakao_place_id, platform, rating) values ('900001', 'naver', 5.5); raise exception 'accepted#rating'; exception when check_violation then null; end;
  begin insert into public.collected_reviews (kakao_place_id, platform, body) values ('900001', 'naver', ''); raise exception 'accepted#empty-body'; exception when check_violation then null; end;
  begin insert into public.collected_reviews (kakao_place_id, platform) values ('x1', 'naver'); raise exception 'accepted#place-id'; exception when check_violation then null; end;
  raise notice 'OK import: writes reviews; platform, rating, empty body and place id are checked';
end $$;

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare s record; begin
  assert (select count(*) from public.collected_reviews where kakao_place_id = '900001') = 4, 'guest reads the reviews';
  select sum(review_count) n, sum(rated_count) rated, sum(rating_sum) total into s
    from public.collected_review_stats where kakao_place_id = '900001';
  assert s.n = 4 and s.rated = 3 and s.total = 12.5, format('stats %s', s);
  assert (select review_count from public.collected_review_stats where kakao_place_id = '900001' and platform = 'naver') = 2,
    'one stats row per platform';
  begin insert into public.collected_reviews (kakao_place_id, platform) values ('900003', 'naver'); raise exception 'accepted#guest-insert'; exception when insufficient_privilege then null; end;
  raise notice 'OK guest: reads reviews and per-platform stats (count, rated count, rating sum), cannot write';
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"ce000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  assert (select count(*) from public.collected_reviews) = 5, 'user reads every review';
  begin insert into public.collected_reviews (kakao_place_id, platform) values ('900003', 'naver'); raise exception 'accepted#user-insert'; exception when insufficient_privilege then null; end;
  begin delete from public.collected_reviews; raise exception 'accepted#user-delete'; exception when insufficient_privilege then null; end;
  raise notice 'OK user: reads, cannot insert or delete';
end $$;
reset role;

delete from public.collected_reviews;
delete from auth.users where id = 'ce000000-0000-4000-8000-0000000000a1';
