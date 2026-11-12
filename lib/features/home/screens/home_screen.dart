import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/content_sync.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../missions/providers/mission_providers.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../conditions/widgets/conditions_sheet.dart';
import '../../records/meal_records.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../university/widgets/university_sheet.dart';
import '../../recommendation/home_ranking.dart';
import '../providers/home_providers.dart';
import '../widgets/alternatives_section.dart';
import '../widgets/cafeteria_card.dart';
import '../widgets/hero_card.dart';
import '../widgets/home_category_bar.dart';
import '../widgets/home_filter_bar.dart';
import '../widgets/home_recommend_button.dart';
import '../widgets/home_search_field.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/advanced_filters.dart';
import '../widgets/home_welcome.dart';
import '../../../core/widgets/web_footer.dart';
import '../../content/providers/app_content_providers.dart';
import '../../content/widgets/home_notices.dart';
import '../widgets/recs_states.dart';
import '../widgets/today_picks_section.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Back to the untouched Home: no conditions, no category, no pick shown.
  void _restart() {
    ref.read(conditionsProvider.notifier).clear();
    ref.read(homeCategoryProvider.notifier).clear();
    ref.read(heroPickProvider.notifier).reset();
    ref.read(homeRecsRequestedProvider.notifier).reset();
    ref.read(activeRecommendationProvider.notifier).clear();
    ref.read(restoreHeroProvider.notifier).consume();
  }

  /// Remembers the pick on screen as the recommendation in use, and puts the
  /// one from the last visit back once the same filters are in place again.
  void _remember(HomeRecs? data) {
    final key = ref.read(homeRecsKeyProvider);
    // Only a confirmed match is ever "the recommendation in use".
    if (data == null || key == null || !ref.read(homeShowRecsProvider)) return;
    final heroId = data.hero.restaurant.kakaoId;
    final restore = ref.read(restoreHeroProvider);
    if (restore != null && restore.key == key) {
      ref.read(restoreHeroProvider.notifier).consume();
      // From here on it is an ordinary pick (reset by any filter change).
      if (heroId == restore.heroId) {
        ref.read(heroPickProvider.notifier).choose(heroId);
      }
    }
    ref.read(activeRecommendationProvider.notifier).save(heroId, key);
  }

  /// "조건에 맞게 추천받기": runs the recommendation for the current filters
  /// (the top-ranked match, or a retry if the list failed to load).
  void _recommend() {
    // Counts toward "오늘 뭐 먹지?" (one per day, decided by the server).
    logMissionActivity(ref, 'recommendation_view');
    if (ref.read(homeRecsProvider).hasError) {
      ref.invalidate(allNearbyRestaurantsProvider);
      ref.invalidate(categoryRestaurantsProvider);
    }
    ref.read(homeRecsRequestedProvider.notifier).request();
    ref.read(heroPickProvider.notifier).reset();
    // A new recommendation is in use even when it is the same place as the
    // meal just logged, and even if nothing on screen changes.
    ref.read(activeRecommendationProvider.notifier).startNew();
    _remember(ref.read(homeRecsProvider).value);
    // The result appears in place. The page is deliberately NOT scrolled to it: it used to jump away from the button
    // the user had just tapped.
  }

  @override
  Widget build(BuildContext context) {
    // 20 on phones; on the website the page gutter (24 / 28 / 40) so Home lines up with the header and the footer
    final gutter = WebLayout.gutterOf(context, phone: AppSpacing.screenH);
    final pad = EdgeInsets.symmetric(horizontal: gutter);
    final recs = ref.watch(homeRecsProvider);
    final categories = ref.watch(homeCategoryProvider);
    final showRecs = ref.watch(homeShowRecsProvider);
    // Deferred: a listener may run while a widget is building. Asking for a
    // pick or showing the unconfirmed ones changes what is on screen without
    // changing the ranking, so those are listened to as well.
    void remember(_, _) => scheduleMicrotask(() {
      if (mounted) _remember(ref.read(homeRecsProvider).value);
    });
    ref.listen(homeRecsProvider, remember);
    ref.listen(homeShowRecsProvider, remember);
    // "정보 미확인" places: never the hero, listed apart under the results.
    final unverified =
        ref.watch(homePoolRankedProvider).value?.unconfirmed ?? const [];
    final shown = showRecs ? recs.value : null;
    final went = ref.watch(activeRecommendationProvider.select((a) => a?.went));
    final reviewFor = ref.watch(reviewPromptProvider);

    return Scaffold(
      backgroundColor: whitePageColor(context),
      body: SafeArea(
        bottom: false, // the bottom bar in the shell handles the home indicator
        // Pull down to re-read everything an admin published (the fallback for
        // when a live update was missed).
        child: RefreshIndicator(
          onRefresh: () => refreshAllContentAndWait(
            ProviderScope.containerOf(context, listen: false),
          ),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Keeps scroll offset when the shell switches tabs (IndexedStack).
            key: const PageStorageKey('home-scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // The shell reports the floating bar's footprint as bottom padding,
            // so the last card can scroll fully above it.
            padding: EdgeInsets.only(
              top: 8,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              // Desktop has the shared header; this row is phone-only. Desktop gets the welcome section instead
              // (the selected university and its selector, which the header does not carry).
              if (MediaQuery.sizeOf(context).width < Breakpoints.desktop) ...[
                Padding(padding: pad, child: HomeTopBar()),
                const SizedBox(height: 8),
              ] else
                Padding(padding: pad, child: HomeWelcome()),
              Padding(padding: pad, child: HomeNotices()),
              // The saved start point is gone (the old "기숙사"): say which
              // one is used meanwhile and offer to choose.
              Padding(padding: pad, child: const OriginReselectBanner()),
              Padding(padding: pad, child: const UniversitySwitchBanner()),
              Padding(padding: pad, child: HomeSearchField()),
              const SizedBox(height: 14),
              HomeCategoryBar(padding: pad),
              const SizedBox(height: 8),
              HomeFilterBar(padding: pad),
              // Desktop: the expandable advanced panel and the removable applied-filter chips.
              if (MediaQuery.sizeOf(context).width >= Breakpoints.desktop)
                Padding(
                  padding: pad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [AdvancedFilterPanel(), AppliedFilterChips()],
                  ),
                ),
              const SizedBox(height: 14),
              Padding(
                padding: pad,
                child: HomeRecommendButton(
                  onPressed: _recommend,
                  onOther: shown == null
                      ? null
                      : () => ref.read(heroPickProvider.notifier).next(shown),
                  onEdit: () => showConditionsSheet(context),
                  onlyOne: shown != null && shown.total < 2,
                  onRestart: showRecs ? _restart : null,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: pad,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final twoColumn =
                        box.maxWidth >= Breakpoints.homeTwoColumn - 2 * 20;
                    final recsBody = !showRecs
                        ? const RecsPrompt()
                        : recs.when(
                            loading: () => const RecsSkeleton(),
                            error: (e, _) => RecsError(error: e),
                            data: (data) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (data == null)
                                  RecsEmpty(unverified: unverified.length)
                                else ...[
                                  // Changing the pick fades the new card in.
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 260),
                                    switchInCurve: Curves.easeOutCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween(
                                              begin: const Offset(0.04, 0),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: HeroCard(
                                      key: ValueKey(
                                        data.hero.restaurant.kakaoId,
                                      ),
                                      recs: data,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  AlternativesSection(recs: data),
                                  const SizedBox(height: 28),
                                  // Before 학식: the places that fit the filters.
                                  TodayPicksSection(
                                    ranked: featuredFirst(
                                      data.ranked,
                                      ref
                                              .watch(
                                                restaurantOverridesProvider,
                                              )
                                              .value ??
                                          const {},
                                      ref.watch(featuredContentIdsProvider),
                                    ),
                                    categories: categories,
                                    bleed: twoColumn ? 0 : gutter,
                                    // website: a responsive grid of cards
                                    grid:
                                        twoColumn &&
                                        WebLayout.fullWidthOf(context),
                                  ),
                                ],
                                if (unverified.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  UnverifiedSection(items: unverified),
                                ],
                              ],
                            ),
                          );
                    // Back from 길찾기: did they eat there? Asked whatever the
                    // ranking shows now (the place may have closed or left the
                    // filters while they were eating).
                    final recsColumn = went == null && reviewFor == null
                        ? recsBody
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (went != null)
                                MealCheckBanner(restaurant: went)
                              else
                                ReviewPromptCard(restaurant: reviewFor!),
                              const SizedBox(height: 16),
                              recsBody,
                            ],
                          );
                    // Tablet / desktop: recommendations left, cafeteria right.
                    if (twoColumn) {
                      // The cafeteria column keeps a card-like width (about a third of the page, 380-520 px) so a
                      // very wide window gives the room to the restaurants, not to a stretched cafeteria card.
                      final side = (box.maxWidth * 0.34).clamp(380.0, 520.0);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: recsColumn),
                          SizedBox(width: gutter > 20 ? 32 : 24),
                          SizedBox(
                            width: side,
                            child: const CafeteriaCard(stackButtons: true),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        recsColumn,
                        const SizedBox(height: 28),
                        const CafeteriaCard(),
                      ],
                    );
                  },
                ),
              ),
              const WebFooterSlot(),
            ],
          ),
        ),
      ),
    );
  }
}
