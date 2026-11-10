# Production acceptance tests (A–H)

**Status key.** *Deployed prerequisites* = checked now against the live project
with `scripts/verify_production.py` (read-only, anon key). *Logic* = covered by
automated tests on a scratch PostgreSQL, the admin test-suite or the Flutter test-suite.
*Live E2E* = performed against the real project with real accounts: **NOT RUN for any
row below**, because it needs an admin account and a student account (and writes
production data), which I do not have and must not create without your approval.
Nothing here is claimed as passed unless it says so.

How to run a live check: sign in to the Admin Web as an admin and to the Flutter app
(or Flutter Web) as a student, perform the action, then read the result in the app.
Record the outcome in the last column.

| # | Action | Expected | Deployed prerequisites (live) | Logic tests | Live E2E | Blocker / what to do |
|---|---|---|---|---|---|---|
| A | Admin → 식당: register a Kakao place (카카오 식당 불러오기), edit name/description, publish | App & Web show the new name/description; the Kakao id and favorites are unchanged | table, columns, `admin_register_kakao_places` deployed; Kakao function returns 15 places | SQL: register is identity-only, dedupes, edits survive; Flutter: published override replaces name/address/phone | NOT RUN | needs an admin login. Record: place id, new name, screenshot of the app |
| B | Admin → 사진 관리: upload a cover | Both clients show that image on cards and detail; never another place's photo | `restaurant_photos` + bucket `restaurant-images` exist; Flutter Web bundle contains the photo code | SQL: one live cover, mirrored to `image_url`, RLS; admin: upload/replace/cleanup; Flutter: cover/gallery/placeholder | NOT RUN | admin login; image URLs are unique per upload (UUID path) so there is no stale cache |
| C | Admin → 메뉴·가격: change a price | Correct price in the detail menu | `restaurant_menus.status/recommended/price_verified_on` exist | SQL: menu→`kakao_place_id` trigger; admin: edit/archive; Flutter: menus parsed, archived hidden | NOT RUN | admin login |
| D | Admin → 학식: publish a meal for a date | Students of that university see it on that date and meal type | `cafeteria_meals` readable; `extra` present; draft status requires 20261111 (applied) | SQL: drafts invisible to anon, publish makes visible; admin: week view/draft/duplicate/photo; Flutter: photo + notice | NOT RUN | admin login |
| E | Admin edits an active mission | App refreshes the definition; points, progress and badges kept | all mission functions deployed | SQL: versioned edits keep history, no double reward; Flutter: refresh on tab, resume, pull-to-refresh, change event | NOT RUN | admin + student login. Gates to check first: campaign *published*, mission *active*, and (for a campus-specific mission) the student's account campus: accounts get theirs saved the first time they open the updated app signed in |
| F | Student submits a review/photo → admin moderates → published | Approved content appears; mission progress moves | `submit_contribution`, `admin_review_contribution`, `admin_moderate_review` deployed | SQL: approval pays once; admin queue tests | **NOT BUILT** | the Flutter write/upload/report screens and the private bucket do not exist yet |
| G | Admin hides a restaurant | Hidden in search, map, recommendations, category pages and saved places; favorites rows remain | `restaurant_overrides` visibility rules deployed | Flutter: one merge point drops hidden places everywhere; favorites untouched | NOT RUN | admin login. Check: the favorite is still in the DB after hiding |
| H | Same account on mobile and web | Same profile and mission progress | Flutter Web and Admin point at the same project (live bundle check) | Flutter: progress comes from the server after logout/login | NOT RUN | student login on two devices |

## What the live check shows today (`python3 scripts/verify_production.py`)

48 of 48 checks pass: every public table readable (published rows only), every
private table refusing anonymous reads, the 20261111 columns present, the identity-only
design in place (no raw Kakao column), every admin/mission function deployed and not
callable anonymously, `search_restaurants` returning real places with CORS, the
`restaurant-images` bucket present, both sites served, no service-role key in client source.

It does **not** show that an admin edit reaches the app. It also cannot see:
the Realtime publication (20261112000100, not yet applied), RLS rows behind a login,
Render dashboard settings, or Supabase auth redirect URLs.
