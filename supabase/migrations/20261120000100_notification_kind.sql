-- =============================================================================
-- Notifications (the bell in the app and on the website): a new `app_content` kind, 'notification'.
--
-- The bell lists what an admin publishes through the EXISTING 앱 콘텐츠 pipeline (admin-only writes, draft -> publish,
-- scheduling, campus targeting, history, audit, live sync), so no new table, policy, function or trigger is needed. The only
-- thing the database must learn is that 'notification' is an allowed kind:
--   * 'notification'  shows in the bell list ONLY (not as a Home banner card);
--   * 'announcement'  keeps showing as a Home card AND now also in the bell list;
--   * 'banner' / 'featured' are unchanged and do not appear in the bell.
--
-- Additive and idempotent: replaces one CHECK constraint with a wider one. Existing rows all satisfy it; no data changes.
-- Until this is applied the Admin can still create 공지 (they appear in the bell too); creating a bell-only 알림 is refused
-- with the constraint error, which the Admin explains. Requires 20261109000100. NOT applied by the repository.
-- =============================================================================
do $$ begin
  if to_regclass('public.app_content') is null then raise exception 'Apply 20261109000100 first.'; end if;
end $$;

alter table public.app_content drop constraint if exists app_content_kind_check;
alter table public.app_content add constraint app_content_kind_check
  check (kind in ('announcement', 'banner', 'featured', 'notification'));
