# Recommendation features: real rows and demo rows

`recommendation_demo_features` holds hours and amenities per Kakao place id. A row is either **real** (`demo_data = false`,
entered by an admin, read by every build, shown like any other information) or **simulated** (`demo_data = true`, read only
while demo mode is on). One row per place: importing a real row replaces its demo row. The restaurant record's own values
still win over both. Real rows need `supabase/migrations/20261126000100_recommendation_features_real.sql` (it lifts the
demo-only CHECK); without it the database rejects them.

## The simulated part (development only)

A synthetic dataset (`meogeobojo_recommendation_DEMO_FEATURES_NOT_DIRECT_IMPORT.csv`) lets the recommendation be shown with
hours and amenities before real data exists. **It is simulated. It is never verified information.**

## What is where
| Thing | Source |
|---|---|
| Position / distance | Kakao's live coordinates (`resolve_places`), never the demo file (its latitude/longitude are empty and ignored) |
| Budget (₩ 이하) | Published menus and their `menu_category` (식사 / 사이드 / 음료 / 기타): a restaurant offers every line except 음료 and 사이드, a cafe its drinks too. Never the file's `meal_under_*_demo` flags |
| Opening time, last order, break time, parking, no-break-time, local currency, fast turnover, takeout, open late | `recommendation_demo_features`: real rows always, simulated rows only while demo mode is on |
| Everything an administrator entered | wins over the demo, always |

## Pieces
* **Migration** `supabase/migrations/20261123000100_recommendation_demo_features.sql` (apply it yourself; drop the table to remove the demo).
  Keyed by `kakao_place_id`, read by anyone, written by admins only. (The original migration forced `demo_data = true`; the later one above lifts that.)
* **Admin import**: 추천 page, "추천 정보 CSV 가져오기" (button in the header, card at the top). Choose per file: follow the
  `demo_data` column (TRUE = demo, FALSE = real), or "모두 실제 데이터" / "모두 데모 데이터". Columns may be named with or without
  `_demo`. Preview (real / demo counts), then save; it upserts into that one table and nothing else. "CSV 양식" and "저장된
  데이터 내려받기" give an empty template and an export that imports back.
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
A budget search confirms a place only when its published menu has a priced line it offers (see recommendation-v3.md) within
the budget. Lines with no category count as nothing, and restaurants with no menu at all cannot be confirmed: that is
correct, not a bug. The 추천 page of the admin shows, per restaurant, the lines the app will use and their cheapest price.
