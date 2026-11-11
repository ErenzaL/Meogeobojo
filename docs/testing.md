# Testing

| Layer | Command | What it proves |
|---|---|---|
| Flutter | `flutter analyze && flutter test` (copy `.env.example` to `.env` first) | UI, ranking, providers, admin-data integration with fake repositories |
| Flutter Web | `bash scripts/render_build.sh` (with env vars) | clean-clone release build |
| Admin | `cd admin && npm run typecheck && npm run lint && npm test && npm run build` | role gating, forms, CSV, validation, edit flow (fake Supabase client) |
| Database | `zsh supabase/tests/run_local.sh <scratch-dir>` | migrations apply twice cleanly; RLS and privileged functions, incl. negative cases, on a real local PostgreSQL |
| Edge Function | `deno test supabase/functions/admin_kakao_search/core_test.ts` (and `deno check` on `index.ts` / `core.ts`) | admin-only Kakao search: auth, area check, pagination, truncation flag, rate-limit mapping, key never in responses (fake `fetch`; no network) |
| Recommendation API | `cd recommendation-api && python -m pytest` | contract validation, mock labelling, 503 without the mock flag, CORS |

`flutter analyze` crashes in a checkout whose path has non-ASCII characters (analysis
server bug); use `dart analyze lib test` or an ASCII-path copy.

## Not automated: end-to-end against a live Supabase project
Use a DEVELOPMENT project, never production.
1. Apply the migrations (`supabase/README.md`) and create a super admin (`docs/admin.md`).
2. Sign in to the dashboard (`npm run dev`) as that admin → 식당 → pick a restaurant (or add one
   with a real `kakao_place_id`, status 공개) → change the description → confirm.
3. Open the app / web build for the same university; reload. The detail page shows the new
   description; add a menu in 메뉴·가격 and it appears under 메뉴. Hide the restaurant → it
   disappears from Home, the map and search.
4. Add a 조식 meal with the 천원의 아침밥 button → the Home 학식 card shows the badge.
5. Negative checks with an ordinary account: the dashboard shows "접근 권한이 없어요", and a
   direct `PATCH /rest/v1/restaurant_overrides` with that user's token changes 0 rows / 401.
6. Web: sign in with email and with Kakao on the deployed site (redirect URLs must be
   registered in Supabase and Kakao), reload (session persists), open the Map tab (needs
   `KAKAO_JAVASCRIPT_KEY` + registered domain).
7. Resize the browser: phone, tablet (~820px), desktop (~1280px).

Record what you ran and the result; the above has NOT been executed in this repository's
development so far.

## iOS: the 지도 tab and marker images

Why markers are verified in Dart (`lib/features/map/utils/marker_image.dart`): the Kakao Maps iOS SDK
re-encodes each marker `UIImage` with `UIImagePNGRepresentation` and parses the result with its own
decoder. On a real iPhone (iPhone 13, iOS 26.1) Flutter's PNG encoder produced a **16-bit-per-channel**
RGBA PNG even though `ui.Image.colorSpace` reported sRGB; the SDK threw a C++ exception in
`kakao::image::ImageData::_setPixelSize` on its render thread (`createPoiStyle`), which aborts the app
(SIGABRT) and cannot be caught from Dart or Swift. The simulator emits 8-bit PNGs and does not reproduce
it, so this can only be checked on a device. Pins are therefore read back as straight 8-bit RGBA and
written as a plain 8-bit PNG that is validated before it is handed to the SDK.

Release test on a physical iPhone (unlock it; wireless debugging may drop, USB is steadier):

    flutter build ios --release
    xcrun devicectl device install app --device <device-id> build/ios/iphoneos/Runner.app
    xcrun devicectl device process launch --device <device-id> com.example.meogeobojo

then tap the 지도 tab. A crash leaves `Runner-<date>.ips` (list with
`xcrun devicectl device info files --device <device-id> --domain-type systemCrashLogs`).

To tell a native map problem from a marker problem, build with `--dart-define=MAP_DIAGNOSTIC_BASIC=true`:
the tab shows a bare Kakao map with no marker layer, styles or markers. It is off by default.

`flutter analyze` can crash in the analysis server when the project path contains Korean characters;
`dart analyze` runs the same analysis.
