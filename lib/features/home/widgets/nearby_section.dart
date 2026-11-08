import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../../core/widgets/skeleton.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/repositories/restaurant_repository.dart';
import '../../restaurants/screens/restaurant_list_screen.dart';
import '../../restaurants/widgets/restaurant_card.dart';
import '../../university/widgets/university_sheet.dart';
import 'home_header.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

class NearbySection extends ConsumerWidget {
  const NearbySection({super.key});

  static const _maxCards = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyRestaurantsProvider);
    final cardWidth =
        ((MediaQuery.sizeOf(context).width - AppSpacing.screenH * 2) / 2.2)
            .clamp(150.0, 200.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: SectionHeader(
            title: context.l10n.homeNearbyTitle,
            icon: Icons.place_rounded,
            onMore: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NearbyRestaurantsScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => _row(cardWidth, [
            for (var i = 0; i < 3; i++)
              SkeletonBox(
                width: cardWidth,
                height: cardWidth / 1.2 + 70,
                radius: 20,
              ),
          ]),
          error: (e, _) => _Inline(
            child: MascotMessage(
              asset: AppAssets.mascotMapConfused,
              imageHeight: 90,
              title: context.l10n.restaurantLoadFailedTitle,
              message: e is RestaurantException
                  ? e.localizedMessage(context.l10n)
                  : context.l10n.tryAgainLater,
              actionLabel: context.l10n.commonRetry,
              onAction: () => ref.invalidate(nearbyRestaurantsProvider),
            ),
          ),
          data: (items) => items.isEmpty
              ? _Inline(
                  child: MascotMessage(
                    asset: AppAssets.mascotSearching,
                    imageHeight: 90,
                    title: context.l10n.restaurantEmptyTitle,
                    actionLabel: context.l10n.commonRetry,
                    onAction: () => ref.invalidate(nearbyRestaurantsProvider),
                    secondaryLabel: context.l10n.universityChange,
                    onSecondary: () => showUniversitySheet(context),
                  ),
                )
              : _row(cardWidth, [
                  for (final r in items.take(_maxCards))
                    RestaurantCard(restaurant: r, width: cardWidth),
                ]),
        ),
      ],
    );
  }

  Widget _row(double cardWidth, List<Widget> children) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Vertical padding keeps card shadows from being clipped.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        6,
        AppSpacing.screenH,
        16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Inline extends StatelessWidget {
  const _Inline({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.palette.border),
      ),
      child: child,
    );
  }
}
