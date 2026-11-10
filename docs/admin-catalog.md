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
