import 'package:flutter/material.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../../core/widgets/skeleton.dart';
import '../models/restaurant.dart';
import '../repositories/restaurant_repository.dart';
import 'restaurant_list_tile.dart';
import '../../../core/l10n/l10n.dart';

/// Skeleton rows shown while a list loads.
class RestaurantListSkeleton extends StatelessWidget {
  const RestaurantListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.screenH),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => const SkeletonBox(height: 96, radius: 20),
    );
  }
}

/// Error view with a friendly message and retry.
class RestaurantErrorView extends StatelessWidget {
  const RestaurantErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = error is RestaurantException
        ? (error as RestaurantException).localizedMessage(l10n)
        : l10n.restaurantLoadFailedMessage;
    return MascotMessage(
      asset: AppAssets.mascotMapConfused,
      title: l10n.restaurantLoadFailedTitle,
      message: message,
      actionLabel: l10n.commonRetry,
      onAction: onRetry,
    );
  }
}

class RestaurantListView extends StatelessWidget {
  const RestaurantListView({
    super.key,
    required this.restaurants,
    this.header,
    this.numbered = false,
  });

  final List<Restaurant> restaurants;
  final Widget? header;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        8,
        AppSpacing.screenH,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: restaurants.length + (header == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (header != null) {
          if (i == 0) return header!;
          i -= 1;
        }
        return RestaurantListTile(
          restaurant: restaurants[i],
          rank: numbered ? i + 1 : null,
        );
      },
    );
  }
}
