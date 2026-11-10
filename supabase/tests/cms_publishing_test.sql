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
  select * into o from public.cms_overview('restaurant') where entity_id = 'e4000000-0000-4000-8000-000000000002';
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
  begin perform * from public.cms_overview('restaurant'); raise exception 'accepted#48'; exception when insufficient_privilege then null; end;
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

-- cleanup
delete from public.publication_jobs where entity_id in ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002');
delete from public.content_drafts where entity_id in ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002');
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_id in ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002');
alter table public.content_versions enable trigger content_versions_no_update;
