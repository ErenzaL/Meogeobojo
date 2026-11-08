\set ON_ERROR_STOP on
\pset pager off
insert into public.campus_cafeterias (id, university_id, kind) values
  ('c1c1c1c1-0000-4000-8000-000000000001','5c0a8f3e-0001-4a6e-9b1d-000000000001','student'),
  ('c2c2c2c2-0000-4000-8000-000000000002','5c0a8f3e-0001-4a6e-9b1d-000000000001','dormitory');

-- ===== constraints =====
do $$ declare ok boolean; begin
  -- helper: each statement must fail with check_violation
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','brunch','[{"name_ko":"x"}]',now()); raise exception 'accepted'; exception when check_violation then null; end;
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','[]',now()); raise exception 'accepted'; exception when check_violation then null; end;   -- published needs items
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','{"a":1}',now()); raise exception 'accepted'; exception when check_violation then null; end;  -- must be an array
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, price_krw, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','[{"name_ko":"x"}]',-1,now()); raise exception 'accepted'; exception when check_violation then null; end;
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, start_time, end_time, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','[{"name_ko":"x"}]','14:00','13:00',now()); raise exception 'accepted'; exception when check_violation then null; end;
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, source_url, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','[{"name_ko":"x"}]','http://insecure.example',now()); raise exception 'accepted'; exception when check_violation then null; end;
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, status, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','[]','maybe',now()); raise exception 'accepted'; exception when check_violation then null; end;
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','[{"name_ko":"x"}]'); raise exception 'accepted'; exception when not_null_violation then null; end;       -- verified_at mandatory
  begin insert into public.campus_cafeterias (university_id, kind) values ('5c0a8f3e-0001-4a6e-9b1d-000000000001','restaurant'); raise exception 'accepted'; exception when check_violation then null; end;
  begin insert into public.campus_cafeterias (university_id, kind, name_ko) values ('5c0a8f3e-0001-4a6e-9b1d-000000000001','student','   '); raise exception 'accepted'; exception when check_violation then null; end;
  raise notice 'OK constraints: meal type, status, items, price, time order, https, verified_at, kind, blank name';
end $$;

-- ===== multiple options per meal period; closed rows =====
insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, option_name, option_order, menu_items, price_krw, verified_at, source_url, status) values
  ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','',0,'[{"name_ko":"A","kind":"main"}]',5500,now(),'https://example.org/a','published'),
  ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','B',1,'[{"name_ko":"B","kind":"main"}]',6000,now(),null,'published'),
  ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','dinner','',0,'[]',null,now(),null,'closed');
update public.cafeteria_meals set price_krw = price_krw where meal_type='dinner';  -- touches updated_at
do $$ begin
  assert (select count(*) from public.cafeteria_meals where meal_type='lunch')=2, 'two lunch options coexist';
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, option_name, menu_items, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-03','lunch','B','[{"name_ko":"dup"}]',now()); raise exception 'accepted'; exception when unique_violation then null; end;
  assert (select count(*) from public.cafeteria_meals)=3, 'duplicate option rejected, nothing overwritten';
  assert (select updated_at > created_at from public.cafeteria_meals where meal_type='dinner'), 'updated_at trigger';
  raise notice 'OK options: two options per meal coexist, duplicate rejected, closed status, updated_at trigger';
end $$;

-- ===== read-only for every client role =====
set role anon; select set_config('request.jwt.claims','{"role":"anon"}',false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals)=3 and (select count(*) from public.campus_cafeterias)=2, 'anon can read';
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-04','lunch','[{"name_ko":"hack"}]',now()); raise exception 'accepted'; exception when insufficient_privilege then null; end;
  begin update public.cafeteria_meals set price_krw=1; raise exception 'accepted'; exception when insufficient_privilege then null; end;
  begin delete from public.cafeteria_meals; raise exception 'accepted'; exception when insufficient_privilege then null; end;
  begin insert into public.campus_cafeterias (university_id, kind) values ('5c0a8f3e-0001-4a6e-9b1d-000000000001','other'); raise exception 'accepted'; exception when insufficient_privilege then null; end;
  begin truncate public.cafeteria_meals; raise exception 'accepted'; exception when insufficient_privilege then null; end;
  raise notice 'OK anon: public read, no insert/update/delete/truncate on meals or cafeterias';
end $$;
reset role;
set role authenticated; select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-0000000000aa","role":"authenticated"}',false);
do $$ begin
  assert (select count(*) from public.cafeteria_meals)=3, 'signed-in can read';
  begin insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, menu_items, verified_at) values ('c1c1c1c1-0000-4000-8000-000000000001','2026-11-04','lunch','[{"name_ko":"hack"}]',now()); raise exception 'accepted'; exception when insufficient_privilege then null; end;
  begin update public.campus_cafeterias set name_ko='hack'; raise exception 'accepted'; exception when insufficient_privilege then null; end;
  begin delete from public.campus_cafeterias; raise exception 'accepted'; exception when insufficient_privilege then null; end;
  raise notice 'OK authenticated: read-only too (only administrators can change menus)';
end $$;
reset role;

-- ===== weekly query shape used by the app =====
do $$ declare n int; begin
  select count(*) into n from public.cafeteria_meals
   where cafeteria_id='c1c1c1c1-0000-4000-8000-000000000001' and meal_date between '2026-11-02' and '2026-11-08';
  assert n=3, 'weekly range query';
  raise notice 'OK weekly range query returns the week in one statement';
end $$;

-- ===== cascades =====
delete from public.campus_cafeterias where id='c1c1c1c1-0000-4000-8000-000000000001';
do $$ begin assert (select count(*) from public.cafeteria_meals)=0, 'meals cascade with cafeteria'; raise notice 'OK cascade: deleting a cafeteria removes its meals'; end $$;
delete from public.campus_cafeterias;
