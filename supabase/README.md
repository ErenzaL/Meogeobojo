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

## Admin Kakao import: `admin_kakao_search` (source in this repo, NOT deployed) and `20261119000100`

**Why it exists.** Admin → 식당 → 카카오 식당 불러오기 used to run 22 fixed keywords through `search_restaurants`, which ignores `radius`,
`page` and `size` and returns at most 15 places. 22 × 15 is at most 330, and after deduplication that was the ~124 places seen for
순천향대학교, whatever the university's `search_radius_m` said (the page never even read that column). `search_restaurants` is
deployed from outside this repo and is left untouched (the Flutter app depends on it). `admin_kakao_search` is a separate,
admin-only function that the Admin app drives with an adaptive grid over the university's whole radius.

| | |
|---|---|
| Source | `supabase/functions/admin_kakao_search/` (`core.ts` = all logic, `index.ts` = `Deno.serve`, `core_test.ts`) |
| URL | `POST {SUPABASE_URL}/functions/v1/admin_kakao_search` |
| Auth | the signed-in admin's JWT (`Authorization: Bearer`). The function asks the database `has_role('admin')` with that same token (no service key), so a non-admin gets `403` before Kakao is called |
| Secrets | `KAKAO_REST_API_KEY` (the one `search_restaurants` already uses). `SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided by the platform. Keep the default JWT verification on |
| Request | `{"university_id": uuid, "category_group_code": "FD6"\|"CE7", "query"?: "치킨집", "page"?: 1..3, "cell": {"lat", "lng", "radius_m"}}` |
| What it checks | the university exists and has coordinates (read from `universities` with the caller's token) and the cell lies inside the circle around that university's `search_radius_m` (so it cannot be used as a general Kakao proxy) |
| What it does | **ONE Kakao call per request**: category search (FD6 / CE7), or keyword search with `category_group_code` when `query` is given, `x`/`y`/`radius`, `size=15`, the requested `page`. The page number is the resume cursor: the caller walks `next_page` |
| Success | `{"success": true, "documents": [...], "meta": {"page", "next_page", "total_count", "pageable_count", "returned", "truncated", "kakao_calls": 1}, "university": {"id","latitude","longitude","search_radius_m"}}` |
| Failures | `401` no token · `403` not an admin · `400` bad input (incl. `page`) / cell outside the university · `404` unknown university · `429` Kakao rate limit or quota (HTTP 429, or Kakao code −10) · `502` Kakao down / timeout · `500` misconfigured |

`truncated` is how the Admin knows to split a search area: Kakao documents `pageable_count` as "at most 45", so a search whose
`total_count` exceeds it (or that reaches 45) cannot be read in full.

**Scan (Admin, `admin/src/features/restaurants/kakaoScan.ts`) = a resumable JOB.** The centre, `search_radius_m` and id of the chosen university are read from
Supabase when the search starts. The bounding square of the circle is searched for FD6 and CE7 as the circle through its corners, **one page per
request**; a truncated square is split into four, down to `maxDepth` 6 (≈94 m squares for 3000 m). Squares that cannot touch the radius are skipped.
Squares still truncated at the finest level are searched once per existing keyword (`KAKAO_QUERIES`, the app's category keywords).
Circles (`x`,`y`,`radius`) are used, not `rect`, because their parameters are unambiguous in Kakao's documentation. Every place is measured
from the **original university coordinates** (haversine) and dropped beyond the radius; places are deduplicated by Kakao place id.

*Job state* (`JobState`): a job id, and for every square its status (`pending` / `done` / `failed`), its **page cursor** and pages read, plus counters.
It is saved in this browser (`kakaoJobStore.ts`, localStorage) every 8 squares and at the end, so an interrupted scan (closed tab, rate limit, budget,
cancel) is offered with "이어서 하기": finished squares are not searched again, failed ones are retried from their cursor (a failure on page 2 does not
re-read page 1). It is dropped if the university's centre or radius changed (the grid would differ) and when the scan completes.
**The saved job holds no Kakao data** (no names, addresses, coordinates or place ids): Kakao's terms allow results in real time only. So the places found
are in the page's memory; within the same page session "이어서 하기" keeps them (and adds the retried squares), but after a reload a continued scan lists only the
places of the squares it still had to search (already registered places stay registered).

*Bounds and failure handling:* default 3 searches in flight (one fewer for every 429 answer, never below 1); a 20 s timeout per request (the request is
aborted and retried); 3 retries with exponential backoff and jitter (a 429 waits twice as long); 1500 function requests and 3000 Kakao calls **per run** (a
resumed run gets a fresh allowance); a stop after 5 squares in a row that stay rate-limited, after 3 in a row that are refused (HTTP 4xx), or at once for
401/403 or a missing function; cancel works immediately even if a request ignores its signal. One failing square marks only that square `failed`: everything
else carries on and the result is shown as **partial**, with "이어서 하기" for the failed and remaining squares. The screen reports job id, radius, cells, Kakao
calls, retries, unique places, how many were beyond the radius, existing vs new, failures (stage, HTTP status, code; messages are redacted, so no key or token
can appear) and any squares still over Kakao's cap.
Simulated cost on a 3000 m radius: ~300 places ≈ 55 Kakao calls, ~1500 ≈ 300, 3000 clustered ≈ 800 (simulation, not a Kakao measurement).

*Diagnosis.* Before scanning, the Admin asks the platform whether the function exists with a plain `GET {SUPABASE_URL}/functions/v1/admin_kakao_search?apikey=…`
(a "simple" cross-origin request: no preflight, so the browser can read the real status): `404` = not deployed, anything else = deployed. This matters
because for a function that does not exist the CORS preflight is a 404, the browser then refuses the real call, and supabase-js reports only a status-less
"Failed to send a request to the Edge Function". The first import failure was exactly that: it was retried as a "network" problem and never recognised as a
missing function (confirmed 2026-11-11: the live project answers `404 NOT_FOUND` for `admin_kakao_search`, while `search_restaurants` answers 200).

**Until the function is deployed** the Admin says so (with the HTTP status) and uses the old keyword search (still filtered to the radius), and states
that the result is partial.

**Deploy (you, deliberately; nothing here deploys anything):** `supabase functions deploy admin_kakao_search --project-ref <ref>`. First run after
deploying: scan a small radius and check the report (a scan that finds 0 places, or only squares that are all "full", means something is off).

**Migration `20261119000100_kakao_register_no_touch.sql` (NOT applied).** `admin_register_kakao_places` answered an already-managed place with
`ON CONFLICT DO UPDATE`, which still wrote the row: it bumped `updated_at` (the Admin list shows it as "just edited") and fired the
`content_sync_bump` live-update signal to every running app. Nothing a person typed was overwritten, but a repeat import should not touch
managed restaurants at all. The function now only looks: a known place gets no write (not even a timestamp), a new one is inserted as a
draft, the campus link is added only if missing. Same signature, return shape, limits (max 500 per call) and audit. One function replaced,
no table or data changed, safe to apply twice. The Admin never sends places it already lists as managed, so this only hardens the server.

**Kakao terms (verified 2026-11-11; not legal advice).** Limits from the official Local API guide: `size` 1–15, `page` 1–45,
`pageable_count` "최대: 45", `radius` ≤ 20000 m; quotas are per app (daily/monthly), exhaustion answers HTTP 429 (Kakao's reference also lists
code −10 "API limit has been exceeded", seen as 400 or 429); no per-second number is published. Kakao staff (developers forum, Aug 2026)
say Local API results are for real-time calls and may not be stored, while storing only a place ID and showing details fetched live was
called acceptable. This code stores nothing from a search: results live in the browser tab's memory, the function does not log or cache
documents (counts only, `Cache-Control: no-store`), and registration stores only the place id and its name as a management label, as before
(the name label is the one thing worth asking Kakao about). Not every place is exposed by the API, and a stored id can stop resolving, so
"found N" is what Kakao returns, never a census.

**Tests.** `deno test supabase/functions/admin_kakao_search/core_test.ts` (15; Deno is not in this repo's toolchain: `npm i deno` in a scratch
folder works), `cd admin && npm test` (scanner: radius propagation, pagination caps, spatial coverage, distance filter, dedupe, repeat scans,
depth/request/concurrency bounds, backoff, timeout, cancellation, rate limits, partial success, page cursor, resume, diagnosis of a missing function, redaction; plus the page), and `zsh supabase/tests/run_local.sh <scratch-dir>`
(includes: registering existing places writes nothing, and 600 places in chunks, repeated, are a no-op).

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
9. `20261031000300_phase2_user_tables.sql` — future-feature tables (`student_reviews`, `restaurant_menus`, ...). **Now required** by the admin migration below.
10. `20261109000100_admin_foundation.sql` — admin roles, audit log, restaurant overrides, menu / cafeteria / university administration, review moderation + reports, account status, app content, `restaurant-images` bucket (see "Admin backend")

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


## Admin backend (`20261109000100_admin_foundation.sql`)

Requires migrations 1, 3 (phase2), 8 and the profiles migration first. Idempotent.

**Roles** (`admin_roles`): `moderator` < `admin` < `super_admin`. Authorization is enforced by RLS through `public.has_role('<min>')`; the React app's route guard is only a convenience. Clients can read only their own role row and can never write it: roles change only through `admin_grant_role` / `admin_revoke_role` (super_admin) or the SQL editor. The last super_admin cannot be revoked.

| Capability | moderator | admin | super_admin |
|---|---|---|---|
| Read drafts, reports, all reviews | ✔ | ✔ | ✔ |
| Moderate reviews / resolve reports (reason required, audited) | ✔ | ✔ | ✔ |
| Edit restaurants, menus, meals, universities, content | | ✔ | ✔ |
| Read audit log, list profiles, suspend normal users | | ✔ | ✔ |
| Delete restaurants / universities, manage roles, act on staff accounts | | | ✔ |

**Bootstrap the first super_admin** (SQL editor, once; the user must already have signed in):
```sql
insert into public.admin_roles (user_id, role)
select id, 'super_admin' from auth.users where email = 'you@example.com';
```

**Data model notes**: restaurants are not stored; `restaurant_overrides` holds what we add or override per `kakao_place_id` (null for hand-made places). `visibility`: `draft` (admin only), `published`, `hidden` / `archived` (the app must hide the place). Deleting a university removes only its links. `cafeteria_meals.badge` carries labels such as `천원의 아침밥`, only when the source says so. Menu changes and moderation state are public through the existing read policies.

**Tests**: `supabase/tests/admin_test.sql` (run by `run_local.sh`) covers anonymous, ordinary user, moderator, admin and super_admin, including negative cases (self-granting roles, writing data, calling privileged functions, editing moderation columns, reading the audit log).
