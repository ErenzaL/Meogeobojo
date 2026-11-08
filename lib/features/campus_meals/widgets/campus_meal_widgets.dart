import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/campus_meal_models.dart';
import '../utils/seoul_date.dart';
import '../../../core/theme/app_palette.dart';

/// [<]  Nov 3 – Nov 9  [>]  [오늘]
class WeekNavigator extends StatelessWidget {
  const WeekNavigator({
    super.key,
    required this.weekStart,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.showTodayButton,
  });

  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final bool showTodayButton;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final end = weekDays(weekStart).last;
    return Row(
      children: [
        IconButton(
          tooltip: l10n.mealPrevWeek,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              l10n.mealWeekRange(weekStart, end),
              style: AppText.title.copyWith(fontSize: 16),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.mealNextWeek,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
        ),
        // Always reserve the space so the range does not jump around.
        SizedBox(
          width: 62,
          child: showTodayButton
              ? TextButton(
                  onPressed: onToday,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: context.palette.accentStrong,
                    backgroundColor: context.palette.accentSoft,
                    shape: const StadiumBorder(),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.mealToday,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

/// Monday-Sunday row. Selected day = orange disc; today = dot underneath.
class DaySelector extends StatelessWidget {
  const DaySelector({
    super.key,
    required this.weekStart,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final DateTime weekStart;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        for (final day in weekDays(weekStart))
          Expanded(
            child: _DayCell(
              label: l10n.mealWeekdayShort(day),
              number: '${day.day}',
              semantics: l10n.mealDayDescription(
                day,
                day == today ? l10n.mealToday : '',
              ),
              selected: day == selected,
              isToday: day == today,
              onTap: () => onSelect(day),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.label,
    required this.number,
    required this.semantics,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final String label;
  final String number;
  final String semantics;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? context.palette.accentStrong
                        : context.palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: isToday && !selected
                      ? Border.all(color: context.palette.accent, width: 1.4)
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    number,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? Colors.white
                          : context.palette.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isToday ? context.palette.accent : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 조식 | 중식 | 석식
class MealTabs extends StatelessWidget {
  const MealTabs({super.key, required this.selected, required this.onSelect});

  final MealType selected;
  final ValueChanged<MealType> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        for (final t in MealType.values)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: t == MealType.dinner ? 0 : 8),
              child: Semantics(
                button: true,
                selected: t == selected,
                label: t.label(l10n),
                excludeSemantics: true,
                child: Material(
                  color: t == selected
                      ? AppColors.primary
                      : context.palette.card,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: () => onSelect(t),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: t == selected
                              ? AppColors.primary
                              : context.palette.border,
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          t.label(l10n),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: t == selected
                                ? Colors.white
                                : context.palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Rounded dropdown, only built when a university has several cafeterias.
class CafeteriaSelector extends StatelessWidget {
  const CafeteriaSelector({
    super.key,
    required this.cafeterias,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  final List<CampusCafeteria> cafeterias;
  final CampusCafeteria selected;
  final String Function(CampusCafeteria) labelOf;
  final ValueChanged<CampusCafeteria> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<CampusCafeteria>(
      tooltip: l10n.mealSelectCafeteria,
      color: context.palette.card,
      position: PopupMenuPosition.under,
      onSelected: onSelect,
      itemBuilder: (_) => [
        for (final c in cafeterias)
          PopupMenuItem(
            value: c,
            child: Row(
              children: [
                Expanded(child: Text(labelOf(c))),
                if (c == selected)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: context.palette.accent,
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.food_bank_rounded,
              size: 20,
              color: context.palette.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                labelOf(selected),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title.copyWith(fontSize: 15),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }
}

/// White card for one published meal option.
class MealCard extends StatelessWidget {
  const MealCard({super.key, required this.meal});

  final CafeteriaMeal meal;

  String _kindLabel(AppLocalizations l10n, MenuItemKind k) => switch (k) {
    MenuItemKind.main => l10n.mealKindMain,
    MenuItemKind.side => l10n.mealKindSide,
    MenuItemKind.soup => l10n.mealKindSoup,
    MenuItemKind.rice => l10n.mealKindRice,
    MenuItemKind.other => '',
  };

  Future<void> _openSource(BuildContext context) async {
    final uri = Uri.tryParse(meal.sourceUrl ?? '');
    if (uri == null || uri.scheme != 'https') return;
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.restaurantLinkOpenFailed;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final hasTime = meal.startTime != null && meal.endTime != null;
    final verified = seoulDate(meal.verifiedAt);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.palette.border),
        boxShadow: context.palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meal.optionName.isNotEmpty || meal.priceKrw != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      meal.optionName,
                      style: AppText.title.copyWith(fontSize: 16),
                    ),
                  ),
                  if (meal.priceKrw != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        l10n.mealPrice(meal.priceKrw!),
                        style: TextStyle(
                          color: context.palette.accentStrong,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (hasTime)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: context.palette.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l10n.mealServingTime(meal.startTime!, meal.endTime!),
                      style: AppText.caption(context).copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          for (final item in meal.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.kind != MenuItemKind.other)
                    Container(
                      margin: const EdgeInsets.only(right: 8, top: 1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.accentFaint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _kindLabel(l10n, item.kind),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.palette.accentStrong,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item.displayName(locale),
                      style: AppText.body.copyWith(
                        fontSize: 15,
                        fontWeight: item.kind == MenuItemKind.main
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, color: context.palette.border),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                l10n.mealVerifiedAt(verified),
                style: AppText.caption(context),
              ),
              if (meal.sourceUrl != null)
                TextButton.icon(
                  onPressed: () => _openSource(context),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(l10n.mealOpenSource),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: context.palette.accentStrong,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Neutral card for "no menu", "closed" and "not collected" explanations.
class MealNoticeCard extends StatelessWidget {
  const MealNoticeCard({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.optionName,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final String? optionName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: context.palette.placeholderIcon),
          const SizedBox(height: 10),
          if (optionName != null && optionName!.isNotEmpty) ...[
            Text(optionName!, style: AppText.caption(context)),
            const SizedBox(height: 4),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.title.copyWith(fontSize: 15.5),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: AppText.caption(context).copyWith(fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
