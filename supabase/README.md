# Supabase backend notes

## Deployed Edge Function: `search_restaurants` (verified 2026-10-31)

Probed against the live project; source is not in this repo.

| | |
|---|---|
| URL | `POST {SUPABASE_URL}/functions/v1/search_restaurants` |
| Auth | `apikey: <publishable key>` (supabase_flutter's `functions.invoke` sends it). Missing → `401 MISSING_CREDENTIALS` |
| Request | `{"query": string, "latitude": number, "longitude": number}` — coordinates must be JSON numbers |
| Success | `{"success": true, "count": n, "restaurants": [<Kakao document>...]}` (max 15) |
| Bad input | `400 {"error": "Invalid search parameters"}` |
| Other | `GET` → `{"error": "Use POST"}`; CORS enabled |

Kakao document fields used: `id, place_name, category_name, category_group_code, distance, address_name, road_address_name, phone, place_url, x (lng), y (lat)`.

**Ignored by the deployed function** (tested): `radius`, `page`, `size`, `category_group_code`. So the app cannot paginate or filter by FD6/CE7 server-side; it issues keyword queries per category chip and filters on Kakao's own `category_name` client-side. To get real pagination / category search / radius control, the function needs to be extended and redeployed (Phase 2).

The Kakao REST key lives only in Supabase Secrets (`KAKAO_REST_API_KEY`); it is never in the Flutter app or `.env`.

## Migrations (NOT applied — no DB credentials were available)

Probed 2026-11-01: the remote project still returns `PGRST205` for `universities`, `favorites`, `profiles` and `user_preferences`. Until applied, the app falls back to a bundled university list, favorites cannot be saved, and **signed-in users see "couldn't load your profile" (retry) instead of onboarding**, because the profile table does not exist yet.

Apply **in this order** via Dashboard → SQL Editor (paste each file), or `supabase link --project-ref jnnofemlolwdyonfhzje && supabase db push`:

1. `20261031000100_universities.sql` — table + public read + 7 seeded campuses
2. `20261031000200_favorites.sql` — per-user favorites with RLS
3. `20261101000100_profiles.sql` — `profiles` (+ `preferred_language`), RLS own-row only, signup trigger (never blocks sign-up), column-level grants so `onboarding_completed*` can only be set by the RPC
4. `20261101000200_user_preferences.sql` — structured preferences (explicit budget min/max/any semantics, CHECK constraints, "상관없음" exclusivity), RLS own-row only. Refuses to run if the superseded draft shape exists.
5. `20261101000300_save_user_preferences_rpc.sql` — atomic save + mark onboarded (`SECURITY DEFINER`, pinned `search_path`, user from `auth.uid()` only)
6. `20261101000400_fix_table_grants.sql` — hosted default privileges grant clients nothing: `SELECT` on `universities`, and removal of unused `TRUNCATE/REFERENCES/TRIGGER/MAINTAIN`
7. `20261101000500_nickname_and_companions.sql` — `profiles.nickname_is_custom` + `set_nickname()`, `user_preferences.companion_types[]`, `save_user_preferences` re-created with `p_companion_types` (old signature dropped in the same transaction)
8. `20261101000600_campus_cafeterias.sql` — 학식: `campus_cafeterias`, `cafeteria_meals` (public read-only; administrators write via `supabase/cafeteria/`). **No rows are seeded.**
9. `20261031000300_phase2_user_tables.sql` — **optional**, future features only (no longer defines `user_preferences`; `restaurant_menus` now has `name_ko/en/zh`, `description_ko/en/zh`)

All files are additive and idempotent; none drops or rewrites existing data.

### Tests for the SQL
`supabase/tests/run_local.sh <scratch-dir>` runs every migration plus the suites below on a scratch PostgreSQL (hosted-like default privileges). `auth_stub.sql` + `rls_test.sql` recreate a minimal Supabase `auth` schema (roles, `auth.users`, `auth.uid()`) in a scratch Postgres and assert: two-user RLS isolation, anon denial, blocked direct `onboarding_completed` writes, constraint rejection with full rollback, edit-keeps-onboarded, cascade delete. They were run against PostgreSQL 18 (20 checks passed). They are **not** a test of the hosted project; re-run the RLS checks there with two real accounts after applying.

### Auth dashboard checklist (verified read-only on 2026-11-01)
* Email provider enabled, "Confirm email" ON (`mailer_autoconfirm=false`) → sign-up shows the verification screen.
* Kakao provider enabled; `/auth/v1/authorize?provider=kakao` redirects to `kauth.kakao.com` with scopes `account_email profile_image profile_nickname`. If Kakao shows error KOE205, the **account_email** consent item is not enabled for the Kakao app (the app also copes with users who share no email).
* Redirect allow-list must contain exactly `com.meogeobojo.app://login-callback/` (trailing slash).
* Optional `.env` keys `TERMS_URL` / `PRIVACY_URL` (https) make the legal links on the login screens open real documents; unset, the app says they are not published yet.

### Abuse protection for the Kakao-backed function
Guests can browse, so `search_restaurants` is callable with only the publishable key. Client side there is a 5-minute cache and a debounced search, but real protection must live in the Edge Function (per-IP / per-day rate limit, optionally a higher quota when a valid user JWT is present). The function source is not in this repo, so this was not changed.

### Why there is no `restaurants` table
Kakao Local API results may not be permanently stored, and their current retention/reuse terms have not been verified. Favorites therefore keep only `kakao_place_id`. Confirm the terms before adding a restaurants cache.

### Email auth
Favorites need a signed-in user. Enable the Email provider in Auth settings; if "Confirm email" is on, sign-up shows a "check your inbox" message.
