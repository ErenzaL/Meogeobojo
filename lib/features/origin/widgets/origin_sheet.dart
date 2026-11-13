import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/campus_points.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../conditions/models/conditions.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../home/providers/home_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../university/providers/university_providers.dart';
import '../models/origin.dart';
import '../providers/origin_providers.dart';
import '../screens/pin_picker_screen.dart';
import 'origin_row.dart';

/// 출발 위치 sheet. Picking a row changes the origin for Home, the map,
/// search and an open detail page at once, and closes the sheet.
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
    // The places Home and the map judge, BEFORE the conditions: a distance
    // limit is measured again from each row's own point.
    final places = ref.watch(homePoolProvider).value ?? const [];
    final insights = ref.watch(homePoolInsightsProvider);
    final hidden = ref.watch(hiddenPlaceIdsProvider);
    final conditions = ref.watch(conditionsProvider);
    final now = ref.watch(seoulNowProvider);

    /// Nearest confirmed match, measured from [o].
    RankedRestaurant? nearestFrom(Origin o) => rankRestaurants(
      all: places,
      lat: o.latitude,
      lng: o.longitude,
      conditions: conditions.copyWith(sort: SortMode.distance),
      insights: insights,
      hiddenIds: hidden,
      nowMinutes: now.hour * 60 + now.minute,
    ).confirmed.firstOrNull;

    Widget group(String title, Set<OriginKind> kinds, {String? empty}) {
      final rows = [
        for (final o in options)
          if (kinds.contains(o.kind)) o,
      ];
      if (rows.isEmpty && empty == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: AppText.caption(context).copyWith(fontSize: 13),
              ),
            ),
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
                      onEdit: o.kind == OriginKind.pin
                          ? () => _pickOnMap(context, ref, editing: o)
                          : null,
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
        const OriginReselectBanner(inSheet: true),
        group(l10n.originGroupGates, const {
          OriginKind.campusCenter,
          OriginKind.gate,
        }),
        group(l10n.originGroupDorms, const {OriginKind.dorm}),
        group(l10n.originGroupBuildings, const {OriginKind.building}),
        group(l10n.originGroupPins, const {
          OriginKind.pin,
        }, empty: l10n.originNoPins),
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

  /// A new place starts on the whole campus; editing a place starts on that
  /// pin at its own zoom. Only "이 위치를 출발점으로 설정" changes anything:
  /// back or cancel keeps the previous origin.
  Future<void> _pickOnMap(
    BuildContext context,
    WidgetRef ref, {
    Origin? editing,
  }) async {
    final university = ref.read(selectedUniversityProvider).value;
    if (university == null) return;
    final picked = await Navigator.of(context).push<PickedPin>(
      MaterialPageRoute<PickedPin>(
        builder: (_) => PinPickerScreen(
          campusLat: university.latitude,
          campusLng: university.longitude,
          editing: editing,
        ),
      ),
    );
    if (picked == null) return;
    final pins = ref.read(savedPinsProvider.notifier);
    final String id;
    if (editing != null) {
      await pins.edit(
        editing.id,
        name: picked.name,
        latitude: picked.latitude,
        longitude: picked.longitude,
        zoomLevel: picked.zoomLevel,
      );
      id = editing.id;
    } else {
      id = (await pins.add(
        universityId: university.id,
        name: picked.name,
        latitude: picked.latitude,
        longitude: picked.longitude,
        zoomLevel: picked.zoomLevel,
      )).id;
    }
    await ref.read(originSelectionProvider.notifier).select(id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// Shown while the saved start point no longer exists (the old single
/// "기숙사", a removed point): what happened, which origin is used meanwhile,
/// and a way to choose. Nothing is moved for the user.
class OriginReselectBanner extends ConsumerWidget {
  const OriginReselectBanner({super.key, this.inSheet = false});

  /// Inside the origin sheet the list itself is the way to choose.
  final bool inSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stale = ref.watch(staleOriginSelectionProvider);
    final origin = ref.watch(originProvider);
    if (stale == null || origin == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(top: inSheet ? 14 : 0, bottom: inSheet ? 0 : 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        decoration: BoxDecoration(
          color: p.rustSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stale == kLegacyDormPointId
                  ? l10n.originReselectDorm
                  : l10n.originReselectGone,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.originUsingNow(origin.label(l10n)),
              style: TextStyle(fontSize: 14, color: p.textSecondary),
            ),
            if (!inSheet)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => showOriginSheet(context),
                  child: Text(l10n.originReselectAction),
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
