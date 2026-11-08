\set ON_ERROR_STOP on
\pset pager off
-- two accounts; the signup trigger should create their profiles
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001','a@example.test','{"name":"Alice Kakao"}'),
  ('bbbbbbbb-0000-4000-8000-000000000002','b@example.test','{}');

do $$ begin
  assert (select count(*) from public.profiles) = 2, 'trigger should create 2 profiles';
  assert (select nickname from public.profiles where id='aaaaaaaa-0000-4000-8000-000000000001') = 'Alice Kakao', 'nickname from provider metadata';
  assert (select nickname from public.profiles where id='bbbbbbbb-0000-4000-8000-000000000002') is null, 'no invented nickname for email users';
  assert (select not onboarding_completed from public.profiles limit 1), 'onboarding starts false';
  raise notice 'OK trigger: profiles created, nickname only from provider metadata';
end $$;

-- ===== anonymous / public reference data =====
set role anon; select set_config('request.jwt.claims','{"role":"anon"}',false);
do $$ begin
  assert (select count(*) from public.universities) = 7, 'anon can read universities';
  begin truncate public.universities; raise exception 'x'; exception when insufficient_privilege then null; end;
  begin insert into public.universities (name_ko) values ('x'); raise exception 'x'; exception when insufficient_privilege then null; end;
  raise notice 'OK anon: universities readable, not writable/truncatable';
end $$;
reset role;

-- ===== user A =====
set role authenticated; select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}',false);
do $$ begin
  assert (select count(*) from public.profiles) = 1, 'A sees only own profile';
  assert (select id from public.profiles) = 'aaaaaaaa-0000-4000-8000-000000000001', 'A sees A';
  raise notice 'OK RLS: A reads only own profile';
end $$;

-- A cannot read/update B
do $$ declare n int; begin
  begin
    update public.profiles set nickname='hacked' where id='bbbbbbbb-0000-4000-8000-000000000002';
    get diagnostics n = row_count; assert n = 0, 'A must not update B';
  exception when insufficient_privilege then null; -- nickname UPDATE is revoked entirely now
  end;
  update public.profiles set preferred_language='en' where id='bbbbbbbb-0000-4000-8000-000000000002';
  get diagnostics n = row_count; assert n = 0, 'A must not update B (RLS)';
  raise notice 'OK RLS: A cannot update B';
end $$;

-- A cannot insert a profile for B
do $$ begin
  begin
    insert into public.profiles (id) values ('bbbbbbbb-0000-4000-8000-000000000002');
    raise exception 'should have failed';
  exception when others then
    assert sqlerrm not like 'should have failed', 'insert for B must fail'; raise notice 'OK RLS: A cannot insert B profile (%)', left(sqlerrm,60);
  end;
end $$;

-- A cannot self-mark onboarding complete (column privilege)
do $$ begin
  begin
    update public.profiles set onboarding_completed = true where id = auth.uid();
    raise exception 'should have failed';
  exception when insufficient_privilege then raise notice 'OK: direct onboarding_completed update blocked (42501)';
  end;
end $$;

-- invalid values are rejected and nothing is written
do $$ begin
  begin
    perform public.save_user_preferences(null,'min',null,'walk',10,'{}','{korean}','{}',false);
    raise exception 'should have failed';
  exception when check_violation then raise notice 'OK: min budget without amount rejected';
  end;
  begin
    perform public.save_user_preferences(null,'any',null,'any',null,'{}','{any,korean}','{}',false);
    raise exception 'should have failed';
  exception when check_violation then raise notice 'OK: "any" cuisine exclusivity enforced in DB';
  end;
  begin
    perform public.save_user_preferences(null,'max',8000,'walk',10,'{bogus}','{}','{}',false);
    raise exception 'should have failed';
  exception when check_violation then raise notice 'OK: bad companion value rejected';
  end;
  assert (select count(*) from public.user_preferences) = 0, 'failed saves wrote nothing';
  assert (select not onboarding_completed from public.profiles), 'failed saves left onboarding false';
  raise notice 'OK atomicity: failed saves left onboarding_completed = false, no prefs';
end $$;

-- valid save
select (public.save_user_preferences('5c0a8f3e-0001-4a6e-9b1d-000000000001','min',12000,'drive',15,'{professor,solo}','{korean,cafe}','{spicy,value}',true)).onboarding_completed as onboarded_after_save;
do $$ begin
  assert (select budget_type||':'||budget_amount_krw from public.user_preferences) = 'min:12000', '12,000+ is stored as MIN';
  assert (select onboarding_completed and onboarding_completed_at is not null from public.profiles), 'onboarded + timestamp';
  assert (select selected_university_id from public.profiles) = '5c0a8f3e-0001-4a6e-9b1d-000000000001', 'university saved on profile';
  raise notice 'OK save: prefs + onboarding flag + timestamp saved together; 12,000원 이상 stored as min';
end $$;

-- re-save (edit mode) keeps flag and original timestamp
create temp table t0 as select onboarding_completed_at as ts from public.profiles;
select pg_sleep(0.05);
select (public.save_user_preferences(null,'any',null,'any',null,'{}','{any}','{}',false)).onboarding_completed;
do $$ begin
  assert (select onboarding_completed from public.profiles), 'still onboarded after edit';
  assert (select onboarding_completed_at from public.profiles) = (select ts from t0), 'timestamp preserved on edit';
  assert (select budget_type from public.user_preferences) = 'any', 'edit applied';
  raise notice 'OK edit: onboarding stays true, original completion time preserved';
end $$;

-- language sync column
update public.profiles set preferred_language='en' where id=auth.uid();
do $$ begin
  begin update public.profiles set preferred_language='fr' where id=auth.uid(); raise exception 'x';
  exception when check_violation then raise notice 'OK: preferred_language restricted to ko/en/zh-Hans'; end;
end $$;

-- ===== user B =====
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-4000-8000-000000000002","role":"authenticated"}',false);
do $$ begin
  assert (select count(*) from public.user_preferences) = 0, 'B must not see A prefs';
  assert (select count(*) from public.profiles) = 1, 'B sees only B';
  assert (select not onboarding_completed from public.profiles), 'B still needs onboarding';
  raise notice 'OK RLS: B cannot see A preferences; B still needs onboarding';
end $$;
-- B cannot write A's prefs directly
do $$ declare n int; begin
  update public.user_preferences set budget_type='max', budget_amount_krw=1 where user_id='aaaaaaaa-0000-4000-8000-000000000001';
  get diagnostics n = row_count; assert n = 0, 'B must not update A prefs';
  begin insert into public.user_preferences (user_id) values ('aaaaaaaa-0000-4000-8000-000000000001'); raise exception 'x';
  exception when others then assert sqlerrm <> 'x'; end;
  raise notice 'OK RLS: B cannot update/insert A preferences';
end $$;

-- ===== anonymous =====
reset role; set role anon; select set_config('request.jwt.claims','{"role":"anon"}',false);
do $$ begin
  begin perform count(*) from public.profiles; raise exception 'x'; exception when insufficient_privilege then raise notice 'OK anon: profiles denied'; end;
  begin perform count(*) from public.user_preferences; raise exception 'x'; exception when insufficient_privilege then raise notice 'OK anon: user_preferences denied'; end;
  begin perform public.save_user_preferences(null,'any',null,'any',null,'{}','{}','{}',false); raise exception 'x';
  exception when insufficient_privilege then raise notice 'OK anon: save_user_preferences denied'; end;
end $$;

-- authenticated but no uid claim -> function refuses
reset role; set role authenticated; select set_config('request.jwt.claims','{"role":"authenticated"}',false);
do $$ begin
  begin perform public.save_user_preferences(null,'any',null,'any',null,'{}','{}','{}',false); raise exception 'x';
  exception when sqlstate '28000' then raise notice 'OK: no auth.uid() -> not authenticated (28000)'; end;
end $$;
reset role;
-- deleting an auth user cascades
delete from auth.users where id='aaaaaaaa-0000-4000-8000-000000000001';
do $$ begin assert (select count(*) from public.profiles)=1 and (select count(*) from public.user_preferences)=0, 'cascade'; raise notice 'OK cascade on auth.users delete'; end $$;
