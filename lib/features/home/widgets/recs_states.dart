import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../../core/widgets/skeleton.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/repositories/restaurant_repository.dart';
import '../providers/home_providers.dart';
import 'home_card_parts.dart';

/// Shown instead of a preview until conditions are set or a pick is asked for.
class RecsPrompt extends StatelessWidget {
  const RecsPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return HomeCard(
      child: MascotMessage(
        asset: AppAssets.mascotSearching,
        imageHeight: 90,
        title: l10n.homePromptTitle,
        message: l10n.homePromptMessage,
      ),
    );
  }
}

/// Placeholder shapes of the hero card and the alternatives while loading.
class RecsSkeleton extends StatelessWidget {
  const RecsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      HomeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 184, radius: 16),
            SizedBox(height: 16),
            SkeletonBox(width: 180, height: 26),
            SizedBox(height: 10),
            SkeletonBox(width: 240, height: 16),
            SizedBox(height: 24),
            SkeletonBox(height: 56),
            SizedBox(height: 16),
            SkeletonBox(height: 52, radius: 14),
          ],
        ),
      ),
      SizedBox(height: 28),
      HomeCard(
        child: Column(
          children: [
            SkeletonBox(height: 64),
            SizedBox(height: 14),
            SkeletonBox(height: 64),
          ],
        ),
      ),
    ],
  );
}

/// The restaurant list could not be loaded: message and retry.
class RecsError extends ConsumerWidget {
  const RecsError({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return HomeCard(
      child: MascotMessage(
        asset: AppAssets.mascotMapConfused,
        imageHeight: 90,
        title: l10n.restaurantLoadFailedTitle,
        message: error is RestaurantException
            ? (error as RestaurantException).localizedMessage(l10n)
            : l10n.tryAgainLater,
        actionLabel: l10n.commonRetry,
        onAction: () {
          ref.invalidate(allNearbyRestaurantsProvider);
          ref.invalidate(categoryRestaurantsProvider);
        },
      ),
    );
  }
}

/// Nothing passes the conditions: offer to clear them.
class RecsEmpty extends ConsumerWidget {
  const RecsEmpty({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return HomeCard(
      child: MascotMessage(
        asset: AppAssets.mascotSearching,
        imageHeight: 90,
        title: l10n.homeEmptyTitle,
        message: l10n.homeEmptyMessage,
        actionLabel: l10n.condResetAll,
        onAction: () {
          ref.read(conditionsProvider.notifier).clear();
          ref.read(homeCategoryProvider.notifier).clear();
        },
      ),
    );
  }
}
