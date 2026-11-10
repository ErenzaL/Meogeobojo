# Flutter Web redesign (branch `feature/web-redesign`)

One Flutter codebase serves Web, Android and iOS; this change is a presentation layer for the web plus fixes. **Nothing here is deployed**
(production is `main` on Render; this branch is not merged). No database migration, schema, RLS, Edge Function or Admin change.

## What changed
| Area | Change | Files |
|---|---|---|
| Startup (web only) | No splash: `SplashGate(skipSplash: kIsWeb)` opens the shell on the first frame; `web/index.html` lost the native-splash picture/CSS/script and the `splash/` images; `flutter_native_splash: web: false`; plain page background; `maximum-scale/user-scalable=no` removed; manifest colours/orientation fixed. Android/iOS splash unchanged (tested). | `lib/app.dart`, `web/index.html`, `web/manifest.json`, `pubspec.yaml` |
| URLs, Back / Forward, direct links | See "Browser URLs" below. | `url_sync.dart`, `shell_tab_provider.dart`, `app.dart`, `app_shell.dart` |
| Map | **Resize:** `web/index.html` tracks the Kakao map instances; on a window resize, when the desktop list panel appears/disappears and when the map tab is shown again, the app asks for a relayout that re-measures the map and restores the same centre and zoom (selected university and manual pan/zoom survive). **East-Asia bug:** the plugin passes `initialLevel` raw to Kakao JS, where 14 is the widest zoom; web now starts at level 4 (campus). **Missing markers on web:** `addMarkerLayer` throws on web and aborted the whole marker setup; it is now native-only. Recenter uses a campus zoom on web (the plugin default is street level). First results are fitted once per campus (campus + nearby results, far strays ignored); no results = stays on the campus; filter changes never move the camera. Desktop: list panel beside the map; clicking a row selects its pin and pans (zoom kept). | `map_screen.dart`, `map_camera.dart`, `map_places_sheet.dart` |
| Home filters (desktop) | The 조건 pill expands an inline **advanced-filter panel** (budget, distance, party, needs, hours & facilities, sort, open-now, untried-first) instead of the modal sheet; **removable chips** for every applied condition (+ 모두 풀기) sit under the filter bar. Both read and write the same shared `conditionsProvider` as the sheet, the map and search, so ranking, filtering and the recommendation are untouched. Phones keep the sheet and have no chip row. | `advanced_filters.dart`, `home_filter_bar.dart`, `home_screen.dart`, `condition_labels.dart` |
| Header | Tab strip scrolls instead of overflowing (English / large text at 1024 px used to overflow by 240 px); the "처음부터 다시" button is gone from the header (the feature stays in MY and the conditions sheet). | `web_header.dart` |
| Home (desktop) | Welcome section with the selected university and its selector (desktop had none). | `home_welcome.dart`, `home_screen.dart` |
| 밥수다 / Missions / MY (desktop) | 밥수다: feed left, composer + campus right; Missions: overview banner beside the progress card, missions in two columns; MY: account left, activity right. Same widgets, same real data; phones unchanged. | `community_screen.dart`, `mission_screen.dart`, `profile_screen.dart`, `v5_widgets.dart` |
| Footer | One `WebFooter` in the shared page shell (`V5Page` and Home), web only (`webFooterEnabledProvider`); 4 columns (about / real published announcements / contact / service) -> 2 -> 1, brand line, copyright, about dialog, legal links, feedback. On a short page it sits at the bottom of the window (`BottomPinned` lays out content and footer for real), on a long page it follows the content; on phones a gap is kept for the floating nav bar. | `web_footer.dart`, `bottom_pinned.dart`, `v5_widgets.dart` |
| Brand colour | Primary actions stay rust (`#C2410C`). `#FFCA80` is a new palette field `brandWarm`, used only as the footer's top rule. No existing colour changed; Android/iOS look is unchanged. | `app_palette.dart`, `web_footer.dart` |
| Admin / backend | None. | |

## Browser URLs, Back / Forward (web only)
* Tabs: `/#/home`, `/#/map`, `/#/community`, `/#/missions`, `/#/profile` (hash URLs, so the static host needs no rewrite rule). Choosing a tab
  adds a browser history entry; the page's first entry is rewritten to its tab. A screen opened over the shell (restaurant detail, settings)
  adds one entry for the current tab, so Back closes it. Dialogs and menus add none.
* Back / Forward / a typed URL arrive in Flutter as a named push; `UrlTabRoute` (an invisible, unnamed route) closes anything stacked on the
  shell, selects the tab and removes itself. It is deliberately **unnamed**: Flutter's root Navigator announces every named route to the browser,
  which first produced extra history entries (found in Chrome, fixed).
* A mistyped path opens Home. Phones (native) and tests are unaffected unless `urlSyncEnabledProvider` is on.
* Known quirk: closing a detail screen with the in-app back arrow leaves its history entry behind, so one later browser Back can look like a no-op.

## Footer configuration (optional Render env vars, never secrets)
`TERMS_URL`, `PRIVACY_URL` (https), `FEEDBACK_URL` (https) and/or `SUPPORT_EMAIL`. Unset = the footer says the document / contact channel is
not set up (no invented link or address). **Required follow-up:** publish the terms and privacy pages and set these variables; the project has
no such pages today. `scripts/render_build.sh` passes them to the build. (The Kakao JavaScript key is already set in Render.)

## Verification run (final code)
| Check | Result |
|---|---|
| `dart analyze lib test` | clean |
| `flutter test` | **841 pass** (new this round: advanced filters / chips 6, URL sync 11, footer-at-bottom 3, plus the earlier footer, layout and map suites) |
| `node --test test/web/kakao_relayout.test.mjs` | 3 pass (the relayout script against a fake Kakao SDK: centre and zoom restored, stale maps forgotten) |
| `flutter build web --release` | succeeds (built with placeholder Supabase values; nothing committed) |
| Chrome, 1440 px (release build, driven with puppeteer-core) | no splash; tab clicks write `#/home -> #/map -> #/community -> #/missions -> #/profile`; Back walks `missions -> community -> map`, Forward `community -> missions`; history length stays stable (no stray entries); no page errors; the correct page is shown for each URL (checked on screenshots); direct `/#/missions`, `/#/community` open that page after a reload; `/#/nonsense` opens Home; advanced panel expands in two columns; footer flush at the bottom on a short page with the #FFCA80 rule |
| Chrome, 390 px mobile emulation | direct `/#/community` opens 밥수다 in one column; bottom-nav taps write `#/map`, `#/missions`; Back `-> #/map`, Forward `-> #/missions` |
| Not verified | **The Kakao map in a browser**: no JavaScript key exists locally (it is only in Render); the Map screenshots show "Couldn't load the map" because of that and the placeholder backend. Verify on the deployed site (the Kakao console must list the site domain): opens centred on the university, resize keeps centre and zoom, markers appear. Back from an open *detail screen* in a real browser (needs real restaurant data; the widget test covers it). Android/iOS devices. |

## Deploy (when you approve)
Merge `feature/web-redesign` into `main` (it is a fast-forward of the current `main`, `b7b9969`): Render rebuilds Flutter Web with
`scripts/render_build.sh`. Optionally set the footer variables above first. Rollback: Render -> service -> Deploys -> previous deploy -> Rollback.
After deploy, check: `/` shows no splash; each tab changes the URL and Back/Forward work; `/#/map` opens centred on the university; the footer
shows; the cafeteria card and the weekly menu still load. No database, Edge Function or Admin change is part of this branch.

## `feature/home-all-meals`
Its two commits (3-meal 오늘의 학식 card, 천원 mark, removed comparison caption) are **already contained in `feature/web-redesign`** (it was
branched from it), so merging the redesign also delivers them; there is nothing separate to integrate and no conflict. Merging
`feature/home-all-meals` alone first would also work (the redesign sits on top of it). Neither branch is merged.

## Not done / known limits
* The browser URL does not include details (restaurant, filters); only the five tabs.
* 밥수다 has no posts or posting backend (it never did); no community backend was added.
* Missions / MY desktop layouts rearrange the existing sections; no new data was added.
* Mobile-width browser screenshots were taken with Chrome's device emulation, not on a physical phone.

## Full-width layout (branch `feature/web-fullwidth`)
The website now uses the **whole browser width**; the 1280 px centred column (and the grey side margins) is gone on the web. Native apps and
phones keep their layout: the bounded column only exists where `webFullWidthProvider` is off (every platform except the website).

| Piece | Change |
|---|---|
| `AppFrame` / `WebLayout` (`responsive.dart`) | On the web the frame no longer caps the width or rewrites the window size; it provides `WebLayout`, from which pages read the **gutter**: 24 px tablet (600-1023), 28 px desktop (1024-1439), 40 px large desktop (1440+); phones keep their own (16 / 20). |
| Header | Edge to edge, same gutter as the pages; logo left, tab strip fills the middle, search pill (360 / 420 px) + language + theme + profile end exactly at the right gutter. Active tab and URL sync unchanged. |
| Footer | Edge to edge (background, top rule, content inset by the gutter); four columns / two / one by width; still pinned to the bottom of short pages. |
| Shared page shell (`V5Page`) | No maximum width on the web; content inset by the gutter. Pages decide their own columns; text, forms and cards keep local limits. |
| Home | Gutter-aligned welcome, search, categories, filters, advanced panel; recommendations column + a cafeteria column of card width (34 %, 380-520 px); "오늘의 추천" cards become a **responsive grid** (as many ~196 px columns as fit) instead of a sideways scroller. |
| Map | Map takes the majority of the width; results panel 400 / 440 / 480 px at 1024 / 1440 / 1920; the map is re-measured whenever **its own box really changes size** (`SizeChangedLayoutNotifier`, plus window resize and tab show), keeping centre and zoom. |
| 밥수다 | Feed from the left gutter to a 360 / 420 px side panel (composer + campus). |
| Missions | Overview banner + progress card; mission cards in 2-4 columns depending on width (about 380 px each). |
| MY | Account column of card width (380 / 420 px); the activity area takes the rest and splits into two columns from about 900 px; the signed-out sign-in prompt and settings keep a 560 px width instead of stretching. |

### Verification (final code)
* `dart analyze lib test` clean; `flutter test` **904 pass** (new `web_fullwidth_test.dart`: 63 checks - every page x 390/768/1024/1440/1920 px x ko/en with no
  overflow, header and footer edge to edge at 1440 and 1920, content inset by the gutter, Home grid grows with the window, map keeps the majority width with the
  400/440/480 panel, MY columns, phones and the native bounded layout unchanged); Node relayout tests 3 pass; `flutter build web --release` succeeds.
* Real Chrome on the release build: **no horizontal overflow** on all five pages at 768, 1024, 1440 and 1920 px (`scrollWidth == innerWidth`); screenshots at 1440 and 1920
  show header, page background and footer spanning the viewport; tab clicks, Back / Forward and direct links behave as before (no page errors).
* Not verifiable here: the Kakao map itself (the JavaScript key exists only in Render); screenshots show its error state locally.
