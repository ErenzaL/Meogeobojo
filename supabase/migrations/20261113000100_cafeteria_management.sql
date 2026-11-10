-- Cafeteria management: an active / inactive / archived state for each campus
-- cafeteria, an optional operating note, audit trails, and a guard against
-- registering the same cafeteria twice.
--
-- Additive and idempotent. Existing cafeterias become 'active', so nothing
-- changes for students until an admin deactivates or archives one.
-- Requires 20261101000600 (campus_cafeterias, cafeteria_meals),
-- 20261109000100 (has_role, audit_row_change) and 20261111000100 (meal drafts).
--
--   * The public (and every ordinary user) sees only ACTIVE cafeterias, and the
--     meals of active cafeterias; inactive / archived ones and drafts stay hidden.
--   * Admins keep full read/write through the existing "admin write" policies.
--   * Archiving never deletes meals: it only hides the cafeteria, so history
--     survives and the cafeteria can be restored.

do $$ begin
  if to_regclass('public.campus_cafeterias') is null
     or to_regclass('public.cafeteria_meals') is null
     or to_regprocedure('public.has_role(text)') is null
     or to_regprocedure('public.audit_row_change()') is null then
    raise exception 'Apply 20261101000600 and 20261109000100 first.';
  end if;
end $$;

alter table public.campus_cafeterias
  add column if not exists status text not null default 'active',
  add column if not exists operating_note text;
alter table public.campus_cafeterias drop constraint if exists campus_cafeterias_status_check;
alter table public.campus_cafeterias add constraint campus_cafeterias_status_check
  check (status in ('active', 'inactive', 'archived'));
alter table public.campus_cafeterias drop constraint if exists campus_cafeterias_operating_note_check;
alter table public.campus_cafeterias add constraint campus_cafeterias_operating_note_check
  check (operating_note is null or (btrim(operating_note) <> '' and char_length(operating_note) <= 300));
create index if not exists campus_cafeterias_status_idx on public.campus_cafeterias (university_id, status, sort_order);

-- Students: only active cafeterias, and only meals that are not drafts of an active cafeteria.
drop policy if exists "campus_cafeterias: public read" on public.campus_cafeterias;
create policy "campus_cafeterias: public read" on public.campus_cafeterias
  for select to anon, authenticated using (status = 'active');

drop policy if exists "cafeteria_meals: public read" on public.cafeteria_meals;
create policy "cafeteria_meals: public read" on public.cafeteria_meals
  for select to anon, authenticated using (
    status <> 'draft'
    and exists (select 1 from public.campus_cafeterias c
                 where c.id = cafeteria_id and c.status = 'active'));

-- Who changed what (the meal row keeps the full old and new values).
drop trigger if exists campus_cafeterias_audit on public.campus_cafeterias;
create trigger campus_cafeterias_audit after insert or update or delete on public.campus_cafeterias
  for each row execute function public.audit_row_change();
drop trigger if exists cafeteria_meals_audit on public.cafeteria_meals;
create trigger cafeteria_meals_audit after insert or update or delete on public.cafeteria_meals
  for each row execute function public.audit_row_change();

-- One cafeteria name per university (live ones). Created only when the data
-- already satisfies it, so applying this can never fail on existing rows.
do $$ begin
  create unique index if not exists campus_cafeterias_unique_name
    on public.campus_cafeterias (university_id, lower(btrim(name_ko)))
    where name_ko is not null and status <> 'archived';
exception when unique_violation then
  raise notice 'campus_cafeterias has duplicate names; the unique index was skipped. Rename or archive the duplicates and run this migration again.';
end $$;
