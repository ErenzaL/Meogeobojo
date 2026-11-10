# System integration audit

Facts below are marked **verified live** (checked against the running services with
read-only requests, `scripts/verify_production.py`), **verified in code** (read from
this repository) or **not verifiable here** (needs an account or dashboard access).
Local tests do not prove production synchronisation; the acceptance matrix is in
[production-acceptance.md](production-acceptance.md).

## Architecture

```
                         ┌───────────────────────────── Supabase project jnnofemlolwdyonfhzje ─────────────────────────────┐
 Flutter iOS / Android ──┤  Auth (users, sessions)        Postgres + RLS + RPC (SECURITY DEFINER)      Storage              │
  (bundled .env,         │                                  universities, restaurant_overrides/_menus/    bucket               │
   publishable key)      │  Edge Function search_restaurants  _photos/_university_links, cafeteria*,   restaurant-images    │
                         │   (holds the Kakao REST key in     student_reviews, favorites, missions...  (public read,        │
 Flutter Web ────────────┤    Supabase Secrets) ◄── Kakao Local API (live place search)                  admin-only write)    │
  Render static site     │                                                                                                    │
  meogeobojo.onrender.com│  Realtime (postgres_changes) ── only the tables in 20261112000100, filtered by each user's RLS    │
                         └────────────────────────────────────────────────────────────────────────────────────────────────────┘
 Admin Web ─────────────────► same project, same publishable key, role checked in SQL (has_role / _require_role)
  Render static site
  meogeobojo-admin.onrender.com

 Not deployed: recommendation-api/ (FastAPI, Dockerfile). The app uses its built-in mock recommendation service.
```

**Where the backend runs: Supabase (managed).** There is no server of your own.
Render hosts only two static sites (Flutter Web and Admin Web: `render.yaml`).
Server-side logic lives in Postgres functions (RPC) and one Edge Function.

## Which project each client uses

| Client | Supabase project | How verified |
|---|---|---|
| Flutter Web (live) | jnnofemlolwdyonfhzje | **verified live**: the deployed `main.dart.js` contains that project URL, a publishable key, no `service_role` |
| Admin Web (live) | jnnofemlolwdyonfhzje | **verified live**: the deployed admin bundle contains that URL, no `service_role` |
| Flutter mobile | `.env` → same host | **verified in code** (`.env` host equals the admin's); a *release* build's `.env` is not verifiable here |

## Deployment state

* Flutter Web: Render static site `meogeobojo-web`, built by `scripts/render_build.sh`
  with `--dart-define` (no `.env` published). **Verified live**: serves the app and
  contains the strings of the latest pushed commit (e.g. "게임으로 정하기", "조건을 고르고 추천받아 보세요").
* Admin Web: Render static site `meogeobojo-admin`. **Verified live**: contains
  "카카오 식당 불러오기" and `admin_register_kakao_places`.
* Both are fronted by Cloudflare; routes rewrite to `/index.html`.
* Whether Render auto-deploys on push, and the exact env values set in the Render
  dashboard: **not verifiable here** (the deployed bundles do point at the right project).

## Migrations in production (verified live through the API surface)

| Migration | State |
|---|---|
| 20261031…–20261101000600 (universities, favorites, profiles, preferences, cafeterias) | applied |
| 20261109000100 admin foundation | applied (admin tables/functions answer) |
| 20261109000200 recommendation telemetry | applied (`admin_recommendation_stats` answers) |
| 20261110000100 missions | applied (every mission function and table answers) |
| 20261111000100 admin content upgrade | **applied**: `restaurant_photos`, the new columns and `admin_register_kakao_places` exist; `kakao_source` does not (the identity-only version) |
| 20261112000100 realtime content | **not applied** (new in this branch; the publication cannot be read with the anon key). Until it is applied, live updates fall back to resume / tab-open / pull-to-refresh |

## Data sources

| Data | Source |
|---|---|
| Restaurant name, address, phone, coordinates, category path, place URL | **Kakao, live** through `search_restaurants` (5-minute in-memory cache in the app, never persisted) |
| Hidden/archived, published name/address/phone override, description, price, last order, cover (`image_url`) | Supabase `restaurant_overrides`, merged in one place: `OverrideAwareRestaurantRepository` |
| Menus (+photos, prices, recommended, archived) | `restaurant_menus` (read by `kakao_place_id`; a trigger fills it from `restaurant_id`) |
| Gallery / cover photos | `restaurant_photos` + Storage `restaurant-images` |
| Cafeteria meals, photos, notices | `cafeteria_meals` (`extra` jsonb), `campus_cafeterias`; drafts hidden by RLS |
| Campus list and coordinates | `universities` |
| Missions, progress, points, badges | `monthly_campaigns`, `missions`, `user_*`, computed by `sync_my_missions()` |
| Favorites, reviews, preferences, profile | Supabase (per user, RLS) |
| **Bundled in the app (needs a new build to change)** | mascot and category artwork, all UI strings (ko/en/zh), fonts, theme. Mission *text* is data, not bundled. |
| Not wired | `app_content` (banners/announcements): the admin writes it, **the app never reads it**; recommendations use the built-in mock service |

## What needs a refresh to show up

Before this branch: only an app restart, or leaving and returning to a screen. Now:
resume (app or browser tab), the mission tab, pull-to-refresh on the mission page,
and live Realtime events (once 20261112000100 is applied). Kakao lists are cached
5 minutes inside the repository, but admin data is read on every list fetch.

## Mission synchronisation: the actual chain and the gaps

Admin form → `admin_save_mission` / `admin_save_campaign` / `admin_set_*` (role
checked, audited) → rows → `sync_my_missions()` → `MissionDashboardNotifier` → UI.

What decides whether an admin change is visible to a student (all three must hold):
1. the **campaign** is `published` and has started (`starts_at <= now`); the app
   shows the latest started published campaign;
2. the **mission** has `status = 'active'` (a saved mission is a *draft* until activated);
3. the mission's own dates / university allow it (`university_id` null = every campus).

Editing a mission that already has progress, in a way that changes target, reward,
rule, recurrence, campus or dates, creates **version + 1** (the old row is archived);
progress, points and badges are kept by lineage. Text-only edits are in place.

**Root cause found (campus eligibility).** The server decides which
university-specific missions a student gets from `profiles.selected_university_id`
(`_my_missions_payload`, `_evaluate_user`). The app only ever stored the chosen
campus on the device (`SharedPreferences`, key `selected_university_id`) and never
wrote it to the profile, so **every account's campus was NULL**. Result: any mission an
admin assigned to a specific campus was never offered to anyone, and a second device
could start on a different campus. Missions for "모든 캠퍼스" were unaffected, which
is why only some admin changes seemed to vanish. Fix: `universityAccountSyncProvider`
saves the campus to the account (account empty → push the shown campus; the device's
own choice wins when it differs; a fresh device adopts the account's), and re-asks the
server for missions after saving. Pinned by `test/features/university/campus_sync_test.dart`
and the SQL checks "no account campus → campus mission hidden / saved → offered / other
campus → hidden". **Existing accounts get their campus saved the next time they open the
updated app signed in.**

Second gap, also fixed: the app re-read missions only when the tab was opened; it never
refreshed on resume, on pull-down or on a change. It now does all of those.

Remaining reasons a saved change can be invisible (by design): the campaign or the
mission is still a draft, the dates have not started, or the mission is for another campus.

## Problems found

1. **Edge Function source is not in the repository.** `search_restaurants` is
   deployed in Supabase only, so its Kakao handling, caching and logging cannot be
   reviewed or redeployed from git. Download it (`supabase functions download
   search_restaurants`) and commit it.
2. **A Gemini key sits in the mobile `.env`** (`GEMINI_API_KEY`, `GEMINI_MODEL`):
   `.env` is a Flutter *asset*, so release builds embed it, and nothing in the code
   uses it. It is not committed (gitignored). **Remove those two lines before any
   release build** and rotate the key if a build was already distributed.
3. ~~`app_content` is never rendered~~ fixed in this branch: notices/banners show on Home and featured items lead the "오늘의 추천" list.
4. The recommendation API (`recommendation-api/`) is not deployed; the app shows
   the mock recommendation service.
5. Student reviews / photo contributions: tables, rules, the admin queue and a
   `submit_contribution` function exist; the Flutter app has no screens to write a
   review, upload a photo, edit/delete or report content, and no private bucket
   for unapproved photos.
6. Kakao data storage: only the place ID and a name label are stored (see
   `admin-catalog.md`); verify Kakao's current terms.
7. Auth redirect URLs / CORS for the Flutter Web domain: **not verifiable here**
   (Supabase dashboard setting). The Edge Function answers CORS with `*`.

## Environment variable names (no values)

* Flutter Web build (Render): `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
  `KAKAO_JAVASCRIPT_KEY`, optional `KAKAO_NATIVE_APP_KEY`, `TERMS_URL`,
  `PRIVACY_URL`, `FLUTTER_VERSION`.
* Admin (Render): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (publishable only), `NODE_VERSION`.
* Flutter mobile `.env`: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `KAKAO_NATIVE_APP_KEY`.
* Supabase Secrets (server only): the Kakao REST key for the Edge Function.
* Never in any client: a service-role key, the Kakao REST key, a Gemini key.

## Manual steps to activate this branch

1. Review and merge `feature/system-integration`; Render redeploys the static sites.
2. Apply `supabase/migrations/20261112000100_realtime_content.sql` (only adds tables
   to the Realtime publication; no RLS or data change).
3. Remove the Gemini lines from the mobile `.env`.
4. Run `python3 scripts/verify_production.py`; then the signed-in acceptance steps
   in `production-acceptance.md`.
5. In Supabase → Authentication → URL configuration, confirm the Flutter Web
   domain is in the redirect allow-list.
