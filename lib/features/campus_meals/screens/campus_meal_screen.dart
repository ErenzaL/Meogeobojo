import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../../core/widgets/skeleton.dart';
import '../../university/models/university_display.dart';
import '../../university/providers/university_providers.dart';
import '../models/campus_meal_models.dart';
import '../providers/campus_meal_providers.dart';
import '../widgets/campus_meal_widgets.dart';
import '../../../core/theme/app_palette.dart';

/// 이번 주 학식: one week of cafeteria menus for the selected university,
/// split into 조식 / 중식 / 석식. Shows only what an administrator imported
/// from a verified source; nothing is invented.
class CampusMealScreen extends ConsumerWidget {
  const CampusMealScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final university = ref.watch(selectedUniversityProvider).value;
    final cafeterias = ref.watch(campusCafeteriasProvider);

    return Scaffold(
      body: SafeArea(
        // Readable column on wide screens (the phone layout is unchanged).
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    4,
                    4,
                    AppSpacing.screenH,
                    4,
                  ),
                  child: Row(
                    children: [
                      BackButton(color: context.palette.textPrimary),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (university != null)
                              Text(
                                university.displayName(locale),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption(context)
                                    .copyWith(fontSize: 13),
                              ),
                            Text(
                              l10n.mealPageTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.sectionTitle.copyWith(
                                fontSize: 21,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: cafeterias.when(
                    loading: () => const _LoadingBody(),
                    error: (_, _) => MascotMessage(
                      asset: AppAssets.mascotMapConfused,
                      title: l10n.mealLoadFailed,
                      message: l10n.mealLoadFailedHint,
                      actionLabel: l10n.commonRetry,
                      onAction: () => ref.invalidate(campusCafeteriasProvider),
                    ),
                    data: (list) => list.isEmpty
                        ? MascotMessage(
                            asset: AppAssets.mascotSearching,
                            title: l10n.mealNoCafeteria,
                            message: l10n.mealNotCollectedHint,
                          )
                        : _Body(cafeterias: list),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(AppSpacing.screenH),
    children: const [
      SkeletonBox(height: 44, radius: 22),
      SizedBox(height: 14),
      SkeletonBox(height: 64, radius: 16),
      SizedBox(height: 14),
      SkeletonBox(height: 44, radius: 22),
      SizedBox(height: 14),
      SkeletonBox(height: 180, radius: 20),
    ],
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.cafeterias});

  final List<CampusCafeteria> cafeterias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final sel = ref.watch(campusMealSelectionProvider);
    final ctrl = ref.read(campusMealSelectionProvider.notifier);
    final cafeteria = ref.watch(effectiveCafeteriaProvider).value;
    if (cafeteria == null) return const SizedBox.shrink();
    final today = ctrl.today;
    String labelOf(CampusCafeteria c) =>
        cafeteriaLabel(l10n, locale, c, cafeterias);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        4,
        AppSpacing.screenH,
        28,
      ),
      children: [
        if (cafeterias.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CafeteriaSelector(
              cafeterias: cafeterias,
              selected: cafeteria,
              labelOf: labelOf,
              onSelect: (c) => ctrl.selectCafeteria(c.id),
            ),
          ),
        WeekNavigator(
          weekStart: sel.weekStart,
          showTodayButton: !(sel.date == today),
          onPrevious: () => ctrl.shiftWeek(-1),
          onNext: () => ctrl.shiftWeek(1),
          onToday: ctrl.goToToday,
        ),
        DaySelector(
          weekStart: sel.weekStart,
          selected: sel.date,
          today: today,
          onSelect: ctrl.selectDate,
        ),
        const SizedBox(height: 10),
        MealTabs(selected: sel.mealType, onSelect: ctrl.selectMealType),
        const SizedBox(height: 16),
        Text(
          l10n.mealHeading(
            sel.date == today
                ? l10n.mealToday
                : sel.date ==
                      DateTime.utc(today.year, today.month, today.day + 1)
                ? l10n.mealDayTomorrow
                : l10n.mealSelectedDate(sel.date),
            sel.mealType.label(l10n),
          ),
          style: AppText.heroTitle,
        ),
        if (cafeterias.length == 1) ...[
          const SizedBox(height: 2),
          Text(
            labelOf(cafeteria),
            style: AppText.caption(context).copyWith(fontSize: 13),
          ),
        ],
        if (cafeteria.locationDescription != null &&
            cafeteria.locationDescription!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            cafeteria.locationDescription!,
            style: AppText.caption(context).copyWith(fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 12),
        _WeekContent(cafeteria: cafeteria),
      ],
    );
  }
}

class _WeekContent extends ConsumerWidget {
  const _WeekContent({required this.cafeteria});

  final CampusCafeteria cafeteria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sel = ref.watch(campusMealSelectionProvider);
    final key = (cafeteriaId: cafeteria.id, weekStart: sel.weekStart);
    final async = ref.watch(campusWeekMealsProvider(key));

    return async.when(
      loading: () =>
          const Column(children: [SkeletonBox(height: 170, radius: 20)]),
      error: (_, _) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: MascotMessage(
          asset: AppAssets.mascotMapConfused,
          imageHeight: 90,
          title: l10n.mealLoadFailed,
          message: l10n.mealLoadFailedHint,
          actionLabel: l10n.commonRetry,
          onAction: () => ref.invalidate(campusWeekMealsProvider(key)),
        ),
      ),
      data: (week) {
        // Three different situations, three different messages:
        //  * whole week missing    -> not collected yet
        //  * this meal missing     -> no registered menu
        //  * source says closed / no menu -> shown as such (verified only)
        if (week.isEmpty) {
          return MealNoticeCard(
            icon: Icons.hourglass_empty_rounded,
            title: l10n.mealNotCollectedWeek,
            hint: l10n.mealNotCollectedHint,
          );
        }
        final options = week.options(sel.date, sel.mealType);
        if (options.isEmpty) {
          return MealNoticeCard(
            icon: Icons.no_meals_rounded,
            title: l10n.mealEmptyTitle,
          );
        }
        final published = [
          for (final m in options)
            if (m.status == MealStatus.published) m,
        ];
        return Column(
          children: [
            if (sel.mealType == MealType.breakfast && published.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BreakfastProgramCard(
                  priceKrw: published.first.priceKrw,
                  start: published.first.startTime,
                  end: published.first.endTime,
                ),
              ),
            for (final m in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: switch (m.status) {
                  MealStatus.published => MealCard(meal: m),
                  MealStatus.closed => MealNoticeCard(
                    icon: Icons.event_busy_rounded,
                    title: l10n.mealClosedTitle,
                    hint: l10n.mealClosedHint,
                    optionName: m.optionName,
                  ),
                  MealStatus.noMenu => MealNoticeCard(
                    icon: Icons.menu_book_outlined,
                    title: l10n.mealNoMenuTitle,
                    hint: l10n.mealNoMenuHint,
                    optionName: m.optionName,
                  ),
                },
              ),
          ],
        );
      },
    );
  }
}
