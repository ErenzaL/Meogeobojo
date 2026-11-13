import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/responsive.dart';
import '../../conditions/models/conditions.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../conditions/widgets/condition_labels.dart';
import '../../conditions/widgets/conditions_sheet.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../preferences/models/user_preferences.dart';
import '../../preferences/screens/preference_labels.dart';
import 'advanced_filters.dart';

/// One scrolling row of filter chips under the categories. They read and
/// write the same shared conditions as the map and search; tapping one opens
/// the 조건 sheet at that section. A chip turns dark and shows its value
/// while its filter is on.
class HomeFilterBar extends ConsumerWidget {
  const HomeFilterBar({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = ref.watch(conditionsProvider);
    final origin = ref.watch(originProvider);
    final ops = opsActiveCount(c);
    // Desktop: the "조건" pill expands the inline advanced panel instead of opening the modal sheet.
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
    final panelOpen = wide && ref.watch(homeAdvancedFiltersOpenProvider);

    void open(ConditionFocus f) => showConditionsSheet(context, focus: f);

    final chips = <Widget>[
      _FilterPill(
        icon: Icons.tune_rounded,
        label: l10n.homeConditionsChip,
        count: c.activeCount,
        active: c.activeCount > 0 || panelOpen,
        chevron: wide,
        expanded: wide ? panelOpen : null,
        onTap: () => wide
            ? ref.read(homeAdvancedFiltersOpenProvider.notifier).toggle()
            : showConditionsSheet(context),
      ),
      if (origin != null)
        _FilterPill(
          icon: Icons.place_outlined,
          label: l10n.homeOriginChip(origin.label(l10n)),
          active: false,
          onTap: () => showOriginSheet(context),
        ),
      _FilterPill(
        label: c.budget == BudgetOption.any
            ? l10n.homeFilterBudget
            : budgetLabel(l10n, c.budget),
        active: c.budget != BudgetOption.any,
        onTap: () => open(ConditionFocus.budget),
      ),
      _FilterPill(
        label: c.distance == DistanceOption.any
            ? l10n.homeFilterDistance
            : distanceLabel(l10n, c.distance),
        active: c.distance != DistanceOption.any,
        onTap: () => open(ConditionFocus.distance),
      ),
      _FilterPill(
        label: l10n.condOps,
        count: ops,
        active: ops > 0,
        onTap: () => open(ConditionFocus.ops),
      ),
      _FilterPill(
        label: c.sort == SortMode.recommended
            ? l10n.homeFilterSort
            : sortLabelOf(l10n, c.sort),
        active: c.sort != SortMode.recommended,
        onTap: () => open(ConditionFocus.sort),
      ),
    ];

    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return SizedBox(
      height: 44 + 14 * (scale - 1),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.count = 0,
    this.chevron = true,
    this.expanded,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  /// Shown after the label while above 0.
  final int count;
  final bool chevron;

  /// Non-null for a pill that expands a panel (reported to screen readers; the chevron turns up).
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = active ? p.chipSelectedFg : p.textPrimary;
    final sub = active ? p.chipSelectedFg : p.textSecondary;
    return Semantics(
      button: true,
      selected: active,
      expanded: expanded,
      child: Material(
        color: active ? p.chipSelectedBg : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: active ? p.chipSelectedBg : p.borderStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: sub),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: active ? p.chipSelectedFg : p.rustText,
                      ),
                    ),
                  ],
                  if (chevron) ...[
                    const SizedBox(width: 2),
                    Icon(
                      expanded == true
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: sub,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
