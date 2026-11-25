\set ON_ERROR_STOP on
\pset pager off
-- 챗봇 기록 (migration 20261129000100, applied twice by run_local.sh): the app records a finished chat turn through
-- log_chat_turn() only; nobody reads or writes the table directly; only admins (not moderators) read the history and
-- opening it is audited; bad input is refused without an error; the table keeps no more than it should.

insert into auth.users (id, email) values
  ('c8000000-0000-4000-8000-0000000000a1', 'ch-user@example.org'),
  ('c8000000-0000-4000-8000-0000000000b1', 'ch-mod@example.org'),
  ('c8000000-0000-4000-8000-0000000000c1', 'ch-admin@example.org');
insert into public.profiles (id, nickname) values ('c8000000-0000-4000-8000-0000000000a1', '국밥러')
  on conflict (id) do update set nickname = excluded.nickname;
insert into public.admin_roles (user_id, role) values
  ('c8000000-0000-4000-8000-0000000000b1', 'moderator'),
  ('c8000000-0000-4000-8000-0000000000c1', 'admin');

-- A guest records a turn; nothing else about the table is reachable.
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare ok boolean; begin
  ok := public.log_chat_turn('c8000000-0000-4000-8000-00000000c001', 'ko', '  8000원 이하 국밥 추천해줘  ', 'search',
          '{"max_price_krw":8000,"dish_keywords":["국밥"]}'::jsonb, 'answered', 'ok', '든든 국밥의 순대국밥이 8,000원이에요.',
          '[{"id":"111","name":"든든 국밥","reason":"순대국밥 8,000원","secret":"x"}]'::jsonb, null);
  assert ok, 'a guest turn is recorded';
  begin perform 1 from public.chat_turns; raise exception 'accepted#read'; exception when insufficient_privilege then null; end;
  begin insert into public.chat_turns (client_id, language, question, outcome, ai_status) values ('c8000000-0000-4000-8000-00000000c001', 'ko', 'x', 'answered', 'ok'); raise exception 'accepted#insert'; exception when insufficient_privilege then null; end;
  begin delete from public.chat_turns; raise exception 'accepted#delete'; exception when insufficient_privilege then null; end;
  begin perform public.admin_chat_turns(10); raise exception 'accepted#history'; exception when insufficient_privilege then null; end;
  begin perform public.admin_chat_stats(7); raise exception 'accepted#stats'; exception when insufficient_privilege then null; end;
  raise notice 'OK guest: can only record a turn through log_chat_turn; cannot read, write, delete or open the history';
end $$;
reset role;

do $$ declare r record; begin
  select * into r from public.chat_turns where client_id = 'c8000000-0000-4000-8000-00000000c001';
  assert r.user_id is null, 'a guest turn has no account';
  assert r.question = '8000원 이하 국밥 추천해줘', format('the question is trimmed, got [%s]', r.question);
  assert r.restaurants = '[{"id":"111","name":"든든 국밥","reason":"순대국밥 8,000원"}]'::jsonb, format('only id/name/reason are kept, got %s', r.restaurants);
  assert r.prefs ->> 'max_price_krw' = '8000', 'the interpreted conditions are kept';
  raise notice 'OK stored: trimmed question, no account for a guest, only id / name / reason per restaurant';
end $$;

-- A signed-in user: the account comes from the session.
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"c8000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ begin
  assert public.log_chat_turn('c8000000-0000-4000-8000-00000000c002', 'en', 'something warm for a cold day', 'search', null, 'no_result', 'busy', null, '[]'::jsonb, null,
    array['aiBusy', 'noneRaiseBudget', '', null, repeat('n', 99), 'a', 'b', 'c', 'd', 'e', 'f']);
  assert public.log_chat_turn('c8000000-0000-4000-8000-00000000c002', 'zh-Hans', '你好', 'chitchat', null, 'chitchat', 'ok', '你好！想吃什么？', null, null);
  assert public.log_chat_turn('c8000000-0000-4000-8000-00000000c002', 'ko', '아무거나', null, null, 'error', 'down', null, '[]'::jsonb, 'networkError');
  begin perform 1 from public.chat_turns; raise exception 'accepted#read'; exception when insufficient_privilege then null; end;
  begin perform public.admin_chat_turns(10); raise exception 'accepted#history'; exception when insufficient_privilege then null; end;
  raise notice 'OK user: records turns (any language), cannot read them or open the history';
end $$;
reset role;

do $$ begin
  assert (select count(*) from public.chat_turns where user_id = 'c8000000-0000-4000-8000-0000000000a1') = 3, 'the three turns carry the session account';
  raise notice 'OK stored: a signed-in user''s turns carry the account from the session, not from the request';
end $$;

-- Bad input is refused quietly (false), never an error and never a row.
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare c uuid := 'c8000000-0000-4000-8000-00000000c003'; begin
  assert not public.log_chat_turn(null, 'ko', 'q', null, null, 'answered', 'ok', null, null, null), 'no device id';
  assert not public.log_chat_turn(c, 'fr', 'q', null, null, 'answered', 'ok', null, null, null), 'unknown language';
  assert not public.log_chat_turn(c, 'ko', '   ', null, null, 'answered', 'ok', null, null, null), 'empty question';
  assert not public.log_chat_turn(c, 'ko', null, null, null, 'answered', 'ok', null, null, null), 'null question';
  assert not public.log_chat_turn(c, 'ko', 'q', 'hack', null, 'answered', 'ok', null, null, null), 'unknown intent';
  assert not public.log_chat_turn(c, 'ko', 'q', null, null, 'weird', 'ok', null, null, null), 'unknown outcome';
  assert not public.log_chat_turn(c, 'ko', 'q', null, null, 'answered', 'meh', null, null, null), 'unknown ai status';
  raise notice 'OK input: language, outcome, intent, status, empty or missing values are refused with false (no error, no row)';
end $$;
reset role;
do $$ begin assert (select count(*) from public.chat_turns where client_id = 'c8000000-0000-4000-8000-00000000c003') = 0, 'nothing stored for refused calls'; end $$;

-- Size limits: a 900-character question is cut to 400, twenty restaurants to ten, odd entries dropped, prefs bounded.
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare big jsonb; many jsonb; begin
  select jsonb_agg(jsonb_build_object('id', 'r' || g, 'name', repeat('이', 200), 'reason', repeat('a', 300))) into many from generate_series(1, 20) g;
  big := jsonb_build_object('k', repeat('x', 5000));
  assert public.log_chat_turn('c8000000-0000-4000-8000-00000000c004', 'ko', repeat('가', 900), 'search', big, 'answered', 'ok', repeat('b', 900),
    many || '["str", {"name":"no id"}, null]'::jsonb, repeat('z', 100));
  raise notice 'OK limits: stored (cut) instead of refused';
end $$;
reset role;
do $$ declare r record; begin
  select * into r from public.chat_turns where client_id = 'c8000000-0000-4000-8000-00000000c004';
  assert char_length(r.question) = 400, format('question cut to 400, got %s', char_length(r.question));
  assert char_length(r.reply) = 600, 'reply cut to 600';
  assert char_length(r.failure) = 40, 'failure code cut to 40';
  assert jsonb_array_length(r.restaurants) = 10, format('ten restaurants at most, got %s', jsonb_array_length(r.restaurants));
  assert char_length(r.restaurants -> 0 ->> 'name') = 80 and char_length(r.restaurants -> 0 ->> 'reason') = 160, 'name 80 / reason 160';
  assert r.prefs is null, 'oversized conditions are dropped, not stored';
  raise notice 'OK limits: question 400, reply 600, restaurants 10 (name 80 / reason 160), oversized conditions dropped';
end $$;

-- One account or device cannot flood the table: 60 turns an hour, then false.
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare c uuid := 'c8000000-0000-4000-8000-00000000c005'; n int := 0; begin
  for i in 1..60 loop if public.log_chat_turn(c, 'ko', 'q' || i, null, null, 'answered', 'ok', null, null, null) then n := n + 1; end if; end loop;
  assert n = 60, format('60 accepted, got %s', n);
  assert not public.log_chat_turn(c, 'ko', 'one too many', null, null, 'answered', 'ok', null, null, null), 'the 61st within the hour is refused';
  assert public.log_chat_turn('c8000000-0000-4000-8000-00000000c006', 'ko', 'another device', null, null, 'answered', 'ok', null, null, null), 'another device is unaffected';
  raise notice 'OK rate: 60 turns per hour per device (or account), the 61st is refused, others are unaffected';
end $$;
reset role;

-- A moderator is not enough: the history holds free text people typed.
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"c8000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  begin perform public.admin_chat_turns(10); raise exception 'accepted#history'; exception when insufficient_privilege then null; end;
  begin perform public.admin_chat_stats(7); raise exception 'accepted#stats'; exception when insufficient_privilege then null; end;
  raise notice 'OK moderator: cannot open the chat history or its totals';
end $$;
reset role;

-- An admin reads it.
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"c8000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ declare r record; s record; first_id bigint; n int; begin
  select * into s from public.admin_chat_stats(30);
  assert s.turns = 66, format('totals include every logged turn (1 guest + 3 user + 1 big + 60 + 1), got %s', s.turns);
  assert s.signed_in_turns = 3, format('three signed-in turns, got %s', s.signed_in_turns);
  assert s.no_result = 1 and s.errors = 1 and s.chitchat = 1, format('no_result/error/chitchat counts %s', s);
  assert s.ai_issues = 2, format('busy + down = 2 AI issues, got %s', s.ai_issues);

  -- newest first, with the nickname of a signed-in asker and none for a guest
  select * into r from public.admin_chat_turns(200, null, 30, '국밥') ;
  assert r.question = '8000원 이하 국밥 추천해줘' and r.nickname is null and r.user_id is null, 'search finds the guest question';
  select * into r from public.admin_chat_turns(10, null, 30, 'warm');
  assert r.nickname = '국밥러' and r.language = 'en' and r.outcome = 'no_result' and r.ai_status = 'busy', format('signed-in turn %s', r);
  assert r.notes[1:2] = array['aiBusy', 'noneRaiseBudget'] and cardinality(r.notes) = 8 and char_length(r.notes[3]) = 30, format('app-written lines are kept as kind names (8 at most, 30 chars), got %s', r.notes);

  -- filters
  assert (select count(*) from public.admin_chat_turns(200, null, 30, null, 'error')) = 1, 'outcome filter';
  assert (select count(*) from public.admin_chat_turns(200, null, 30, null, null, 'zh-Hans')) = 1, 'language filter';
  assert (select count(*) from public.admin_chat_turns(200, null, 30, null, null, null, true)) = 3, 'signed-in only';
  -- search wildcards are literal: "%" and "_" match nothing here
  assert (select count(*) from public.admin_chat_turns(200, null, 30, '%')) = 0, 'a percent sign is not a wildcard';
  assert (select count(*) from public.admin_chat_turns(200, null, 30, '_')) = 0, 'an underscore is not a wildcard';

  -- keyset pagination: pages of 10 never repeat and never skip
  select count(*) into n from public.admin_chat_turns(100, null, 30);
  select min(id) into first_id from public.admin_chat_turns(10, null, 30);
  assert (select count(*) from public.admin_chat_turns(1000, first_id, 30)) = n - 10, 'load-more continues exactly after the first page';
  assert (select count(*) from public.admin_chat_turns(1, null, 30)) = 1 and (select count(*) from public.admin_chat_turns(1000, null, 30)) <= 100, 'limit is clamped to 1..100';
  raise notice 'OK admin: totals, nickname join, filters, literal search, load-more pagination and the 100-row cap';
end $$;
reset role;

-- Opening the history is audited (first page only, not "load more").
do $$ declare before_n bigint; begin
  select count(*) into before_n from public.audit_log where action = 'view_chat_history';
  assert before_n >= 1, 'the first-page reads were audited';
  assert (select actor_id from public.audit_log where action = 'view_chat_history' order by id desc limit 1) = 'c8000000-0000-4000-8000-0000000000c1', 'the audit row names the admin';
  assert not exists (select 1 from public.audit_log where action = 'view_chat_history' and details::text ilike '%국밥%'), 'the search words are not written to the audit log';
  raise notice 'OK audit: opening the history is recorded with the admin, never the words searched';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"c8000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ declare b bigint; a bigint; begin
  select count(*) into b from public.audit_log where action = 'view_chat_history';
  perform public.admin_chat_turns(10, 999999999, 30);
  select count(*) into a from public.audit_log where action = 'view_chat_history';
  assert a = b, '"load more" does not add an audit row';
  raise notice 'OK audit: load-more reads do not flood the audit log';
end $$;
reset role;

-- Retention: rows past 90 days are deleted along the way (2% of inserts do it), and a deleted account takes its rows.
insert into public.chat_turns (created_at, client_id, language, question, outcome, ai_status)
values (now() - interval '100 days', 'c8000000-0000-4000-8000-00000000c007', 'ko', '아주 오래된 질문', 'answered', 'ok');
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare i int; begin
  for i in 1..1500 loop
    perform public.log_chat_turn(gen_random_uuid(), 'ko', 'q' || i, null, null, 'answered', 'ok', null, null, null);
  end loop;
end $$;
reset role;
do $$ begin
  assert not exists (select 1 from public.chat_turns where question = '아주 오래된 질문'), 'a row older than 90 days is pruned';
  raise notice 'OK retention: rows older than 90 days are deleted as turns are recorded';
end $$;

delete from auth.users where id = 'c8000000-0000-4000-8000-0000000000a1';
do $$ begin
  assert not exists (select 1 from public.chat_turns where question = 'something warm for a cold day'), 'a deleted account takes its chat turns';
  raise notice 'OK privacy: deleting an account deletes its chat history';
end $$;
