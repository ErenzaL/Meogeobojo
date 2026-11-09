import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../preferences/models/user_preferences.dart';
import '../../preferences/restart_onboarding.dart';
import '../../preferences/screens/preference_labels.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../models/conditions.dart';
import '../providers/conditions_providers.dart';
import 'condition_parts.dart';

/// 조건 sheet. Every tap applies immediately to Home, the map and search; the
/// footer shows how many places the current conditions leave.
Future<void> showConditionsSheet(BuildContext context) => showAppSheet<void>(
  context,
  builder: (ctx, controller) => _ConditionsSheet(controller: controller),
);

const _cuisineChoices = [
  Cuisine.korean,
  Cuisine.japanese,
  Cuisine.chinese,
  Cuisine.snack,
  Cuisine.cafe,
  Cuisine.western,
  Cuisine.salad,
];

class _ConditionsSheet extends ConsumerWidget {
  const _ConditionsSheet({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = ref.watch(conditionsProvider);
    final origin = ref.watch(originProvider);
    final notifier = ref.read(conditionsProvider.notifier);
    void set(Conditions Function(Conditions) f) => notifier.update(f);

    Set<T> toggled<T>(Set<T> s, T v) =>
        s.contains(v) ? ({...s}..remove(v)) : {...s, v};

    String amenityLabel(Amenity a) => switch (a) {
      Amenity.noBreakTime => l10n.condAmenityNoBreak,
      Amenity.parking => l10n.condAmenityParking,
      Amenity.localCurrency => l10n.condAmenityLocalCurrency,
      Amenity.fastTurnover => l10n.condAmenityFast,
      Amenity.takeout => l10n.condAmenityTakeout,
      Amenity.openLate => l10n.condAmenityLate,
    };
    IconData amenityIcon(Amenity a) => switch (a) {
      Amenity.noBreakTime => Icons.schedule_rounded,
      Amenity.parking => Icons.local_parking_rounded,
      Amenity.localCurrency => Icons.payments_outlined,
      Amenity.fastTurnover => Icons.bolt_rounded,
      Amenity.takeout => Icons.takeout_dining_outlined,
      Amenity.openLate => Icons.dark_mode_outlined,
    };
    String needLabel(Need n) => switch (n) {
      Need.quietTalk => l10n.condNeedQuiet,
      Need.quickMeal => l10n.condNeedQuick,
      Need.generousPortion => l10n.condNeedGenerous,
    };
    String partyLabel(CompanionType t) => switch (t) {
      CompanionType.solo => l10n.companionSolo,
      CompanionType.friends => l10n.condPartyFew,
      _ => l10n.companionGroup,
    };
    String sortLabel(SortMode s) => switch (s) {
      SortMode.recommended => l10n.condSortRecommended,
      SortMode.distance => l10n.categorySortDistance,
      SortMode.price => l10n.condSortPrice,
      SortMode.rating => l10n.condSortRating,
    };

    final body = ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Text(
          l10n.condTitle,
          style: AppText.sectionTitle.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.condSubtitle,
          style: AppText.body.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: 14),
        Divider(color: context.palette.hairline),
        CondGroupHeader(title: l10n.condMust, hint: l10n.condMustHint),
        const SizedBox(height: 4),
        Text(l10n.condMissingNote, style: AppText.caption(context)),
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
        if (origin != null)
          CondOriginCard(
            label: l10n.homeOriginChip(origin.label(l10n)),
            action: l10n.condChange,
            onTap: () => showOriginSheet(context),
          ),
        CondSwitchRow(
          title: l10n.condOpenNow,
          hint: l10n.condOpenNowHint,
          value: c.openNowOnly,
          onChanged: (v) => set((x) => x.copyWith(openNowOnly: v)),
        ),
        CondSection(
          title: l10n.condCuisine,
          child: ChipWrap(
            children: [
              PillChip(
                label: l10n.categoryAll,
                selected: c.cuisines.isEmpty,
                onTap: () => set((x) => x.copyWith(cuisines: const {})),
              ),
              for (final u in _cuisineChoices)
                PillChip(
                  label: cuisineLabel(l10n, u),
                  selected: c.cuisines.contains(u),
                  onTap: () =>
                      set((x) => x.copyWith(cuisines: toggled(x.cuisines, u))),
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
                  label: amenityLabel(a),
                  icon: amenityIcon(a),
                  selected: c.amenities.contains(a),
                  onTap: () => set(
                    (x) => x.copyWith(amenities: toggled(x.amenities, a)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Divider(color: context.palette.hairline),
        CondGroupHeader(title: l10n.condSoft),
        const SizedBox(height: 4),
        Text(l10n.condSoftNote, style: AppText.caption(context)),
        CondSection(
          title: l10n.condParty,
          child: ChipWrap(
            children: [
              for (final t in kPartyOptions)
                PillChip(
                  label: partyLabel(t),
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
                  label: needLabel(n),
                  selected: c.needs.contains(n),
                  onTap: () =>
                      set((x) => x.copyWith(needs: toggled(x.needs, n))),
                ),
            ],
          ),
        ),
        CondSwitchRow(
          title: l10n.condUntried,
          hint: l10n.condUntriedHint(ref.watch(visitedRecordCountProvider)),
          value: c.untriedFirst,
          onChanged: (v) => set((x) => x.copyWith(untriedFirst: v)),
        ),
        CondSection(
          title: l10n.condSort,
          child: ChipWrap(
            children: [
              for (final s in SortMode.values)
                PillChip(
                  label: sortLabel(s),
                  selected: c.sort == s,
                  onTap: () => set((x) => x.copyWith(sort: s)),
                ),
            ],
          ),
        ),
      ],
    );

    return Column(
      children: [
        Expanded(child: body),
        _Footer(
          onClear: notifier.clear,
          onRestart: () => restartOnboarding(context, ref),
        ),
      ],
    );
  }
}

/// Sticky footer: clear / show-count buttons and the start-over link.
class _Footer extends ConsumerWidget {
  const _Footer({required this.onClear, required this.onRestart});

  final VoidCallback onClear;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final count = ref.watch(filteredRestaurantsProvider).value?.length;
    final empty = count == 0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          8 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClear,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: shape,
                      side: BorderSide(color: p.hairline),
                    ),
                    child: Text(l10n.condResetAll),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: empty ? null : () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.rust,
                      foregroundColor: p.onRust,
                      minimumSize: const Size.fromHeight(54),
                      shape: shape,
                    ),
                    child: Text(
                      empty
                          ? l10n.condNoMatch
                          : count == null
                          ? l10n.commonClose
                          : l10n.condShowCount(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.condRestart),
              style: TextButton.styleFrom(foregroundColor: p.rustText),
            ),
          ],
        ),
      ),
    );
  }
}
