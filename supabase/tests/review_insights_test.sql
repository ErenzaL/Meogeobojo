\set ON_ERROR_STOP on
\pset pager off
-- Review insights (migration 20261124000100, applied twice by run_local.sh): everyone reads the visible rows, only
-- moderators and up see hidden ones, only admins write, and the checks keep the rows in shape.

insert into auth.users (id, email) values
  ('a1000000-0000-4000-8000-0000000000a1', 'ri-user@example.org'),
  ('a1000000-0000-4000-8000-0000000000b1', 'ri-mod@example.org'),
  ('a1000000-0000-4000-8000-0000000000c1', 'ri-admin@example.org');
insert into public.admin_roles (user_id, role) values
  ('a1000000-0000-4000-8000-0000000000b1', 'moderator'),
  ('a1000000-0000-4000-8000-0000000000c1', 'admin');

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$ begin
  insert into public.restaurant_review_insights (kakao_place_id, review_count, avg_rating, review_signal, summary_ko, highlights, source)
    values ('153662672', 658, 4.94, 0.0098, '국물이 진해요.', array['양이 푸짐해요'], 'provided_reviews'),
           ('21752387', 349, 4.72, -0.0385, '배달이 빨라요.', '{}', 'provided_reviews');
  insert into public.restaurant_review_insights (kakao_place_id, review_count, source, visible) values ('42', 3, 'student_reviews', false);
  update public.restaurant_review_insights set review_signal = 0.01 where kakao_place_id = '153662672';
  begin insert into public.restaurant_review_insights (kakao_place_id, review_count, source, highlights) values ('43', 1, 'student_reviews', array['a','b','c','d']); raise exception 'accepted#4-highlights'; exception when check_violation then null; end;
  begin insert into public.restaurant_review_insights (kakao_place_id, review_count, source, review_signal) values ('44', 1, 'student_reviews', 2); raise exception 'accepted#R>1'; exception when check_violation then null; end;
  begin insert into public.restaurant_review_insights (kakao_place_id, review_count, source) values ('45', 1, 'web'); raise exception 'accepted#source'; exception when check_violation then null; end;
  begin insert into public.restaurant_review_insights (kakao_place_id, review_count, source) values ('x1', 1, 'student_reviews'); raise exception 'accepted#id'; exception when check_violation then null; end;
  raise notice 'OK admin: writes insights; highlights, R, source and place id are checked';
end $$;
reset role;

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  if (select count(*) from public.restaurant_review_insights) <> 2 then raise exception 'guest sees hidden rows'; end if;
  begin insert into public.restaurant_review_insights (kakao_place_id, review_count, source) values ('46', 1, 'student_reviews'); raise exception 'accepted#guest-insert'; exception when insufficient_privilege then null; end;
  raise notice 'OK guest: reads the visible insights only, cannot write';
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$ declare n int; begin
  if (select count(*) from public.restaurant_review_insights) <> 2 then raise exception 'user sees hidden rows'; end if;
  begin insert into public.restaurant_review_insights (kakao_place_id, review_count, source) values ('47', 1, 'student_reviews'); raise exception 'accepted#user-insert'; exception when insufficient_privilege then null; end;
  update public.restaurant_review_insights set review_signal = 1 where kakao_place_id = '153662672';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'user updated an insight'; end if;
  raise notice 'OK user: reads the visible insights only, cannot write';
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$ begin
  if (select count(*) from public.restaurant_review_insights) <> 3 then raise exception 'moderator does not see hidden rows'; end if;
  raise notice 'OK moderator: also sees hidden insights';
end $$;
reset role;

delete from public.restaurant_review_insights;
delete from public.admin_roles where user_id::text like 'a1000000-%';
delete from auth.users where id::text like 'a1000000-%';
