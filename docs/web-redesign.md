# Flutter Web redesign (branch `feature/web-redesign`)

One Flutter codebase serves Web, Android and iOS; this change is a presentation layer for the web plus fixes. **Nothing here is deployed**
(production is `main` on Render; this branch is not merged). No database migration, schema, RLS, Edge Function or Admin change.

## What changed
| Area | Change | Files |
|---|---|---|
| Startup (web only) | No splash: `SplashGate(skipSplash: kIsWeb)` opens the shell on the first frame; `web/index.html` lost the native-splash picture/CSS/script and the `splash/` images; `flutter_native_splash: web: false`; plain page background; `maximum-scale/user-scalable=no` removed; manifest colours/orientation fixed. Android/iOS splash unchanged (tested). | `lib/app.dart`, `web/index.html`, `web/manifest.json`, `pubspec.yaml` |
| Direct links | `/#/map`, `/#/community`, `/#/missions`, `/#/profile`, `/#/home` open that tab; an unknown path opens Home; the Navigator always starts at the app (no "unknown route" error). Session restore is unchanged (Supabase restores it before `runApp`). | `shell_tab_provider.dart`, `app.dart` |
| Map | **East-Asia bug:** the plugin passes `initialLevel` raw to Kakao JS, where 14 is the widest zoom; web now starts at level 4 (campus). **Missing markers on web:** `addMarkerLayer` throws on web and aborted the whole marker setup; it is now native-only. Recenter uses a campus zoom on web (the plugin default is street level). First results are fitted once per campus (campus + nearby results, far strays ignored); no results = stays on the campus; filter changes never move the camera. Desktop: list panel beside the map; clicking a row selects its pin and pans (zoom kept). | `map_screen.dart`, `map_camera.dart`, `map_places_sheet.dart` |
| Header | Tab strip scrolls instead of overflowing (English / large text at 1024 px used to overflow by 240 px); the "처음부터 다시" button is gone from the header (the feature stays in MY and the conditions sheet). | `web_header.dart` |
| Home (desktop) | Welcome section with the selected university and its selector (desktop had none). | `home_welcome.dart`, `home_screen.dart` |
| 밥수다 / Missions / MY (desktop) | 밥수다: feed left, composer + campus right; Missions: overview banner beside the progress card, missions in two columns; MY: account left, activity right. Same widgets, same real data; phones unchanged. | `community_screen.dart`, `mission_screen.dart`, `profile_screen.dart`, `v5_widgets.dart` |
| Footer | One `WebFooter` in the shared page shell (`V5Page` and Home), web only (`webFooterEnabledProvider`); 4 columns (about / real published announcements / contact / service) -> 2 -> 1, brand line, copyright, about dialog, legal links, feedback. | `web_footer.dart` |
| Admin / backend | None. | |

## Footer configuration (optional Render env vars, never secrets)
`TERMS_URL`, `PRIVACY_URL` (https), `FEEDBACK_URL` (https) and/or `SUPPORT_EMAIL`. Unset = the footer says the document / contact channel is
not set up (no invented link or address). **Required follow-up:** publish the terms and privacy pages and set these variables; the project has
no such pages today.

## Verification run
`dart analyze` clean; `flutter test` 821 pass (new: footer 27, layout 53 incl. every page x 390/768/1024/1440/1920 px signed in and guest,
map camera, desktop map panel / phone sheet, web splash skip / mobile splash kept, URL -> tab); `flutter test --platform chrome` for the
cafeteria suites earlier; `flutter build web --release` succeeds; real Chrome screenshots of the release build at 1440 px: no splash,
home welcome + footer, `/#/community` deep link. **Not verified here:** the Kakao map in a browser (needs the production JS key and the
registered domain), a phone-width browser capture (headless Chrome has a ~500 px minimum window), Android/iOS devices.

## Deploy (when you approve)
Merge `feature/web-redesign` into `main`: Render rebuilds Flutter Web with `scripts/render_build.sh` (auto-deploy). Optionally add the footer
variables above in the Render dashboard first. Rollback: Render -> service -> Deploys -> previous deploy -> Rollback.
After deploy check: `/` shows no splash; `/#/map` opens centred on the university (Kakao console must list the site domain); the footer shows.

## Not done / known limits
* The brand colour #FFCA80 is not the theme's primary colour (the app's palette is rust `#C2410C`; #FFCA80 is only the old splash colour). Changing it
  would restyle mobile too, so it was left for a decision.
* The URL does not follow tab changes and the browser back button leaves the site (no router yet).
* The Kakao map is not told to `relayout()` after a container resize (the plugin offers no call); a window resize may need a map interaction.
* Home keeps its existing filter bar; applied-filter chips with per-filter remove and an expandable advanced panel were not added.
* 밥수다 has no posts or posting backend (it never did); the desktop layout keeps the honest empty state and "coming soon" composer.
* Missions / MY desktop layouts rearrange the existing sections; no new data was added.
* Footer sits directly under short pages (it is not pinned to the viewport bottom).
