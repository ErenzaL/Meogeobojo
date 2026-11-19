-- =============================================================================
-- Collected reviews: Naver, Kakao Map and delivery-app (배달의민족, 쿠팡이츠, 요기요) reviews of a Kakao place, shown
-- read-only on the restaurant page next to the students' own reviews.
--
--   * Rows come from scripts/collected_reviews/build_collected_reviews.py (the review CSV is not in the repository),
--     run in the SQL editor; its first part empties the table, so a re-run replaces the data.
--   * Everyone reads; nobody writes through the API (the import runs as the database owner).
--   * collected_review_stats: count, rated count and rating sum per place and platform, so the app gets the average
--     and the total without downloading every row (PostgREST returns at most 1000 rows).
--
-- Additive and idempotent. To remove: drop view public.collected_review_stats; drop table public.collected_reviews;
-- =============================================================================
create table if not exists public.collected_reviews (
  id             bigint generated always as identity primary key,
  kakao_place_id text not null check (kakao_place_id ~ '^[0-9]{1,20}$'),
  platform       text not null check (platform in ('naver', 'kakao', 'baemin', 'coupangeats', 'yogiyo')),
  rating         numeric(2, 1) check (rating is null or rating between 0.5 and 5),
  body           text check (body is null or char_length(body) between 1 and 4000),
  reviewed_on    date
);
comment on table public.collected_reviews is
  'Naver / Kakao Map / delivery-app reviews per Kakao place, imported offline. See the migration header.';
create index if not exists collected_reviews_place_idx
  on public.collected_reviews (kakao_place_id, reviewed_on desc nulls last);

alter table public.collected_reviews enable row level security;
revoke all on public.collected_reviews from anon, authenticated;
grant select on public.collected_reviews to anon, authenticated;
drop policy if exists "collected_reviews: read" on public.collected_reviews;
create policy "collected_reviews: read" on public.collected_reviews
  for select to anon, authenticated using (true);

create or replace view public.collected_review_stats with (security_invoker = true) as
  select kakao_place_id,
         platform,
         count(*)::integer                       as review_count,
         count(rating)::integer                  as rated_count,
         coalesce(sum(rating), 0)::double precision as rating_sum
    from public.collected_reviews
   group by kakao_place_id, platform;
revoke all on public.collected_review_stats from anon, authenticated;
grant select on public.collected_review_stats to anon, authenticated;
