-- =============================================================================
-- 문의 및 제안: a signed-in user sends a question, a suggestion or a bug report from the app or the website.
--
-- Stored as a `reports` row of target_type 'feedback' (target_id = the category: question / suggestion / bug,
-- reason = the title, description = the message). The EXISTING 리뷰·신고 admin page lists it and resolves or dismisses it
-- with a note (admin_resolve_report, audit log), and the existing policies already give: sign-in required to send, a user
-- reads only their own, moderators read all. So no new table, policy or function: the database only learns that
-- 'feedback' is an allowed type, and feedback is left out of the one-open-report-per-target index (that rule is for
-- reports about a review, a place or a user; a user may send several suggestions).
--
-- Additive and idempotent. Requires 20261109000100 and 20261114000100. NOT applied by the repository.
-- =============================================================================
do $$ begin
  if to_regclass('public.reports') is null then raise exception 'Apply 20261109000100 first.'; end if;
end $$;

alter table public.reports drop constraint if exists reports_target_type_check;
alter table public.reports add constraint reports_target_type_check
  check (target_type in ('review', 'restaurant', 'user', 'feedback'));

drop index if exists public.reports_one_open_per_user_target;
do $$ begin
  create unique index if not exists reports_one_open_per_user_target
    on public.reports (reporter_id, target_type, target_id) where status = 'open' and target_type <> 'feedback';
exception when unique_violation then
  raise notice 'duplicate open reports exist; the unique index was skipped. Resolve them and run this migration again.';
end $$;
