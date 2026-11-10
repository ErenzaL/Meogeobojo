import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../conditions/models/conditions.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../home/widgets/restaurant_art.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/repositories/restaurant_repository.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';

/// V5 bottom sheet over the map: "조건에 맞는 N곳", the sort, and the places
/// that pass the shared conditions, nearest-first by default. Walking times are
/// straight-line estimates and the sheet says so.
class MapPlacesSheet extends ConsumerWidget {
  const MapPlacesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.16,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.16, 0.4, 0.95],
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: p.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ..._placesChildren(context, ref),
          ],
        ),
      ),
    );
  }
}

/// Desktop: the same list as a fixed panel beside the map. A row focuses its pin on the map ([onFocus]) instead of
/// leaving the page; the focused card then offers the details.
class MapPlacesPanel extends ConsumerWidget {
  const MapPlacesPanel({super.key, required this.onFocus, this.focusedId});

  final void Function(Restaurant restaurant) onFocus;

  /// The restaurant whose pin is selected (its row is highlighted).
  final String? focusedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Container(
      key: const ValueKey('map-places-panel'),
      decoration: BoxDecoration(
        color: p.background,
        border: Border(left: BorderSide(color: p.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: _placesChildren(
          context,
          ref,
          onRowTap: onFocus,
          focusedId: focusedId,
        ),
      ),
    );
  }
}

String _sortLabel(BuildContext context, SortMode m) {
  final l10n = context.l10n;
  return switch (m) {
    SortMode.recommended => l10n.condSortRecommended,
    SortMode.distance => l10n.categorySortDistance,
    SortMode.price => l10n.condSortPrice,
    SortMode.rating => l10n.condSortRating,
  };
}

/// "조건에 맞는 N곳", the sort and the places: shared by the phone sheet and the desktop panel.
List<Widget> _placesChildren(
  BuildContext context,
  WidgetRef ref, {
  void Function(Restaurant restaurant)? onRowTap,
  String? focusedId,
}) {
  final l10n = context.l10n;
  final p = context.palette;
  final ranked = ref.watch(rankedRestaurantsProvider);
  final origin = ref.watch(originProvider);
  final sort = ref.watch(conditionsProvider.select((c) => c.sort));
  return [
    Row(
      children: [
        Expanded(
          child: Text(
            l10n.mapMatchCount(ranked.value?.length ?? 0),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        PopupMenuButton<SortMode>(
          tooltip: l10n.condSort,
          initialValue: sort,
          onSelected: (m) => ref
              .read(conditionsProvider.notifier)
              .update((c) => c.copyWith(sort: m)),
          itemBuilder: (_) => [
            for (final m in SortMode.values)
              PopupMenuItem(value: m, child: Text(_sortLabel(context, m))),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _sortLabel(context, sort),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ],
    ),
    if (origin != null) ...[
      const SizedBox(height: 4),
      Text(
        l10n.mapSortHint(origin.label(l10n)),
        style: TextStyle(fontSize: 14, color: p.textMuted),
      ),
    ],
    const SizedBox(height: 12),
    ranked.when(
      loading: () => const Column(
        children: [
          SkeletonBox(height: 64),
          SizedBox(height: 12),
          SkeletonBox(height: 64),
        ],
      ),
      error: (e, _) => V5EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l10n.restaurantLoadFailedTitle,
        message: e is RestaurantException
            ? e.localizedMessage(l10n)
            : l10n.tryAgainLater,
        actions: [
          V5SmallButton(
            label: l10n.commonRetry,
            onPressed: () => ref.invalidate(allNearbyRestaurantsProvider),
          ),
        ],
      ),
      data: (list) => list.isEmpty
          ? V5EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: l10n.homeEmptyTitle,
              message: l10n.homeEmptyMessage,
              actions: [
                V5SmallButton(
                  label: l10n.condResetAll,
                  onPressed: ref.read(conditionsProvider.notifier).clear,
                ),
              ],
            )
          : V5RowGroup(
              rows: [
                for (final r in list)
                  _PlaceRow(
                    item: r,
                    focused: focusedId == r.restaurant.kakaoId,
                    onTap: onRowTap == null
                        ? null
                        : () => onRowTap(r.restaurant),
                  ),
              ],
            ),
    ),
  ];
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.item, this.onTap, this.focused = false});

  final RankedRestaurant item;

  /// Overrides opening the details (the desktop panel focuses the pin instead).
  final VoidCallback? onTap;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = item.restaurant;
    final price = item.insight.minPriceKrw;
    return InkWell(
      onTap: onTap ?? () => openRestaurantDetail(context, r),
      child: Container(
        color: focused ? p.accentSoft : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              RestaurantArt(
                restaurant: r,
                insight: item.insight,
                radius: 12,
                width: 56,
                height: 56,
                compact: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.categoryTag} · ${l10n.homeWalkAbout(item.walkMinutes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              if (price != null) ...[
                const SizedBox(width: 8),
                Text(
                  l10n.homePriceFrom(price),
                  style: AppText.numeric(size: 15, weight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
