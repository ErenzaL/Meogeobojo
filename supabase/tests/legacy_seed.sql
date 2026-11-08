-- Data as it exists on the hosted project BEFORE 20261101000500:
-- old RPC signature (single companion), provider-copied nickname.
\set ON_ERROR_STOP on
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-0000-4000-8000-000000000001','kakao@example.test','{"name":"에렌자"}'),
  ('22222222-0000-4000-8000-000000000002','solo@example.test','{}'),
  ('33333333-0000-4000-8000-000000000003','none@example.test','{}');
set role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-0000-4000-8000-000000000001","role":"authenticated"}',false);
select public.save_user_preferences(null,'min',12000,'walk',10,'friends_2_3','{korean}','{spicy}',true) is not null as legacy_saved_1;
select set_config('request.jwt.claims','{"sub":"22222222-0000-4000-8000-000000000002","role":"authenticated"}',false);
select public.save_user_preferences(null,'any',null,'any',null,'solo','{}','{}',false) is not null as legacy_saved_2;
select set_config('request.jwt.claims','{"sub":"33333333-0000-4000-8000-000000000003","role":"authenticated"}',false);
select public.save_user_preferences(null,'any',null,'any',null,null,'{}','{}',false) is not null as legacy_saved_3;
reset role;
