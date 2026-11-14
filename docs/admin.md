# Admin dashboard

React + TypeScript + Vite + Tailwind, TanStack Query / Table, React Hook Form + Zod,
React Router. Lives in `admin/` and talks to the SAME Supabase project as the app.
It uses only the publishable key; **every permission is enforced by Row Level
Security in the database** (`public.has_role`). Menu hiding in the UI is cosmetic.

## Sections and who may use them
| Section | moderator | admin | super_admin |
|---|---|---|---|
| 개요 (real COUNT queries) | ✔ | ✔ | ✔ |
| 리뷰·신고 (moderate with a reason) | ✔ | ✔ | ✔ |
| 분석 (honest "not collected yet" page), 설정 | ✔ | ✔ | ✔ (+ role manager) |
| 식당 (list, search, filters, edit, publish/hide, CSV import/export) | | ✔ | ✔ |
| 메뉴·가격 (+ photo upload) | | ✔ | ✔ |
| 대학교 (coordinates, radius, active) | | ✔ | ✔ |
| 학식 (조식 incl. 천원의 아침밥, 중식, 석식) | | ✔ | ✔ |
| 사용자 (limited profile data, suspend with reason) | | ✔ | ✔ |
| 앱 콘텐츠 (announcements, banners, featured) | | ✔ | ✔ |
| 활동 기록 (audit log) | | ✔ | ✔ |

## Run locally
```bash
cd admin
cp .env.example .env     # VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY (publishable key only)
npm ci
npm run dev              # http://localhost:5173
npm run typecheck && npm run lint && npm test && npm run build
```

## Database setup
Apply the migrations in `supabase/README.md` (including
`20261109000100_admin_foundation.sql`), then create the first super admin once in
the SQL editor (the user must already have an account):
```sql
insert into public.admin_roles (user_id, role)
select id, 'super_admin' from auth.users where email = 'you@example.com';
```
Local database tests: `zsh supabase/tests/run_local.sh <scratch-dir>` (needs a local
PostgreSQL; does not touch any hosted project).

## How an admin edit reaches the app
1. Dashboard validates (Zod), asks for confirmation, then writes with the admin's own
   session. RLS checks the role; an audit row is written by a trigger.
2. The Flutter app reads `restaurant_overrides` (published / hidden / archived rows only),
   `restaurant_menus` and `cafeteria_meals` through the same read policies as any user.
3. Home, search and the map hide places an admin hid or archived; Home and the detail
   page show description, price, last order, menus; the cafeteria card shows the
   `천원의 아침밥` badge. The app refetches on the next load or retry.
Failures (for example migrations not applied yet) degrade to plain Kakao data, never to an error.

## What has and has not been verified
Verified: SQL authorization rules on a real local PostgreSQL (46 checks, negative cases
included); admin UI logic, route protection and the edit flow against a fake Supabase
client (34 tests); Flutter reading and hiding data against a fake repository
(including "admin edit appears after refresh"); production builds.
**Not verified**: the complete chain against a live Supabase project (no credentials
here), Storage policies (no storage schema locally), and Auth with real accounts.
Run `docs/testing.md` steps against a development project before relying on it.

## Known limits
- Restaurant edits and university links are separate requests (PostgREST has no
  client transaction); links are added before removals so a failure never drops data.
- The Flutter app uses `universities.is_active` and `app_content` (announcements,
  banners, featured), but not yet `search_radius_m` or `restaurant_university_links`.
- Analytics has no event collection yet (the page says so).
