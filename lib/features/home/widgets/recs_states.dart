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
import '../../recommendation/home_ranking.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../utils/home_text.dart';
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

/// No place is confirmed to fit the conditions: change them, open the
/// [unverified] places whose data could not confirm them, or reset.
class RecsEmpty extends ConsumerWidget {
  const RecsEmpty({super.key, this.unverified = 0});

  /// "정보 미확인" places (listed apart, see [UnverifiedSection]).
  final int unverified;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final open = ref.watch(homeShowUnverifiedProvider);
    return HomeCard(
      child: Column(
        children: [
          MascotMessage(
            asset: AppAssets.mascotSearching,
            imageHeight: 90,
            title: unverified > 0
                ? l10n.homeNoConfirmedTitle
                : l10n.homeEmptyTitle,
            message: unverified > 0
                ? l10n.homeUnverifiedHint(unverified)
                : l10n.homeEmptyMessage,
            actionLabel: l10n.homeEditConditions,
            onAction: () => showConditionsSheet(context),
          ),
          if (unverified > 0)
            OutlinedButton.icon(
              onPressed: ref.read(homeShowUnverifiedProvider.notifier).toggle,
              icon: Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.help_outline_rounded,
                size: 19,
              ),
              label: Text(
                open
                    ? l10n.homeHideUnverified
                    : l10n.homeShowUnverified(unverified),
              ),
            ),
          TextButton.icon(
            onPressed: () {
              ref.read(conditionsProvider.notifier).clear();
              ref.read(homeCategoryProvider.notifier).clear();
            },
            style: TextButton.styleFrom(
              foregroundColor: context.palette.textSecondary,
            ),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l10n.homeRestart),
          ),
        ],
      ),
    );
  }
}

/// "가격·운영정보 미확인 N곳": the places no condition is known to fail but
/// whose data could not confirm one. Folded by default, never mixed into the
/// confirmed results.
class UnverifiedSection extends ConsumerWidget {
  const UnverifiedSection({super.key, required this.items, this.onTap});

  final List<RankedRestaurant> items;

  /// Overrides opening the details (the desktop map focuses the pin).
  final void Function(Restaurant restaurant)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final open = ref.watch(homeShowUnverifiedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: ref.read(homeShowUnverifiedProvider.notifier).toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 19,
                    color: p.statusWarn,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.listUnverifiedTitle(items.length),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: p.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open) ...[
          Text(
            l10n.listUnverifiedNote,
            style: TextStyle(fontSize: 13.5, color: p.textMuted),
          ),
          const SizedBox(height: 8),
          HomeCard(
            clip: true,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.hairline),
                  _UnverifiedRow(item: items[i], onTap: onTap),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _UnverifiedRow extends StatelessWidget {
  const _UnverifiedRow({required this.item, this.onTap});

  final RankedRestaurant item;
  final void Function(Restaurant restaurant)? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = item.restaurant;
    return InkWell(
      onTap: () => onTap == null ? openRestaurantDetail(context, r) : onTap!(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${r.categoryTag} · ${l10n.homeWalkAbout(item.walkMinutes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: p.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              missingText(l10n, item.missing),
              style: TextStyle(fontSize: 13, color: p.statusWarn),
            ),
          ],
        ),
      ),
    );
  }
}

/// After 길찾기: "다녀오셨어요?" with 먹었어요 (→ MY 식사 기록) or 아직이요
/// (stop asking). Writing a review is offered afterwards, as a choice.
class MealCheckBanner extends ConsumerWidget {
  const MealCheckBanner({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ate = RustButton(
      icon: Icons.check_circle_outline_rounded,
      label: l10n.mealAteButton,
      onPressed: () => markEaten(context, ref, restaurant, offerReview: true),
    );
    final notYet = OutlineActionButton(
      label: l10n.mealCheckDismiss,
      onPressed: () =>
          ref.read(activeRecommendationProvider.notifier).forgetWent(),
    );
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
          // Side by side only where both labels fit whole; on a phone the
          // buttons stack, each at full width.
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 420
                ? Row(
                    children: [
                      Expanded(flex: 2, child: ate),
                      const SizedBox(width: 10),
                      Expanded(child: notYet),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [ate, const SizedBox(height: 8), notYet],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Right after a meal was recorded from Home: a review is offered, never
/// opened by itself.
class ReviewPromptCard extends ConsumerWidget {
  const ReviewPromptCard({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final prompt = ref.read(reviewPromptProvider.notifier);
    return HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reviewPromptTitle(restaurant.name),
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
                  icon: Icons.rate_review_outlined,
                  label: l10n.reviewPromptWrite,
                  onPressed: () {
                    prompt.dismiss();
                    writeReviewFor(context, ref, restaurant);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlineActionButton(
                  label: l10n.reviewPromptSkip,
                  onPressed: prompt.dismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
