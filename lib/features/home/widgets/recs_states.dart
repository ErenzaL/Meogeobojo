import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/skeleton.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../conditions/widgets/conditions_sheet.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../records/meal_records.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/repositories/restaurant_repository.dart';
import '../providers/home_providers.dart';
import 'home_card_parts.dart';

/// Shown instead of a preview until conditions are set or a pick is asked for.
/// Starts with the campus / start point the recommendation is measured from.
class RecsPrompt extends ConsumerWidget {
  const RecsPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final origin = ref.watch(originProvider);
    return HomeCard(
      child: Column(
        children: [
          MascotMessage(
            asset: AppAssets.mascotSearching,
            imageHeight: 90,
            title: l10n.homePromptTitle,
            message: l10n.homePromptMessage,
          ),
          if (origin != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              decoration: BoxDecoration(
                color: p.fillMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.place_outlined, size: 20, color: p.rustText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.homePromptOrigin(origin.label(l10n)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showOriginSheet(context),
                    child: Text(l10n.homePromptOriginChange),
                  ),
                ],
              ),
            ),
        ],
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
    final reason = error is RestaurantException
        ? (error as RestaurantException).localizedMessage(l10n)
        : l10n.tryAgainLater;
    return HomeCard(
      child: MascotMessage(
        asset: AppAssets.mascotMapConfused,
        imageHeight: 90,
        title: l10n.restaurantLoadFailedTitle,
        // Retrying keeps the chosen conditions.
        message: '$reason\n${l10n.homeErrorKeepsConditions}',
        actionLabel: l10n.commonRetry,
        onAction: () {
          ref.invalidate(allNearbyRestaurantsProvider);
          ref.invalidate(categoryRestaurantsProvider);
        },
      ),
    );
  }
}

/// No place is confirmed to fit the conditions: change them, see the
/// [unverified] places whose data could not confirm them, or clear them all.
class RecsEmpty extends ConsumerWidget {
  const RecsEmpty({super.key, this.unverified = 0});

  /// Places that passed only because their data is missing.
  final int unverified;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return HomeCard(
      child: Column(
        children: [
          MascotMessage(
            asset: AppAssets.mascotSearching,
            imageHeight: 90,
            title: l10n.homeEmptyTitle,
            message: unverified > 0
                ? l10n.homeEmptyUnverifiedMessage
                : l10n.homeEmptyMessage,
            actionLabel: l10n.homeEmptyChange,
            onAction: () => showConditionsSheet(context),
          ),
          if (unverified > 0)
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(homeShowUnverifiedProvider.notifier).show(),
              icon: const Icon(Icons.help_outline_rounded, size: 19),
              label: Text(l10n.homeShowUnverified(unverified)),
            ),
          TextButton(
            onPressed: () {
              ref.read(conditionsProvider.notifier).clear();
              ref.read(homeCategoryProvider.notifier).clear();
            },
            style: TextButton.styleFrom(
              foregroundColor: context.palette.textSecondary,
            ),
            child: Text(l10n.condResetAll),
          ),
        ],
      ),
    );
  }
}

/// After 길찾기: "다녀오셨어요?" with 먹었어요 · 평가 남기기 (→ MY 식사 기록) or
/// 아직이요 (stop asking).
class MealCheckBanner extends ConsumerWidget {
  const MealCheckBanner({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.mealCheckTitle(restaurant.name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: RustButton(
                  icon: Icons.check_circle_outline_rounded,
                  label: l10n.mealAteButton,
                  onPressed: () => markEaten(context, ref, restaurant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlineActionButton(
                  label: l10n.mealCheckDismiss,
                  onPressed: () => ref
                      .read(activeRecommendationProvider.notifier)
                      .forgetWent(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
