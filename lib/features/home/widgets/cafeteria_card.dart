import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/skeleton.dart';
import '../../campus_meals/models/campus_meal_models.dart';
import '../../campus_meals/screens/campus_meal_screen.dart';
import '../providers/home_meal_providers.dart';
import '../screens/outside_compare_screen.dart';
import '../utils/home_text.dart';
import '../utils/next_meal.dart';
import 'home_card_parts.dart';
import 'price_comparison.dart';

/// "오늘의 학식": the next meal that has not ended, then how its price
/// compares with eating outside.
class CafeteriaCard extends ConsumerWidget {
  const CafeteriaCard({super.key, this.stackButtons = false});

  /// Stack the two buttons vertically (narrow desktop column). Phones keep
  /// them side by side.
  final bool stackButtons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final next = ref.watch(homeNextMealProvider);
    final source = ref.watch(homeMealSourceProvider);

    final String? chip = next.value == null
        ? null
        : _chipText(l10n, next.value!);

    return HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.homeMealTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (chip != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.palette.fillMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      chip,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          next.when(
            loading: () => const SkeletonBox(height: 110, radius: 16),
            error: (_, _) => _Notice(
              text: l10n.mealLoadFailed,
              actionLabel: l10n.commonRetry,
              onAction: () => ref.invalidate(homeMealSourceProvider),
            ),
            data: (meal) {
              final src = source.value;
              if (meal == null || src?.cafeteria == null) {
                return _Notice(
                  text: src?.cafeteria == null
                      ? l10n.mealNoCafeteria
                      : l10n.homeMealNone,
                );
              }
              return _MealTile(
                meal: meal.meal,
                cafeteria: src!.cafeteria!,
                all: src.all,
              );
            },
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: context.palette.hairline),
          const SizedBox(height: 14),
          const PriceComparison(),
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final weekly = OutlineActionButton(
                filled: true,
                icon: Icons.calendar_view_week_rounded,
                label: l10n.homeMealWeekly,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CampusMealScreen(),
                  ),
                ),
              );
              final compare = OutlineActionButton(
                icon: Icons.compare_arrows_rounded,
                label: l10n.homeMealCompare,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OutsideCompareScreen(),
                  ),
                ),
              );
              if (stackButtons) {
                return Column(
                  children: [weekly, const SizedBox(height: 10), compare],
                );
              }
              return Row(
                children: [
                  Expanded(child: weekly),
                  const SizedBox(width: 10),
                  Expanded(child: compare),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _chipText(AppLocalizations l10n, NextMeal m) {
    final meal = switch (m.meal.type) {
      MealType.breakfast => l10n.dayPartBreakfast,
      MealType.lunch => l10n.dayPartLunch,
      MealType.dinner => l10n.dayPartDinner,
    };
    return switch (m.when) {
      MealWhen.now => l10n.homeMealChipNow(meal),
      MealWhen.today => l10n.homeMealChipToday(meal),
      MealWhen.tomorrow => l10n.homeMealChipTomorrow(meal),
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.palette.fillMuted,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 14.5,
            color: context.palette.textSecondary,
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ),
  );
}

class _MealTile extends StatelessWidget {
  const _MealTile({
    required this.meal,
    required this.cafeteria,
    required this.all,
  });

  final CafeteriaMeal meal;
  final CampusCafeteria cafeteria;
  final List<CampusCafeteria> all;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final locale = Localizations.localeOf(context);
    final main = meal.items.firstWhere(
      (i) => i.kind == MenuItemKind.main,
      orElse: () => meal.items.first,
    );
    final sides = [
      for (final i in meal.items)
        if (i != main) i.displayName(locale),
    ];
    final place = cafeteriaLabel(l10n, locale, cafeteria, all);
    final where = meal.optionName.isEmpty ? place : '$place ${meal.optionName}';
    final secondary = TextStyle(fontSize: 14, color: p.textSecondary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.fillMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 56,
              height: 56,
              color: p.card,
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                AppAssets.categoryCampusMeals,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (meal.badge != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: p.rustSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      meal.badge!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.rustText,
                      ),
                    ),
                  ),
                ],
                Text(
                  main.displayName(locale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary,
                ),
                if (sides.isNotEmpty)
                  Text(
                    sides.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondary,
                  ),
                if (meal.startTime != null && meal.endTime != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusDot(p.barMuted, size: 8),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${meal.startTime}–${meal.endTime}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.numeric(
                            size: 13.5,
                            weight: FontWeight.w500,
                          ).copyWith(color: p.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (meal.priceKrw != null) ...[
            const SizedBox(width: 10),
            // Shrinks instead of overflowing at large text sizes.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  wonSigned(meal.priceKrw!),
                  style: AppText.numeric(size: 17, weight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
