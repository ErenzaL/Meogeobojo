# Recommendation V3 (what the app actually does)

The ranking is the team's V3 model, implemented as a fixed formula inside the app. It is **not** a trained model at run
time and nothing here claims otherwise: the same request always gives the same order.

Code: `lib/features/recommendation/recommendation_score.dart` (formula), `home_ranking.dart` (`rankRestaurants`, one
ranking for Home, the map, search and the recommendation screen), `review_signal_repository.dart` (R).

## Who qualifies (조건 판정, unchanged)
Distance (straight line from the chosen start) and the budget decide this. Menus are filed under four categories:
**식사** (a one-person meal: noodles, rice, soup, burger, toast ...), **사이드** (add-ons and small sides), **음료** (every drink)
and **기타** (shared dishes and 안주, pizza, whole chicken, sets for several people, desserts, bakery). With a budget, a
place is a **match** when a priced, in-stock, currently served line that the place *offers* is within the budget
(`MenuLine.isOffered`): at a restaurant every line except 음료 and 사이드, at a cafe (Kakao group CE7) the drinks too.
Older categories (면류, 분식, 안주, 디저트) are still understood (면류 / 분식 count as meals). Missing prices or lines with
no category make it **정보 미확인** (listed after the matches); a place whose offered lines are all over the budget is
**dropped**. The matching-menus row under the top pick on Home lists the same lines, meals first.

## How they are ordered (V3)
```
C  = 1 if the place is in a preferred food class, else 0
D  = max(0, 1 - distance / max distance)         (any distance: the farthest candidate is the scale)
V0 = D
V1 = 0.5 * C + 0.5 * D                           (no preference chosen: V1 = D)
V3 = clip(V1 + 0.2 * R, 0, 1)
```
Matches first, then 정보 미확인; inside each group by V3 (high first), then nearer, then place id.
`SortMode.distance / price / rating` still sort as before.

R (review signal): `0.7 * (adjusted stars - overall stars) / 4 + 0.3 * (adjusted text - overall text)`, where the adjusted
mean is `(sum(w * x) + 20 * overall) / (sum(w) + 20)` and `w = 2^(-age / 90 days)`. No reviews: R = 0.

## Differences from the team's notes (decide / fix)
1. **Food preference is a score, not a filter.** Before, choosing 한식 hid everything else; now it only lifts matching
   places (as in the notes). The 조건 sheet no longer reduces the count by food type.
2. **Review text score is not available.** The notes use a text classifier trained on their review data. The app has no
   such model, so R uses the star rating only (the notes say a single available signal is used alone). The text term is
   implemented and activates when scores are provided.
3. **Review data.** The notes' reviews are the team's own dataset. The app uses the visible `student_reviews` (currently
   none), so R is 0 until students review.
4. **Radius.** The notes use 1 km; the app's distance options are walking / driving minutes converted at 80 m/min and
   500 m/min (approximate, straight line), as before.
5. **Menu classification** (the 43 restaurants / 192 meals in the notes) lives in the team's offline file, not in our
   database. `restaurant_menus.category` is mostly empty, so budgets cannot be confirmed for most places. A proposal for
   review is generated separately (`menu_categories_proposed.csv`, import with 메뉴 CSV in update mode). Until the
   categories are published, budget searches stay "정보 미확인".
