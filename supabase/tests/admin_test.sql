\set ON_ERROR_STOP on
\pset pager off
-- Admin foundation: roles, RLS, privileged functions, audit log.
-- Every "cannot" below is a NEGATIVE test that must fail with 42501 / 0 rows.

-- Fixtures (run as the superuser, like the SQL editor)
insert into auth.users (id, email) values
  ('a0000000-0000-4000-8000-00000000000a', 'super@example.org'),
  ('b0000000-0000-4000-8000-00000000000b', 'admin@example.org'),
  ('c0000000-0000-4000-8000-00000000000c', 'mod@example.org'),
  ('d0000000-0000-4000-8000-00000000000d', 'user@example.org'),
  ('e0000000-0000-4000-8000-00000000000e', 'user2@example.org');
insert into public.admin_roles (user_id, role) values
  ('a0000000-0000-4000-8000-00000000000a', 'super_admin'),
  ('b0000000-0000-4000-8000-00000000000b', 'admin'),
  ('c0000000-0000-4000-8000-00000000000c', 'moderator');
insert into public.profiles (id) values
  ('a0000000-0000-4000-8000-00000000000a'), ('b0000000-0000-4000-8000-00000000000b'),
  ('c0000000-0000-4000-8000-00000000000c'), ('d0000000-0000-4000-8000-00000000000d'),
  ('e0000000-0000-4000-8000-00000000000e') on conflict do nothing;
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, visibility) values
  ('11111111-0000-4000-8000-000000000001', 'k1', '공개식당', 'published'),
  ('11111111-0000-4000-8000-000000000002', 'k2', '초안식당', 'draft'),
  ('11111111-0000-4000-8000-000000000003', 'k3', '숨김식당', 'hidden');
insert into public.student_reviews (id, user_id, kakao_place_id, rating, body) values
  ('22222222-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-00000000000d', 'k1', 5, 'good'),
  ('22222222-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-00000000000e', 'k1', 1, 'bad');
insert into public.reports (id, reporter_id, target_type, target_id, reason) values
  ('33333333-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-00000000000d', 'review', '22222222-0000-4000-8000-000000000002', 'spam');
insert into public.app_content (id, kind, title, active) values
  ('44444444-0000-4000-8000-000000000001', 'announcement', 'live', true),
  ('44444444-0000-4000-8000-000000000002', 'announcement', 'off', false);
insert into public.campus_cafeterias (id, university_id, kind) values
  ('c1c1c1c1-0000-4000-8000-0000000000f1', '5c0a8f3e-0001-4a6e-9b1d-000000000001', 'student');
delete from public.audit_log;  -- ignore fixture noise

-- ===== anonymous visitors =====
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.restaurant_overrides) = 2, 'anon sees published + hidden, not draft';
  assert (select count(*) from public.student_reviews) = 2, 'anon sees visible reviews';
  assert (select count(*) from public.app_content) = 1, 'anon sees only live content';
  begin perform 1 from public.admin_roles; raise exception 'accepted#1'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.audit_log; raise exception 'accepted#2b'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.reports; raise exception 'accepted#3'; exception when insufficient_privilege then null; end;
  begin insert into public.restaurant_overrides (name_ko) values ('x'); raise exception 'accepted#4'; exception when insufficient_privilege then null; end;
  begin perform public.admin_grant_role('d0000000-0000-4000-8000-00000000000d', 'admin'); raise exception 'accepted#5'; exception when insufficient_privilege then null; end;
  raise notice 'OK anon: reads public data only; no admin tables, no writes, no admin functions';
end $$;
reset role;

-- ===== an ordinary signed-in user =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000d","role":"authenticated"}', false);
do $$ begin
  assert public.current_admin_rank() = 0 and not public.has_role('moderator'), 'user has no role';
  assert (select count(*) from public.admin_roles) = 0, 'user sees no role rows';
  assert (select count(*) from public.audit_log) = 0, 'user sees no audit rows (RLS filters them)';
end $$;
do $$ declare n int; begin
  -- cannot give themselves a role (no insert grant) ...
  begin insert into public.admin_roles (user_id, role) values ('d0000000-0000-4000-8000-00000000000d', 'super_admin'); raise exception 'accepted#7'; exception when insufficient_privilege then null; end;
  begin update public.admin_roles set role = 'super_admin'; raise exception 'accepted#8'; exception when insufficient_privilege then null; end;
  -- ... nor through the function
  begin perform public.admin_grant_role('d0000000-0000-4000-8000-00000000000d', 'super_admin'); raise exception 'accepted#9'; exception when insufficient_privilege then null; end;
  -- cannot write restaurant data, menus, meals, universities, content
  begin insert into public.restaurant_overrides (name_ko, visibility) values ('내식당', 'published'); raise exception 'accepted#10'; exception when insufficient_privilege then null; end;
  update public.restaurant_overrides set name_ko = 'hacked'; get diagnostics n = row_count;
  assert n = 0, 'user update of restaurants touches 0 rows';
  delete from public.restaurant_overrides; get diagnostics n = row_count; assert n = 0, 'user delete touches 0 rows';
  begin insert into public.restaurant_menus (kakao_place_id, name_ko, source) values ('k1', 'x', 'user'); raise exception 'accepted#11'; exception when insufficient_privilege then null; end;
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, verified_at) values ('c1c1c1c1-0000-4000-8000-0000000000f1', '2026-11-09', 'lunch', '[{"name_ko":"x"}]', now()); raise exception 'accepted#12'; exception when insufficient_privilege then null; end;
  update public.universities set is_active = false; get diagnostics n = row_count; assert n = 0, 'user cannot deactivate universities';
  begin insert into public.app_content (kind, title, active) values ('banner', 'x', true); raise exception 'accepted#13'; exception when insufficient_privilege then null; end;
  -- cannot change their own account status or any other profile column
  begin update public.profiles set account_status = 'suspended' where id = 'd0000000-0000-4000-8000-00000000000d'; raise exception 'accepted#14'; exception when insufficient_privilege then null; end;
  begin perform public.admin_set_account_status('e0000000-0000-4000-8000-00000000000e', 'suspended', 'why'); raise exception 'accepted#15'; exception when insufficient_privilege then null; end;
  -- cannot moderate or resolve
  begin perform public.admin_moderate_review('22222222-0000-4000-8000-000000000002', 'hidden', 'x'); raise exception 'accepted#16'; exception when insufficient_privilege then null; end;
  begin perform public.admin_resolve_report('33333333-0000-4000-8000-000000000001', 'resolved', 'x'); raise exception 'accepted#17'; exception when insufficient_privilege then null; end;
  -- cannot edit moderation columns on their own review
  begin update public.student_reviews set moderation_status = 'visible' where user_id = 'd0000000-0000-4000-8000-00000000000d'; raise exception 'accepted#18'; exception when insufficient_privilege then null; end;
  -- reports: can file one, sees only their own
  insert into public.reports (target_type, target_id, reason) values ('restaurant', 'k1', 'wrong info');
  assert (select count(*) from public.reports) = 2, 'user sees own reports only (2 filed by this user)';
  begin insert into public.reports (reporter_id, target_type, target_id, reason) values ('e0000000-0000-4000-8000-00000000000e', 'user', 'x', 'spoof'); raise exception 'accepted#19'; exception when others then null; end;
  -- draft restaurants stay invisible
  assert (select count(*) from public.restaurant_overrides where visibility = 'draft') = 0, 'draft hidden from users';
  raise notice 'OK ordinary user: no roles, no admin writes, no privileged functions, own-row rules hold';
end $$;
reset role;

-- ===== moderator =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-00000000000c","role":"authenticated"}', false);
do $$ declare n int; begin
  assert public.has_role('moderator') and not public.has_role('admin'), 'moderator rank';
  assert (select count(*) from public.reports) = 2, 'moderator reads all reports';
  assert (select count(*) from public.restaurant_overrides) = 3, 'moderator may read drafts';
  begin update public.restaurant_overrides set name_ko = 'x'; get diagnostics n = row_count; assert n = 0; exception when insufficient_privilege then null; end;
  assert (select count(*) from public.audit_log) = 0, 'moderator sees no audit rows';
  begin perform public.admin_moderate_review('22222222-0000-4000-8000-000000000002', 'hidden', ''); raise exception 'accepted#20'; exception when invalid_parameter_value then null; end;  -- reason required
  perform public.admin_moderate_review('22222222-0000-4000-8000-000000000002', 'hidden', 'abusive');
  perform public.admin_resolve_report('33333333-0000-4000-8000-000000000001', 'resolved', 'review hidden');
  begin perform public.admin_resolve_report('33333333-0000-4000-8000-000000000001', 'dismissed', ''); raise exception 'accepted#21'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_set_account_status('e0000000-0000-4000-8000-00000000000e', 'suspended', 'x'); raise exception 'accepted#22'; exception when insufficient_privilege then null; end;
  raise notice 'OK moderator: moderates reviews and reports with reasons; cannot edit data, suspend users or read the audit log';
end $$;
reset role;
do $$ begin
  assert (select moderation_status from public.student_reviews where id = '22222222-0000-4000-8000-000000000002') = 'hidden', 'review hidden';
  assert (select status from public.reports where id = '33333333-0000-4000-8000-000000000001') = 'resolved', 'report resolved';
  assert (select count(*) from public.audit_log where action in ('moderate_review','resolve_report') and reason is not null) = 2, 'moderation audited with reasons';
end $$;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin assert (select count(*) from public.student_reviews) = 1, 'hidden review disappears from the public'; raise notice 'OK hidden reviews are no longer public'; end $$;
reset role;

-- ===== admin =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"b0000000-0000-4000-8000-00000000000b","role":"authenticated"}', false);
do $$ declare n int; begin
  assert public.has_role('admin') and not public.has_role('super_admin'), 'admin rank';
  update public.restaurant_overrides set description = '새 설명', visibility = 'published' where kakao_place_id = 'k2';
  assert (select description from public.restaurant_overrides where kakao_place_id = 'k2') = '새 설명', 'admin edits restaurants';
  insert into public.restaurant_overrides (name_ko, visibility) values ('수제식당', 'published');   -- hand-made, no kakao id
  begin insert into public.restaurant_overrides (kakao_place_id, name_ko) values ('k1', 'dup'); raise exception 'accepted#23'; exception when unique_violation then null; end;
  insert into public.restaurant_university_links values ('11111111-0000-4000-8000-000000000001', '5c0a8f3e-0001-4a6e-9b1d-000000000001');
  insert into public.restaurant_menus (restaurant_id, name_ko, price_krw, source, representative, sort_order)
    values ('11111111-0000-4000-8000-000000000001', '비빔밥', 9000, 'admin', true, 1);
  insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, price_krw, badge, verified_at)
    values ('c1c1c1c1-0000-4000-8000-0000000000f1', '2026-11-10', 'breakfast', '[{"name_ko":"북엇국","kind":"main"}]', 1000, '천원의 아침밥', now());
  update public.universities set search_radius_m = 2000, is_active = true where id = '5c0a8f3e-0001-4a6e-9b1d-000000000001';
  begin update public.universities set search_radius_m = 10; raise exception 'accepted#24'; exception when check_violation then null; end;
  insert into public.app_content (kind, title, active) values ('banner', '새 배너', true);
  assert (select count(*) from public.audit_log) >= 6, 'admin changes are audited';
  -- cannot delete restaurants / universities, cannot manage roles
  delete from public.restaurant_overrides where kakao_place_id = 'k1'; get diagnostics n = row_count; assert n = 0, 'admin cannot delete restaurants (archive instead)';
  begin perform public.admin_grant_role('d0000000-0000-4000-8000-00000000000d', 'moderator'); raise exception 'accepted#25'; exception when insufficient_privilege then null; end;
  -- suspend an ordinary user, but not other staff
  perform public.admin_set_account_status('e0000000-0000-4000-8000-00000000000e', 'suspended', 'spam');
  begin perform public.admin_set_account_status('c0000000-0000-4000-8000-00000000000c', 'suspended', 'x'); raise exception 'accepted#26'; exception when insufficient_privilege then null; end;
  begin perform public.admin_set_account_status('e0000000-0000-4000-8000-00000000000e', 'suspended', ''); raise exception 'accepted#27'; exception when invalid_parameter_value then null; end;
  assert (select count(*) from public.profiles) >= 5, 'admin can list all profiles (5 fixtures)';
  assert (select count(*) from public.profiles where id in ('a0000000-0000-4000-8000-00000000000a','e0000000-0000-4000-8000-00000000000e')) = 2, 'including other users';
  raise notice 'OK admin: edits restaurants/menus/meals/universities/content; audited; cannot delete, grant roles or touch staff accounts';
end $$;
reset role;
do $$ begin
  assert (select account_status from public.profiles where id = 'e0000000-0000-4000-8000-00000000000e') = 'suspended', 'status applied';
  assert (select count(*) from public.audit_log where actor_id = 'b0000000-0000-4000-8000-00000000000b' and action = 'set_account_status') = 1, 'suspension audited';
  assert (select count(*) from public.audit_log where actor_id = 'b0000000-0000-4000-8000-00000000000b' and table_name = 'restaurant_overrides') >= 2, 'actor recorded by the trigger';
end $$;

-- ===== super admin =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-4000-8000-00000000000a","role":"authenticated"}', false);
do $$ declare n int; begin
  perform public.admin_grant_role('d0000000-0000-4000-8000-00000000000d', 'moderator');
  assert (select role from public.admin_roles where user_id = 'd0000000-0000-4000-8000-00000000000d') = 'moderator', 'granted';
  begin perform public.admin_grant_role('d0000000-0000-4000-8000-00000000000d', 'owner'); raise exception 'accepted#28'; exception when invalid_parameter_value then null; end;
  perform public.admin_revoke_role('d0000000-0000-4000-8000-00000000000d');
  begin perform public.admin_revoke_role('a0000000-0000-4000-8000-00000000000a'); raise exception 'accepted#29'; exception when check_violation then null; end;  -- last super_admin
  perform public.admin_set_account_status('c0000000-0000-4000-8000-00000000000c', 'active', 'restore');  -- may act on staff
  delete from public.restaurant_overrides where kakao_place_id = 'k3'; get diagnostics n = row_count; assert n = 1, 'super admin can delete';
  assert (select count(*) from public.admin_roles) = 3, 'super admin sees all roles';
  raise notice 'OK super admin: grants and revokes roles, keeps the last super_admin, may delete and act on staff';
end $$;
reset role;

-- ===== referential integrity =====
do $$ declare u uuid := gen_random_uuid(); begin
  insert into public.universities (id, name_ko) values (u, '테스트대');
  insert into public.restaurant_university_links values ('11111111-0000-4000-8000-000000000001', u);
  delete from public.universities where id = u;
  assert (select count(*) from public.restaurant_university_links where university_id = u) = 0, 'links removed with the university';
  assert exists (select 1 from public.restaurant_overrides where id = '11111111-0000-4000-8000-000000000001'), 'restaurant kept';
  begin insert into public.restaurant_menus (name_ko, source) values ('orphan', 'x'); raise exception 'accepted#30'; exception when check_violation then null; end;
  raise notice 'OK integrity: deleting a university never deletes restaurants; menus need an owner';
end $$;

-- ===== recommendation telemetry =====
insert into public.recommendation_requests (model_version, is_mock, status, latency_ms) values
  ('mock-0', true, 'ok', 100), ('mock-0', true, 'ok', 200), ('mock-0', true, 'error', null);
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000d","role":"authenticated"}', false);
do $$ begin
  assert (select count(*) from public.recommendation_requests) = 0, 'ordinary user reads no telemetry';
  begin insert into public.recommendation_requests (model_version, status) values ('x', 'ok'); raise exception 'accepted#T1'; exception when insufficient_privilege then null; end;
  begin perform * from public.admin_recommendation_stats(7); raise exception 'accepted#T2'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"b0000000-0000-4000-8000-00000000000b","role":"authenticated"}', false);
do $$ declare s record; begin
  begin insert into public.recommendation_requests (model_version, status) values ('x', 'ok'); raise exception 'accepted#T3'; exception when insufficient_privilege then null; end;  -- even admins cannot fabricate rows
  select * into s from public.admin_recommendation_stats(7);
  assert s.total = 3 and s.errors = 1 and s.mock_requests = 3, 'counts';
  assert s.avg_latency_ms = 150.0, 'average latency over ok requests only';
  assert s.latest_model_version = 'mock-0' and s.latest_is_mock, 'mock is labelled as a mock';
  raise notice 'OK recommendation telemetry: server-written only, admin-readable aggregates, mock flagged';
end $$;
reset role;
