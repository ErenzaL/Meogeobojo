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
import '../../home/providers/home_providers.dart';
import '../../recommendation/home_ranking.dart';

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../models/conditions.dart';
import '../providers/conditions_providers.dart';
import 'condition_parts.dart';

/// 조건 sheet. Every tap applies immediately to Home, the map and search; the
/// footer button counts the confirmed matches of the list the sheet was
/// opened from ([pool]: Home and the map by default, the results on search),
/// so its number is what that screen shows once the sheet closes.
///
/// With [focus] only that one setting is shown (a Home filter chip opens just
/// the setting it stands for, with its own reset); null shows every setting.
Future<void> showConditionsSheet(
  BuildContext context, {
  ConditionFocus? focus,
  ProviderListenable<AsyncValue<List<RankedRestaurant>>>? pool,
}) {
  final counted = pool ?? homePoolRankedProvider;
  return focus == null
      ? showAppSheet<void>(
          context,
          builder: (ctx, controller) =>
              _ConditionsSheet(controller: controller, pool: counted),
        )
      : showCompactSheet<void>(
          context,
          builder: (ctx) => _ConditionsSheet(focus: focus, pool: counted),
        );
}

/// Settings of the 조건 sheet that can be opened on their own.
enum ConditionFocus { budget, distance, ops, sort }

/// [c] with only the setting [f] back to its default.
Conditions _resetSetting(Conditions c, ConditionFocus f) => switch (f) {
  ConditionFocus.budget => c.copyWith(budget: BudgetOption.any),
  ConditionFocus.distance => c.copyWith(distance: DistanceOption.any),
  ConditionFocus.ops => c.copyWith(
    openNowOnly: Conditions.defaults.openNowOnly,
    amenities: const {},
  ),
  ConditionFocus.sort => c.copyWith(sort: SortMode.recommended),
};

const _cuisineChoices = [
  Cuisine.korean,
  Cuisine.japanese,
  Cuisine.chinese,
  Cuisine.snack,
  Cuisine.cafe,
  Cuisine.western,
  Cuisine.salad,
];

class _ConditionsSheet extends ConsumerStatefulWidget {
  const _ConditionsSheet({required this.pool, this.controller, this.focus});

  /// The draggable sheet's scroll controller (full sheet only).
  final ScrollController? controller;
  final ConditionFocus? focus;
  final ProviderListenable<AsyncValue<List<RankedRestaurant>>> pool;

  @override
  ConsumerState<_ConditionsSheet> createState() => _ConditionsSheetState();
}

class _ConditionsSheetState extends ConsumerState<_ConditionsSheet> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
    String sortLabel(SortMode s) => switch (s) {
      SortMode.recommended => l10n.condSortRecommended,
      SortMode.distance => l10n.categorySortDistance,
      SortMode.price => l10n.condSortPrice,
      SortMode.rating => l10n.condSortRating,
    };

    final budgetSection = CondSection(
      showTitle: widget.focus == null,
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
    );
    final distanceSection = CondSection(
      showTitle: widget.focus == null,
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
    );
    final opsSection = CondSection(
      showTitle: widget.focus == null,
      title: l10n.condOps,
      child: ChipWrap(
        children: [
          for (final a in Amenity.values)
            PillChip(
              label: amenityLabel(a),
              icon: amenityIcon(a),
              selected: c.amenities.contains(a),
              onTap: () =>
                  set((x) => x.copyWith(amenities: toggled(x.amenities, a))),
            ),
        ],
      ),
    );
    final sortSection = CondSection(
      showTitle: widget.focus == null,
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
    );
    final openNowRow = CondSwitchRow(
      title: l10n.condOpenNow,
      hint: l10n.condOpenNowHint,
      value: c.openNowOnly,
      onChanged: (v) => set((x) => x.copyWith(openNowOnly: v)),
    );

    final focus = widget.focus;
    if (focus != null) {
      // One setting only: its title, its choices, and a reset for just it.
      final (title, content) = switch (focus) {
        ConditionFocus.budget => (l10n.onbBudgetTitle, [budgetSection]),
        ConditionFocus.distance => (l10n.onbDistanceTitle, [distanceSection]),
        ConditionFocus.ops => (l10n.condOps, [openNowRow, opsSection]),
        ConditionFocus.sort => (l10n.condSort, [sortSection]),
      };
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.sectionTitle.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 2),
                  ...content,
                ],
              ),
            ),
          ),
          _Footer(
            pool: widget.pool,
            resetLabel: l10n.condResetThis,
            onClear: () => set((x) => _resetSetting(x, focus)),
          ),
        ],
      );
    }

    final body = ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Text(
          l10n.condTitle,
          style: AppText.sectionTitle.copyWith(fontSize: 24),
        ),
        CondGroupHeader(title: l10n.condMust, hint: l10n.condMustHint),
        const SizedBox(height: 4),
        Text(l10n.condMissingNote, style: AppText.caption(context)),
        budgetSection,
        distanceSection,
        if (origin != null)
          CondOriginCard(
            label: l10n.homeOriginChip(origin.label(l10n)),
            action: l10n.condChange,
            onTap: () => showOriginSheet(context),
          ),
        openNowRow,
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
        opsSection,
        const SizedBox(height: 12),
        Divider(color: context.palette.hairline),
        CondGroupHeader(title: l10n.condSoft),
        const SizedBox(height: 4),
        Text(l10n.condSoftNote, style: AppText.caption(context)),
        CondSwitchRow(
          title: l10n.condUntried,
          hint: l10n.condUntriedHint(ref.watch(visitedRecordCountProvider)),
          value: c.untriedFirst,
          onChanged: (v) => set((x) => x.copyWith(untriedFirst: v)),
        ),
        sortSection,
      ],
    );

    return Column(
      children: [
        Expanded(child: body),
        _Footer(
          pool: widget.pool,
          onClear: notifier.clear,
          onRestart: () => restartOnboarding(context, ref),
        ),
      ],
    );
  }
}

/// Sticky footer: clear / show-count buttons and the start-over link.
class _Footer extends ConsumerWidget {
  const _Footer({
    required this.pool,
    required this.onClear,
    this.onRestart,
    this.resetLabel,
  });

  final ProviderListenable<AsyncValue<List<RankedRestaurant>>> pool;
  final VoidCallback onClear;

  /// Null in a single-setting sheet (no start-over link there).
  final VoidCallback? onRestart;

  /// Overrides 모두 풀기 when the sheet holds one setting.
  final String? resetLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final ranked = ref.watch(pool).value;
    final count = ranked?.confirmed.length;
    final unverified = ranked?.unconfirmed.length ?? 0;
    final empty = count == 0 && unverified == 0;
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
                    child: Text(resetLabel ?? l10n.condResetAll),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: empty
                        ? null
                        : () {
                            // Nothing confirmed: the button opens the
                            // "정보 미확인" list it counts.
                            if (count == 0) {
                              ref
                                  .read(homeShowUnverifiedProvider.notifier)
                                  .show();
                            }
                            Navigator.of(context).pop();
                          },
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
                          : count == 0
                          ? l10n.condShowUnverified(unverified)
                          : l10n.condShowCount(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            if (onRestart != null)
              TextButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(l10n.condRestart),
                style: TextButton.styleFrom(foregroundColor: p.rustText),
              ),
          ],
        ),
      ),
    );
  }
}
