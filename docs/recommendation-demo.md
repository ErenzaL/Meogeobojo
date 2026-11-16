# Recommendation demo data (development only)

A synthetic dataset (`meogeobojo_recommendation_DEMO_FEATURES_NOT_DIRECT_IMPORT.csv`) lets the recommendation be shown with
hours and amenities before real data exists. **It is simulated. It is never verified information.**

## What is where
| Thing | Source |
|---|---|
| Position / distance | Kakao's live coordinates (`resolve_places`), never the demo file (its latitude/longitude are empty and ignored) |
| Budget (₩ 이하) | Published menus and their `menu_category` (식사 / 면류 / 분식), never the file's `meal_under_*_demo` flags |
| Opening time, last order, break time, parking, no-break-time, local currency, fast turnover, takeout, open late | `recommendation_demo_features` (this demo), only while demo mode is on |
| Everything an administrator entered | wins over the demo, always |

## Pieces
* **Migration** `supabase/migrations/20261123000100_recommendation_demo_features.sql` (apply it yourself; drop the table to remove the demo).
  Keyed by `kakao_place_id`, `demo_data` must be true on every row (CHECK), read by anyone, written by admins only.
* **Admin import**: 추천 page, "추천 데모 데이터 (개발용)". Preview, then save; it upserts into that one table and nothing else.
  The restaurant and menu CSV imports are unchanged.
* **App**: `lib/features/recommendation/demo/`. `applyDemo` fills only what is missing from the real data and flags the
  insight `demo`. Demo mode is OFF by default and the switch only exists in debug runs and in builds made with
  `--dart-define=MEOGEOBOJO_DEMO=true` (Settings → 계정). By the owner's decision the app and web show **no "demo" label**:
  while the switch is on, simulated hours/amenities look like any other data. The ranking still records which results rest
  on them (`RankedRestaurant.demoBasis`), so a label can be turned back on without changing the logic.
* **Ranking**: unchanged (V3). A place is a confirmed match only when every chosen condition is known and holds; with
  missing data it is listed apart as "정보 미확인" and the card names what is missing (e.g. "주차 정보 미확인").

## Demo build
`flutter build ios --release --dart-define=MEOGEOBOJO_DEMO=true` (and the same for apk). A normal build has no switch.

## Caution
With no label, a confirmed match that rests on a simulated fact (e.g. parking) reads like a verified one. Keep demo mode
off in anything students use (a normal build has no switch), and say it is a demo to whoever you show it to.

## Reading the results honestly
A budget search confirms a place only when its published menu has a priced meal line whose category is 식사 / 면류 / 분식.
Most menu items are uncategorized today, so with the demo on, "₩10,000 이하 + 도보 10분 + 주차" lists most places as
unverified (price) until menu categories are published. That is correct, not a bug.
