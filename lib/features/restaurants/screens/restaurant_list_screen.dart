import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../recommendation/recommendation_service.dart';
import '../../university/providers/university_providers.dart';
import '../../university/widgets/university_sheet.dart';
import '../providers/restaurant_providers.dart';
import '../widgets/restaurant_async_list.dart';
import '../../../core/l10n/l10n.dart';
import '../../preferences/screens/preferences_screen.dart';
import '../../university/models/university_display.dart';
import '../../../core/theme/app_palette.dart';

/// Full list of places around the selected university ("더보기").
class NearbyRestaurantsScreen extends ConsumerWidget {
  const NearbyRestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyRestaurantsProvider);
    final category = ref.watch(selectedCategoryProvider);
    final univ = ref.watch(selectedUniversityProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.homeNearbyTitle)),
      body: async.when(
        loading: () => const RestaurantListSkeleton(),
        error: (e, _) => RestaurantErrorView(
          error: e,
          onRetry: () => ref.invalidate(nearbyRestaurantsProvider),
        ),
        data: (items) => items.isEmpty
            ? MascotMessage(
                asset: AppAssets.mascotSearching,
                title: context.l10n.restaurantEmptyTitle,
                actionLabel: context.l10n.commonRetry,
                onAction: () => ref.invalidate(nearbyRestaurantsProvider),
                secondaryLabel: context.l10n.universityChange,
                onSecondary: () => showUniversitySheet(context),
              )
            : RestaurantListView(
                restaurants: items,
                header: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    context.l10n.restaurantListSubtitle(
                      univ?.displayName(Localizations.localeOf(context)) ?? '',
                      category.label(context.l10n),
                    ),
                    style: AppText.caption(context),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Recommendation result. With [usePreferences] the signed-in user's saved
/// distance / cuisine conditions are applied (see `applyPreferences`).
class RecommendationScreen extends ConsumerWidget {
  const RecommendationScreen({super.key, this.usePreferences = false});

  final bool usePreferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final provider = recommendationProvider(usePreferences);
    final async = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeBannerLabel)),
      body: async.when(
        loading: () => const RestaurantListSkeleton(),
        error: (e, _) => RestaurantErrorView(
          error: e,
          onRetry: () => ref.invalidate(provider),
        ),
        data: (result) {
          if (result.restaurants.isEmpty) {
            return usePreferences
                ? MascotMessage(
                    asset: AppAssets.mascotSearching,
                    title: l10n.recommendNoMatchTitle,
                    message: l10n.recommendNoMatchMessage,
                    actionLabel: l10n.profilePreferences,
                    onAction: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const PreferencesScreen(mode: PreferencesMode.edit),
                      ),
                    ),
                    secondaryLabel: l10n.universityChange,
                    onSecondary: () => showUniversitySheet(context),
                  )
                : MascotMessage(
                    asset: AppAssets.mascotSearching,
                    title: l10n.restaurantEmptyTitle,
                    actionLabel: l10n.commonRetry,
                    onAction: () => ref.invalidate(provider),
                    secondaryLabel: l10n.universityChange,
                    onSecondary: () => showUniversitySheet(context),
                  );
          }
          final university = result.university.displayName(
            Localizations.localeOf(context),
          );
          final (title, explanation) = switch (result.strategy) {
            RecommendationStrategy.proximityBaseline => (
              l10n.recommendStrategyProximity(university),
              l10n.recommendExplainBaseline,
            ),
            RecommendationStrategy.proximityWithPreferences => (
              l10n.recommendStrategyPreferences,
              l10n.recommendExplainPreferences(
                result.restaurants.length,
                result.candidateCount,
              ),
            ),
          };
          return RestaurantListView(
            restaurants: result.restaurants,
            numbered: true,
            header: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.palette.accentFaint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.title.copyWith(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(explanation, style: AppText.caption(context)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
