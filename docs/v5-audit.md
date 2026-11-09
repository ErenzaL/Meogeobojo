# V5 design migration: audit and status

Reference: `design_references/먹어보조_시안_5차.html` (one single-page prototype with an
"app" view and a "web" view). It was rendered in headless Chrome and every
screen was inspected, not only read as code.

## Discrepancy in the brief
The brief's colour table lists Background `#FFFFFF` and Card `#F6F5F3`. The HTML
(`:root`) defines the reverse: `--bg:#F6F5F3`, `--card:#FFFFFF`. The HTML was
followed (it is the stated source of truth). All other tokens match the table.
Dark tokens come from the HTML's `prefers-color-scheme` block. Borders use the
HTML's opacity lines (`rgb(28 26 23 / .09)` and `.17`), not solid greys.

## Screen inventory (HTML `render()` map) and Flutter status
| Prototype screen | Flutter | Status |
|---|---|---|
| login | `auth/screens/login_screen.dart` | Re-skinned by tokens only; layout not rebuilt |
| prefs (4 questions) | `preferences/screens/preferences_screen.dart` | Re-skinned by tokens only |
| home | `home/screens/home_screen.dart` | **Done** (hero pick, alternatives, 학식 card, origin + conditions sheets); two columns on desktop |
| search (hashtags, photo browse) | `search/screens/search_screen.dart` | Conditions apply; hashtag / photo-feed layout **not built** |
| map | `map/screens/map_screen.dart` | Existing Kakao map kept; shares origin/conditions; V5 list/side panel **not built** |
| detail, reviews, review composer | `restaurants/screens/restaurant_detail_screen.dart` | Admin description + menus added; V5 detail layout, review UI **not built** (no review backend UI exists) |
| community (밥수다) | `community/screens/community_screen.dart` | Placeholder screen (feature not built); not redesigned |
| saved, activity, my | `profile/screens/*` | Re-skinned by tokens only |
| records | `records/screens/records_screen.dart` | Placeholder (feature not built) |
| cafe (학식) | `campus_meals/screens/campus_meal_screen.dart` | **Done**: 조식 · 천원의 아침밥 / 중식 / 석식, Mon-Fri selector, empty state |
| navbar (flat 64px) | `navigation/widgets/floating_nav_bar.dart` | **Done**: flat bar, V5 order and icons |
| web header (`whead`) | `navigation/widgets/web_header.dart` | **Done** (brand, tabs, search, 처음으로, 한국어/English/中文, theme, account) |
| comparison "학식 vs 바깥 식당" | `home/widgets/price_comparison.dart` | Shown only when both prices exist (no outside-price data yet) |

## Data the prototype shows that the backend does not have
Photos, kcal, ratings, review counts, outside-restaurant prices, "매일 학식
알림", hashtags and community posts. None of it was invented: those parts render
as "unknown" / empty, or are not built.

## Design system
Tokens in `core/theme/app_palette.dart` (light and dark), Pretendard bundled
(`assets/fonts`, SIL OFL licence included), controls: 48px filled / outlined
buttons at 12px radius, 16px cards, selected chips in ink. Contrast of every text
token pair is asserted ≥ 4.5:1 in `test/core/theme_test.dart`.
