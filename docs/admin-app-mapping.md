# Admin feature → Supabase → Flutter map

Every row was traced in code. "Live" = a change reaches a running app without a
new build (resume, pull-to-refresh, or Realtime once `20261112000100` is applied).

| Admin page / action | Written to (RLS / RPC) | Flutter reads it through | Visible to students when | Live |
|---|---|---|---|---|
| 식당 → 카카오 식당 불러오기 | RPC `admin_register_kakao_places` → `restaurant_overrides` (+`restaurant_university_links`), id + name label only | `OverrideAwareRestaurantRepository` (merge by Kakao id) | draft = no change; published = admin fields apply | yes |
| 식당 → edit (name, address, phone, description, price, last order) | `restaurant_overrides` (admin RLS) | `restaurant_override_repository.forPlaces` → merge + detail + insight | `visibility = published` | yes |
| 식당 → hide / archive | `restaurant_overrides.visibility` | the same merge drops the place from Home, map, search, category pages, saved places | immediately on refresh | yes |
| 식당 → 추천 식당 + order | `restaurant_overrides.featured, display_order`, `app_content` kind featured | `featuredFirst()` orders the "오늘의 추천" carousel (ranking untouched) | published place, on Home | yes |
| 사진 관리 (cover, gallery) | `restaurant_photos` + Storage `restaurant-images`; cover mirrored to `restaurant_overrides.image_url` (trigger) | `restaurant_override_repository.photos`, `restaurantPhotosProvider`; cards use `insight.imageUrl` | published photo of a published place | yes |
| 메뉴·가격 | `restaurant_menus` (`restaurant_id`; trigger fills `kakao_place_id`) | `menus(kakaoId)` → detail; archived items dropped | active menus of a published place | yes |
| 학식 (meals, photo, notice, draft/publish) | `cafeteria_meals` (+`extra`), `campus_cafeterias` | `campus_meal_repository` (`weekMeals`) → 학식 screen | `status <> 'draft'` (RLS) | yes |
| 앱 콘텐츠 (notice, banner, featured) | `app_content` (admin write; public read only while active and inside dates) | `appContentProvider` → Home notices, featured order | active and in window; campus filter in the app | yes |
| 미션 관리 (missions, campaigns) | RPC `admin_save_mission`, `admin_save_campaign`, `admin_set_*` → `missions`, `monthly_campaigns` | RPC `sync_my_missions()` → `missionDashboardProvider` | campaign published + started, mission active, dates OK, **account campus matches** | yes |
| 미션 → 기여 검토 | RPC `admin_review_contribution` → `user_contributions` | mission progress via `sync_my_missions()` | approved contribution counts | on refresh |
| 리뷰·신고 | RPC `admin_moderate_review`, `admin_resolve_report` → `student_reviews` | review lists hide non-visible reviews (RLS) | `moderation_status = visible` | n/a: no review UI in the app yet |
| 사용자 | RPC `admin_set_account_status`, `admin_grant_role` → `profiles`, `admin_roles` | auth/profile load | per account | n/a |
| 대학교 | `universities` (admin RLS) | `universityListProvider` (campus list, coordinates) | `is_active` | on restart / campus list reload |
| 추천 | read-only stats `admin_recommendation_stats` | none (mock recommendation service) | n/a | n/a |
| 분석, 활동 기록 | read-only (`admin_*_stats`, `audit_log`) | n/a | n/a | n/a |

Known disconnects: reviews and photo submissions have no Flutter UI; the
recommendation engine is a mock service; 대학교 edits need a campus-list reload
(restart) to show in the picker.
