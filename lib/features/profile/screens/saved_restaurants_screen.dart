import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../auth/widgets/auth_fields.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/widgets/restaurant_async_list.dart';
import '../../restaurants/widgets/restaurant_list_tile.dart';

/// 저장한 맛집 (V5): title, "N곳 저장됨", the saved places, or an empty state that leads back to the recommendations.
/// Only the Kakao place id is stored (retention terms are unverified), so details are shown for saved places that
/// appear in the currently loaded results around the selected university.
class SavedRestaurantsScreen extends ConsumerWidget {
  const SavedRestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final favorites = ref.watch(favoritesProvider);
    final nearby = ref.watch(allNearbyRestaurantsProvider);
    final ids = favorites.value ?? const <String>{};

    void toHome() {
      ref.read(shellTabProvider.notifier).select(ShellTabs.home);
      Navigator.of(context).popUntil((r) => r.isFirst);
    }

    final List<Widget> body;
    if (favorites.isLoading) {
      body = const [SizedBox(height: 480, child: RestaurantListSkeleton())];
    } else if (favorites.hasError) {
      body = [
        V5EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.savedLoadFailed,
          actions: [
            V5SmallButton(
              label: l10n.commonRetry,
              onPressed: () => ref.invalidate(favoritesProvider),
            ),
          ],
        ),
      ];
    } else if (ids.isEmpty) {
      body = [
        V5EmptyState(
          icon: Icons.favorite_border_rounded,
          title: l10n.savedEmptyTitle,
          message: l10n.savedEmptyMessage,
          actions: [
            V5SmallButton(label: l10n.savedGoRecommend, onPressed: toHome),
          ],
        ),
      ];
    } else {
      final known = (nearby.value ?? const [])
          .where((r) => ids.contains(r.kakaoId))
          .toList();
      final hidden = ids.length - known.length;
      final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
      body = [
        // Two columns of cards on a wide window, one list on a phone.
        LayoutBuilder(
          builder: (context, box) {
            final w = wide ? (box.maxWidth - 12) / 2 : box.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final r in known)
                  SizedBox(
                    width: w,
                    child: RestaurantListTile(restaurant: r),
                  ),
              ],
            );
          },
        ),
        if (hidden > 0) ...[
          const SizedBox(height: 12),
          AuthMessage.info(l10n.savedHiddenNote(hidden)),
        ],
      ];
    }

    return V5Page(
      maxWidth: 960,
      children: [
        V5Header(
          leading: BackButton(color: context.palette.textPrimary),
          title: l10n.profileSaved,
          subtitle: favorites.hasValue && ids.isNotEmpty
              ? l10n.savedCountLine(ids.length)
              : null,
        ),
        const SizedBox(height: 16),
        ...body,
      ],
    );
  }
}
