\set ON_ERROR_STOP on
\pset pager off
-- ===== existing data survives =====
do $$ begin
  assert (select companion_types from public.user_preferences where user_id='11111111-0000-4000-8000-000000000001') = array['friends_2_3'], 'friends_2_3 -> [friends_2_3]';
  assert (select companion_types from public.user_preferences where user_id='22222222-0000-4000-8000-000000000002') = array['solo'], 'solo -> [solo]';
  assert (select companion_types from public.user_preferences where user_id='33333333-0000-4000-8000-000000000003') = '{}', 'null -> empty array';
  assert (select companion_type from public.user_preferences where user_id='11111111-0000-4000-8000-000000000001') = 'friends_2_3', 'old column kept';
  assert (select budget_type||budget_amount_krw||travel_mode||max_travel_minutes from public.user_preferences where user_id='11111111-0000-4000-8000-000000000001') = 'min12000walk10', 'other prefs untouched';
  assert (select onboarding_completed from public.profiles where id='11111111-0000-4000-8000-000000000001'), 'onboarding flag untouched';
  raise notice 'OK data: single companions migrated to arrays, null -> {}, old column + other fields preserved';
  assert (select nickname from public.profiles where id='11111111-0000-4000-8000-000000000001') = '에렌자', 'provider nickname untouched';
  assert (select count(*) from public.profiles where nickname_is_custom) = 0, 'no existing nickname is silently marked custom';
  raise notice 'OK nickname: existing provider nickname kept and NOT counted as custom';
end $$;

-- ===== exactly one RPC overload =====
do $$ begin
  assert (select count(*) from pg_proc where proname='save_user_preferences' and pronamespace='public'::regnamespace) = 1, 'one overload';
  assert (select pg_get_function_identity_arguments(oid) like '%p_companion_types text[]%' from pg_proc where proname='save_user_preferences'), 'new signature';
  assert (select prosecdef and proconfig @> array['search_path=""'] from pg_proc where proname='save_user_preferences'), 'definer + pinned search_path';
  assert not has_function_privilege('anon','public.save_user_preferences(uuid,text,integer,text,integer,text[],text[],text[],boolean)','execute'), 'anon cannot execute';
  assert has_function_privilege('authenticated','public.save_user_preferences(uuid,text,integer,text,integer,text[],text[],text[],boolean)','execute');
  assert not has_function_privilege('anon','public.set_nickname(text)','execute');
  assert has_function_privilege('authenticated','public.set_nickname(text)','execute');
  raise notice 'OK RPCs: one save_user_preferences overload, pinned search_path, anon denied';
end $$;

-- ===== nickname RPC as user 1 =====
set role authenticated; select set_config('request.jwt.claims','{"sub":"11111111-0000-4000-8000-000000000001","role":"authenticated"}',false);
do $$ begin
  begin update public.profiles set nickname='direct' where id=auth.uid(); raise exception 'x'; exception when insufficient_privilege then raise notice 'OK: direct nickname UPDATE blocked'; end;
  begin update public.profiles set nickname_is_custom=true where id=auth.uid(); raise exception 'x'; exception when insufficient_privilege then raise notice 'OK: client cannot set nickname_is_custom'; end;
end $$;
do $$ declare t text; begin
  foreach t in array array[null, '', 'a', ' 맛집왕', '맛집왕 ', 'abcdefghijklmnop', E'ab\tcd', E'ab\u200bcd', E'ab\u202ecd'] loop
    begin perform public.set_nickname(t); raise exception 'accepted %', coalesce(t,'NULL');
    exception when check_violation then null; end;
  end loop;
  raise notice 'OK nickname: null/empty/1 char/outer space/16 chars/control/zero-width/bidi all rejected';
  assert (select not nickname_is_custom from public.profiles where id=auth.uid()), 'rejections changed nothing';
end $$;
select (public.set_nickname('맛집왕')).nickname_is_custom as saved_ko;
do $$ begin
  assert (select nickname from public.profiles where id=auth.uid())='맛집왕';
  perform public.set_nickname('Foodie 123'); perform public.set_nickname('美食家2'); perform public.set_nickname('가나'); perform public.set_nickname('열다섯글자를꽉채운닉네임입니다');
  assert char_length((select nickname from public.profiles where id=auth.uid())) = 15, '15 chars ok';
  raise notice 'OK nickname: Korean, English+space+digits, Chinese, 2 and 15 chars accepted';
  perform public.set_nickname('맛집왕');
end $$;
-- user 2 cannot touch user 1; custom flag is per user
select set_config('request.jwt.claims','{"sub":"22222222-0000-4000-8000-000000000002","role":"authenticated"}',false);
select (public.set_nickname('맛집왕')).id::text like '22222222%' as duplicate_nicknames_allowed;
do $$ begin
  assert (select count(*) from public.profiles)=1, 'user 2 sees only own profile';
  assert (select nickname from public.profiles)='맛집왕' and (select nickname_is_custom from public.profiles);
  raise notice 'OK: nicknames are not unique; each user only sees/changes own profile';
end $$;
reset role;
do $$ begin
  assert (select nickname_is_custom from public.profiles where id='11111111-0000-4000-8000-000000000001');
  assert (select not nickname_is_custom from public.profiles where id='33333333-0000-4000-8000-000000000003'), 'user 3 untouched';
end $$;

-- custom nickname survives provider metadata changes / re-login style writes
update auth.users set raw_user_meta_data='{"name":"Kakao Renamed"}' where id='11111111-0000-4000-8000-000000000001';
set role authenticated; select set_config('request.jwt.claims','{"sub":"11111111-0000-4000-8000-000000000001","role":"authenticated"}',false);
insert into public.profiles (id, nickname) values ('11111111-0000-4000-8000-000000000001','Kakao Renamed') on conflict (id) do nothing; -- what loadOrCreate does
do $$ begin assert (select nickname from public.profiles)='맛집왕' and (select nickname_is_custom from public.profiles); raise notice 'OK: re-login/provider rename never overwrites a custom nickname'; end $$;

-- ===== companions via the new RPC (as user 1) =====
select (public.save_user_preferences(null,'max',10000,'drive',15,'{solo,friends_2_3,professor,solo}','{japanese}','{light}',true)).onboarding_completed as saved_multi;
do $$ begin
  assert (select companion_types from public.user_preferences) = array['friends_2_3','professor','solo'], 'deduped + ordered';
  assert (select companion_type from public.user_preferences) is null, 'legacy column nulled for multi';
  assert (select budget_type||budget_amount_krw||travel_mode||max_travel_minutes||prioritize_untried::text from public.user_preferences) = 'max10000drive15true', 'other fields saved';
  raise notice 'OK companions: multi-select saved (deduped), other fields intact';
  begin perform public.save_user_preferences(null,'max',9000,'walk',5,'{solo,martian}','{}','{}',false); raise exception 'x';
  exception when check_violation then null; end;
  assert (select budget_amount_krw from public.user_preferences) = 10000, 'invalid companion rolled everything back';
  assert (select onboarding_completed from public.profiles);
  raise notice 'OK atomicity: invalid companion value rejected, nothing changed';
end $$;
select (public.save_user_preferences(null,'any',null,'any',null,'{solo}','{}','{}',false)).onboarding_completed;
do $$ begin assert (select companion_type from public.user_preferences)='solo'; end $$;
select (public.save_user_preferences(null,'any',null,'any',null,'{}','{}','{}',false)).onboarding_completed;
do $$ begin assert (select companion_types from public.user_preferences)='{}'; raise notice 'OK companions: zero selections allowed, single keeps legacy column in sync'; end $$;
reset role;
-- anon
set role anon; select set_config('request.jwt.claims','{"role":"anon"}',false);
do $$ begin
  begin perform public.set_nickname('hacker'); raise exception 'x'; exception when insufficient_privilege then raise notice 'OK anon: set_nickname denied'; end;
end $$;
reset role;
