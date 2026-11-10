import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/content_sync.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../missions/providers/mission_providers.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../providers/home_providers.dart';
import '../widgets/alternatives_section.dart';
import '../widgets/cafeteria_card.dart';
import '../widgets/hero_card.dart';
import '../widgets/home_category_bar.dart';
import '../widgets/home_filter_bar.dart';
import '../widgets/home_recommend_button.dart';
import '../widgets/home_search_field.dart';
import '../widgets/home_top_bar.dart';
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
  final _resultsKey = GlobalKey();

  /// Back to the untouched Home: no conditions, no category, no pick shown.
  void _restart() {
    ref.read(conditionsProvider.notifier).clear();
    ref.read(homeCategoryProvider.notifier).clear();
    ref.read(heroPickProvider.notifier).reset();
    ref.read(homeRecsRequestedProvider.notifier).reset();
  }

  /// "오늘의 추천 받기": runs the recommendation again for the current
  /// filters (the top-ranked place, or a retry if the list failed to load)
  /// and brings the result into view.
  void _recommend() {
    // Counts toward "오늘 뭐 먹지?" (one per day, decided by the server).
    logMissionActivity(ref, 'recommendation_view');
    if (ref.read(homeRecsProvider).hasError) {
      ref.invalidate(allNearbyRestaurantsProvider);
      ref.invalidate(categoryRestaurantsProvider);
    }
    ref.read(homeRecsRequestedProvider.notifier).request();
    ref.read(heroPickProvider.notifier).reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultsKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.04,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const gutter = AppSpacing.screenH;
    const pad = EdgeInsets.symmetric(horizontal: gutter);
    final recs = ref.watch(homeRecsProvider);
    final categories = ref.watch(homeCategoryProvider);
    final showRecs = ref.watch(homeShowRecsProvider);

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
                const Padding(padding: pad, child: HomeTopBar()),
                const SizedBox(height: 8),
              ] else
                const Padding(padding: pad, child: HomeWelcome()),
              const Padding(padding: pad, child: HomeNotices()),
              const Padding(padding: pad, child: HomeSearchField()),
              const SizedBox(height: 14),
              const HomeCategoryBar(padding: pad),
              const SizedBox(height: 8),
              const HomeFilterBar(padding: pad),
              const SizedBox(height: 14),
              Padding(
                padding: pad,
                child: HomeRecommendButton(
                  onPressed: _recommend,
                  onRestart: showRecs ? _restart : null,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                key: _resultsKey,
                padding: pad,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final twoColumn =
                        box.maxWidth >= Breakpoints.homeTwoColumn - 2 * 20;
                    final recsColumn = !showRecs
                        ? const RecsPrompt()
                        : recs.when(
                            loading: () => const RecsSkeleton(),
                            error: (e, _) => RecsError(error: e),
                            data: (data) => data == null
                                ? const RecsEmpty()
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Changing the pick fades the new card in.
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 260,
                                        ),
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
                                      ),
                                    ],
                                  ),
                          );
                    // Tablet / desktop: recommendations left, cafeteria right.
                    if (twoColumn) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: recsColumn),
                          const SizedBox(width: 24),
                          const Expanded(
                            flex: 2,
                            child: CafeteriaCard(stackButtons: true),
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
