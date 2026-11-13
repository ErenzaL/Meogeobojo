import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../conditions/models/conditions.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../conditions/widgets/conditions_sheet.dart';
import '../../home/providers/home_providers.dart';
import '../../home/widgets/home_chip.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';

String _amenityLabel(dynamic l10n, Amenity a) => switch (a) {
  Amenity.noBreakTime => l10n.condAmenityNoBreak,
  Amenity.parking => l10n.condAmenityParking,
  Amenity.localCurrency => l10n.condAmenityLocalCurrency,
  Amenity.fastTurnover => l10n.condAmenityFast,
  Amenity.takeout => l10n.condAmenityTakeout,
  Amenity.openLate => l10n.condAmenityLate,
};

IconData _amenityIcon(Amenity a) => switch (a) {
  Amenity.noBreakTime => Icons.schedule_rounded,
  Amenity.parking => Icons.local_parking_rounded,
  Amenity.localCurrency => Icons.payments_outlined,
  Amenity.fastTurnover => Icons.bolt_rounded,
  Amenity.takeout => Icons.takeout_dining_outlined,
  Amenity.openLate => Icons.dark_mode_outlined,
};

/// Origin chip, the categories chosen on Home (×), "지금 주문 가능", 조건 chip
/// and a scrolling row of quick facility chips (V5 map header). Everything
/// reads and writes the shared conditions and categories, so the map shows
/// exactly what Home does.
class MapFilterBar extends ConsumerWidget {
  const MapFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final origin = ref.watch(originProvider);
    final c = ref.watch(conditionsProvider);
    final notifier = ref.read(conditionsProvider.notifier);
    final categories = ref.watch(homeCategoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One line, scrolls sideways when the chips do not fit (V5 `.condbar`).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              HomeChip(
                dense: true,
                onTap: () => showOriginSheet(context),
                background: p.card,
                children: [
                  Icon(Icons.place_outlined, size: 19, color: p.rustText),
                  const SizedBox(width: 8),
                  Text(
                    origin == null
                        ? ''
                        : l10n.homeOriginChip(origin.label(l10n)),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: p.textSecondary,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              for (final cat in categories) ...[
                HomeChip(
                  dense: true,
                  onTap: () =>
                      ref.read(homeCategoryProvider.notifier).toggle(cat),
                  background: p.fillMuted,
                  children: [
                    Text(
                      cat.label(l10n),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.close_rounded, size: 18, color: p.textSecondary),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              PillChip(
                label: l10n.mapOpenNowChip,
                icon: Icons.schedule_rounded,
                selected: c.openNowOnly,
                onTap: () => notifier.update(
                  (x) => x.copyWith(openNowOnly: !x.openNowOnly),
                ),
              ),
              const SizedBox(width: 8),
              HomeChip(
                dense: true,
                onTap: () => showConditionsSheet(context),
                background: p.card,
                children: [
                  Icon(Icons.tune_rounded, size: 19, color: p.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    l10n.homeConditionsChip,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (c.activeCount > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${c.activeCount}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.rustText,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: Amenity.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final a = Amenity.values[i];
              return PillChip(
                label: _amenityLabel(l10n, a),
                icon: _amenityIcon(a),
                selected: c.amenities.contains(a),
                onTap: () => notifier.update(
                  (x) => x.copyWith(
                    amenities: x.amenities.contains(a)
                        ? ({...x.amenities}..remove(a))
                        : {...x.amenities, a},
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
