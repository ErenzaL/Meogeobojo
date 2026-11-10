\set ON_ERROR_STOP on
\pset pager off
-- Weekly cafeteria management: cafeteria details, the week as one publishable unit, draft isolation, atomic
-- and day-selective publishing, scheduling, rollback, the CSV import, authorization and what students can read.

-- earlier suites deliberately narrow the publishing constraints (upgrade-path test); apply this migration again, as a real deployment would
\ir ../migrations/20261118000100_cafeteria_weekly.sql

insert into auth.users (id, email) values
  ('f8000000-0000-4000-8000-0000000000a1', 'wk-admin@example.org'),
  ('f8000000-0000-4000-8000-0000000000b1', 'wk-mod@example.org'),
  ('f8000000-0000-4000-8000-0000000000c1', 'wk-student@example.org');
insert into public.admin_roles (user_id, role) values
  ('f8000000-0000-4000-8000-0000000000a1', 'admin'), ('f8000000-0000-4000-8000-0000000000b1', 'moderator');

-- two universities (existing seeded ones) and cafeterias
create temp table _u as select id, name_ko, row_number() over (order by name_ko) rn from public.universities order by name_ko limit 2;
grant select on _u to public;
insert into public.campus_cafeterias (id, university_id, kind, name_ko, status) values
  ('cafe0000-0000-4000-8000-000000000001', (select id from _u where rn = 1), 'student', '학생식당', 'active'),
  ('cafe0000-0000-4000-8000-000000000002', (select id from _u where rn = 1), 'dormitory', '기숙사식당', 'active'),
  ('cafe0000-0000-4000-8000-000000000003', (select id from _u where rn = 2), 'student', '학생식당', 'active'),
  ('cafe0000-0000-4000-8000-000000000004', (select id from _u where rn = 1), 'staff', '교직원식당', 'inactive');

-- ===== 1. cafeteria details: never assume every meal, weekday or photo =====
do $$ begin
  assert (select meal_periods from public.campus_cafeterias where id = 'cafe0000-0000-4000-8000-000000000001') = array['breakfast', 'lunch', 'dinner'], 'existing cafeterias keep all three meals by default';
  assert (select operating_days from public.campus_cafeterias where id = 'cafe0000-0000-4000-8000-000000000001') = array[1, 2, 3, 4, 5]::smallint[], 'Monday-Friday by default';
  update public.campus_cafeterias set meal_periods = array['lunch'], operating_days = array[1, 2, 3, 4, 5, 6]::smallint[], photo_url = 'https://x.supabase.co/p.jpg' where id = 'cafe0000-0000-4000-8000-000000000002';
  begin update public.campus_cafeterias set meal_periods = '{}' where id = 'cafe0000-0000-4000-8000-000000000002'; raise exception 'accepted#1'; exception when check_violation then null; end;
  begin update public.campus_cafeterias set meal_periods = array['brunch'] where id = 'cafe0000-0000-4000-8000-000000000002'; raise exception 'accepted#2'; exception when check_violation then null; end;
  begin update public.campus_cafeterias set operating_days = array[0, 8]::smallint[] where id = 'cafe0000-0000-4000-8000-000000000002'; raise exception 'accepted#3'; exception when check_violation then null; end;
  begin update public.campus_cafeterias set photo_url = 'http://insecure' where id = 'cafe0000-0000-4000-8000-000000000002'; raise exception 'accepted#4'; exception when check_violation then null; end;
  raise notice 'OK weekly: meal periods, weekdays and photo are validated; defaults assume nothing new';
end $$;

-- test-only access to the internal canonical sort (signed-in users rightly cannot call the helper)
create function public._wk_sort(j jsonb) returns jsonb language sql security definer as $$ select public._cafeteria_sort_meals(j) $$;
grant execute on function public._wk_sort(jsonb) to public;

-- ===== 2. the week entity =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f8000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare a uuid; b uuid; c uuid; begin
  a := public.cafeteria_week_entity('cafe0000-0000-4000-8000-000000000001', '2026-11-11');   -- a Wednesday
  b := public.cafeteria_week_entity('cafe0000-0000-4000-8000-000000000001', '2026-11-09');   -- the Monday of the same week
  c := public.cafeteria_week_entity('cafe0000-0000-4000-8000-000000000001', '2026-11-16');   -- next week
  assert a = b, 'any day of the week names the same week entity';
  assert a <> c, 'another week is another entity';
  assert (select week_start from public.cafeteria_weeks where id = a) = date '2026-11-09', 'a week always starts on Monday';
  begin perform public.cafeteria_week_entity(gen_random_uuid(), '2026-11-09'); raise exception 'accepted#5'; exception when no_data_found then null; end;
  perform set_config('test.wk', a::text, false);
  raise notice 'OK weekly: one publishable unit per (cafeteria, Monday)';
end $$;

-- ===== 3. a full Monday-Friday week as ONE draft: 15 slots, two options at lunch, 천원의 아침밥 on one date only =====
do $$ declare w uuid := current_setting('test.wk')::uuid; meals jsonb := '[]'; d date; t text; s jsonb; r jsonb; begin
  foreach d in array array['2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13']::date[] loop
    foreach t in array array['breakfast', 'lunch', 'dinner'] loop
      s := jsonb_build_object('date', d::text, 'meal_type', t, 'option_name', '', 'option_order', 0,
             'menu_items', jsonb_build_array(jsonb_build_object('name_ko', t || ' 메뉴 ' || d::text, 'kind', 'main')),
             'price_krw', case t when 'breakfast' then 3000 when 'lunch' then 5500 else 6000 end, 'start_time', case t when 'breakfast' then '08:00' when 'lunch' then '11:30' else '17:00' end,
             'end_time', case t when 'breakfast' then '09:30' when 'lunch' then '13:30' else '19:00' end,
             'status', 'published', 'badge', null, 'source_url', null, 'verified_at', '2026-11-09T00:00:00+09:00', 'extra', '{}'::jsonb);
      meals := meals || jsonb_build_array(s);
    end loop;
  end loop;
  -- 천원의 아침밥 only on Monday (with an official source); the other four breakfasts are ordinary
  meals := jsonb_set(meals, '{0}', (meals -> 0) || '{"badge":"천원의 아침밥","price_krw":1000,"source_url":"https://example.org/1000won"}');
  -- a second lunch option on Tuesday with its own price
  meals := meals || jsonb_build_array(jsonb_build_object('date', '2026-11-10', 'meal_type', 'lunch', 'option_name', 'B코너', 'option_order', 1,
             'menu_items', '[{"name_ko":"돈까스","kind":"main"}]'::jsonb, 'price_krw', 7000, 'start_time', '11:30', 'end_time', '13:30', 'status', 'published',
             'badge', null, 'source_url', null, 'verified_at', '2026-11-09T00:00:00+09:00', 'extra', '{"description":"B 메뉴"}'::jsonb));
  assert jsonb_array_length(meals) = 16, '15 slots + one extra option';
  meals := public._wk_sort(meals);
  r := public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', meals), 0);
  assert (r ->> 'revision')::int = 1, 'the whole week is saved in ONE call';
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 0, 'a draft week writes no live menu';
  perform set_config('test.meals', meals::text, false);
  raise notice 'OK weekly: 5 days x 3 meals (+ a second option) saved as one draft; nothing live';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals) = 0, 'students see no draft menus';
  assert (select count(*) from public.campus_cafeterias where status <> 'active') = 0, 'students never see inactive cafeterias';
  raise notice 'OK weekly: draft isolation (students read nothing)';
end $$;
reset role;

-- ===== 4. validation =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f8000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare w uuid := current_setting('test.wk')::uuid; good jsonb := current_setting('test.meals')::jsonb; m jsonb; begin
  m := good -> 3;   -- a Tuesday breakfast
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"date":"2026-11-23"}')), 1); raise exception 'accepted#v1'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m, m)), 1); raise exception 'accepted#v2'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"meal_type":"brunch"}')), 1); raise exception 'accepted#v3'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"menu_items":[]}')), 1); raise exception 'accepted#v4'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"price_krw":-5}')), 1); raise exception 'accepted#v5'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"start_time":"10:00","end_time":"09:00"}')), 1); raise exception 'accepted#v6'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"date":"2026-11-10","meal_type":"lunch","badge":"천원의 아침밥","source_url":"https://e.org"}')), 1); raise exception 'accepted#v7'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"badge":"천원의 아침밥","source_url":null}')), 1); raise exception 'accepted#v8'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"evil":1}')), 1); raise exception 'accepted#v9'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_save_draft('cafeteria_week', w, '{"meals":"x"}', 1); raise exception 'accepted#v10'; exception when invalid_parameter_value then null; end;
  -- closed / no menu need no items; a blank menu is NOT silently published
  perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', jsonb_build_array(m || '{"status":"closed","menu_items":[]}')), 1);
  perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', current_setting('test.meals')::jsonb), 2);
  raise notice 'OK weekly: dates, duplicates, meal types, empty menus, prices, times, the 천원의 아침밥 rules and unknown fields are refused';
end $$;

-- ===== 5. publish the entire week atomically =====
do $$ declare w uuid := current_setting('test.wk')::uuid; v int; begin
  v := public.cms_publish('cafeteria_week', w, 3, '11월 2주차 식단');
  assert v = 1, 'version 1';
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001' and status = 'published') = 16, 'all 16 menus are live together';
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001' and meal_type = 'lunch' and meal_date = '2026-11-10') = 2, 'two options on one date coexist';
  assert (select price_krw from public.cafeteria_meals where meal_date = '2026-11-09' and meal_type = 'breakfast' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 1000
     and (select count(*) from public.cafeteria_meals where badge = '천원의 아침밥' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 1, '천원의 아침밥 is on that one date only';
  assert not exists (select 1 from public.content_drafts where entity_type = 'cafeteria_week' and entity_id = w), 'the draft is consumed';
  raise notice 'OK weekly: the whole week is published in one atomic step as version 1';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals) = 16, 'students now see the published week';
  assert (select count(*) from public.cafeteria_meals m join public.campus_cafeterias c on c.id = m.cafeteria_id where c.university_id = (select id from _u where rn = 2)) = 0, 'nothing leaks to the other university';
  raise notice 'OK weekly: students see exactly the published week; the other university stays empty';
end $$;
reset role;

-- ===== 6. blank cells never erase; removing is explicit; a removed menu is hidden, not deleted =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f8000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare w uuid := current_setting('test.wk')::uuid; live jsonb; d jsonb; v int; begin
  live := public.cms_state('cafeteria_week', w) -> 'live';
  assert jsonb_array_length(live -> 'meals') = 16, 'live snapshot holds the published week';
  -- remove Wednesday dinner explicitly (it is simply left out of the new draft)
  d := jsonb_build_object('meals', (select jsonb_agg(e) from jsonb_array_elements(live -> 'meals') e where not (e ->> 'date' = '2026-11-11' and e ->> 'meal_type' = 'dinner')));
  perform public.cms_save_draft('cafeteria_week', w, d, 0);
  v := public.cms_publish('cafeteria_week', w, 1, '수요일 석식 제거');
  assert (select count(*) from public.cafeteria_meals where meal_date = '2026-11-11' and meal_type = 'dinner') = 1, 'the row still exists (not deleted)';
  assert (select status from public.cafeteria_meals where meal_date = '2026-11-11' and meal_type = 'dinner' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 'draft', 'it is only hidden';
  assert jsonb_array_length((public.cms_state('cafeteria_week', w) -> 'live') -> 'meals') = 15, 'the live snapshot no longer lists it';
  -- bringing it back revives the same row
  perform public.cms_save_draft('cafeteria_week', w, live, 0);
  v := public.cms_publish('cafeteria_week', w, 1, '다시 게시');
  assert (select status from public.cafeteria_meals where meal_date = '2026-11-11' and meal_type = 'dinner' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 'published', 'revived';
  raise notice 'OK weekly: removing is explicit and non-destructive; re-adding revives the menu';
end $$;

-- ===== 7. day-selective publishing =====
do $$ declare w uuid := current_setting('test.wk')::uuid; live jsonb; d jsonb; v int; e jsonb; arr jsonb := '[]'; rev int; begin
  live := public.cms_state('cafeteria_week', w) -> 'live';
  -- change prices on Monday lunch, Tuesday lunch and Thursday dinner in ONE draft
  for e in select * from jsonb_array_elements(live -> 'meals') loop
    if (e ->> 'date' = '2026-11-09' and e ->> 'meal_type' = 'lunch') then e := e || '{"price_krw":5600}'; end if;
    if (e ->> 'date' = '2026-11-10' and e ->> 'meal_type' = 'lunch' and e ->> 'option_name' = '') then e := e || '{"price_krw":5700}'; end if;
    if (e ->> 'date' = '2026-11-12' and e ->> 'meal_type' = 'dinner') then e := e || '{"price_krw":6100}'; end if;
    arr := arr || jsonb_build_array(e);
  end loop;
  perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', arr), 0);
  begin perform public.cms_publish_week_days(w, 1, array['2026-11-23']::date[], 'x'); raise exception 'accepted#d1'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_publish_week_days(w, 1, '{}'::date[], 'x'); raise exception 'accepted#d2'; exception when invalid_parameter_value then null; end;
  begin perform public.cms_publish_week_days(w, 9, array['2026-11-09']::date[], 'x'); raise exception 'accepted#d3'; exception when serialization_failure then null; end;
  v := public.cms_publish_week_days(w, 1, array['2026-11-09', '2026-11-10']::date[], 'Monday and Tuesday only');
  assert (select price_krw from public.cafeteria_meals where meal_date = '2026-11-09' and meal_type = 'lunch' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 5600, 'Monday is live';
  assert (select price_krw from public.cafeteria_meals where meal_date = '2026-11-10' and meal_type = 'lunch' and option_name = '' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 5700, 'Tuesday is live';
  assert (select price_krw from public.cafeteria_meals where meal_date = '2026-11-12' and meal_type = 'dinner' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 6000, 'Thursday is NOT published yet';
  select revision into rev from public.content_drafts where entity_type = 'cafeteria_week' and entity_id = w;
  assert rev is not null, 'the Thursday change stays in the draft';
  assert (public.cms_state('cafeteria_week', w) -> 'draft' ->> 'stale')::boolean = false, 'and the draft is rebased on the new live version';
  v := public.cms_publish_week_days(w, rev, array['2026-11-12']::date[], 'Thursday');
  assert (select price_krw from public.cafeteria_meals where meal_date = '2026-11-12' and meal_type = 'dinner' and cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') = 6100, 'Thursday is live now';
  assert not exists (select 1 from public.content_drafts where entity_type = 'cafeteria_week' and entity_id = w), 'nothing left in the draft';
  raise notice 'OK weekly: selected days publish independently; the rest stays a rebased draft';
end $$;
reset role;

-- ===== 8. atomic: if ANY menu of the batch cannot be applied, NONE is =====
create function public._wk_poison() returns trigger language plpgsql as $$ begin if new.price_krw = 999 then raise exception 'poisoned menu'; end if; return new; end $$;
create trigger wk_poison before insert or update on public.cafeteria_meals for each row execute function public._wk_poison();
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f8000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare w uuid := current_setting('test.wk')::uuid; live jsonb; arr jsonb := '[]'; e jsonb; before_v int; n int := 0; begin
  live := public.cms_state('cafeteria_week', w) -> 'live';
  before_v := (public.cms_state('cafeteria_week', w) ->> 'live_version')::int;
  for e in select * from jsonb_array_elements(live -> 'meals') loop
    n := n + 1;
    e := e || jsonb_build_object('price_krw', case when n = 16 then 999 else 4200 end);   -- 15 good changes and one that the database refuses
    arr := arr || jsonb_build_array(e);
  end loop;
  perform public.cms_save_draft('cafeteria_week', w, jsonb_build_object('meals', arr), 0);
  begin perform public.cms_publish('cafeteria_week', w, 1, 'poisoned'); raise exception 'accepted#a1'; exception when others then
    if sqlerrm not like '%poisoned%' then raise; end if; end;
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001' and price_krw = 4200) = 0, 'not one of the 15 good changes was published';
  assert (public.cms_state('cafeteria_week', w) ->> 'live_version')::int = before_v, 'no new version was recorded';
  begin perform public.cms_publish_week_days(w, 1, array['2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13']::date[], 'poisoned days'); raise exception 'accepted#a2'; exception when others then
    if sqlerrm not like '%poisoned%' then raise; end if; end;
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001' and price_krw = 4200) = 0, 'day-selective publish is atomic too';
  perform public.cms_discard_draft('cafeteria_week', w, (select revision from public.content_drafts where entity_id = w and entity_type = 'cafeteria_week'));
  raise notice 'OK weekly: publication is all-or-nothing (whole week and selected days)';
end $$;
reset role;
drop trigger wk_poison on public.cafeteria_meals;
drop function public._wk_poison();

-- ===== 9. schedule the week (server side), weekend menus, unpublish and rollback =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f8000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare w2 uuid; j bigint; sat jsonb; begin
  w2 := public.cafeteria_week_entity('cafe0000-0000-4000-8000-000000000002', '2026-11-16');
  sat := jsonb_build_object('date', '2026-11-21', 'meal_type', 'lunch', 'option_name', '', 'option_order', 0, 'menu_items', '[{"name_ko":"토요 특식","kind":"main"}]'::jsonb,
          'price_krw', 5000, 'start_time', '12:00', 'end_time', '13:00', 'status', 'published', 'badge', null, 'source_url', null, 'verified_at', '2026-11-16T00:00:00+09:00', 'extra', '{}'::jsonb);
  perform public.cms_save_draft('cafeteria_week', w2, jsonb_build_object('meals', jsonb_build_array(sat)), 0);   -- a Saturday menu (the cafeteria operates Mon-Sat)
  j := public.cms_schedule('cafeteria_week', w2, 1, now() + interval '1 day', null, '다음 주 식단');
  perform set_config('test.wkjob', j::text, false);
  perform set_config('test.wk2', w2::text, false);
  assert not exists (select 1 from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000002'), 'a scheduled week is not live';
  raise notice 'OK weekly: a whole week (with a Saturday menu) is scheduled';
end $$;
reset role;
do $$ declare res jsonb; w2 uuid := current_setting('test.wk2')::uuid; begin
  update public.publication_jobs set run_at = now() - interval '1 minute' where id = current_setting('test.wkjob')::bigint;
  res := public.cms_run_due_jobs();
  assert (res ->> 'published')::int = 1, 'the server ran it: ' || res::text;
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000002' and meal_date = '2026-11-21' and status = 'published') = 1, 'the Saturday menu is live';
  assert (public.cms_run_due_jobs() ->> 'published')::int = 0, 'exactly once';
  raise notice 'OK weekly: the server (pg_cron runner) publishes the scheduled week exactly once';
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f8000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare w uuid := current_setting('test.wk')::uuid; v int; before_n int; begin
  v := public.cms_unpublish('cafeteria_week', w, '점검');
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001' and status <> 'draft') = 0, 'unpublish hides the whole week';
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001') >= 16, 'and deletes nothing';
  v := public.cms_rollback('cafeteria_week', w, 1, '되돌리기');
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = 'cafe0000-0000-4000-8000-000000000001' and status = 'published') = 16, 'rollback restores the first published version';
  assert (select count(*) from public.content_versions where entity_type = 'cafeteria_week' and entity_id = w) >= 5, 'every step is in the history';
  assert (select count(*) from public.cms_overview('cafeteria_week', 'cafe0000-0000-4000-8000-000000000001')) = 2, 'overview lists this cafeteria''s weeks (two were opened) and no other cafeteria''s';
  raise notice 'OK weekly: unpublish and rollback act on the whole week; history is kept';
end $$;
reset role;

-- cleanup (publish history is immutable by design: lift the guard only for this clean-up)
delete from public.publication_jobs where entity_type = 'cafeteria_week';
delete from public.content_drafts where entity_type = 'cafeteria_week';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'cafeteria_week';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.audit_log where details ->> 'mode' is not null and action = 'cafeteria_import';
delete from public.campus_cafeterias where id::text like 'cafe0000%' or name_ko in ('새 식당', '새 학생식당');
drop function public._wk_sort(jsonb);
