-- Student contributions: restaurant photos in PRIVATE storage, safe deletion of
-- one's own pending photo, one open report per user and target.
--
-- Additive and idempotent. Requires 20261109000100 (has_role, reports, admin
-- functions) and 20261110000100 (user_contributions, submit_contribution).
--
-- Security model
--   * An unapproved photo lives in the PRIVATE bucket `contribution-photos`, in
--     the uploader's own folder (`<user id>/<file>`). Only that user, moderators
--     and admins can read it; nobody else, and never the public.
--   * A student cannot make a photo public: publishing is an admin action that
--     copies the picture into the public `restaurant-images` bucket.
--   * submit_contribution() validates on the server that the file is in the
--     caller's own folder (and, where Storage exists, that it was uploaded).
--   * A student can withdraw only their OWN contribution, and only while it is
--     still pending.

do $$ begin
  if to_regclass('public.user_contributions') is null
     or to_regprocedure('public.has_role(text)') is null
     or to_regclass('public.reports') is null then
    raise exception 'Apply 20261109000100 and 20261110000100 first.';
  end if;
end $$;

-- A restaurant photo is a contribution kind of its own (a menu photo keeps
-- feeding the "메뉴 사진 수집가" mission; a restaurant photo does not).
alter table public.user_contributions drop constraint if exists user_contributions_kind_check;
alter table public.user_contributions add constraint user_contributions_kind_check
  check (kind in ('menu_photo', 'restaurant_photo', 'info_correction'));

create or replace function public.submit_contribution(p_kind text, p_place text, p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_id   uuid;
  v_path text := p_payload ->> 'path';
  v_cap  text := p_payload ->> 'caption';
begin
  if v_user is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if p_kind not in ('menu_photo', 'restaurant_photo', 'info_correction') then
    raise exception 'unknown contribution kind' using errcode = '22023';
  end if;
  if p_place is null or btrim(p_place) = '' or char_length(p_place) > 64 then
    raise exception 'place is required' using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' or octet_length(p_payload::text) > 4000 then
    raise exception 'invalid payload' using errcode = '22023';
  end if;
  if p_kind in ('menu_photo', 'restaurant_photo') then
    -- the picture must be the caller's own upload in the private bucket
    if v_path is null or v_path !~ ('^' || v_user::text || '/[A-Za-z0-9._-]+$') then
      raise exception 'photo must be uploaded to your own folder first' using errcode = '22023';
    end if;
    if to_regclass('storage.objects') is not null
       and not exists (select 1 from storage.objects o where o.bucket_id = 'contribution-photos' and o.name = v_path) then
      raise exception 'uploaded photo not found' using errcode = 'P0002';
    end if;
    -- the student agrees that the photo may be shown in the app (ownership / licence)
    if coalesce(p_payload ->> 'consent', '') <> 'true' then
      raise exception 'consent to publish is required' using errcode = '22023';
    end if;
    if v_cap is not null and char_length(v_cap) > 100 then
      raise exception 'caption too long' using errcode = '22023';
    end if;
  end if;
  if (select count(*) from public.user_contributions where user_id = v_user and status = 'pending') >= 20 then
    raise exception 'too many pending contributions' using errcode = '54000';
  end if;
  if exists (select 1 from public.user_contributions c
              where c.user_id = v_user and c.kind = p_kind and c.kakao_place_id = btrim(p_place)
                and c.payload = p_payload and c.status <> 'rejected') then
    raise exception 'duplicate contribution' using errcode = '23505';
  end if;
  insert into public.user_contributions (user_id, kind, kakao_place_id, payload)
  values (v_user, p_kind, btrim(p_place), p_payload)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.submit_contribution(text, text, jsonb) from public, anon;
grant execute on function public.submit_contribution(text, text, jsonb) to authenticated;

-- Withdraw one's own PENDING contribution. Returns the private file path so the
-- app can remove the picture too. Reviewed (approved / rejected) ones stay.
create or replace function public.delete_my_contribution(p_id uuid)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_path text;
begin
  if v_user is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  delete from public.user_contributions
   where id = p_id and user_id = v_user and status = 'pending'
  returning payload ->> 'path' into v_path;
  if not found then
    raise exception 'only your own pending contribution can be withdrawn' using errcode = 'P0002';
  end if;
  return coalesce(v_path, '');
end $$;
revoke all on function public.delete_my_contribution(uuid) from public, anon;
grant execute on function public.delete_my_contribution(uuid) to authenticated;

-- One OPEN report per user and target (re-reporting the same thing changes nothing).
do $$ begin
  create unique index if not exists reports_one_open_per_user_target
    on public.reports (reporter_id, target_type, target_id) where status = 'open';
exception when unique_violation then
  raise notice 'duplicate open reports exist; the unique index was skipped. Resolve them and run this migration again.';
end $$;

-- Private bucket for unapproved photos (only where Supabase Storage exists).
do $$ begin
  if to_regclass('storage.objects') is not null and to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('contribution-photos', 'contribution-photos', false, 5242880,
            array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update
      set public = false, file_size_limit = 5242880,
          allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

    -- A student writes and removes only inside their own folder.
    drop policy if exists "contribution-photos: own insert" on storage.objects;
    create policy "contribution-photos: own insert" on storage.objects
      for insert to authenticated
      with check (bucket_id = 'contribution-photos'
                  and (storage.foldername(name))[1] = (select auth.uid())::text);
    -- Read: the owner, and staff who review photos. Never anon.
    drop policy if exists "contribution-photos: own or staff read" on storage.objects;
    create policy "contribution-photos: own or staff read" on storage.objects
      for select to authenticated
      using (bucket_id = 'contribution-photos'
             and ((storage.foldername(name))[1] = (select auth.uid())::text
                  or (select public.has_role('moderator'))));
    drop policy if exists "contribution-photos: own delete" on storage.objects;
    create policy "contribution-photos: own delete" on storage.objects
      for delete to authenticated
      using (bucket_id = 'contribution-photos'
             and ((storage.foldername(name))[1] = (select auth.uid())::text
                  or (select public.has_role('moderator'))));
  end if;
end $$;
