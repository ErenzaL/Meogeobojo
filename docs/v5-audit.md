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
| login | `auth/screens/login_screen.dart` | **Done**: brand row, mascot tile, "{campus} 앞 맛집을 취향대로 찾아봐요", Kakao / email sign-in (outlined) / email sign-up (tonal) / guest; desktop two-panel layout. No Apple button (no Apple sign-in exists) |
| prefs (4 questions) | `preferences/screens/preferences_screen.dart` | Re-skinned by tokens only |
| home | `home/screens/home_screen.dart` | **Done** (hero pick, alternatives, 학식 card, origin + conditions sheets); two columns on desktop |
| search (hashtags, photo browse) | `search/screens/search_screen.dart` | **Done**: back + search field, 조건 / origin chips, 최근 검색 (on the device) and 이런 건 어때요? before a search, "‘q’ 검색 결과 N곳 · 지금 조건에 맞는 곳 M곳", places outside the conditions listed below, dimmed. Hashtags and the photo feed **not built** (no hashtag or visitor-photo data) |
| map | `map/screens/map_screen.dart` | Existing Kakao map kept; shares origin/conditions; V5 list/side panel **not built** |
| detail, reviews, review composer | `restaurants/screens/restaurant_detail_screen.dart`, `reviews/widgets/reviews_section.dart` | **Done**: 맛집 정보 bar with save, photo strip with "사진 N장", rating line, order status, price / category chips, info box (주문 마감, 위치, 가는 길 from the chosen origin + 기준 바꾸기 + Kakao link, 전화, 운영·편의, 1인 예상), 소개, 메뉴, review summary (average, stars, 5→1 spread) and list, photo upload rows, bottom bar 지도 (opens the map tab on the place) + 길찾기 · 도보 N분; desktop two columns. Live reports, seats and "추천한 이유" not built (no data) |
| community (밥수다) | `community/screens/community_screen.dart` | Placeholder screen (feature not built); not redesigned |
| saved, activity, my | `profile/screens/*` | 저장한 맛집 **done** (title, "N곳 저장됨", list / two columns on desktop, empty state with 추천 보러 가기). MY keeps 미션 as the bottom tab; 기록 opens from MY (내 활동 row and the 기록 stat) |
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
