import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/campus_points.dart';
import '../../../core/utils/geo.dart';
import '../../campus_meals/models/campus_meal_models.dart';
import '../../campus_meals/providers/campus_meal_providers.dart';
import '../../campus_meals/utils/seoul_date.dart';
import '../../origin/models/origin.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../utils/next_meal.dart';

/// Cafeteria used on Home and this week's (and, near a week's end, the next
/// week's) meals for it. [cafeteria] is null when the campus has none.
class HomeMealSource {
  const HomeMealSource(this.cafeteria, this.all, this.meals);

  final CampusCafeteria? cafeteria;
  final List<CampusCafeteria> all;
  final List<CafeteriaMeal> meals;
}

final homeMealSourceProvider = FutureProvider<HomeMealSource>((ref) async {
  // Only the calendar day matters here, so the minute tick does not refetch.
  final today = ref.watch(seoulNowProvider.select((n) => seoulDate(n)));
  final all = await ref.watch(campusCafeteriasProvider.future);
  if (all.isEmpty) return const HomeMealSource(null, [], []);
  final cafeteria = all.firstWhere(
    (c) => c.kind == CafeteriaKind.student,
    orElse: () => all.first,
  );
  final tomorrow = DateTime.utc(today.year, today.month, today.day + 1);
  final weeks = {weekStartOf(today), weekStartOf(tomorrow)};
  final meals = <CafeteriaMeal>[];
  for (final w in weeks) {
    final week = await ref.watch(
      campusWeekMealsProvider((cafeteriaId: cafeteria.id, weekStart: w)).future,
    );
    meals.addAll(week.meals);
  }
  return HomeMealSource(cafeteria, all, meals);
});

/// The meal the card shows, re-evaluated every minute as meals end.
final homeNextMealProvider = Provider<AsyncValue<NextMeal?>>((ref) {
  final now = ref.watch(seoulNowProvider);
  return ref
      .watch(homeMealSourceProvider)
      .whenData((s) => pickNextMeal(s.meals, now));
});

/// All the meals of the day the card shows, re-evaluated every minute as meals end.
final homeDayMealsProvider = Provider<AsyncValue<DayMeals?>>((ref) {
  final now = ref.watch(seoulNowProvider);
  return ref
      .watch(homeMealSourceProvider)
      .whenData((s) => pickDayMeals(s.meals, now));
});

/// Mean price of the cafeteria's lunches that have a price; null if none.
final cafeteriaLunchAverageProvider = Provider<int?>((ref) {
  final source = ref.watch(homeMealSourceProvider).value;
  if (source == null) return null;
  final prices = [
    for (final m in source.meals)
      if (m.type == MealType.lunch &&
          m.status == MealStatus.published &&
          m.priceKrw != null)
        m.priceKrw!,
  ];
  return _mean(prices);
});

/// The spot the comparison is measured from: 학생회관 where we know it, else
/// the campus center.
final comparisonAnchorProvider = Provider<Origin?>((ref) {
  final options = ref.watch(originOptionsProvider);
  for (final o in options) {
    if (o.id == kStudentCenterPointId) return o;
  }
  for (final o in options) {
    if (o.kind == OriginKind.campusCenter) return o;
  }
  return options.isEmpty ? null : options.first;
});

/// Mean cheapest-menu price of restaurants within a 15 minute walk of the
/// anchor, ignoring places without a known price; null when none has one.
final outsideLunchAverageProvider = Provider<int?>((ref) {
  final anchor = ref.watch(comparisonAnchorProvider);
  final places = ref.watch(allNearbyRestaurantsProvider).value;
  if (anchor == null || places == null) return null;
  final insights = ref.watch(restaurantInsightsProvider);
  final prices = <int>[];
  for (final r in places) {
    final price = insights[r.kakaoId]?.minPriceKrw;
    if (price == null) continue;
    final meters = haversineMeters(
      anchor.latitude,
      anchor.longitude,
      r.latitude,
      r.longitude,
    ).round();
    if (walkMinutesFor(meters) <= 15) prices.add(price);
  }
  return _mean(prices);
});

int? _mean(List<int> xs) =>
    xs.isEmpty ? null : (xs.reduce((a, b) => a + b) / xs.length).round();
