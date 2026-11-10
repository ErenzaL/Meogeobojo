\set ON_ERROR_STOP on
\pset pager off
-- CSV import (server side): validation, resolution, modes, duplicates, drafts only, idempotent retry, permissions.

\ir ../migrations/20261118000100_cafeteria_weekly.sql   -- earlier suites narrow the publishing constraints on purpose

insert into auth.users (id, email) values
  ('f9100000-0000-4000-8000-0000000000a1', 'imp-admin@example.org'),
  ('f9100000-0000-4000-8000-0000000000b1', 'imp-mod@example.org');
insert into public.admin_roles (user_id, role) values
  ('f9100000-0000-4000-8000-0000000000a1', 'admin'), ('f9100000-0000-4000-8000-0000000000b1', 'moderator');
create temp table _iu as select id, name_ko, row_number() over (order by name_ko) rn from public.universities order by name_ko limit 2;
grant select on _iu to public;
insert into public.campus_cafeterias (id, university_id, kind, name_ko, status) values
  ('1a000000-0000-4000-8000-000000000001', (select id from _iu where rn = 1), 'student', '임포트 학생식당', 'active'),
  ('1a000000-0000-4000-8000-000000000002', (select id from _iu where rn = 2), 'student', '임포트 학생식당', 'active');

-- a row builder: (line, university, cafeteria, date, meal, menu, price, 'HH:MM-HH:MM', extra)
create function public._ir(line int, uni text, caf text, d text, meal text, menu text, price text, tr text, extra jsonb default '{}')
returns jsonb language sql immutable as $$
  select jsonb_build_object('line', line, 'university', uni, 'cafeteria_name', caf, 'date', d, 'meal_type', meal, 'menu_name', menu, 'price', price,
           'start_time', nullif(split_part(tr, '-', 1), ''), 'end_time', nullif(split_part(tr, '-', 2), '')) || extra
$$;
grant execute on function public._ir(int, text, text, text, text, text, text, text, jsonb) to public;
create function public._week15(uni text, caf text, extra jsonb default '{}') returns jsonb language sql stable as $$
  select jsonb_agg(public._ir(q.rn::int, uni, caf, q.d::text, q.meal, q.meal || ' ' || q.d::text, q.price::text, q.tr, extra) order by q.rn)
  from (select row_number() over (order by d, m.ord) rn, d::date d, m.meal, m.price, m.tr
          from generate_series(date '2026-11-23', date '2026-11-27', interval '1 day') d,
               (values (1, 'breakfast', 3000, '08:00-09:30'), (2, 'lunch', 5500, '11:30-13:30'), (3, 'dinner', 6000, '17:00-19:00')) m(ord, meal, price, tr)) q
$$;
grant execute on function public._week15(text, text, jsonb) to public;
create function public._imp(p_rows jsonb, p_mode text default 'upsert', p_dry boolean default true, p_create boolean default false, p_multi boolean default false)
returns jsonb language sql security invoker as $$ select public.cafeteria_import(p_rows, p_mode, p_dry, p_create, p_multi) $$;
grant execute on function public._imp(jsonb, text, boolean, boolean, boolean) to public;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f9100000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);

-- ===== 1. a full Monday-Friday week (15 rows, Korean text), preview first: nothing is written =====
do $$ declare rows jsonb; r jsonb; u1 text := (select name_ko from _iu where rn = 1); begin
  rows := public._week15(u1, '임포트 학생식당');
  r := public._imp(rows, 'upsert', true);
  assert (r -> 'summary' ->> 'created')::int = 15 and (r -> 'summary' ->> 'failed')::int = 0, 'a dry run plans 15 new menus: ' || (r -> 'summary')::text;
  assert (r ->> 'dry_run')::boolean, 'it says it was a preview';
  assert not exists (select 1 from public.content_drafts where entity_type = 'cafeteria_week'), 'a preview writes nothing';
  assert (r -> 'rows' -> 0 ->> 'status') = 'create' and (r -> 'rows' -> 0 ->> 'cafeteria') = '임포트 학생식당', 'row-level result with the Korean name';
  perform set_config('test.imp_rows', rows::text, false);
  raise notice 'OK import: a Monday-Friday week x 3 meals previews as 15 creations and writes nothing';
end $$;

-- ===== 2. apply: DRAFTS only; an admin reviews, then publishes =====
do $$ declare rows jsonb := current_setting('test.imp_rows')::jsonb; r jsonb; w uuid; d jsonb; v int; begin
  r := public._imp(rows, 'upsert', false);
  assert (r -> 'summary' ->> 'created')::int = 15 and (r -> 'summary' ->> 'weeks_changed')::int = 1, 'applied: ' || (r -> 'summary')::text;
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = '1a000000-0000-4000-8000-000000000001') = 0, 'an import never publishes';
  w := public.cafeteria_week_entity('1a000000-0000-4000-8000-000000000001', '2026-11-23');
  d := public.cms_state('cafeteria_week', w) -> 'draft';
  assert d is not null and jsonb_array_length(d -> 'data' -> 'meals') = 15, 'the 15 menus wait in the week draft';
  assert (d -> 'data' -> 'meals' -> 0 ->> 'verified_at') is not null, 'each menu carries its verification time';
  perform set_config('test.imp_week', w::text, false);
  raise notice 'OK import: applying saves the week as a draft only; nothing is published';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = '1a000000-0000-4000-8000-000000000001') = 0, 'students cannot see imported drafts';
  raise notice 'OK import: students cannot see imported drafts';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f9100000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);

-- ===== 3. retrying the same file is safe =====
do $$ declare rows jsonb := current_setting('test.imp_rows')::jsonb; r jsonb; rev1 int; rev2 int; w uuid := current_setting('test.imp_week')::uuid; begin
  select revision into rev1 from public.content_drafts where entity_id = w and entity_type = 'cafeteria_week';
  r := public._imp(rows, 'upsert', false);
  assert (r -> 'summary' ->> 'created')::int = 0 and (r -> 'summary' ->> 'unchanged')::int = 15 and (r -> 'summary' ->> 'weeks_changed')::int = 0, 'the same file again creates nothing: ' || (r -> 'summary')::text;
  select revision into rev2 from public.content_drafts where entity_id = w and entity_type = 'cafeteria_week';
  assert rev1 = rev2, 'and does not even touch the draft';
  r := public._imp(rows, 'create_only', false);
  assert (r -> 'summary' ->> 'skipped')::int = 15, 'create-only skips what already exists';
  assert (select count(*) from jsonb_array_elements(public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals')) = 15, 'still exactly 15, no duplicates';
  raise notice 'OK import: retrying the same CSV creates no duplicates and changes nothing';
end $$;

-- publish after review
do $$ declare w uuid := current_setting('test.imp_week')::uuid; rev int; v int; begin
  select revision into rev from public.content_drafts where entity_id = w and entity_type = 'cafeteria_week';
  v := public.cms_publish('cafeteria_week', w, rev, '가져온 식단 검토 완료');
  assert (select count(*) from public.cafeteria_meals where cafeteria_id = '1a000000-0000-4000-8000-000000000001' and status = 'published') = 15, 'published after review';
  raise notice 'OK import: imported drafts go live only when an admin publishes them';
end $$;

-- ===== 4. modes: update-only changes what exists and creates nothing; the live menu stays until publication =====
do $$ declare u1 text := (select name_ko from _iu where rn = 1); rows jsonb; r jsonb; w uuid := current_setting('test.imp_week')::uuid; begin
  rows := jsonb_build_array(public._ir(2, u1, '임포트 학생식당', '2026-11-23', 'lunch', 'lunch 2026-11-23', '5800', '11:30-13:30'),
                            public._ir(3, u1, '임포트 학생식당', '2026-11-28', 'lunch', '토요 특식', '5000', '12:00-13:00'));   -- the 2nd does not exist (and is a Saturday)
  r := public._imp(rows, 'update_only', false);
  assert (r -> 'rows' -> 0 ->> 'status') = 'update' and (r -> 'rows' -> 1 ->> 'status') = 'skip', 'update-only: changes the existing, skips the new: ' || (r -> 'rows')::text;
  assert (select price_krw from public.cafeteria_meals where cafeteria_id = '1a000000-0000-4000-8000-000000000001' and meal_date = '2026-11-23' and meal_type = 'lunch') = 5500, 'the live price is untouched until the draft is published';
  assert (public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals' -> 1 ->> 'price_krw')::int = 5800, 'the change sits in the draft';
  r := public._imp(rows, 'upsert', false);
  assert (r -> 'rows' -> 1 ->> 'status') = 'create', 'upsert creates the Saturday menu';
  assert (select count(*) from jsonb_array_elements(public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals') e where e ->> 'date' = '2026-11-28') = 1
     and jsonb_array_length(public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals') = 16, 'the Saturday menu joins the same Monday-based week draft (15 weekday menus + 1)';
  perform public.cms_discard_draft('cafeteria_week', w, (select revision from public.content_drafts where entity_id = w and entity_type = 'cafeteria_week'));
  raise notice 'OK import: create-only / update-only / upsert behave, existing menus are not overwritten unintentionally, weekend dates work';
end $$;

-- ===== 5. validation: every bad row is reported with a reason; good rows still go through =====
do $$ declare u1 text := (select name_ko from _iu where rn = 1); c text := '임포트 학생식당'; rows jsonb; r jsonb; s text; begin
  rows := jsonb_build_array(
    public._ir(1, u1, c, '2026-12-01', 'lunch', '정상 메뉴', '5500', '11:30-13:30'),
    public._ir(2, u1, c, '2026-13-45', 'lunch', '날짜 오류', '5500', '11:30-13:30'),
    public._ir(3, u1, c, '2026-12-01', 'brunch', '식사 오류', '5500', '11:30-13:30'),
    public._ir(4, u1, c, '2026-12-02', 'lunch', '가격 오류', '-5', '11:30-13:30'),
    public._ir(5, u1, c, '2026-12-02', 'lunch', '가격 문자', 'abc', '11:30-13:30'),
    public._ir(6, u1, c, '2026-12-03', 'lunch', '시간 오류', '5500', '14:00-13:00'),
    public._ir(7, u1, c, '2026-12-03', 'lunch', '', '5500', '11:30-13:30'),
    public._ir(8, '없는대학교', c, '2026-12-03', 'lunch', '대학 오류', '5500', '11:30-13:30'),
    public._ir(9, u1, '없는식당', '2026-12-03', 'lunch', '식당 오류', '5500', '11:30-13:30'),
    public._ir(10, u1, c, '2026-12-04', 'lunch', '천원 점심', '1000', '11:30-13:30', '{"program":"천원의 아침밥","source_url":"https://e.org"}'),
    public._ir(11, u1, c, '2026-12-04', 'breakfast', '천원 출처 없음', '1000', '08:00-09:00', '{"program":"천원의 아침밥"}'),
    public._ir(12, u1, c, '2026-12-04', 'breakfast', '알 수 없는 프로그램', '1000', '08:00-09:00', '{"program":"만원의 아침밥","source_url":"https://e.org"}'),
    public._ir(13, u1, c, '2026-12-01', 'lunch', '중복', '5500', '11:30-13:30'),
    public._ir(14, u1, c, '2026-12-05', 'dinner', '가격 비어 있음', '', '17:00-19:00'));
  r := public._imp(rows, 'upsert', true);
  assert (r -> 'summary' ->> 'created')::int = 2 and (r -> 'summary' ->> 'failed')::int = 12, 'two good rows, twelve refused: ' || (r -> 'summary')::text;
  for s in select jsonb_array_elements_text(jsonb_build_array(2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)) loop
    assert (r -> 'rows' -> (s::int - 1) ->> 'status') = 'error' and length(r -> 'rows' -> (s::int - 1) ->> 'message') > 3, 'row ' || s || ' is an error with a reason: ' || (r -> 'rows' -> (s::int - 1))::text;
  end loop;
  assert (r -> 'rows' -> 13 -> 'warnings' ->> 0) like '%가격이 비어%', 'an empty price is a warning, saved as "price unknown"';
  assert (r -> 'rows' -> 12 ->> 'message') like '%겹쳐요%', 'a duplicate inside the file is named';
  rows := rows - 1 - 1 - 1;   -- (just to be sure the array is still usable)
  -- applying keeps only the good rows and refuses the rest
  r := public._imp(jsonb_build_array(public._ir(1, u1, c, '2026-12-01', 'lunch', '정상 메뉴', '5500', '11:30-13:30'), public._ir(2, u1, c, '2026-13-45', 'lunch', '날짜 오류', '5500', '11:30-13:30')), 'upsert', false);
  assert (r -> 'summary' ->> 'created')::int = 1 and (r -> 'summary' ->> 'failed')::int = 1, 'apply: one created, one failed: ' || (r -> 'summary')::text;
  raise notice 'OK import: invalid dates, meal types, prices, times, programmes, names and duplicates are reported per row; good rows still import';
end $$;

-- ===== 6. several options for the same meal; the same option twice is a duplicate =====
do $$ declare u1 text := (select name_ko from _iu where rn = 1); c text := '임포트 학생식당'; r jsonb; w uuid; begin
  r := public._imp(jsonb_build_array(
      public._ir(1, u1, c, '2026-12-08', 'lunch', 'A 메뉴', '5500', '11:30-13:30', '{"meal_option":"A코너"}'),
      public._ir(2, u1, c, '2026-12-08', 'lunch', 'B 메뉴', '6500', '11:30-13:30', '{"meal_option":"B코너","menu_items":["밥","국"],"description":"B 설명","notes":"한정 판매"}'),
      public._ir(3, u1, c, '2026-12-08', 'lunch', 'A 메뉴 또', '5500', '11:30-13:30', '{"meal_option":"A코너"}')), 'upsert', false);
  assert (r -> 'summary' ->> 'created')::int = 2 and (r -> 'summary' ->> 'failed')::int = 1, 'two options created, the repeated one refused (never overwritten)';
  w := public.cafeteria_week_entity('1a000000-0000-4000-8000-000000000001', '2026-12-08');
  assert (select count(*) from jsonb_array_elements(public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals')) = 2, 'both options sit side by side';
  assert (public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals' -> 1 -> 'extra' ->> 'description') = 'B 설명'
     and jsonb_array_length(public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals' -> 1 -> 'menu_items') = 3, 'menu_items, description and notes are kept';
  raise notice 'OK import: multiple options for one meal coexist; each row maps to one cafeteria, date, meal and option';
end $$;

-- ===== 7. a cafeteria that does not exist is created only on explicit request, inactive =====
do $$ declare u1 text := (select name_ko from _iu where rn = 1); r jsonb; rows jsonb; begin
  rows := jsonb_build_array(public._ir(1, u1, '새 학생식당', '2026-12-15', 'lunch', '새 메뉴', '5000', '11:30-13:30', '{"cafeteria_type":"student","location":"새 건물 1층"}'));
  r := public._imp(rows, 'upsert', true, false);
  assert (r -> 'rows' -> 0 ->> 'status') = 'error', 'without "create missing" it is refused';
  r := public._imp(rows, 'upsert', true, true);
  assert (r -> 'summary' ->> 'cafeterias_created')::int = 1 and jsonb_array_length(r -> 'new_cafeterias') = 1, 'the preview names the cafeteria it would create';
  assert not exists (select 1 from public.campus_cafeterias where name_ko = '새 학생식당'), 'a preview creates nothing';
  r := public._imp(rows, 'upsert', false, true);
  assert (select status from public.campus_cafeterias where name_ko = '새 학생식당') = 'inactive', 'created INACTIVE: students see nothing until an admin enables it';
  assert (select location_description from public.campus_cafeterias where name_ko = '새 학생식당') = '새 건물 1층', 'with its location';
  r := public._imp(rows, 'upsert', false, true);
  assert (select count(*) from public.campus_cafeterias where name_ko = '새 학생식당') = 1, 'a retry does not create it twice';
  assert (r -> 'rows' -> 0 ->> 'status') = 'unchanged', 'and finds the same menu';
  raise notice 'OK import: missing cafeterias are created only on request, inactive, once';
end $$;

-- ===== 8. an import across universities needs an explicit confirmation =====
do $$ declare u1 text := (select name_ko from _iu where rn = 1); u2 text := (select name_ko from _iu where rn = 2); r jsonb; rows jsonb; begin
  rows := jsonb_build_array(public._ir(1, u1, '임포트 학생식당', '2026-12-22', 'lunch', '대학1 메뉴', '5000', '11:30-13:30'),
                            public._ir(2, u2, '임포트 학생식당', '2026-12-22', 'lunch', '대학2 메뉴', '5100', '11:30-13:30'));
  r := public._imp(rows, 'upsert', true);
  assert (r ->> 'multi_university')::boolean and jsonb_array_length(r -> 'universities') = 2, 'the preview flags the cross-university import';
  begin perform public._imp(rows, 'upsert', false, false, false); raise exception 'accepted#m1'; exception when invalid_parameter_value then null; end;
  assert not exists (select 1 from public.content_drafts d join public.cafeteria_weeks w on w.id = d.entity_id where w.week_start = '2026-12-21'), 'refused without confirmation: nothing written';
  r := public._imp(rows, 'upsert', false, false, true);
  assert (select count(*) from public.content_drafts d join public.cafeteria_weeks w on w.id = d.entity_id where w.week_start = '2026-12-21') = 2, 'confirmed: one draft per university, kept separate';
  assert (select count(distinct c.university_id) from public.cafeteria_weeks w join public.content_drafts d on d.entity_id = w.id join public.campus_cafeterias c on c.id = w.cafeteria_id where w.week_start = '2026-12-21') = 2, 'each in its own university';
  raise notice 'OK import: several universities in one file require explicit confirmation and stay separated';
end $$;

-- ===== 9. a stable id must match the university =====
do $$ declare u2 text := (select name_ko from _iu where rn = 2); r jsonb; begin
  r := public._imp(jsonb_build_array(public._ir(1, u2, 'x', '2026-12-29', 'lunch', '메뉴', '5000', '11:30-13:30', '{"cafeteria_id":"1a000000-0000-4000-8000-000000000001"}')), 'upsert', true);
  assert (r -> 'rows' -> 0 ->> 'status') = 'error' and (r -> 'rows' -> 0 ->> 'message') like '%다른 대학교%', 'a cafeteria id from another university is refused';
  r := public._imp(jsonb_build_array(public._ir(1, 'ignored name', 'ignored', '2026-12-29', 'lunch', '메뉴', '5000', '11:30-13:30',
        jsonb_build_object('university_id', (select id from _iu where rn = 1), 'cafeteria_id', '1a000000-0000-4000-8000-000000000001'))), 'upsert', true);
  assert (r -> 'rows' -> 0 ->> 'status') = 'create', 'stable ids win over names';
  begin perform public._imp('[]'::jsonb); raise exception 'accepted#i1'; exception when invalid_parameter_value then null; end;
  begin perform public._imp(jsonb_build_array(1), 'bogus'); raise exception 'accepted#i2'; exception when invalid_parameter_value then null; end;
  raise notice 'OK import: stable ids are honoured and checked; bad input is refused';
end $$;
reset role;

-- ===== 10. authorization =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f9100000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ declare rows jsonb := current_setting('test.imp_rows')::jsonb; begin
  begin perform public._imp(rows, 'upsert', true); raise exception 'accepted#p1'; exception when insufficient_privilege then null; end;
  begin perform public._imp(rows, 'upsert', false); raise exception 'accepted#p2'; exception when insufficient_privilege then null; end;
  begin perform public.cafeteria_week_entity('1a000000-0000-4000-8000-000000000001', '2026-11-23'); raise exception 'accepted#p3'; exception when insufficient_privilege then null; end;
  begin perform public.cms_publish_week_days(gen_random_uuid(), 1, array['2026-11-23']::date[], 'x'); raise exception 'accepted#p4'; exception when insufficient_privilege then null; end;
  begin insert into public.cafeteria_weeks (cafeteria_id, week_start) values ('1a000000-0000-4000-8000-000000000001', '2027-01-04'); raise exception 'accepted#p5'; exception when insufficient_privilege then null; end;
  raise notice 'OK import: moderators cannot import, open or publish weeks, or write the week table';
end $$;
reset role;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  begin perform public.cafeteria_import('[]', 'upsert', true, false, false); raise exception 'accepted#p6'; exception when insufficient_privilege then null; end;
  begin perform public.cafeteria_week_entity('1a000000-0000-4000-8000-000000000001', '2026-11-23'); raise exception 'accepted#p7'; exception when insufficient_privilege then null; end;
  begin perform count(*) from public.cafeteria_weeks; raise exception 'accepted#p8'; exception when insufficient_privilege then null; end;   -- students cannot read the week table
  raise notice 'OK import: students and anonymous callers are refused';
end $$;
reset role;

-- ===== 11. several dishes per meal: structured dishes, shared dishes, origin, labels =====
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"f9100000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare u1 text := (select name_ko from _iu where rn = 1); rows jsonb; r jsonb; w uuid; meal jsonb; begin
  rows := jsonb_build_array(public._ir(1, u1, '임포트 학생식당', '2026-12-14', 'lunch', '치즈닭갈비볶음밥', '', '',
    jsonb_build_object('dishes', '[{"name_ko":"새우튀김*타르타르","kind":"side"},{"name_ko":"참나물무침","kind":"side"},{"name_ko":"계란국","kind":"soup"},
                                   {"name_ko":"김치","kind":"kimchi","shared":true},{"name_ko":"샐러드","kind":"salad","shared":true},{"name_ko":"후식차","kind":"dessert","shared":true}]'::jsonb,
                       'origin', '쌀:국내산 / 배추김치:중국산', 'notes', '재료수급상황에 따라 변경될 수 있습니다', 'labels', '["HALAL"]'::jsonb, 'labels_verified', true)));
  r := public._imp(rows, 'upsert', false);
  assert (r -> 'summary' ->> 'created')::int = 1 and (r -> 'summary' ->> 'failed')::int = 0, 'imported: ' || (r -> 'summary')::text;
  w := (select id from public.cafeteria_weeks where cafeteria_id = '1a000000-0000-4000-8000-000000000001' and week_start = '2026-12-14');
  meal := public.cms_state('cafeteria_week', w) -> 'draft' -> 'data' -> 'meals' -> 0;
  assert jsonb_array_length(meal -> 'menu_items') = 7 and meal -> 'menu_items' -> 0 ->> 'kind' = 'main' and meal -> 'menu_items' -> 3 ->> 'kind' = 'soup', 'the main dish comes first, then the dishes in the order given';
  assert (meal -> 'menu_items' -> 4 ->> 'shared')::boolean and meal -> 'menu_items' -> 4 ->> 'kind' = 'kimchi', 'shared dishes keep their category and flag';
  assert meal -> 'extra' ->> 'origin' = '쌀:국내산 / 배추김치:중국산' and meal -> 'extra' -> 'labels' = '["HALAL"]'::jsonb, 'origin and the label are imported';
  assert not exists (select 1 from public.cafeteria_meals where cafeteria_id = '1a000000-0000-4000-8000-000000000001' and meal_date = '2026-12-14'), 'imports are drafts: nothing is live';
  assert (public._imp(rows, 'upsert', false) -> 'summary' ->> 'unchanged')::int = 1, 'the same file again is unchanged (idempotent)';
  -- a label without the confirmation, an unknown category and a blank dish are row errors, never silently dropped
  r := public._imp(jsonb_build_array(
        public._ir(2, u1, '임포트 학생식당', '2026-12-15', 'lunch', '비빔밥', '', '', '{"labels":["HALAL"]}'),
        public._ir(3, u1, '임포트 학생식당', '2026-12-15', 'dinner', '비빔밥', '', '', '{"dishes":[{"name_ko":"국","kind":"pizza"}]}'),
        public._ir(4, u1, '임포트 학생식당', '2026-12-16', 'lunch', '비빔밥', '', '', '{"dishes":[{"name_ko":"국","kind":"soup"}]}')), 'upsert', true);
  assert (r -> 'rows' -> 0 ->> 'status') = 'error' and (r -> 'rows' -> 0 ->> 'message') like '%HALAL%', 'an unconfirmed HALAL label is refused: ' || (r -> 'rows' -> 0)::text;
  assert (r -> 'rows' -> 1 ->> 'status') = 'error' and (r -> 'rows' -> 1 ->> 'message') like '%분류%', 'an unknown category is refused';
  assert (r -> 'rows' -> 2 ->> 'status') = 'create', 'the valid row is planned';
  raise notice 'OK import: structured dishes, shared dishes, origin and confirmed labels import as a draft; bad rows are reported';
end $$;
reset role;

-- cleanup
drop function public._imp(jsonb, text, boolean, boolean, boolean);
drop function public._week15(text, text, jsonb);
drop function public._ir(int, text, text, text, text, text, text, text, jsonb);
delete from public.publication_jobs where entity_type = 'cafeteria_week';
delete from public.content_drafts where entity_type = 'cafeteria_week';
alter table public.content_versions disable trigger content_versions_no_update;
delete from public.content_versions where entity_type = 'cafeteria_week';
alter table public.content_versions enable trigger content_versions_no_update;
delete from public.audit_log where action = 'cafeteria_import';
delete from public.campus_cafeterias where id::text like '1a000000%' or name_ko in ('새 학생식당', '임포트 학생식당');
