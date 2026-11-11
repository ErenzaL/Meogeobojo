-- =============================================================================
-- Kakao import: registering a place that is ALREADY managed writes nothing.
--
-- admin_register_kakao_places (20261111000100) answered a known place with
--   ON CONFLICT (kakao_place_id) DO UPDATE SET kakao_registered_at = coalesce(...)
-- which still UPDATEs the row. That fires restaurant_overrides_set_updated_at (the row then looks "just edited" in
-- the Admin list) and the content_sync_bump statement trigger (a live-update signal to every running app), and it
-- fills kakao_registered_at on rows an admin created by hand. Nothing a person typed is overwritten by it, but a
-- repeat import should not touch managed restaurants at all.
--
-- New behaviour (same signature, return shape, validation, limits and audit entry):
--   * NEW place   -> one restaurant_overrides row (draft) + a campus link, as before.
--   * KNOWN place -> NO write to restaurant_overrides (not even a timestamp). Only the campus link is added, and
--                    only if it is missing.
--   * Re-running the same registration changes nothing and signals nothing.
--
-- Additive: CREATE OR REPLACE of one function. Changes no data, no table, no policy. Safe to run twice.
-- Requires 20261111000100. NOT applied by the repository: apply deliberately, after review.
-- =============================================================================

create or replace function public.admin_register_kakao_places(p_university uuid, p_places jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  d        jsonb;
  v_id     text;
  v_name   text;
  v_lat    double precision;
  v_lng    double precision;
  v_group  text;
  v_rid    uuid;
  v_new    boolean;
  v_added  integer := 0;
  v_known  integer := 0;
  v_skip   integer := 0;
begin
  perform public._require_role('admin');
  if not exists (select 1 from public.universities where id = p_university) then
    raise exception 'unknown university' using errcode = 'P0002';
  end if;
  if p_places is null or jsonb_typeof(p_places) <> 'array' then
    raise exception 'places must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_places) > 500 then
    raise exception 'too many places in one registration (max 500)' using errcode = '22023';
  end if;

  for d in select * from jsonb_array_elements(p_places) loop
    v_id    := nullif(btrim(d ->> 'id'), '');
    v_name  := nullif(btrim(d ->> 'place_name'), '');
    v_group := d ->> 'category_group_code';
    -- Kakao: x = longitude, y = latitude (as text). Validated, never stored.
    begin
      v_lng := (d ->> 'x')::double precision;
      v_lat := (d ->> 'y')::double precision;
    exception when others then v_lng := null; v_lat := null;
    end;
    if v_id is null or char_length(v_id) > 40 or v_name is null
       or v_group is null or v_group not in ('FD6', 'CE7')
       or v_lat is null or v_lng is null
       or v_lat not between 33 and 39 or v_lng not between 124 and 132 then
      v_skip := v_skip + 1;
      continue;
    end if;

    -- Look first: an existing row must not be written at all.
    select o.id into v_rid from public.restaurant_overrides o where o.kakao_place_id = v_id;
    v_new := false;
    if v_rid is null then
      insert into public.restaurant_overrides (kakao_place_id, name_ko, visibility, kakao_registered_at)
      values (v_id, left(v_name, 120), 'draft', now())
      on conflict (kakao_place_id) do nothing
      returning id into v_rid;
      v_new := v_rid is not null;
      if v_rid is null then
        -- lost a race with a concurrent registration of the same place: it is known now, leave it alone
        select o.id into v_rid from public.restaurant_overrides o where o.kakao_place_id = v_id;
      end if;
    end if;

    if not exists (select 1 from public.restaurant_university_links where restaurant_id = v_rid and university_id = p_university) then
      insert into public.restaurant_university_links (restaurant_id, university_id)
      values (v_rid, p_university) on conflict do nothing;
    end if;

    if v_new then v_added := v_added + 1; else v_known := v_known + 1; end if;
  end loop;

  perform public._audit('register_kakao_places', 'restaurant_overrides', p_university::text, null,
    jsonb_build_object('added', v_added, 'already_managed', v_known, 'skipped', v_skip));
  return jsonb_build_object('added', v_added, 'already_managed', v_known, 'skipped', v_skip);
end $$;
revoke all on function public.admin_register_kakao_places(uuid, jsonb) from public, anon;
grant execute on function public.admin_register_kakao_places(uuid, jsonb) to authenticated;
