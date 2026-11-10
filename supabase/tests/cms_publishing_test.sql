\set ON_ERROR_STOP on
\pset pager off
-- Publishing: draft separate from live, optimistic concurrency, immediate and
-- scheduled publish, atomic failure, cancel, retry, unpublish, rollback,
-- immutability and authorization. Every "cannot" is a NEGATIVE test.

insert into auth.users (id, email) values
  ('f4000000-0000-4000-8000-0000000000a1', 'cms-a1@example.org'),
  ('f4000000-0000-4000-8000-0000000000a2', 'cms-a2@example.org'),
  ('f4000000-0000-4000-8000-0000000000b1', 'cms-mod@example.org'),
  ('f4000000-0000-4000-8000-0000000000c1', 'cms-user@example.org');
insert into public.admin_roles (user_id, role) values
  ('f4000000-0000-4000-8000-0000000000a1', 'admin'),
  ('f4000000-0000-4000-8000-0000000000a2', 'admin'),
  ('f4000000-0000-4000-8000-0000000000b1', 'moderator');
insert into public.restaurant_overrides (id, kakao_place_id, name_ko, description, visibility, price_min_krw) values
  ('e4000000-0000-4000-8000-000000000001', 'cms-1', '원래 이름', '원래 설명', 'published', 7000),
  ('e4000000-0000-4000-8000-000000000002', 'cms-2', '두번째 식당', null, 'published', null);
insert into public.restaurant_university_links values ('e4000000-0000-4000-8000-000000000001', '5c0a8f3e-0001-4a6e-9b1d-000000000001');

-- ===== A: a draft never touches live; concurrency; validation; the guard =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; d jsonb; s jsonb; v int; begin
  s := public.cms_state('restaurant', r);
  assert (s ->> 'live_version')::int = 0 and s -> 'draft' = 'null'::jsonb, 'nothing published yet, no draft';
  assert s -> 'live' ->> 'name_ko' = '원래 이름' and (s -> 'live' -> 'university_ids') = '["5c0a8f3e-0001-4a6e-9b1d-000000000001"]'::jsonb, 'live snapshot, with its campus links';

  d := jsonb_set(jsonb_set(jsonb_set(s -> 'live', '{name_ko}', '"새 이름"'), '{description}', '"새 설명"'), '{price_min_krw}', '9000');
  s := public.cms_save_draft('restaurant', r, d, 0);
  assert (s ->> 'revision')::int = 1 and (s ->> 'base_version')::int = 0, 'first save is revision 1';
  assert (select name_ko from public.restaurant_overrides where id = r) = '원래 이름', 'A: the LIVE row is untouched by a draft';
  assert (select description from public.restaurant_overrides where id = r) = '원래 설명', 'A: live description untouched';
  s := public.cms_state('restaurant', r);
  assert (s -> 'draft' ->> 'has_changes')::boolean and not (s -> 'draft' ->> 'stale')::boolean, 'pending changes are reported';
  assert s -> 'draft' -> 'data' ->> 'name_ko' = '새 이름', 'the draft holds the new content';

  -- optimistic concurrency
  s := public.cms_save_draft('restaurant', r, d, 1);
  assert (s ->> 'revision')::int = 2, 'a save with the current revision bumps it';
  begin perform public.cms_save_draft('restaurant', r, d, 1); raise exception 'accepted#1'; exception when serialization_failure then null; end;
  begin perform public.cms_save_draft('restaurant', r, d, 0); raise exception 'accepted#2'; exception when serialization_failure then null; end;

  -- validation (nothing is stored when it fails)
  begin perform public.cms_save_draft('restaurant', r, jsonb_set(d, '{name_ko}', '" "'), 2); raise exception 'accepted#3'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant', r, d || '{"kakao_place_id":"hack"}', 2); raise exception 'accepted#4'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant', r, jsonb_set(jsonb_set(d, '{price_min_krw}', '9000'), '{price_max_krw}', '5000'), 2); raise exception 'accepted#5'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant', r, jsonb_set(d, '{visibility}', '"live"'), 2); raise exception 'accepted#6'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant', r, jsonb_set(d, '{last_order_time}', '"25:99"'), 2); raise exception 'accepted#7'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('nothing', r, d, 0); raise exception 'accepted#8'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant', '00000000-0000-4000-8000-000000000000', d, 0); raise exception 'accepted#9'; exception when no_data_found then null; end;
  assert (public.cms_state('restaurant', r) -> 'draft' ->> 'revision')::int = 2, 'refused saves changed nothing';

  -- the guard: live content cannot be edited through the API, photos can still mirror
  begin update public.restaurant_overrides set name_ko = '직접' where id = r; raise exception 'accepted#10'; exception when insufficient_privilege then null; end;
  begin update public.restaurant_overrides set visibility = 'hidden' where id = r; raise exception 'accepted#11'; exception when insufficient_privilege then null; end;
  begin insert into public.restaurant_overrides (name_ko, visibility) values ('바로 공개', 'published'); raise exception 'accepted#12'; exception when insufficient_privilege then null; end;
  insert into public.restaurant_overrides (id, name_ko, visibility) values ('e4000000-0000-4000-8000-0000000000d1', '초안 식당', 'draft');
  update public.restaurant_overrides set image_url = 'https://example.org/i.jpg' where id = r;
  raise notice 'OK cms A: a draft never changes live; stale saves and bad content refused; live edits blocked at the database';
end $$;

-- a second admin cannot overwrite or publish over the first admin's draft
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a2","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; begin
  begin perform public.cms_save_draft('restaurant', r, public.cms_state('restaurant', r) -> 'live', 0); raise exception 'accepted#13'; exception when serialization_failure then null; end;
  begin perform public.cms_publish('restaurant', r, 1, 'x'); raise exception 'accepted#14'; exception when serialization_failure then null; end;
  begin perform public.cms_discard_draft('restaurant', r, 1); raise exception 'accepted#15'; exception when serialization_failure then null; end;
  assert (public.cms_state('restaurant', r) -> 'draft' ->> 'revision')::int = 2, 'the other admin''s draft is intact';
  raise notice 'OK cms conflicts: a second admin is told, and nothing is overwritten';
end $$;

-- ===== B: publish now =====
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; v int; vr public.content_versions; begin
  begin perform public.cms_publish('restaurant', r, 1, 'stale'); raise exception 'accepted#16'; exception when serialization_failure then null; end;
  v := public.cms_publish('restaurant', r, 2, '메뉴판 반영');
  assert v = 1, 'the first publish is version 1';
  assert (select name_ko from public.restaurant_overrides where id = r) = '새 이름', 'B: the live row now has the new name';
  assert (select description from public.restaurant_overrides where id = r) = '새 설명' and (select price_min_krw from public.restaurant_overrides where id = r) = 9000, 'B: all draft fields are live';
  assert not exists (select 1 from public.content_drafts where entity_id = r), 'the draft is consumed';
  select * into vr from public.content_versions where entity_id = r and version = 1;
  assert vr.kind = 'publish' and vr.reason = '메뉴판 반영' and vr.published_by = 'f4000000-0000-4000-8000-0000000000a1' and vr.data ->> 'name_ko' = '새 이름', 'the version records what is live, who and why';
  assert exists (select 1 from public.audit_log where action = 'cms_publish' and row_id = r::text and actor_id = 'f4000000-0000-4000-8000-0000000000a1'), 'publishing is audited';
  begin perform public.cms_publish('restaurant', r, 0, 'again'); raise exception 'accepted#17'; exception when no_data_found then null; end;
  assert (public.cms_state('restaurant', r) ->> 'live_version')::int = 1, 'state reports the live version';
  raise notice 'OK cms B: publish applies the draft atomically as version 1, audited';
end $$;

-- ===== C/H: scheduling, frozen snapshot, the server-side runner =====
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; d jsonb; j bigint; rev int; begin
  d := jsonb_set(public.cms_state('restaurant', r) -> 'live', '{name_ko}', '"예약된 이름"');
  perform public.cms_save_draft('restaurant', r, d, 0);
  begin perform public.cms_schedule('restaurant', r, 1, now() - interval '5 minutes'); raise exception 'accepted#18'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_schedule('restaurant', r, 1, now() + interval '2 days', now() + interval '1 day'); raise exception 'accepted#19'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_schedule('restaurant', r, 9, now() + interval '2 days'); raise exception 'accepted#20'; exception when serialization_failure then null; end;
  j := public.cms_schedule('restaurant', r, 1, now() + interval '2 days', now() + interval '3 days', '아침 7시 메뉴');
  perform set_config('test.job', j::text, false);
  assert (select count(*) from public.publication_jobs where entity_id = r and status = 'scheduled') = 2, 'a publish job and its end job are scheduled';
  assert (select name_ko from public.restaurant_overrides where id = r) = '새 이름', 'scheduling changes nothing yet';
  begin perform public.cms_schedule('restaurant', r, 1, now() + interval '4 days'); raise exception 'accepted#21'; exception when object_in_use then null; end;
  begin perform public.cms_publish('restaurant', r, 1, 'now'); raise exception 'accepted#22'; exception when object_in_use then null; end;
  -- later edits never alter the scheduled snapshot
  perform public.cms_save_draft('restaurant', r, jsonb_set(d, '{name_ko}', '"나중에 고친 이름"'), 1);
  assert (select snapshot ->> 'name_ko' from public.publication_jobs where id = j) = '예약된 이름', 'the scheduled snapshot is frozen';
  raise notice 'OK cms scheduling: validated, one schedule per entity, snapshot frozen against later edits';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_run_due_jobs(); raise exception 'accepted#23'; exception when insufficient_privilege then null; end;
  raise notice 'OK cms runner: not callable through the API';
end $$;
reset role;
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; res jsonb; j bigint := current_setting('test.job')::bigint; begin
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 0 and (select name_ko from public.restaurant_overrides where id = r) = '새 이름', 'before the time, nothing runs';
  -- time passes (the publish moment is now in the past; the end stays in the future)
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = j;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1 and (res ->> 'failed')::int = 0, 'the due job runs: ' || res::text;
  assert (select name_ko from public.restaurant_overrides where id = r) = '예약된 이름', 'C: the scheduled snapshot (not the later edit) went live';
  assert (select status from public.publication_jobs where id = j) = 'published' and (select published_version from public.publication_jobs where id = j) = 2, 'the job records the version';
  assert (select executed_at from public.publication_jobs where id = j) is not null, 'the actual publication time is recorded';
  assert (select count(*) from public.content_versions where entity_id = r) = 2, 'one new version';
  assert (select published_by from public.content_versions where entity_id = r and version = 2) = 'f4000000-0000-4000-8000-0000000000a1', 'the publisher is the person who scheduled it';
  -- the later edit survives, restarted from the new live version
  assert (select data ->> 'name_ko' from public.content_drafts where entity_id = r) = '나중에 고친 이름' and (select base_version from public.content_drafts where entity_id = r) = 2, 'later edits are kept and rebased';
  -- H: running again (a retry, a second runner) publishes nothing twice
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 0 and (select count(*) from public.content_versions where entity_id = r) = 2, 'H: a second run is a no-op';
  raise notice 'OK cms C/H: the runner publishes the frozen snapshot once, records it, and is idempotent';
end $$;

-- the end-time job unpublishes later (non-destructively)
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; res jsonb; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where entity_id = r and action = 'unpublish' and status = 'scheduled';
  -- (its parent window check is on the publish row; the end job may be moved freely)
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'the end job ran: ' || res::text;
  assert (select visibility from public.restaurant_overrides where id = r) = 'hidden', 'the restaurant is hidden, not deleted';
  assert (select name_ko from public.restaurant_overrides where id = r) = '예약된 이름', 'its content is intact';
  assert (select kind from public.content_versions where entity_id = r and version = 3) = 'unpublish', 'recorded as an unpublish version';
  raise notice 'OK cms: automatic end hides the restaurant without deleting anything';
end $$;

-- ===== failure atomicity, permissions at run time, conflicts, retry =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; d jsonb; j bigint; begin
  d := jsonb_set(public.cms_state('restaurant', r) -> 'live', '{description}', '"예약 설명"');
  perform public.cms_save_draft('restaurant', r, d, 0);
  j := public.cms_schedule('restaurant', r, 1, now() + interval '1 day', null, '실패 시험');
  perform set_config('test.job2', j::text, false);
end $$;
reset role;
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; j bigint := current_setting('test.job2')::bigint; res jsonb; begin
  -- corrupt the frozen snapshot: validation must stop it, leaving live untouched
  update public.publication_jobs set snapshot = jsonb_set(snapshot, '{name_ko}', '""'), run_at = now() - interval '1 minute' where id = j;
  res := public.cms_run_due_jobs();
  assert (res ->> 'failed')::int = 1 and (res ->> 'published')::int = 0, 'the invalid job fails: ' || res::text;
  assert (select status from public.publication_jobs where id = j) = 'failed' and (select last_error from public.publication_jobs where id = j) like '%이름%', 'the failure and its reason are recorded';
  assert (select description from public.restaurant_overrides where id = r) is null and public._cms_live_version('restaurant', r) = 0, 'a failed publish exposes nothing';
  assert exists (select 1 from public.audit_log where action = 'cms_job_failed' and row_id = r::text), 'the failure is audited';
  assert (public.cms_run_due_jobs() ->> 'failed')::int = 0, 'a failed job is not retried by itself in a loop';
  -- fix the snapshot, retry as an admin: it publishes exactly once
  update public.publication_jobs set snapshot = jsonb_set(snapshot, '{name_ko}', '"두번째 식당"') where id = j;
  raise notice 'OK cms failure: invalid snapshot fails atomically, recorded and audited, live untouched';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare j bigint := current_setting('test.job2')::bigint; begin
  perform public.cms_retry_job(j);
  begin perform public.cms_retry_job(j); raise exception 'accepted#24'; exception when no_data_found then null; end; -- no longer failed
end $$;
reset role;
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; j bigint := current_setting('test.job2')::bigint; res jsonb; begin
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'the retried job publishes: ' || res::text;
  assert (select description from public.restaurant_overrides where id = r) = '예약 설명', 'live has the content';
  assert (select attempts from public.publication_jobs where id = j) = 2, 'attempts are counted';
  res := public.cms_run_due_jobs();
  assert (select count(*) from public.content_versions where entity_id = r) = 1, 'published exactly once';
  raise notice 'OK cms retry: a failed job retried by an admin publishes exactly once';
end $$;

-- the scheduler of record loses the admin role: the job must not run
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a2","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; j bigint; begin
  perform public.cms_save_draft('restaurant', r, jsonb_set(public.cms_state('restaurant', r) -> 'live', '{description}', '"권한 시험"'), 0);
  j := public.cms_schedule('restaurant', r, 1, now() + interval '1 day', null, '권한');
  perform set_config('test.job3', j::text, false);
end $$;
reset role;
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; j bigint := current_setting('test.job3')::bigint; res jsonb; begin
  delete from public.admin_roles where user_id = 'f4000000-0000-4000-8000-0000000000a2';
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = j;
  res := public.cms_run_due_jobs();
  assert (res ->> 'failed')::int = 1 and (select last_error from public.publication_jobs where id = j) like '%권한%', 'the run re-checks permission';
  assert (select description from public.restaurant_overrides where id = r) = '예약 설명', 'nothing was published';
  insert into public.admin_roles (user_id, role) values ('f4000000-0000-4000-8000-0000000000a2', 'admin');
  raise notice 'OK cms: a scheduler who lost the admin role cannot publish';
end $$;
-- live changed after scheduling: the job refuses to overwrite it
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; j bigint := current_setting('test.job3')::bigint; begin
  perform public.cms_retry_job(j);
  perform public.cms_set_visibility('restaurant', r, 'hidden', '긴급 숨김');   -- somebody publishes meanwhile
end $$;
reset role;
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; j bigint := current_setting('test.job3')::bigint; res jsonb; begin
  res := public.cms_run_due_jobs();
  assert (res ->> 'failed')::int = 1 and (select last_error from public.publication_jobs where id = j) like '%충돌%', 'a stale scheduled snapshot does not overwrite newer live content';
  assert (select visibility from public.restaurant_overrides where id = r) = 'hidden', 'the newer live content stands';
  raise notice 'OK cms: a scheduled snapshot never silently overwrites newer live content';
end $$;

-- ===== D: cancel; unpublish; F: rollback; immutability =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; j bigint; v int; before int; rev int; begin
  rev := (public.cms_state('restaurant', r) -> 'draft' ->> 'revision')::int;
  assert (public.cms_state('restaurant', r) -> 'draft' ->> 'stale')::boolean, 'the kept draft is stale after the end job moved live';
  rev := (public.cms_rebase_draft('restaurant', r, rev) ->> 'revision')::int;
  rev := (public.cms_save_draft('restaurant', r, jsonb_set(public.cms_state('restaurant', r) -> 'live', '{name_ko}', '"취소될 이름"'), rev) ->> 'revision')::int;
  j := public.cms_schedule('restaurant', r, rev, now() + interval '1 day', now() + interval '2 days', '취소 시험');
  perform public.cms_cancel_job(j, '마음이 바뀜');
  assert (select count(*) from public.publication_jobs where entity_id = r and status = 'scheduled') = 0, 'D: the schedule and its end are cancelled';
  assert (select status from public.publication_jobs where id = j) = 'cancelled', 'cancelled, not deleted';
  begin perform public.cms_cancel_job(j); raise exception 'accepted#25'; exception when no_data_found then null; end;
  -- reschedule keeps the snapshot
  j := public.cms_schedule('restaurant', r, rev, now() + interval '1 day');
  perform public.cms_reschedule(j, now() + interval '3 days', now() + interval '4 days');
  assert (select count(*) from public.publication_jobs where entity_id = r and status = 'scheduled') = 2 and (select run_at from public.publication_jobs where id = j) > now() + interval '2 days', 'rescheduled, with an end';
  perform public.cms_reschedule(j, now() + interval '3 days', null);
  assert (select count(*) from public.publication_jobs where entity_id = r and status = 'scheduled') = 1, 'removing the end cancels the end job';
  perform public.cms_cancel_job(j);
  select count(*) into before from public.content_versions where entity_id = r;
  assert (select name_ko from public.restaurant_overrides where id = r) = '예약된 이름', 'D: cancelling changed nothing public';
  raise notice 'OK cms D: cancel and reschedule never change live content';

  -- unpublish needs a reason, is a version, deletes nothing
  begin perform public.cms_unpublish('restaurant', r, ' '); raise exception 'accepted#26'; exception when invalid_parameter_value then null; end;
  v := public.cms_set_visibility('restaurant', r, 'published', '다시 공개');
  assert v = 4, 'visibility change is versioned';
  v := public.cms_unpublish('restaurant', r, '내용 점검');
  assert v = 5 and (select visibility from public.restaurant_overrides where id = r) = 'hidden', 'unpublished';

  -- F: rollback = publish an older snapshot as a NEW version
  v := public.cms_rollback('restaurant', r, 1, '처음 내용으로');
  assert v = 6 and (select name_ko from public.restaurant_overrides where id = r) = '새 이름', 'F: the old content is live again';
  assert (select kind from public.content_versions where entity_id = r and version = 6) = 'rollback' and (select rolled_back_from from public.content_versions where entity_id = r and version = 6) = 1, 'recorded as a rollback of version 1';
  assert (select count(*) from public.content_versions where entity_id = r) = 6, 'history keeps every version';
  begin perform public.cms_rollback('restaurant', r, 99, 'x'); raise exception 'accepted#27'; exception when no_data_found then null; end;
  begin perform public.cms_rollback('restaurant', r, 1, ''); raise exception 'accepted#28'; exception when invalid_parameter_value then null; end;
  -- the draft is stale after live moved: it must be rebased before publishing
  assert (public.cms_state('restaurant', r) -> 'draft' ->> 'stale')::boolean, 'the older draft is reported stale';
  begin perform public.cms_publish('restaurant', r, (public.cms_state('restaurant', r) -> 'draft' ->> 'revision')::int, 'x'); raise exception 'accepted#29'; exception when serialization_failure then null; end;
  perform public.cms_rebase_draft('restaurant', r, (public.cms_state('restaurant', r) -> 'draft' ->> 'revision')::int);
  assert not (public.cms_state('restaurant', r) -> 'draft' ->> 'stale')::boolean, 'after rebase it can be published';
  perform public.cms_discard_draft('restaurant', r, (public.cms_state('restaurant', r) -> 'draft' ->> 'revision')::int);
  assert (public.cms_state('restaurant', r) -> 'draft') = 'null'::jsonb, 'discarding a draft leaves live alone';
  raise notice 'OK cms F: unpublish and rollback are new versions; stale drafts must be rebased; nothing is deleted';
end $$;
reset role;
do $$ begin
  begin update public.content_versions set reason = 'edited'; raise exception 'accepted#30'; exception when object_not_in_prerequisite_state then null; end;
  begin delete from public.content_versions; raise exception 'accepted#31'; exception when object_not_in_prerequisite_state then null; end;
  raise notice 'OK cms: versions are immutable, even for the superuser';
end $$;

-- overview for the list filters
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare o record; begin
  select * into o from public.cms_overview('restaurant', null) where entity_id = 'e4000000-0000-4000-8000-000000000002';
  assert o.failed_jobs >= 1 and o.live_version >= 1 and o.last_published_at is not null, 'the overview reports failed jobs and versions';
  raise notice 'OK cms overview: draft / scheduled / failed per restaurant';
end $$;

-- ===== G: authorization =====
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; n int; begin
  begin perform public.cms_state('restaurant', r); raise exception 'accepted#40'; exception when insufficient_privilege then null; end;
  begin perform public.cms_save_draft('restaurant', r, '{}', 0); raise exception 'accepted#41'; exception when insufficient_privilege then null; end;
  begin perform public.cms_publish('restaurant', r, 1, 'x'); raise exception 'accepted#42'; exception when insufficient_privilege then null; end;
  begin perform public.cms_schedule('restaurant', r, 1, now() + interval '1 day'); raise exception 'accepted#43'; exception when insufficient_privilege then null; end;
  begin perform public.cms_unpublish('restaurant', r, 'x'); raise exception 'accepted#44'; exception when insufficient_privilege then null; end;
  begin perform public.cms_rollback('restaurant', r, 1, 'x'); raise exception 'accepted#45'; exception when insufficient_privilege then null; end;
  begin perform public.cms_cancel_job(1); raise exception 'accepted#46'; exception when insufficient_privilege then null; end;
  begin perform public.cms_set_visibility('restaurant', r, 'hidden', 'x'); raise exception 'accepted#47'; exception when insufficient_privilege then null; end;
  begin perform * from public.cms_overview('restaurant', null); raise exception 'accepted#48'; exception when insufficient_privilege then null; end;
  select count(*) into n from public.content_drafts; assert n = 0, 'a moderator reads no drafts';
  select count(*) into n from public.content_versions; assert n = 0, 'no history';
  select count(*) into n from public.publication_jobs; assert n = 0, 'no jobs';
  begin insert into public.content_versions (entity_type, entity_id, version, kind, data) values ('restaurant', r, 99, 'publish', '{}'); raise exception 'accepted#49'; exception when insufficient_privilege then null; end;
  raise notice 'OK cms G: moderators cannot publish, schedule, roll back or read drafts';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; n int; begin
  begin perform public.cms_publish('restaurant', r, 1, 'x'); raise exception 'accepted#50'; exception when insufficient_privilege then null; end;
  begin perform public.cms_state('restaurant', r); raise exception 'accepted#51'; exception when insufficient_privilege then null; end;
  select count(*) into n from public.content_drafts; assert n = 0, 'a student reads no drafts';
  begin insert into public.content_drafts (entity_type, entity_id, data, base_version) values ('restaurant', r, '{}', 0); raise exception 'accepted#52'; exception when insufficient_privilege then null; end;
  begin insert into public.publication_jobs (entity_type, entity_id, snapshot, run_at) values ('restaurant', r, '{}', now()); raise exception 'accepted#53'; exception when insufficient_privilege then null; end;
  update public.restaurant_overrides set name_ko = 'x' where id = r; get diagnostics n = row_count; assert n = 0, 'a student edit touches no rows';
  raise notice 'OK cms G: students cannot publish or read drafts';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000001'; begin
  begin perform public.cms_state('restaurant', r); raise exception 'accepted#60'; exception when insufficient_privilege then null; end;
  begin perform count(*) from public.content_drafts; raise exception 'accepted#61'; exception when insufficient_privilege then null; end;
  raise notice 'OK cms G: anon has no access to publishing at all';
end $$;
reset role;

-- ===== cafeteria meals: the same engine, with students watching =====
insert into public.campus_cafeterias (id, university_id, kind, name_ko) values
  ('c4000000-0000-4000-8000-000000000001', '5c0a8f3e-0001-4a6e-9b1d-000000000001', 'student', 'CMS 학생식당');
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare m uuid; d jsonb; s jsonb; v int; j bigint; rev int; begin
  insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, status, verified_at)
    values ('c4000000-0000-4000-8000-000000000001', '2026-11-20', 'lunch', '[{"name_ko":"첫 메뉴","kind":"main"}]', 'draft', now()) returning id into m;
  perform set_config('test.meal', m::text, false);
  -- a new meal is a hidden draft; the first publication goes through the engine
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, status, verified_at)
    values ('c4000000-0000-4000-8000-000000000001', '2026-11-21', 'lunch', '[{"name_ko":"x"}]', 'published', now()); raise exception 'accepted#70'; exception when insufficient_privilege then null; end;
  s := public.cms_state('cafeteria_meal', m);
  d := jsonb_set(jsonb_set(s -> 'live', '{status}', '"published"'), '{price_krw}', '5500');
  perform public.cms_save_draft('cafeteria_meal', m, d, 0);
  assert (select status from public.cafeteria_meals where id = m) = 'draft', 'saving a draft does not publish';
  v := public.cms_publish('cafeteria_meal', m, 1, '첫 게시');
  assert v = 1 and (select status from public.cafeteria_meals where id = m) = 'published' and (select price_krw from public.cafeteria_meals where id = m) = 5500, 'publish makes the meal live';
  raise notice 'OK cms meal: a new meal is a hidden draft until published';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select menu_items -> 0 ->> 'name_ko' from public.cafeteria_meals where id = current_setting('test.meal')::uuid) = '첫 메뉴', 'students see the published menu';
  raise notice 'OK cms meal: students see it after publication';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare m uuid := current_setting('test.meal')::uuid; d jsonb; j bigint; v int; begin
  -- 1: edit as a draft: the published menu is unchanged
  d := jsonb_set(public.cms_state('cafeteria_meal', m) -> 'live', '{menu_items}', '[{"name_ko":"새 메뉴","kind":"main"}]');
  perform public.cms_save_draft('cafeteria_meal', m, d, 0);
  assert (select menu_items -> 0 ->> 'name_ko' from public.cafeteria_meals where id = m) = '첫 메뉴', 'the live menu is still the published one';
  begin update public.cafeteria_meals set price_krw = 1 where id = m; raise exception 'accepted#71'; exception when insufficient_privilege then null; end;
  begin delete from public.cafeteria_meals where id = m; raise exception 'accepted#72'; exception when insufficient_privilege then null; end;
  -- validation specific to meals
  begin perform public.cms_save_draft('cafeteria_meal', m, jsonb_set(d, '{menu_items}', '[]'), 1); raise exception 'accepted#73'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_meal', m, jsonb_set(d, '{start_time}', '"13:00"') || '{"end_time":"12:00"}', 1); raise exception 'accepted#74'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_meal', m, d || '{"badge":"천원의 아침밥"}', 1); raise exception 'accepted#75'; exception when invalid_parameter_value then null; end;  -- no source
  begin perform public.cms_save_draft('cafeteria_meal', m, d || '{"badge":"천원의 아침밥","source_url":"https://example.org/a"}', 1); raise exception 'accepted#76'; exception when invalid_parameter_value then null; end;  -- lunch, not breakfast
  begin perform public.cms_save_draft('cafeteria_meal', m, jsonb_set(d, '{source_url}', '"http://x"'), 1); raise exception 'accepted#77'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_meal', m, d || '{"cafeteria_id":"x"}', 1); raise exception 'accepted#78'; exception when invalid_parameter_value then null; end;
  -- 3: schedule, then the server publishes it with no client involved
  j := public.cms_schedule('cafeteria_meal', m, 1, now() + interval '1 day', null, '아침 7시');
  perform set_config('test.mjob', j::text, false);
  assert (select menu_items -> 0 ->> 'name_ko' from public.cafeteria_meals where id = m) = '첫 메뉴', 'scheduled content is not live';
  -- 4: cancel and re-create
  perform public.cms_cancel_job(j, '취소');
  j := public.cms_schedule('cafeteria_meal', m, 1, now() + interval '1 day', null, '다시 예약');
  perform set_config('test.mjob', j::text, false);
  raise notice 'OK cms meal: draft leaves the published menu alone; guard, validation, schedule, cancel';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select menu_items -> 0 ->> 'name_ko' from public.cafeteria_meals where id = current_setting('test.meal')::uuid) = '첫 메뉴', 'Flutter still reads the previously published menu';
  raise notice 'OK cms meal: students still see the old menu while a draft and a schedule exist';
end $$;
reset role;
do $$ declare m uuid := current_setting('test.meal')::uuid; j bigint := current_setting('test.mjob')::bigint; res jsonb; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = j;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'the due meal job ran: ' || res::text;
  assert (select menu_items -> 0 ->> 'name_ko' from public.cafeteria_meals where id = m) = '새 메뉴', 'the scheduled menu is now live';
  assert (select count(*) from public.content_versions where entity_type = 'cafeteria_meal' and entity_id = m) = 2, 'two versions';
  assert (public.cms_run_due_jobs() ->> 'published')::int = 0, 'running again publishes nothing twice';
  raise notice 'OK cms meal: the server publishes a scheduled meal exactly once';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare m uuid := current_setting('test.meal')::uuid; v int; begin
  v := public.cms_unpublish('cafeteria_meal', m, '점검');
  assert (select status from public.cafeteria_meals where id = m) = 'draft' and (select menu_items -> 0 ->> 'name_ko' from public.cafeteria_meals where id = m) = '새 메뉴', 'unpublished = hidden, content kept';
  v := public.cms_rollback('cafeteria_meal', m, 1, '처음 메뉴로');
  assert (select menu_items -> 0 ->> 'name_ko' from public.cafeteria_meals where id = m) = '첫 메뉴' and (select status from public.cafeteria_meals where id = m) = 'published', 'rollback restores version 1 as a new version';
  assert (select count(*) from public.content_versions where entity_type = 'cafeteria_meal' and entity_id = m) = 4, 'history keeps all four versions';
  assert (select count(*) from public.cms_overview('cafeteria_meal', 'c4000000-0000-4000-8000-000000000001')) = 1, 'the overview is limited to one cafeteria';
  -- a hidden draft meal can be deleted, a live one cannot
  perform public.cms_unpublish('cafeteria_meal', m, '삭제 준비');
  delete from public.cafeteria_meals where id = m;
  raise notice 'OK cms meal: unpublish, rollback, history; only drafts can be deleted';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_publish('cafeteria_meal', gen_random_uuid(), 1, 'x'); raise exception 'accepted#79'; exception when insufficient_privilege then null; end;
  raise notice 'OK cms meal: moderators cannot publish meals';
end $$;
reset role;
delete from public.publication_jobs where entity_type = 'cafeteria_meal';
delete from public.content_drafts where entity_type = 'cafeteria_meal';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'cafeteria_meal';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.campus_cafeterias where id = 'c4000000-0000-4000-8000-000000000001';

-- ===== restaurant_menus: a restaurant's menu list is published as one set =====
insert into public.restaurant_menus (id, restaurant_id, name_ko, price_krw, source, sort_order) values
  ('aaaaaaaa-0000-4000-8000-0000000000b1', 'e4000000-0000-4000-8000-000000000002', '기존 메뉴', 8000, 'admin', 1);
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; live jsonb; d jsonb; v int; j bigint; begin
  live := public.cms_state('restaurant_menus', r) -> 'live';
  assert jsonb_array_length(live -> 'items') = 1 and live -> 'items' -> 0 ->> 'name_ko' = '기존 메뉴', 'live snapshot = the existing menu';
  -- a draft: price change + a new item; live is untouched
  d := jsonb_build_object('items', jsonb_build_array(
    (live -> 'items' -> 0) || '{"price_krw":9000}',
    '{"id":"aaaaaaaa-0000-4000-8000-0000000000b2","name_ko":"새 메뉴","description_ko":null,"price_krw":7000,"category":"식사","price_verified_on":"2026-11-10","available":true,"representative":false,"recommended":false,"status":"active","sort_order":2,"image_url":null}'::jsonb));
  perform public.cms_save_draft('restaurant_menus', r, d, 0);
  assert (select price_krw from public.restaurant_menus where id = 'aaaaaaaa-0000-4000-8000-0000000000b1') = 8000, 'draft price is not live';
  assert (select count(*) from public.restaurant_menus where restaurant_id = r) = 1, 'draft item is not live';
  -- direct API writes are refused
  begin update public.restaurant_menus set price_krw = 1 where id = 'aaaaaaaa-0000-4000-8000-0000000000b1'; raise exception 'accepted#m1'; exception when insufficient_privilege then null; end;
  begin delete from public.restaurant_menus where id = 'aaaaaaaa-0000-4000-8000-0000000000b1'; raise exception 'accepted#m2'; exception when insufficient_privilege then null; end;
  -- validation: negative price, price date without price, duplicate id, unknown field, other restaurant's id
  begin perform public.cms_save_draft('restaurant_menus', r, jsonb_build_object('items', jsonb_build_array((live -> 'items' -> 0) || '{"price_krw":-1}')), 1); raise exception 'accepted#m3'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', r, jsonb_build_object('items', jsonb_build_array((live -> 'items' -> 0) || '{"price_krw":null,"price_verified_on":"2026-11-10"}')), 1); raise exception 'accepted#m4'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', r, jsonb_build_object('items', jsonb_build_array(live -> 'items' -> 0, live -> 'items' -> 0)), 1); raise exception 'accepted#m5'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', r, jsonb_build_object('items', jsonb_build_array((live -> 'items' -> 0) || '{"evil":1}')), 1); raise exception 'accepted#m6'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('restaurant_menus', r, jsonb_build_object('items', jsonb_build_array((live -> 'items' -> 0) || '{"id":"aaaaaaaa-0000-4000-8000-0000000000b1"}', '{}'::jsonb)), 1); raise exception 'accepted#m7'; exception when invalid_parameter_value then null; end;
  -- publish: both changes go live together as version 1
  v := public.cms_publish('restaurant_menus', r, 1, '가격 인상');
  assert v = 1, 'first menu version';
  assert (select price_krw from public.restaurant_menus where id = 'aaaaaaaa-0000-4000-8000-0000000000b1') = 9000, 'published price';
  assert (select kakao_place_id from public.restaurant_menus where id = 'aaaaaaaa-0000-4000-8000-0000000000b2') = 'cms-2', 'new menu gets the Kakao id the app reads by';
  -- schedule the removal of the new item; the server runs it later
  live := public.cms_state('restaurant_menus', r) -> 'live';
  perform public.cms_save_draft('restaurant_menus', r, jsonb_build_object('items', jsonb_build_array(live -> 'items' -> 0)), 0);
  j := public.cms_schedule('restaurant_menus', r, 1, now() + interval '1 day', null, '내일 메뉴 정리');
  perform set_config('test.menujob', j::text, false);
  assert (select count(*) from public.restaurant_menus where restaurant_id = r and status = 'active') = 2, 'scheduled change is not live';
  raise notice 'OK cms menus: draft invisible, direct writes refused, validation, publish as one set, schedule';
end $$;
reset role;
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; res jsonb; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = current_setting('test.menujob')::bigint;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'menu job ran: ' || res::text;
  assert (select status from public.restaurant_menus where id = 'aaaaaaaa-0000-4000-8000-0000000000b2') = 'archived', 'the removed item is archived, not deleted';
  assert (select count(*) from public.restaurant_menus where restaurant_id = r) = 2, 'nothing was deleted';
  assert (public.cms_run_due_jobs() ->> 'published')::int = 0, 'exactly once';
  raise notice 'OK cms menus: the server applies the schedule once; removed menus are archived';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; v int; begin
  v := public.cms_rollback('restaurant_menus', r, 1, '되돌리기');
  assert (select status from public.restaurant_menus where id = 'aaaaaaaa-0000-4000-8000-0000000000b2') = 'active', 'rollback restores the item';
  v := public.cms_unpublish('restaurant_menus', r, '점검');
  assert (select count(*) from public.restaurant_menus where restaurant_id = r and status = 'active') = 0, 'unpublish hides every menu';
  assert (select count(*) from public.restaurant_menus where restaurant_id = r) = 2, 'and deletes none';
  begin perform public.cms_set_visibility('restaurant_menus', r, 'published', 'x'); raise exception 'accepted#m8'; exception when invalid_parameter_value then null; end;
  assert (select count(*) from public.cms_overview('restaurant_menus') where entity_id = r and live_version = 4) = 1, 'overview lists menu sets';
  raise notice 'OK cms menus: rollback, unpublish keep every row; history';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_save_draft('restaurant_menus', 'e4000000-0000-4000-8000-000000000002', '{"items":[]}', 0); raise exception 'accepted#m9'; exception when insufficient_privilege then null; end;
  raise notice 'OK cms menus: moderators cannot draft or publish menus';
end $$;
reset role;
delete from public.publication_jobs where entity_type = 'restaurant_menus';
delete from public.content_drafts where entity_type = 'restaurant_menus';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'restaurant_menus';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.restaurant_menus where restaurant_id = 'e4000000-0000-4000-8000-000000000002';

-- ===== restaurant_photos: cover + gallery of one restaurant, published together =====
insert into storage.objects (bucket_id, name) values ('restaurant-images', 'restaurants/cms/unpublished.jpg');
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; d jsonb; v int; j bigint;
  cov1 text := '{"id":"bbbbbbbb-0000-4000-8000-0000000000a1","kind":"cover","storage_path":"restaurants/cms/c1.jpg","url":"https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/cms/c1.jpg","caption":null,"sort_order":0,"status":"published","source":"admin","credit":null,"width":800,"height":600,"bytes":1000}';
  cov2 text := '{"id":"bbbbbbbb-0000-4000-8000-0000000000a2","kind":"cover","storage_path":"restaurants/cms/c2.jpg","url":"https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/cms/c2.jpg","caption":null,"sort_order":0,"status":"published","source":"admin","credit":null,"width":800,"height":600,"bytes":1000}';
begin
  perform public.cms_save_draft('restaurant_photos', r, jsonb_build_object('photos', jsonb_build_array(cov1::jsonb)), 0);
  assert not exists (select 1 from public.restaurant_photos where restaurant_id = r), 'a draft photo is not live';
  assert (select image_url from public.restaurant_overrides where id = r) is null, 'and does not reach the card image';
  begin insert into public.restaurant_photos (restaurant_id, kind, storage_path, url) values (r, 'gallery', 'restaurants/cms/direct.jpg', 'https://x/d.jpg'); raise exception 'accepted#p10'; exception when insufficient_privilege then null; end;
  v := public.cms_publish('restaurant_photos', r, 1, '첫 대표 사진');
  assert (select image_url from public.restaurant_overrides where id = r) = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/cms/c1.jpg', 'the published cover reaches the card image';
  -- change the cover: scheduled, then applied by the server
  perform public.cms_save_draft('restaurant_photos', r, jsonb_build_object('photos', jsonb_build_array(
    (public.cms_state('restaurant_photos', r) -> 'live' -> 'photos' -> 0) || '{"status":"archived"}', cov2::jsonb)), 0);
  j := public.cms_schedule('restaurant_photos', r, 1, now() + interval '1 day', null, '내일 사진 교체');
  perform set_config('test.photojob', j::text, false);
  assert (select image_url from public.restaurant_overrides where id = r) = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/cms/c1.jpg', 'a scheduled photo is not live yet';
  raise notice 'OK cms photos: drafts and schedules do not change what students see; direct writes refused';
end $$;
reset role;
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; res jsonb; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = current_setting('test.photojob')::bigint;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'photo job ran: ' || res::text;
  assert (select image_url from public.restaurant_overrides where id = r) = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/cms/c2.jpg', 'the new cover is live';
  assert (select status from public.restaurant_photos where storage_path = 'restaurants/cms/c1.jpg') = 'archived', 'the old cover is archived, its row kept';
  assert (public.cms_run_due_jobs() ->> 'published')::int = 0, 'exactly once';
  raise notice 'OK cms photos: the server swaps the cover once; the old photo is archived, not deleted';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare r constant uuid := 'e4000000-0000-4000-8000-000000000002'; v int; begin
  v := public.cms_rollback('restaurant_photos', r, 1, '이전 사진');
  assert (select image_url from public.restaurant_overrides where id = r) = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/restaurants/cms/c1.jpg', 'rollback brings the old cover back';
  v := public.cms_unpublish('restaurant_photos', r, '점검');
  assert (select image_url from public.restaurant_overrides where id = r) is null, 'unpublish clears the card image';
  assert (select count(*) from public.restaurant_photos where restaurant_id = r) = 2, 'and deletes no photo';
  -- an approved student photo is staged hidden; only publishing shows it
  insert into public.restaurant_photos (restaurant_id, kind, storage_path, url, status, source, credit) values (r, 'gallery', 'restaurants/cms/s1.jpg', 'https://x/s1.jpg', 'archived', 'student', '학생 제공');
  assert (select count(*) from public.restaurant_photos where restaurant_id = r and status = 'published') = 0, 'a staged student photo is hidden';
  -- the storage list of unpublished files is admin-only
  assert (select count(*) from storage.objects where bucket_id = 'restaurant-images' and name = 'restaurants/cms/unpublished.jpg') = 1, 'admins can list';
  raise notice 'OK cms photos: rollback, unpublish keep every row; staging row stays hidden';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from storage.objects where bucket_id = 'restaurant-images') = 0, 'the public cannot list the bucket (unpublished files stay undiscoverable)';
  raise notice 'OK storage: anon cannot enumerate restaurant-images';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_publish('restaurant_photos', 'e4000000-0000-4000-8000-000000000002', 1, 'x'); raise exception 'accepted#p11'; exception when insufficient_privilege then null; end;
  assert (select count(*) from storage.objects where bucket_id = 'restaurant-images') = 0, 'moderators cannot list unpublished files either';
  raise notice 'OK cms photos: moderators cannot publish';
end $$;
reset role;
delete from storage.objects where name = 'restaurants/cms/unpublished.jpg';
delete from public.publication_jobs where entity_type = 'restaurant_photos';
delete from public.content_drafts where entity_type = 'restaurant_photos';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'restaurant_photos';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.restaurant_photos where restaurant_id = 'e4000000-0000-4000-8000-000000000002';

-- ===== mission: edits are drafts until published; progress and rewards survive =====
insert into public.missions (id, lineage_id, slug, kind, title, reward_points, rule_type, target_count, recurrence, status)
values ('d4000000-0000-4000-8000-000000000001', 'd4000000-0000-4000-8000-000000000001', 'cms-m1', 'daily', '원래 미션', 10, 'favorite_distinct', 2, 'daily', 'draft');
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare l constant uuid := 'd4000000-0000-4000-8000-000000000001'; d jsonb; v int; j bigint; begin
  assert (public.cms_state('mission', l) -> 'live' ->> 'status') = 'draft', 'live snapshot of the mission';
  -- first publication: activate it on a schedule (a draft mission is invisible until then)
  d := public.cms_state('mission', l) -> 'live';
  perform public.cms_save_draft('mission', l, d || '{"status":"active","title":"새 미션"}', 0);
  assert (select status from public.missions where id = l) = 'draft', 'a draft does not activate the mission';
  j := public.cms_schedule('mission', l, 1, now() + interval '1 day', null, '내일 시작');
  perform set_config('test.missionjob', j::text, false);
  assert (select status from public.missions where id = l) = 'draft' and (select title from public.missions where id = l) = '원래 미션', 'a scheduled mission is not live';
  raise notice 'OK cms mission: drafts and schedules change nothing for students';
end $$;
reset role;
do $$ declare l constant uuid := 'd4000000-0000-4000-8000-000000000001'; res jsonb; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = current_setting('test.missionjob')::bigint;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'mission job ran: ' || res::text;
  assert (select status from public.missions where id = l) = 'active' and (select title from public.missions where id = l) = '새 미션', 'the server activated the mission';
  assert (public.cms_run_due_jobs() ->> 'published')::int = 0, 'exactly once';
  -- a student earns progress on the live mission
  insert into public.user_mission_progress (user_id, mission_id, lineage_id, period_key, progress, target, completed_at)
  values ('f4000000-0000-4000-8000-0000000000c1', l, l, 'all', 2, 2, now());
  raise notice 'OK cms mission: the server activates a scheduled mission once';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare l constant uuid := 'd4000000-0000-4000-8000-000000000001'; d jsonb; v int; nv uuid; begin
  -- changing the reward of a mission that has progress: the draft changes nothing, publishing makes a NEW VERSION
  d := public.cms_state('mission', l) -> 'live';
  perform public.cms_save_draft('mission', l, d || '{"reward_points":99,"target_count":5}', 0);
  assert (select reward_points from public.missions where id = l) = 10, 'the reward is unchanged until publication';
  begin perform public.admin_save_mission(jsonb_build_object('id', l, 'reward_points', 99)); raise exception 'accepted#ms1'; exception when insufficient_privilege then null; end;
  v := public.cms_publish('mission', l, 1, '보상 변경');
  nv := (select id from public.missions where lineage_id = l and version = 2);
  assert nv is not null and (select reward_points from public.missions where id = nv) = 99, 'published as version 2';
  assert (select status from public.missions where id = l) = 'archived' and (select reward_points from public.missions where id = l) = 10, 'the old version is archived and untouched';
  assert (select completed_at from public.user_mission_progress where mission_id = l and user_id = 'f4000000-0000-4000-8000-0000000000c1') is not null, 'earned progress is kept';
  -- unpublish pauses it (nothing deleted); rollback restores the earlier content as another version
  v := public.cms_unpublish('mission', l, '점검');
  assert (select status from public.missions where id = (select id from public.missions where lineage_id = l order by version desc limit 1)) = 'paused', 'unpublish pauses the mission';
  assert (select count(*) from public.user_mission_progress where lineage_id = l) = 1, 'progress survives';
  begin perform public.cms_set_visibility('mission', l, 'nonsense', 'x'); raise exception 'accepted#ms2'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('mission', l, (public.cms_state('mission', l) -> 'live') || '{"reward_points":-5}', 0); raise exception 'accepted#ms3'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('mission', l, (public.cms_state('mission', l) -> 'live') || '{"evil":1}', 0); raise exception 'accepted#ms4'; exception when invalid_parameter_value then null; end;
  assert (select count(*) from public.cms_overview('mission')) >= 1, 'overview lists missions by lineage';
  raise notice 'OK cms mission: material edit becomes a new version; progress kept; unpublish pauses';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_publish('mission', 'd4000000-0000-4000-8000-000000000001', 1, 'x'); raise exception 'accepted#ms5'; exception when insufficient_privilege then null; end;
  raise notice 'OK cms mission: moderators cannot publish missions';
end $$;
reset role;
delete from public.publication_jobs where entity_type = 'mission';
delete from public.content_drafts where entity_type = 'mission';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'mission';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.user_mission_progress where lineage_id = 'd4000000-0000-4000-8000-000000000001';
delete from public.audit_log where row_id in (select id::text from public.missions where lineage_id = 'd4000000-0000-4000-8000-000000000001');
update public.missions set supersedes_id = null where lineage_id = 'd4000000-0000-4000-8000-000000000001';
delete from public.missions where lineage_id = 'd4000000-0000-4000-8000-000000000001';

-- ===== app_content: announcements / banners / featured restaurants =====
insert into public.app_content (id, kind, title, body, active) values ('ac000000-0000-4000-8000-000000000001', 'announcement', '원래 공지', '내용', true);
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare c constant uuid := 'ac000000-0000-4000-8000-000000000001'; d jsonb; v int; j bigint; begin
  d := public.cms_state('app_content', c) -> 'live';
  begin update public.app_content set title = '직접 수정' where id = c; raise exception 'accepted#ac1'; exception when insufficient_privilege then null; end;
  begin delete from public.app_content where id = c; raise exception 'accepted#ac2'; exception when insufficient_privilege then null; end;
  begin insert into public.app_content (kind, title, active) values ('banner', '바로 노출', true); raise exception 'accepted#ac3'; exception when insufficient_privilege then null; end;
  perform public.cms_save_draft('app_content', c, d || '{"title":"새 공지"}', 0);
  assert (select title from public.app_content where id = c) = '원래 공지', 'a draft notice is not live';
  begin perform public.cms_save_draft('app_content', c, d || '{"link_url":"http://insecure"}', 1); raise exception 'accepted#ac4'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('app_content', c, d || '{"starts_at":"2030-01-02T00:00:00Z","ends_at":"2030-01-01T00:00:00Z"}', 1); raise exception 'accepted#ac5'; exception when invalid_parameter_value then null; end;
  j := public.cms_schedule('app_content', c, 1, now() + interval '1 day', now() + interval '3 days', '내일 공지 교체');
  perform set_config('test.acjob', j::text, false);
  assert (select title from public.app_content where id = c) = '원래 공지', 'a scheduled notice is not live';
  -- a staged (switched-off) row is freely editable and deletable
  insert into public.app_content (id, kind, title, active) values ('ac000000-0000-4000-8000-000000000002', 'banner', '숨김 배너', false);
  update public.app_content set title = '숨김 배너 수정' where id = 'ac000000-0000-4000-8000-000000000002';
  begin update public.app_content set active = true where id = 'ac000000-0000-4000-8000-000000000002'; raise exception 'accepted#ac6'; exception when insufficient_privilege then null; end;
  perform public.cms_set_visibility('app_content', 'ac000000-0000-4000-8000-000000000002', 'published', '배너 시작');
  assert (select active from public.app_content where id = 'ac000000-0000-4000-8000-000000000002'), 'a staged banner goes live by publishing';
  raise notice 'OK cms app_content: drafts and schedules do not change live content; direct writes refused';
end $$;
reset role;
do $$ declare c constant uuid := 'ac000000-0000-4000-8000-000000000001'; res jsonb; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = current_setting('test.acjob')::bigint;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'content job ran: ' || res::text;
  assert (select title from public.app_content where id = c) = '새 공지', 'the new notice is live';
  assert (select ends_at is null from public.app_content where id = c), 'the publish carries the draft, the end is a separate unpublish job';
  assert (public.cms_run_due_jobs() ->> 'published')::int = 0, 'exactly once';
  raise notice 'OK cms app_content: the server publishes a scheduled notice once';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare c constant uuid := 'ac000000-0000-4000-8000-000000000001'; v int; begin
  v := public.cms_unpublish('app_content', c, '내림');
  assert not (select active from public.app_content where id = c) and (select title from public.app_content where id = c) = '새 공지', 'unpublish switches it off and keeps the content';
  v := public.cms_rollback('app_content', c, 1, '처음 상태');
  assert (select active from public.app_content where id = c), 'rollback restores a version';
  assert (select count(*) from public.cms_overview('app_content')) >= 2, 'overview lists content';
  raise notice 'OK cms app_content: unpublish and rollback keep everything';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.cms_publish('app_content', 'ac000000-0000-4000-8000-000000000001', 1, 'x'); raise exception 'accepted#ac7'; exception when insufficient_privilege then null; end;
  raise notice 'OK cms app_content: moderators cannot publish content';
end $$;
reset role;
delete from public.publication_jobs where entity_type = 'app_content';
delete from public.content_drafts where entity_type = 'app_content';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'app_content';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.app_content where id in ('ac000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000002');

-- cleanup
delete from public.publication_jobs where entity_id in ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002');
delete from public.content_drafts where entity_id in ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002');
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_id in ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002');
alter table public.content_versions enable trigger content_versions_no_update;
