import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../auth/widgets/auth_fields.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/widgets/restaurant_async_list.dart';
import '../../restaurants/widgets/restaurant_list_tile.dart';

/// The user's saved places. Only the Kakao place id is stored (retention
/// terms are unverified), so details are shown for saved places that appear
/// in the currently loaded results around the selected university.
class SavedRestaurantsScreen extends ConsumerWidget {
  const SavedRestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final favorites = ref.watch(favoritesProvider);
    final nearby = ref.watch(allNearbyRestaurantsProvider);

    Widget body() {
      if (favorites.isLoading) return const RestaurantListSkeleton();
      if (favorites.hasError) {
        return MascotMessage(
          asset: AppAssets.mascotMapConfused,
          title: l10n.savedLoadFailed,
          actionLabel: l10n.commonRetry,
          onAction: () => ref.invalidate(favoritesProvider),
        );
      }
      final ids = favorites.requireValue;
      if (ids.isEmpty) {
        return MascotMessage(
          asset: AppAssets.mascotSleeping,
          title: l10n.savedEmptyTitle,
          message: l10n.savedEmptyMessage,
        );
      }
      final known = (nearby.value ?? const [])
          .where((r) => ids.contains(r.kakaoId))
          .toList();
      final hidden = ids.length - known.length;
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          Text(l10n.savedCount(ids.length), style: AppText.sectionTitle),
          const SizedBox(height: 12),
          for (final r in known) ...[
            RestaurantListTile(restaurant: r),
            const SizedBox(height: 12),
          ],
          if (hidden > 0) AuthMessage.info(l10n.savedHiddenNote(hidden)),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileSaved)),
      body: body(),
    );
  }
}
