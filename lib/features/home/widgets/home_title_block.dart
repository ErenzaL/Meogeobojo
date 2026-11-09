import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/seoul_clock.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../conditions/widgets/conditions_sheet.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../recommendation/providers/ranking_providers.dart';

/// "오늘 뭐 먹지?" and "저녁 · 18:54 · 정문 출발 기준" (ticks every minute).
class HomeTitleBlock extends ConsumerWidget {
  const HomeTitleBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final now = ref.watch(seoulNowProvider);
    final origin = ref.watch(originProvider);
    final part = switch (DayPart.at(now)) {
      DayPart.breakfast => l10n.dayPartBreakfast,
      DayPart.lunch => l10n.dayPartLunch,
      DayPart.dinner => l10n.dayPartDinner,
      DayPart.lateNight => l10n.dayPartLateNight,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeTitle,
          style: const TextStyle(
            fontSize: 34,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          origin == null
              ? '$part · ${formatHm(now)}'
              : l10n.homeSubtitle(part, formatHm(now), origin.label(l10n)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, color: context.palette.textSecondary),
        ),
      ],
    );
  }
}

/// Origin chip (opens the 출발 위치 sheet) and 조건 chip (opens the 조건
/// sheet, with a count badge while any non-default condition is on).
class HomeChipRow extends ConsumerWidget {
  const HomeChipRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final origin = ref.watch(originProvider);
    final active = ref.watch(conditionsProvider.select((c) => c.activeCount));
    // A Wrap: at large text sizes the chips flow onto a second line instead of
    // squeezing each other.
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        HomeChip(
          onTap: () => showOriginSheet(context),
          background: p.card,
          children: [
            Icon(Icons.place_outlined, size: 19, color: p.rustText),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                origin == null ? '' : l10n.homeOriginChip(origin.label(l10n)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
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
        Semantics(
          label: active > 0 ? l10n.homeConditionsActive(active) : null,
          child: HomeChip(
            onTap: () => showConditionsSheet(context),
            background: p.card,
            children: [
              Icon(Icons.tune_rounded, size: 19, color: p.textSecondary),
              const SizedBox(width: 8),
              Text(
                l10n.homeConditionsChip,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (active > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.rust,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.onRust,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The rounded chip used by Home and the map header.
class HomeChip extends StatelessWidget {
  const HomeChip({
    super.key,
    required this.onTap,
    required this.background,
    required this.children,
    this.dense = false,
  });

  /// Tighter padding (the map header, where three chips share a phone row).
  final bool dense;
  final VoidCallback onTap;
  final Color background;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.palette.borderStrong),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 11 : 14,
          vertical: dense ? 11 : 12,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}
