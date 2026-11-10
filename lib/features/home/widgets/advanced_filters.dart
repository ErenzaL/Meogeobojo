import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../conditions/models/conditions.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../conditions/widgets/condition_labels.dart';
import '../../conditions/widgets/condition_parts.dart';
import '../../preferences/models/user_preferences.dart';
import '../../preferences/screens/preference_labels.dart';

/// Whether the desktop Home shows the expanded advanced-filter panel (the "조건" pill toggles it).
final homeAdvancedFiltersOpenProvider = NotifierProvider<_OpenController, bool>(
  _OpenController.new,
);

class _OpenController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void close() => state = false;
}

/// Desktop Home: every condition on one expandable panel instead of a modal sheet. It reads and writes the SAME shared
/// [conditionsProvider] as the sheet, the map and search, so ranking, filtering and the recommendation are untouched.
class AdvancedFilterPanel extends ConsumerWidget {
  const AdvancedFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(homeAdvancedFiltersOpenProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: open
          ? const _PanelBody(key: ValueKey('advanced-filters'))
          : const SizedBox(width: double.infinity),
    );
  }
}

class _PanelBody extends ConsumerWidget {
  const _PanelBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final c = ref.watch(conditionsProvider);
    void set(Conditions Function(Conditions) f) =>
        ref.read(conditionsProvider.notifier).update(f);
    Set<T> toggled<T>(Set<T> s, T v) =>
        s.contains(v) ? ({...s}..remove(v)) : {...s, v};

    final sections = <Widget>[
      CondSection(
        title: l10n.onbBudgetTitle,
        child: ChipWrap(
          children: [
            for (final o in BudgetOption.values)
              PillChip(
                label: budgetLabel(l10n, o),
                selected: c.budget == o,
                onTap: () => set((x) => x.copyWith(budget: o)),
              ),
          ],
        ),
      ),
      CondSection(
        title: l10n.onbDistanceTitle,
        child: ChipWrap(
          children: [
            for (final o in DistanceOption.values)
              PillChip(
                label: distanceLabel(l10n, o),
                selected: c.distance == o,
                onTap: () => set((x) => x.copyWith(distance: o)),
              ),
          ],
        ),
      ),
      CondSection(
        title: l10n.condParty,
        child: ChipWrap(
          children: [
            for (final t in kPartyOptions)
              PillChip(
                label: partyLabelOf(l10n, t),
                selected: c.party == t,
                onTap: () => set(
                  (x) => x.copyWith(party: () => x.party == t ? null : t),
                ),
              ),
          ],
        ),
      ),
      CondSection(
        title: l10n.condNeeds,
        child: ChipWrap(
          children: [
            for (final n in Need.values)
              PillChip(
                label: needLabelOf(l10n, n),
                selected: c.needs.contains(n),
                onTap: () => set((x) => x.copyWith(needs: toggled(x.needs, n))),
              ),
          ],
        ),
      ),
      CondSection(
        title: l10n.condOps,
        child: ChipWrap(
          children: [
            for (final a in Amenity.values)
              PillChip(
                label: amenityLabelOf(l10n, a),
                icon: amenityIconOf(a),
                selected: c.amenities.contains(a),
                onTap: () =>
                    set((x) => x.copyWith(amenities: toggled(x.amenities, a))),
              ),
          ],
        ),
      ),
      CondSection(
        title: l10n.condSort,
        child: ChipWrap(
          children: [
            for (final s in SortMode.values)
              PillChip(
                label: sortLabelOf(l10n, s),
                selected: c.sort == s,
                onTap: () => set((x) => x.copyWith(sort: s)),
              ),
          ],
        ),
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.homeFiltersAdvancedTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: c.activeCount == 0
                      ? null
                      : ref.read(conditionsProvider.notifier).clear,
                  child: Text(l10n.condResetAll),
                ),
                TextButton.icon(
                  onPressed: ref
                      .read(homeAdvancedFiltersOpenProvider.notifier)
                      .close,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  label: Text(l10n.homeFiltersHide),
                ),
              ],
            ),
          ),
          // Two columns of sections on a wide panel.
          LayoutBuilder(
            builder: (context, box) {
              final half = (box.maxWidth - 32) / 2;
              return Wrap(
                spacing: 32,
                children: [
                  for (final s in sections)
                    SizedBox(
                      width: box.maxWidth >= 760 ? half : box.maxWidth,
                      child: s,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          CondSwitchRow(
            title: l10n.condOpenNow,
            hint: l10n.condOpenNowHint,
            value: c.openNowOnly,
            onChanged: (v) => set((x) => x.copyWith(openNowOnly: v)),
          ),
          CondSwitchRow(
            title: l10n.condUntried,
            hint: l10n.condUntriedHint(ref.watch(visitedRecordCountProvider)),
            value: c.untriedFirst,
            onChanged: (v) => set((x) => x.copyWith(untriedFirst: v)),
          ),
        ],
      ),
    );
  }
}

/// One removable chip per condition that differs from the defaults, then "모두 풀기". Hidden when nothing is applied.
/// Removing a chip resets only that condition.
class AppliedFilterChips extends ConsumerWidget {
  const AppliedFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = ref.watch(conditionsProvider);
    if (c.activeCount == 0) return const SizedBox.shrink();
    void set(Conditions Function(Conditions) f) =>
        ref.read(conditionsProvider.notifier).update(f);

    final chips = <(String, VoidCallback)>[
      if (c.budget != BudgetOption.any)
        (
          budgetLabel(l10n, c.budget),
          () => set((x) => x.copyWith(budget: BudgetOption.any)),
        ),
      if (c.distance != DistanceOption.any)
        (
          distanceLabel(l10n, c.distance),
          () => set((x) => x.copyWith(distance: DistanceOption.any)),
        ),
      for (final k in c.cuisines)
        (
          cuisineLabel(l10n, k),
          () => set((x) => x.copyWith(cuisines: {...x.cuisines}..remove(k))),
        ),
      if (c.party != null)
        (
          partyLabelOf(l10n, c.party!),
          () => set((x) => x.copyWith(party: () => null)),
        ),
      for (final n in c.needs)
        (
          needLabelOf(l10n, n),
          () => set((x) => x.copyWith(needs: {...x.needs}..remove(n))),
        ),
      for (final a in c.amenities)
        (
          amenityLabelOf(l10n, a),
          () => set((x) => x.copyWith(amenities: {...x.amenities}..remove(a))),
        ),
      if (c.openNowOnly != Conditions.defaults.openNowOnly)
        (
          l10n.homeFilterOpenAny,
          () => set((x) => x.copyWith(openNowOnly: true)),
        ),
      if (c.untriedFirst)
        (l10n.condUntried, () => set((x) => x.copyWith(untriedFirst: false))),
      if (c.sort != SortMode.recommended)
        (
          sortLabelOf(l10n, c.sort),
          () => set((x) => x.copyWith(sort: SortMode.recommended)),
        ),
    ];

    return Padding(
      key: const ValueKey('applied-filters'),
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        container: true,
        label: l10n.homeFiltersApplied,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (label, remove) in chips)
              InputChip(
                label: Text(label),
                onDeleted: remove,
                deleteButtonTooltipMessage: l10n.homeFilterRemove(label),
                visualDensity: VisualDensity.compact,
              ),
            TextButton(
              onPressed: ref.read(conditionsProvider.notifier).clear,
              child: Text(l10n.condResetAll),
            ),
          ],
        ),
      ),
    );
  }
}
