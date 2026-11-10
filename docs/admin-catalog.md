# Shared restaurant catalog, photos, menus and cafeteria (admin ↔ app)

## Why the admin list said "총 0개" (audit result)

| | Source |
|---|---|
| **Flutter app / Flutter Web** | Kakao Local **keyword search** through the deployed Supabase Edge Function `search_restaurants` (`{query, latitude, longitude}` → ≤15 places per keyword), around the selected campus's coordinates from `universities`. Results are **transient: never written to any table** (`restaurant.dart`: "Transient: never persisted to our database"). Admin data is layered on top by `kakao_place_id` from `restaurant_overrides` / `restaurant_menus`. |
| **Admin dashboard (before)** | `restaurant_overrides` only: rows an admin typed by hand or imported from a CSV. Nothing ever copied the Kakao places in. |

**Root cause: two different data sources and no import path.** The list was empty
because `restaurant_overrides` really is empty (no code path inserted Kakao places).
It was **not** an RLS or query bug (moderators/admins read all rows by policy;
the query has no hidden filter) and **not** a wrong project: the app and the admin
`.env` point at the same Supabase project (same host, checked). The Edge
Function's source is not in this repository; it is deployed in the project.

Checked live with the publishable key (read-only): `universities` has 7 rows with
coordinates; `restaurant_overrides`, `restaurant_menus`, `campus_cafeterias`,
`cafeteria_meals`, `app_content` exist and show 0 *public* rows (drafts are hidden
from anon by design, so this alone cannot prove they are empty); mission tables
exist and refuse anon; `search_restaurants` answers with CORS `*` and returned 15
real places for 순천향대학교. What a signed-in admin sees could not be checked
without an admin login.

## The shared catalog

* One table, no duplicate: **`restaurant_overrides`**, keyed by the unique
  `kakao_place_id`. The app and the dashboard merge through the same rule.
* **What is stored from Kakao: only identity / management metadata**: the
  `kakao_place_id`, the place's name as an (editable) label, and when it was
  registered. Address, phone, coordinates, category path and the raw document are
  **not** stored. Reason: Kakao's operating policy lists caching of data Kakao
  provides, beyond improving the in-app experience and without keeping it current,
  as a prohibited use, and Kakao's developer answers say place IDs/URLs may be
  kept but Local API response content may not. This was not confirmed against the
  current official terms: **please verify them** (and relax or tighten this) before launch.
  Kakao's details are fetched **live** when needed (preview, edit page).
* **카카오 식당 불러오기** (`식당` page): pick a university → the dashboard runs the
  same `search_restaurants` function the app uses (no Kakao key in the browser)
  with the campus coordinates and the app's keywords → a live preview lists the
  places with **which are already managed** → tick the ones to manage →
  `admin_register_kakao_places` (admin-only, validates, deduplicates by Kakao
  place ID, audited) stores ID + name label as a **draft** and links the campus.
  Re-registering changes nothing.
* **Merging in Flutter** (`OverrideAwareRestaurantRepository`, the single place):
  hidden/archived places are dropped from Home, map, search, category pages and
  saved places; a *published* override's name / address / phone replace Kakao's;
  the Kakao id, category path, coordinates and distance never change, so
  favorites, markers, filtering, ranking and reviews are unaffected.
* The edit page shows Kakao's current data live and read-only next to the values
  we manage.
* The list shows thumbnails, coverage counts (photo / menu) and filters for
  "사진 없음" / "메뉴 없음".
* Not done: scheduled sync; a keyword returns ≤15 places, so a campus search is
  the nearest matches, not an exhaustive list.

## Migration to approve: `supabase/migrations/20261111000100_admin_content_upgrade.sql`

Additive and idempotent; **not applied to the hosted project.** Requires
`20261109000100` and `20261110000100` (both already applied).

* `restaurant_overrides`: `kakao_registered_at`, `featured`, `display_order`,
  `verified_at`.
* `restaurant_menus`: `category`, `recommended`, `price_verified_on`, `status`
  (active/archived) + a **trigger that fills `kakao_place_id` from the restaurant**
  and a backfill. (Sync bug fixed: the dashboard stored menus by `restaurant_id`
  while the app reads by `kakao_place_id`, so admin-added menus never showed.)
* `restaurant_photos` (cover + gallery; storage path, caption, order, status,
  source/credit, size) with RLS: public reads only *published* photos of
  *published* places; only admins write; audited; at most one live cover; the live
  cover is mirrored to `restaurant_overrides.image_url` (a hand-typed link is never wiped).
* `cafeteria_meals`: a `draft` status, hidden from the public until published.
* `admin_register_kakao_places(...)` (identity only, see above).
* Storage: the existing `restaurant-images` bucket (public read, admin-only write,
  5 MB, JPEG/PNG/WebP) is reused. Nothing new to create.

Tested on a scratch PostgreSQL (migrations apply twice): `supabase/tests/admin_content_test.sql`.

## Admin screens

| Screen | What now works (against the tables above) |
|---|---|
| 식당 | list with thumbnails (name, category, university, address, Kakao ID, status), coverage + photo/menu filters, 카카오 식당 불러오기, edit with live Kakao data |
| 메뉴·가격 | add / edit / archive / delete, category, recommended, representative, sold out, order, price verification date, photo upload (resized, old file removed) |
| 사진 관리 | cover + gallery upload (multi-file, resized to ≤1600px WebP/JPEG), captions, order, make-cover, archive/restore, delete (file removed too), student credit |
| 학식 | week view with prev/next/this week, add/edit/duplicate-to-next-week, draft ↔ published, meal photo, notice, delete (photo removed) |
| 미션 관리 | unchanged (see `missions.md`) |

## Flutter changes

* 식당 상세: published **cover**, **gallery** (tap to enlarge), menu **photos**,
  recommended label, archived menus hidden. Loading, error and "no photo" states;
  never a stock photo.
* 학식: meal photo + notice from `extra`; drafts never arrive (RLS).
* Failures of the new tables (not deployed yet) degrade to "no photos", never an error.

## Manual steps / limits

1. Approve and apply the migration (SQL editor or `supabase db push`).
2. Sign in as an admin → 식당 → 카카오에서 가져오기 → pick each campus.
3. Not built: Kakao scheduled sync, CSV import for cafeteria in the browser (the
   Python importer in `supabase/cafeteria/` still works), featured/display-order
   *controls* (columns exist), tag editor beyond the existing 식사 목적 field,
   app-content (banners/notices) rendering in Flutter (the admin page writes
   `app_content`; the app does not read it yet), 대학교/사용자/리뷰 pages were left as they were.
4. End-to-end against the live project is **not verified**: it needs the migration
   and an admin login. What is verified is each side separately (SQL suite,
   admin vitest, Flutter tests) plus the live Kakao function call.

## 학식 management (per university)

* **Admin → 학식** works one university at a time: the university is always chosen
  (first one by default, "학식 N곳" shown per university), its cafeterias are
  listed, searched and picked, and only that cafeteria's meals are queried. There is no
  "all universities" mode, and menus never cross universities (database test + Flutter test).
* **학식 식당 추가 / 수정** (modal): university (required), Korean name (optional, only
  when an official source gives it), en/zh names, kind (학생/기숙사/교직원/기타),
  location, display order, operating note, status. **활성/비활성/보관** is a status
  change (never a delete); inactive and archived cafeterias and their meals disappear
  from the app, and can be restored.
* **Meals**: week navigation, 조식 / 중식 / 석식 sections per day, missing meals shown as
  "등록 안 함" (nothing is created automatically), several corners per meal, price,
  hours, photo (with preview in the edit form), notice, official source URL, the date the
  information was verified, draft/published, duplicate-to-next-week. A 천원의 아침밥
  badge needs an official source and a breakfast.
* Flutter: the screen shows the cafeteria's operating note, supports pull-to-refresh, and
  re-reads on app resume and on live changes.
* Migration `20261113000100_cafeteria_management.sql` (additive; existing cafeterias
  become `active`): `status`, `operating_note`, audit triggers on cafeterias and meals,
  public read limited to active cafeterias, a per-university unique name (skipped with a
  notice if existing data already has duplicates).

## Student reviews and photos

* **Flutter**: the restaurant page shows the average and the visible reviews (authors
  are "학생", never names), lets a signed-in student write / edit / delete their own
  review, report someone else's (one open report per user and review) and submit a
  restaurant or menu photo. **내 리뷰·사진** shows each item's status (공개 / 숨김 /
  삭제됨, 검토 중 / 게시됨 / 반려됨 with the moderator's reason) and lets a student
  withdraw a pending photo. Guests are asked to sign in. A saved review or photo makes
  the app ask the server to recompute missions.
* **Privacy**: an unapproved photo is stored in the PRIVATE bucket `contribution-photos`
  in the student's own folder (`<user id>/<file>`); only that student and moderators/admins
  can read it. The student must agree to publication; the server checks the path is in
  the caller's own folder, the file exists, and the caption/size limits. A student can
  withdraw only their own *pending* contribution.
* **Admin → 미션 관리 → 기여 검토**: shows the private photo through a short-lived signed
  link, the place name, caption and consent; **갤러리에 올리고 승인** copies it into the
  public `restaurant-images` bucket as a gallery photo (source "student", credited as a
  student photo), then approves it (rolled back if the approval fails) and removes the
  private original; **승인만** approves for the mission without publishing; **반려** needs a
  reason and deletes the private photo; recent decisions are listed. Choosing the official
  *cover* stays a separate step in 사진 관리.
* **Missions**: valid reviews and approved menu photos already count in the server rules;
  approval updates progress at once. Restaurant photos do not count for the menu-photo mission.
* Migration `20261114000100_student_contributions.sql` (additive): the `restaurant_photo`
  kind, the private bucket and its storage policies, `submit_contribution` validation,
  `delete_my_contribution`, and one open report per user and target. Tested on a scratch
  PostgreSQL with a Storage stub (own folder only, others and anon see nothing, moderators
  can read but not publish, withdrawal rules).
* Not built: editing a submitted photo (withdraw and upload again), suggesting menu/price
  corrections (the mission still says "준비 중"), push notifications for decisions.
