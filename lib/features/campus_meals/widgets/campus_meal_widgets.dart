import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
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
/// Mon–Fri selector (V5 `.cafe-day`): weekday + date, "오늘" under today, the
/// selected day filled with ink.
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
    final days = weekDays(weekStart).take(5).toList();
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _DayCell(
              date: days[i],
              selected: days[i] == selected,
              isToday: days[i] == today,
              onTap: () => onSelect(days[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final fg = selected ? p.chipSelectedFg : p.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.mealDayDescription(date, isToday ? l10n.mealToday : ''),
      excludeSemantics: true,
      child: Material(
        color: selected ? p.chipSelectedBg : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: selected ? p.chipSelectedBg : p.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l10n.mealWeekdayShort(date),
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? fg : p.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                SizedBox(
                  height: 16,
                  child: isToday
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            l10n.mealToday,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? fg : p.accentStrong,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 조식 · 중식 · 석식 as a segmented control (V5 `.seg`). Changing the meal
/// never changes the selected date.
class MealTabs extends StatelessWidget {
  const MealTabs({super.key, required this.selected, required this.onSelect});

  final MealType selected;
  final ValueChanged<MealType> onSelect;

  static IconData _icon(MealType t) => switch (t) {
    MealType.breakfast => Icons.wb_twilight_rounded,
    MealType.lunch => Icons.light_mode_outlined,
    MealType.dinner => Icons.dark_mode_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: p.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final t in MealType.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: t == selected,
                child: InkWell(
                  onTap: () => onSelect(t),
                  child: Container(
                    height: 44,
                    color: t == selected
                        ? p.chipSelectedBg
                        : Colors.transparent,
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _icon(t),
                            size: 18,
                            color: t == selected
                                ? p.chipSelectedFg
                                : p.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.label(l10n),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: t == selected
                                  ? p.chipSelectedFg
                                  : p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "조식 · 천원의 아침밥" with the price and hours FROM THE DATA (never an
/// assumed ₩1,000). Shown on the breakfast tab only.
class BreakfastProgramCard extends StatelessWidget {
  const BreakfastProgramCard({super.key, this.priceKrw, this.start, this.end});

  final int? priceKrw;
  final String? start;
  final String? end;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_twilight_rounded, color: p.accentStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.mealBreakfastProgram,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.accentStrong,
                  ),
                ),
                if (start != null && end != null)
                  Text(
                    l10n.mealServingTime(start!, end!),
                    style: AppText.caption(context).copyWith(fontSize: 13),
                  ),
              ],
            ),
          ),
          if (priceKrw != null)
            Text(
              l10n.mealPrice(priceKrw!),
              style: AppText.numeric(
                size: 16,
                weight: FontWeight.w700,
              ).copyWith(color: p.accentStrong),
            ),
        ],
      ),
    );
  }
}

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
          if (meal.photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.network(
                    meal.photoUrl!,
                    fit: BoxFit.cover,
                    semanticLabel: meal.optionName.isNotEmpty
                        ? meal.optionName
                        : null,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : ColoredBox(color: context.palette.fillMuted),
                    // A broken link is simply left out, never replaced by a stock photo.
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
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
          // V5 menu chips: the main dish in the accent tint, sides neutral.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in meal.items)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: item.kind == MenuItemKind.main
                        ? context.palette.accentSoft
                        : context.palette.fillMuted,
                    borderRadius: BorderRadius.circular(10),
                    border: item.kind == MenuItemKind.main
                        ? null
                        : Border.all(color: context.palette.border),
                  ),
                  child: Text(
                    item.displayName(locale),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: item.kind == MenuItemKind.main
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: item.kind == MenuItemKind.main
                          ? context.palette.accentStrong
                          : context.palette.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          if (meal.notice != null) ...[
            const SizedBox(height: 10),
            Text(
              meal.notice!,
              style: AppText.caption(context).copyWith(fontSize: 13.5),
            ),
          ],
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
