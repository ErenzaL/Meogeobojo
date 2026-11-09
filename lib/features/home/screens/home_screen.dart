import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/home_providers.dart';
import '../widgets/alternatives_section.dart';
import '../widgets/cafeteria_card.dart';
import '../widgets/hero_card.dart';
import '../widgets/home_title_block.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/recs_states.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const pad = EdgeInsets.symmetric(horizontal: AppSpacing.screenH);
    final recs = ref.watch(homeRecsProvider);

    return Scaffold(
      backgroundColor: context.palette.pageWarm,
      body: SafeArea(
        bottom: false, // the bottom bar in the shell handles the home indicator
        child: ListView(
          // Keeps scroll offset when the shell switches tabs (IndexedStack).
          key: const PageStorageKey('home-scroll'),
          // The shell reports the floating bar's footprint as bottom padding,
          // so the last card can scroll fully above it.
          padding: EdgeInsets.only(
            top: 8,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const Padding(padding: pad, child: HomeTopBar()),
            const SizedBox(height: 22),
            const Padding(padding: pad, child: HomeTitleBlock()),
            const SizedBox(height: 18),
            const Padding(padding: pad, child: HomeChipRow()),
            const SizedBox(height: 18),
            Padding(
              padding: pad,
              child: recs.when(
                loading: () => const RecsSkeleton(),
                error: (e, _) => RecsError(error: e),
                data: (data) => data == null
                    ? const RecsEmpty()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                              key: ValueKey(data.hero.restaurant.kakaoId),
                              recs: data,
                            ),
                          ),
                          const SizedBox(height: 28),
                          AlternativesSection(recs: data),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 28),
            const Padding(padding: pad, child: CafeteriaCard()),
          ],
        ),
      ),
    );
  }
}
