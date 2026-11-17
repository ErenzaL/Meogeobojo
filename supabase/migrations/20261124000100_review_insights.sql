-- =============================================================================
-- Review insights: the review signal R of the V3 ranking and an AI-written review summary, per Kakao place.
--
-- Rows are produced offline by scripts/review_insights/build_review_insights.py from the provided delivery/Naver
-- reviews (matched by shop name + address) and the app's own student reviews, then run in the SQL editor. The app:
--   * uses review_signal as R for places without visible student reviews (student reviews keep priority);
--   * shows summary_ko / highlights as "AI 리뷰 요약" on the top pick and the detail screen, with the review count.
-- Hiding a summary: update ... set visible = false (admins only). Nothing else is read or written.
--
-- Additive and idempotent. Requires 20261109000100 (has_role). NOT applied by the repository.
-- =============================================================================
do $$ begin
  if to_regprocedure('public.has_role(text)') is null then
    raise exception 'Apply 20261109000100_admin_foundation.sql first.';
  end if;
end $$;

create table if not exists public.restaurant_review_insights (
  kakao_place_id text primary key check (kakao_place_id ~ '^[0-9]{1,20}$'),
  review_count   integer not null check (review_count > 0),
  avg_rating     numeric(3, 2) check (avg_rating is null or avg_rating between 1 and 5),
  review_signal  double precision not null default 0 check (review_signal between -1 and 1),
  summary_ko     text check (summary_ko is null or char_length(summary_ko) between 1 and 400),
  highlights     text[] not null default '{}' check (cardinality(highlights) <= 3),
  source         text not null check (source in ('provided_reviews', 'student_reviews', 'provided_and_student')),
  model          text check (model is null or char_length(model) <= 120),
  period_from    date,
  period_to      date,
  visible        boolean not null default true,
  generated_at   timestamptz not null default now()
);
comment on table public.restaurant_review_insights is
  'Per-place review signal (R) and AI review summary, generated offline from collected reviews. See the migration header.';

alter table public.restaurant_review_insights enable row level security;
revoke all on public.restaurant_review_insights from anon, authenticated;
grant select on public.restaurant_review_insights to anon, authenticated;
grant insert, update, delete on public.restaurant_review_insights to authenticated;

drop policy if exists "restaurant_review_insights: read visible" on public.restaurant_review_insights;
create policy "restaurant_review_insights: read visible" on public.restaurant_review_insights
  for select to anon, authenticated using (visible);
drop policy if exists "restaurant_review_insights: moderators read hidden" on public.restaurant_review_insights;
create policy "restaurant_review_insights: moderators read hidden" on public.restaurant_review_insights
  for select to authenticated using ((select public.has_role('moderator')));
drop policy if exists "restaurant_review_insights: admin write" on public.restaurant_review_insights;
create policy "restaurant_review_insights: admin write" on public.restaurant_review_insights
  for all to authenticated using ((select public.has_role('admin'))) with check ((select public.has_role('admin')));
