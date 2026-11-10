import '../../../core/utils/seoul_clock.dart';
import '../../campus_meals/models/campus_meal_models.dart';

enum MealWhen { now, today, tomorrow }

class NextMeal {
  const NextMeal(this.meal, this.when);

  final CafeteriaMeal meal;
  final MealWhen when;
}

// Used only when a meal row has no verified serving time. Same boundaries as
// the meal screen's default tab (breakfast < 10:00, lunch < 15:00).
(int, int) _defaultWindow(MealType t) => switch (t) {
  MealType.breakfast => (0, 600),
  MealType.lunch => (600, 900),
  MealType.dinner => (900, 1440),
};

int? _hhmm(String? s) {
  if (s == null || s.length < 5) return null;
  final h = int.tryParse(s.substring(0, 2));
  final m = int.tryParse(s.substring(3, 5));
  return (h == null || m == null) ? null : h * 60 + m;
}

/// The next meal that has not ended yet, looking at today and then tomorrow,
/// in breakfast → lunch → dinner order. Only published meals with a menu
/// count; when a meal has several corners, the first one is used.
NextMeal? pickNextMeal(List<CafeteriaMeal> meals, DateTime nowWall) {
  final nowMin = minutesOfDay(nowWall);
  for (var day = 0; day <= 1; day++) {
    final date = DateTime.utc(nowWall.year, nowWall.month, nowWall.day + day);
    for (final type in MealType.values) {
      final options =
          meals
              .where(
                (m) =>
                    m.date == date &&
                    m.type == type &&
                    m.status == MealStatus.published &&
                    m.items.isNotEmpty,
              )
              .toList()
            ..sort((a, b) => a.optionOrder.compareTo(b.optionOrder));
      if (options.isEmpty) continue;
      final meal = options.first;
      final (defStart, defEnd) = _defaultWindow(type);
      final start = _hhmm(meal.startTime) ?? defStart;
      final end = _hhmm(meal.endTime) ?? defEnd;
      if (day == 0 && nowMin >= end) continue; // already over
      final when = day == 1
          ? MealWhen.tomorrow
          : (nowMin >= start ? MealWhen.now : MealWhen.today);
      return NextMeal(meal, when);
    }
  }
  return null;
}

/// The meals the home card lists: all of today's published meals (breakfast, lunch, dinner; one row per meal, the
/// first corner when there are several), or, once today's last meal has ended, all of tomorrow's. [next] is the
/// meal being served or coming up next (highlighted), [when] says which day the list is for.
class DayMeals {
  const DayMeals(this.meals, this.next, this.when);

  final List<CafeteriaMeal> meals;
  final CafeteriaMeal next;
  final MealWhen when;
}

DayMeals? pickDayMeals(List<CafeteriaMeal> meals, DateTime nowWall) {
  final next = pickNextMeal(meals, nowWall);
  if (next == null) return null;
  final day = next.when == MealWhen.tomorrow ? 1 : 0;
  final date = DateTime.utc(nowWall.year, nowWall.month, nowWall.day + day);
  final rows = <CafeteriaMeal>[];
  for (final type in MealType.values) {
    final options =
        meals
            .where(
              (m) =>
                  m.date == date &&
                  m.type == type &&
                  m.status == MealStatus.published &&
                  m.items.isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.optionOrder.compareTo(b.optionOrder));
    if (options.isNotEmpty) rows.add(options.first);
  }
  return DayMeals(rows, next.meal, next.when);
}
