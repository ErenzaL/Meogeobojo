import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../conditions/models/conditions.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../university/providers/university_providers.dart';
import '../models/origin.dart';
import '../providers/origin_providers.dart';
import '../screens/pin_picker_screen.dart';
import 'origin_row.dart';

/// 출발 위치 sheet. Picking a row changes the origin, closes the sheet and
/// re-ranks Home and the map.
Future<void> showOriginSheet(BuildContext context) => showAppSheet<void>(
  context,
  builder: (ctx, controller) => _OriginSheet(controller: controller),
);

class _OriginSheet extends ConsumerWidget {
  const _OriginSheet({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final options = ref.watch(originOptionsProvider);
    final current = ref.watch(originProvider);
    final places = ref.watch(allNearbyRestaurantsProvider).value ?? const [];
    final conditions = ref.watch(conditionsProvider);
    final insights = ref.watch(restaurantInsightsProvider);
    final now = ref.watch(seoulNowProvider);

    /// Nearest place that passes the current conditions, measured from [o].
    RankedRestaurant? nearestFrom(Origin o) {
      final ranked = rankRestaurants(
        all: places,
        lat: o.latitude,
        lng: o.longitude,
        conditions: conditions.copyWith(sort: SortMode.distance),
        insights: insights,
        nowMinutes: now.hour * 60 + now.minute,
      );
      return ranked.isEmpty ? null : ranked.first;
    }

    Widget group(String title, OriginKind kind, {String? empty}) {
      final rows = [
        for (final o in options)
          if (o.kind == kind) o,
      ];
      if (rows.isEmpty && empty == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.caption(context).copyWith(fontSize: 13)),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(empty!, style: AppText.body),
              )
            else
              OriginGroupCard(
                rows: [
                  for (final o in rows)
                    OriginRow(
                      origin: o,
                      selected: o == current,
                      nearest: nearestFrom(o),
                      onTap: () {
                        ref.read(originSelectionProvider.notifier).select(o.id);
                        Navigator.of(context).pop();
                      },
                      onDelete: o.kind == OriginKind.pin
                          ? () => ref
                                .read(savedPinsProvider.notifier)
                                .remove(o.id)
                          : null,
                    ),
                ],
              ),
          ],
        ),
      );
    }

    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          l10n.originSheetTitle,
          style: AppText.sectionTitle.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.originSheetDesc,
          style: AppText.body.copyWith(color: context.palette.textSecondary),
        ),
        group(l10n.originGroupGates, OriginKind.campusCenter),
        group(l10n.originGroupGates, OriginKind.gate),
        group(l10n.originGroupColleges, OriginKind.college),
        group(l10n.originGroupBuildings, OriginKind.building),
        group(l10n.originGroupPins, OriginKind.pin, empty: l10n.originNoPins),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => _pickOnMap(context, ref),
          icon: const Icon(Icons.add_location_alt_outlined, size: 20),
          label: Text(l10n.originPickOnMap),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(color: context.palette.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickOnMap(BuildContext context, WidgetRef ref) async {
    final university = ref.read(selectedUniversityProvider).value;
    if (university == null) return;
    final picked = await Navigator.of(context).push<PickedPin>(
      MaterialPageRoute<PickedPin>(
        builder: (_) => PinPickerScreen(
          startLat: ref.read(originProvider)?.latitude ?? university.latitude,
          startLng: ref.read(originProvider)?.longitude ?? university.longitude,
          nextPinNumber: ref.read(savedPinsProvider).length + 1,
        ),
      ),
    );
    if (picked == null) return;
    final pin = await ref
        .read(savedPinsProvider.notifier)
        .add(
          universityId: university.id,
          name: picked.name,
          latitude: picked.latitude,
          longitude: picked.longitude,
        );
    await ref.read(originSelectionProvider.notifier).select(pin.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}
