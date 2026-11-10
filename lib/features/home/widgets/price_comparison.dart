import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/home_meal_providers.dart';
import '../utils/home_text.dart';

/// Whether both lunch averages exist, i.e. whether the comparison can be drawn at all.
final priceComparisonAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(cafeteriaLunchAverageProvider) != null &&
      ref.watch(outsideLunchAverageProvider) != null,
);

/// Average lunch price: cafeteria versus restaurants within a 15 minute walk
/// of the comparison spot, as two bars and a monthly saving. Both averages
/// come from real data; when either is missing nothing is drawn (no
/// explanatory text, no basis line).
class PriceComparison extends ConsumerWidget {
  const PriceComparison({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final cafeteria = ref.watch(cafeteriaLunchAverageProvider);
    final outside = ref.watch(outsideLunchAverageProvider);

    if (cafeteria == null || outside == null) return const SizedBox.shrink();
    final longest = cafeteria > outside ? cafeteria : outside;
    final saving = (outside - cafeteria) * 20;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Bar(
          label: l10n.homeMealBarCafeteria,
          value: cafeteria,
          fraction: cafeteria / longest,
          color: p.rust,
        ),
        const SizedBox(height: 10),
        _Bar(
          label: l10n.homeMealBarOutside,
          value: outside,
          fraction: outside / longest,
          color: p.barMuted,
        ),
        if (saving > 0) ...[
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: l10n.homeMealSavingPre),
                TextSpan(
                  text: wonSigned(saving),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: l10n.homeMealSavingPost),
              ],
            ),
            style: const TextStyle(fontSize: 15.5),
          ),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final int value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5),
          ),
        ),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: p.fillMuted,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.02, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          wonSigned(value),
          style: AppText.numeric(size: 15.5, weight: FontWeight.w500),
        ),
      ],
    );
  }
}
