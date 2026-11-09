# 먹어보조 — Repository audit (Phase 1)

Date: 2026-11-09. Based on the code in this repository and on commands I ran
locally. **Nothing below was checked against the live Supabase project**: no
credentials were available, so "applied / not applied" for the remote database
is unknown (see "Blockers").

## 1. What exists

### Flutter app (repo root; Dart `^3.13.7`, Flutter 3.47.8)
- State management: Riverpod 3 (`flutter_riverpod`). Navigation: plain
  `Navigator` + a 5-tab `IndexedStack` shell (`lib/features/navigation`).
  **No go_router.**
- Backend access: `supabase_flutter` (PKCE auth), repositories behind
  interfaces in each feature (`restaurants`, `favorites`, `preferences`,
  `campus_meals`, `university`, `auth`). Widgets never call Supabase directly.
- Config: `flutter_dotenv`, `.env` is bundled **as an asset** (client-safe
  values only: Supabase URL + publishable key, Kakao native key).
- Localization: Korean (template), English, Chinese via ARB.
- Tests: 459 tests (`flutter test`), all passing at commit `da421c7`.
  `dart analyze lib test` is clean.
- Platforms present: `ios/`, `android/`, `web/`, `macos/`, `windows/`, `linux/`.

### Feature status
| Feature | Status |
|---|---|
| Home (hero pick, alternatives, 학식 card), origin + conditions sheets | Done (commit `da421c7`) |
| Restaurant search / category browse / detail | Done, **Kakao-only data** (see below) |
| Map tab (Kakao Maps, filtered markers, origin pin) | Done on mobile |
| Auth (Kakao OAuth, email), nickname, onboarding preferences | Done |
| Favorites | Done (stores Kakao place id only) |
| University selector (multi-campus, offline fallback list) | Done |
| 학식 (campus cafeterias + weekly meals) | Done; **no rows seeded** |
| Reviews, records (먹은 기록), 밥수다 (community) | Placeholders only |
| Recommendation | `RecommendationService` seam + proximity baseline; no ML model |
| Admin dashboard, admin roles, content management | **Nothing exists** |
| Render config, FastAPI service | **Nothing exists** |

### Supabase (`supabase/`)
- Migrations in repo: universities, favorites, phase2 tables
  (`food_records`, `student_reviews`, `restaurant_menus`,
  `recommendation_events`), profiles, user_preferences, save-preferences RPC,
  grant fixes, nickname/companions, campus cafeterias.
- SQL test harness: `supabase/tests/run_local.sh` (scratch PostgreSQL 18,
  present at `/Library/PostgreSQL/18/bin`). Not run in this audit.
- RLS is enabled on every table above. Reference tables are public-read;
  user tables are own-row only.
- **No `supabase/functions/`.** The deployed `search_restaurants` Edge
  Function's source is not in the repo (documented in `supabase/README.md`).
- Per `supabase/README.md` (probed 2026-11-01) the migrations were **not yet
  applied** to the hosted project. Current state unknown.

## 2. Key finding that shapes the whole plan

**Restaurants are not stored anywhere.** `Restaurant` is a transient Kakao
Local result ("never persisted"), keyed by `kakaoId`. Kakao gives no photos,
price, rating, hours or menus, and the app deliberately shows none.
Consequences:

1. An admin "restaurant editor" cannot edit rows that do not exist. The right
   model is an **override/enrichment table keyed by `kakao_place_id`**
   (visibility, description, price range, hours, images, university links),
   plus menus. Admin-created restaurants without a Kakao id need a nullable
   `kakao_place_id`.
2. The Flutter app already has the exact seam for this data:
   `restaurantInsightsProvider` (price, rating, review count, last order,
   main menu, image, amenities; every field optional). It is empty today and
   the new Home, the conditions sheet and search already read it. Admin edits
   → a repository behind that provider → the app displays them, with no UI
   rework.
3. `restaurant_menus` already exists (optional migration `…000300`, public
   read, "curated server-side only"). It lacks `available`, `representative`,
   `sort_order`, image, and an admin write path.

## 3. Missing components
Admin roles + permissions + audit log · restaurant override table ·
menu admin columns · review moderation columns (`student_reviews` has no
status) · reports table · app-content tables (announcements, banners,
featured) · recommendation telemetry table · Storage buckets and policies ·
React admin app · Edge Function source control · web-capable Kakao map
verification · Render config · negative-authorization tests for admin paths.

## 4. Bugs, risks, observations
- **Remote schema state unknown**; if migrations are still unapplied, signed-in
  users cannot load profiles (documented in `supabase/README.md`).
- `search_restaurants` ignores `radius`, `page`, `size`, `category_group_code`
  and its source is not versioned. Radius configuration per university (admin
  requirement) needs this function in the repo and redeployed.
- `.env` is a bundled asset. On Flutter Web it is publicly downloadable. Safe
  today (publishable values only); must never hold a secret. A web build should
  inject values with `--dart-define` or a generated file instead.
- `lib/features/restaurants/repositories/restaurant_repository.dart` imports
  `dart:io` (for `SocketException`). It compiles for web (verified below) but
  the network-error classification will not match on web; browser failures
  surface as `ClientException`, which the code already matches by name.
- `student_reviews` allows public read of every row with no moderation state,
  so hidden/removed reviews cannot be expressed yet.
- `flutter analyze` crashes in this checkout (analysis-server JSON framing bug
  with the Korean directory name). `dart analyze` and an ASCII-path copy work.
  Tooling issue, not a code issue.
- Working tree has an unrelated uncommitted edit to
  `lib/features/home/widgets/recommendation_banner.dart` (yours, left alone) and
  untracked `.vscode/` and `assets/images/mascot.zip`.
- Old Home widgets (`category_section`, `menu_section`, `nearby_section`,
  `home_header`, `home_hero`, `home_search_bar`, `recommendation_banner`) are
  still in the tree but unused by the new Home. **The category browse and the
  메뉴 shortcuts currently have no entry point from the UI.** Decision needed.

## 5. Flutter Web
- `flutter build web --release` **compiled successfully** (30 s, ASCII-path
  copy of this repo; `main.dart.js` produced). That proves it compiles. It does
  **not** prove it runs: not tested in a browser.
- `kakao_maps_flutter` ships a web controller, so a web map is plausible, but it
  needs a Kakao **JavaScript** key + registered web domain, neither of which is
  configured. `kakaoMapInitProvider` passes the *native* key today.
- OAuth on web needs redirect URLs registered in Supabase/Kakao
  (`flutter_web_auth_2` has a web callback flow; not configured or tested).
- Layout is phone-first; it is not responsive for wide screens yet.

## 6. Recommended order
1. **Backend migration** (additive, idempotent): `admin_roles`, `is_admin()` /
   role helper, `audit_log`, `restaurant_overrides`, extend `restaurant_menus`,
   moderation + `reports`, content tables, telemetry table, Storage buckets.
   Test in the local PostgreSQL harness with negative authorization tests.
2. **Flutter read path**: `RestaurantInsightRepository` (Supabase-backed) behind
   the existing `restaurantInsightsProvider`; menus on the detail page.
3. **React admin**: login + role gate, restaurant list/edit, then menus,
   universities.
4. **End-to-end check** (admin edit → Supabase → Flutter shows it; ordinary user
   denied), against a dev project or local PostgreSQL, not production.
5. Users, moderation, content, analytics, recommendation monitoring.
6. Flutter Web hardening (responsive shell, Kakao JS map, OAuth redirects),
   Render config and docs.

## 7. Files
**Will be modified:** `lib/features/recommendation/providers/ranking_providers.dart`
(insights provider), `lib/features/restaurants/screens/restaurant_detail_screen.dart`
(menus, description), `pubspec.yaml` only if a dependency is required,
`supabase/README.md`.
**New:** `supabase/migrations/*`, `supabase/tests/*`, `admin/`, `docs/*`,
`render.yaml`, `recommendation-api/` (only if a real model needs Python).
**Should stay unchanged:** auth flow, onboarding/preferences screens, 학식
feature, navigation shell, theme tokens, mascot assets, existing migrations
(add new ones; never edit applied ones).

## 8. Blockers / manual steps (need you)
- Supabase project access (to apply migrations and create the first admin user).
  Without it I can only test against the local PostgreSQL harness.
- A Kakao JavaScript key and web domain for the web map.
- Render account and GitHub connection to deploy anything.
- The recommendation model's real API contract from your teammate.

## 9. Repository layout decision
I recommend **not** moving the Flutter app into `mobile/`: the checkout path
contains Korean characters (already breaks `flutter analyze`), the iOS/Android
projects reference relative paths, and the benefit is cosmetic. Add `admin/`,
`recommendation-api/`, `docs/` and `render.yaml` next to the existing
`supabase/`. A later move can be done as its own reviewed step.
