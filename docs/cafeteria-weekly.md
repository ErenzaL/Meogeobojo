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

## 3b. Real menu tables: several dishes per meal, shared dishes, origin, labels

A university menu table (e.g. the 향설1관 주간메뉴표: per day and meal a list of dishes, one shared row per meal such as 아산쌀밥/김치/샐러드, an origin
block and a footer notice) is stored as **structured data inside the existing columns**; no table was rebuilt and `cafeteria_meals` is unchanged:

| Where | What |
|---|---|
| `menu_items` (jsonb array, existing) | one object per dish: `{name_ko, kind, shared?}`; `kind` = `main` `side` `soup` `rice` `kimchi` `salad` `dessert` `drink` `other`. The first dish is the main dish, the order is the table's order. |
| `extra.origin` | 원산지 표시사항 (text, ≤ 1200 chars) |
| `extra.notice` | the footer / shared notice (≤ 1000 chars) |
| `extra.labels` + `extra.labels_verified` | dietary labels (`HALAL`, `VEGETARIAN`, `VEGAN`). The server refuses a label unless `labels_verified` is `true`, and the apps show a label only then. |

* **Shared dishes** are marked `shared: true` and are listed once per meal. The Admin tool **공통 메뉴·공지** enters the shared row of each meal
  (조식 / 중식 / 석식 separately), the origin statement and the notice for the chosen days at once; it adds a dish only to published meals that do not
  already list it, never creates a cell, and can remove exactly what it added. Nothing is typed twice.
* **Editing:** each cell has the dish text field (one dish per line, or separated by `/`, so `도시락김/미소장국` is two dishes; `*` and `·` stay in a name),
  a collapsible list with a category selector, a 공통 checkbox and ↑/↓ reordering for every dish, an origin field and a **HALAL** checkbox ("공식 인증 자료로
  확인한 경우에만"). Typing never resets a category the admin chose: a dish that is still in the text keeps its category, shared mark and order metadata;
  a new dish gets a guessed category (국/탕/찌개 → soup, 김치 → kimchi, 샐러드 → salad, …밥 → rice, 후식/차 → dessert; otherwise side), shown and editable.
* Copy day / copy week / bulk edit carry the dishes, shared marks, origin and labels along.
* **Preview and the change list** show the dishes (shared ones separately) and mark category / shared changes, so a change that only moves a dish between
  categories is visible before publishing.
* **Flutter (Web and mobile, one codebase):** the card shows the main dish, then the dishes of the day, then **함께 제공** (shared dishes and rice / kimchi /
  salad / dessert / drinks), a verified label chip, and the origin statement collapsed under "원산지 표시사항".
* **Installed older apps keep working:** they read `name_ko` and `kind`, show an unknown category as an ordinary dish and ignore `shared`, `origin` and
  `labels` (so they simply do not show them). An older Admin tab writes items without `kind`, which the server and the apps accept.
* The importer's old `menu_items` column still works (as side dishes).

## 4. CSV import
Required: `university,cafeteria_name,date,meal_type,menu_name,price,serving_time`.
Optional: `meal_option, program, description, notes, location, source_url, university_id, cafeteria_id, cafeteria_type` and the dish columns
`side_dishes` (alias `menu_items`), `soup`, `rice`, `kimchi`, `salad`, `dessert`, `shared`, plus `origin`, `labels` (`HALAL`, …) with `labels_verified` (`예`; a label
without it is a row error) and `sold_out`. Several dishes in one cell are separated by `/`, `|`, `;` or a line break. The dishes of a row are stored in the
order main (`menu_name`) → side_dishes → soup → rice → kimchi → salad → dessert → shared (flagged shared). Korean headers (반찬, 국, 밥, 김치, 샐러드, 후식, 공통,
원산지, 표시, 표시확인, 품절) work too. A real example, transcribed from the 향설1관 table: `supabase/cafeteria/examples/hyangseol1_2026-11-09.csv`
(15 meals; no HALAL label is claimed in it: confirm where the table's HALAL mark applies before adding `labels`).
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

## 10. Several cafeterias per university, and meals that are optional
A university can have any number of cafeterias (Admin → 학식 → 학식 식당 추가; no database change was needed, `campus_cafeterias` already allows it).

* **Choosing (app and web).** The 오늘의 학식 card on Home shows a picker (the same widget as the weekly page) as soon as the campus has more than one
  active cafeteria; with one there is nothing to choose and nothing is drawn. The choice is shared by Home and 이번 주 식단 (change it in either, both follow)
  and remembered on the device **per university** (`selected_cafeteria_id:<university id>`), so choosing at one campus never changes another.
  With no choice yet (or a remembered cafeteria that was removed or switched off) the first *student* cafeteria is shown, else the first one (`chooseCafeteria`).
* **Meals are optional.** 조식, 중식 and 석식 are each entered or not. Home lists only the meals that have a published menu. The weekly page offers a tab
  only for meals entered somewhere in the shown week (any status, so a meal marked "운영 안 함" still explains itself) and opens on the next meal that
  exists when the usual one for the time of day is missing (`visibleMealTypes`, `resolveMealType`). A week with nothing entered falls back to the
  cafeteria's own 운영하는 식사 setting. Nothing is required in Admin: an empty cell changes nothing and shows nothing.
* **Admin.** The new-cafeteria form puts a new cafeteria **after** the university's existing ones (표시 순서 = highest + 1), so adding a second one never
  takes the first place (the app opens on the first student cafeteria and lists them in this order). When the university already has another cafeteria
  and the name is empty, the form asks for a name: the picker shows the name, and nameless ones can only be called "학생식당 1 / 2". The weekly grid no
  longer counts "n/15칸" as if every slot were due.
* **Rollout.** Admin and web update when this is merged to `main` (Render). The phone apps need a new build. No migration; existing data is untouched.

## 11. Weekly update from a CSV, one cafeteria and one week at a time
Admin → 학식 → pick the cafeteria → 주간 메뉴 → choose the week → **CSV로 이 주 채우기**.

1. **이 주 양식 내려받기** gives `학식_<식당>_<월요일>.csv`: one row per day and per meal *this cafeteria serves* (Mon-Fri, plus the weekend if it opens then),
   with only `date` and `meal_type` filled in. The admin fills `menu_name` (required) and whatever else is known (price, `serving_time`, `side_dishes` ... the same
   columns as the page-wide importer) and uploads the file.
2. **Rows left empty are skipped**, not errors, so a meal the cafeteria does not serve that day stays out (and then does not appear in the app, see §10).
3. The importer is **scoped**: the university and cafeteria are the ones being edited, so the file needs **no** university / cafeteria columns; a name column is
   allowed but must match (any of the cafeteria's Korean / English / Chinese names), otherwise that row is refused (a wrong file cannot reach another restaurant).
   Every date must lie in the shown week (Mon-Sun); other dates are refused row by row. Rows with errors are listed and never sent; the rest can still be imported.
4. Preview (a server dry run: new / changed / unchanged per row) then **초안으로 가져오기**. Default mode is "만들고 수정하기" (upsert); the other two modes remain.
   Nothing is published: the menus land in the week's draft, the grid reloads, and the usual preview → 지금 게시 / 예약 게시 applies.
5. The button waits while the grid has unsaved edits (save or discard them first), so an import can never clash with hand edits.

It uses the existing server function `cafeteria_import` with `university_id` / `cafeteria_id` (no migration, no new permission). The page-wide
**CSV 일괄 등록** stays for files that cover several cafeterias, weeks or universities.

