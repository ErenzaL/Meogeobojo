# 학식: university-based weekly cafeteria management

Status: **built and tested locally; nothing is applied or deployed.** Needs migration `20261118000100` (and, for the fastest
take-down sync, `20261117000100`).

## 1. Audit: what already existed (and was reused)
| Area | Found | Used as is / changed |
|---|---|---|
| Tables | `campus_cafeterias` (university_id, kind, names, location, status, operating_note), `cafeteria_meals` (one row per cafeteria × date × meal × **option**, `badge`, `extra` jsonb, `status`) | reused; `cafeteria_meals` **unchanged** |
| 천원의 아침밥 | `badge = '천원의 아침밥'`, breakfast only, needs `source_url` (DB + Admin rules) | reused: a per-option programme, never a fourth meal period |
| Publishing engine | `content_drafts / versions / jobs`, `cms_*` RPCs, guards, pg_cron runner | reused: a new entity type `cafeteria_week` (wraps the functions, no copy) |
| Admin | single-meal editor (`MealEditor`), cafeteria modal, week list | replaced by the weekly grid; the cafeteria modal extended |
| Importer | Python CLI (`supabase/cafeteria/import_cafeteria_csv.py`) | kept; the browser importer is new and server side |
| Flutter | `campus_meals` (university-scoped list, week, day, meal tabs, options, programme card, empty states, pull-to-refresh) | extended, not rebuilt |
| Realtime | `cafeteria_meals` / `campus_cafeterias` already synced; take-downs need the `content_sync` signal | reused (fixed in the earlier sync work) |
| Storage | `restaurant-images` bucket | reused for the cafeteria photo |

## 2. Data model (migration `20261118000100_cafeteria_weekly.sql`, additive, idempotent, no data changed)
* `campus_cafeterias`: `meal_periods text[]` (default all three), `operating_days smallint[]` (default Mon-Fri), `photo_url/photo_path`. Nothing is assumed: a cafeteria may serve only lunch, or open on Saturday.
* `cafeteria_weeks` (cafeteria, Monday) = the **publishable unit**. CMS entity `cafeteria_week`: its snapshot is *all menus of that week* (`{meals:[…]}`), so draft / preview / publish / schedule / unpublish / rollback / history act on the whole week **atomically**, with the existing version history, audit log and pg_cron runner.
* `cms_publish_week_days(week, revision, days[], reason)`: atomic publish of **selected days**; the other days stay in the draft (rebased).
* `cafeteria_import(rows, mode, dry_run, create_missing, allow_multi_university)`: validates, resolves, de-duplicates and writes **drafts only**.
* A menu removed from a published week is **hidden (status draft), never deleted**; a blank cell changes nothing.
* Original publishing functions are renamed `*_v1` and wrapped; other entity types behave exactly as before (the full earlier suites still pass).

## 3. Admin → 학식
University selector → search + status filter → cafeteria cards (meals served, weekend, status, draft / scheduled / failed weeks) →
**주간 메뉴 · 식당 정보 · 게시 이력** tabs. Weekly tab: Monday-Friday × 조식/중식/석식 grid (weekend on request or if the cafeteria opens then),
several options per cell, 천원의 아침밥 per breakfast date, **요일 복사 · 다른 주 복사 · 공통 운영 시간 · 일괄 수정**, 초안 저장 (**one** call for the whole week),
미리보기 (week table + exact diff), 지금 게시, **선택한 날만 게시**, 예약 게시, 예약 취소, 게시 중단, 이전 버전 복원. New cafeterias start **inactive**.
Clearing a published menu, "closed", copy-overwrite and moving a cafeteria to another university each ask for confirmation.

## 4. CSV import
Required: `university,cafeteria_name,date,meal_type,menu_name,price,serving_time`.
Optional: `meal_option, program, description, notes, menu_items (a|b|c), location, source_url, university_id, cafeteria_id, cafeteria_type`.
Korean headers (대학교, 식당, 날짜, 식사, 메뉴, 가격, 이용시간 …), `조식/중식/석식`, `YYYY-MM-DD` or `YYYY.MM.DD`, `5,500원`, `11:30~13:30` are accepted. UTF-8 with or without BOM.
Example: `supabase/cafeteria/weekly_import_template.csv` (also the Admin's 예시 파일 내려받기).

1. 학식 → **CSV 일괄 등록** → choose the file. The server previews it (dry run): per-row result, errors, warnings, new cafeterias, universities touched.
2. Choose the mode: **create-only** (default), **update-only**, **upsert**. Tick "없는 식당은 새로 만들기" only if intended (created inactive); tick the multi-university confirmation if the file spans universities.
3. **초안으로 가져오기**: rows with errors are skipped and listed; everything else lands in the week **drafts**. Retrying the same file changes nothing.
4. Open each cafeteria's week, preview, then publish (whole week or selected days).

A row = one cafeteria, one date, one meal, one option; two rows with the same four keys are a duplicate (refused, never overwritten). 천원의 아침밥 (`program`) needs breakfast and `source_url`.

## 5. Flutter (Mobile and Web run the same code)
University → its cafeterias only → cafeteria picker → week → day → meal tabs (only the meals served) → option cards with price, hours, photo, description,
notice, **품절**; the 천원의 아침밥 card appears **only on a breakfast marked for that date**; weekend cells only for a cafeteria that opens then.
Empty states: nothing registered / closed / no menu / failed load with retry. Never shows drafts, inactive or archived cafeterias (RLS).

## 6. Synchronisation
Insert / update / delete / unpublish and an empty server answer all replace what is on screen; an outage (failed read) keeps the last answer.
Refresh also on app resume, on a Realtime reconnect, on switching university, on returning to 학식 (cache bypass) and by pull-to-refresh; a burst of changes is one reload.
Take-downs reach running apps through the `content_sync` signal (`20261117000100`); without it within the 60 s foreground refresh.

## 7. Tests
Admin 305 (weekly grid, tools, CSV logic and dialog, cafeteria form, publishing), Flutter 712 (+30 weekly/sync, 5 days × 3 meals, options, programme per date,
university separation, INSERT/UPDATE/DELETE/unpublish, stale-state clearing, reconnect, resume, return, pull-to-refresh), SQL 190 (+26: weekly publish, selected days,
atomicity with a poisoned row, scheduler, rollback, import validation, idempotence, modes, multi-university, permissions, student visibility, preservation).

## 8. Deployment (each step needs approval; nothing here has been run)
1. Review the PR. Merging to `main` redeploys Render Admin and Flutter Web. The Admin works **before** the migration (a notice explains what is missing; the old single-meal data is untouched).
2. Apply `20261117000100_content_sync_signal.sql` then `20261118000100_cafeteria_weekly.sql` (SQL editor, each once; re-running is harmless).
3. `python3 scripts/verify_production.py` (all migration lines OK) and re-run `scripts/prod_readonly_checks.sql` (no FAIL; baseline counts not lower).
4. Admin → 학식: pick a university, add a cafeteria, fill a week, preview, 초안 저장, 지금 게시 (or 예약), then open the Flutter app/web and pull to refresh.
5. Mobile apps need a new build for the Flutter changes; published menus themselves never need a rebuild.
Rollback: 게시 이력 → 이전 버전 복원 (whole week), 게시 중단, 예약 취소; code → previous Render deploy. The migration is additive (the extra columns/tables can stay).

## 9. End-to-end checklist
- [ ] two universities, two cafeterias in one; the app shows only the chosen university's cafeterias
- [ ] fill Mon-Fri × 3 meals in one session → **one** save → app shows nothing yet
- [ ] preview shows five days; publish the week → app shows it after pull-to-refresh / live
- [ ] change Tuesday lunch and Thursday dinner → publish only Tuesday → only Tuesday changes
- [ ] 천원의 아침밥 on one date → only that date is labelled
- [ ] schedule a week → app unchanged → after the time (browser closed) it appears
- [ ] unpublish the week → app clears (no restart); roll back → it returns
- [ ] CSV: example file → preview → drafts → publish; same file again → "변경 없음"; a bad row is listed, not imported
- [ ] disable a cafeteria → it disappears from the app
