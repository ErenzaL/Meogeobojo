import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/campus_meals/utils/seoul_date.dart';
import 'package:meogeobojo/l10n/app_localizations.dart';

import '../../support/fakes.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  group('Asia/Seoul "today"', () {
    test('UTC evening is already the next day in Seoul (UTC+9)', () {
      // 2026-11-02 16:00 UTC = 2026-11-03 01:00 Seoul
      expect(seoulDate(DateTime.utc(2026, 11, 2, 16)), d(2026, 11, 3));
      expect(seoulDate(DateTime.utc(2026, 11, 2, 14, 59)), d(2026, 11, 2));
      expect(seoulDate(DateTime.utc(2026, 11, 2, 15)), d(2026, 11, 3));
    });

    test('works across the new year', () {
      expect(seoulDate(DateTime.utc(2026, 12, 31, 15)), d(2027, 1, 1));
    });

    test('a local (non-UTC) instant is converted correctly', () {
      final instant = DateTime.parse('2026-11-03T08:30:00+09:00');
      expect(seoulDate(instant), d(2026, 11, 3));
      expect(seoulHour(instant), 8);
    });

    test('default meal follows the Seoul hour', () {
      expect(
        defaultMealTypeAt(DateTime.utc(2026, 11, 2, 22)),
        MealType.breakfast,
      ); // 07:00
      expect(
        defaultMealTypeAt(DateTime.utc(2026, 11, 3, 3)),
        MealType.lunch,
      ); // 12:00
      expect(
        defaultMealTypeAt(DateTime.utc(2026, 11, 3, 9)),
        MealType.dinner,
      ); // 18:00
    });
  });

  group('weeks start on Monday and end on Sunday', () {
    test('Monday is its own week start; Sunday belongs to the week before', () {
      expect(weekStartOf(d(2026, 11, 2)), d(2026, 11, 2)); // Monday
      expect(weekStartOf(d(2026, 11, 8)), d(2026, 11, 2)); // Sunday
      expect(weekStartOf(d(2026, 11, 9)), d(2026, 11, 9)); // next Monday
    });

    test('every weekday maps to the same Monday', () {
      for (var i = 0; i < 7; i++) {
        expect(weekStartOf(d(2026, 11, 2 + i)), d(2026, 11, 2));
      }
    });

    test('weekDays is Monday..Sunday, seven consecutive dates', () {
      final days = weekDays(d(2026, 11, 2));
      expect(days.length, 7);
      expect(days.first.weekday, DateTime.monday);
      expect(days.last.weekday, DateTime.sunday);
      expect(days.last, d(2026, 11, 8));
    });

    test('end of month: the week spans October into November', () {
      // 2026-10-31 is a Saturday
      final start = weekStartOf(d(2026, 10, 31));
      expect(start, d(2026, 10, 26));
      final days = weekDays(start);
      expect(days.map((e) => e.day), [26, 27, 28, 29, 30, 31, 1]);
      expect(days.last.month, 11);
    });

    test('end of year: the week spans December into January', () {
      // 2026-12-31 is a Thursday
      final start = weekStartOf(d(2026, 12, 31));
      expect(start, d(2026, 12, 28));
      final days = weekDays(start);
      expect(days.last, d(2027, 1, 3));
      expect(days.map((e) => e.year).toSet(), {2026, 2027});
    });

    test('1 January that falls mid-week', () {
      expect(weekStartOf(d(2027, 1, 1)), d(2026, 12, 28)); // Friday
    });

    test('leap day', () {
      final start = weekStartOf(d(2028, 2, 29)); // Tuesday
      expect(start, d(2028, 2, 28));
      expect(weekDays(start).map((e) => e.day), [28, 29, 1, 2, 3, 4, 5]);
    });

    test('addWeeks crosses month and year boundaries both ways', () {
      expect(addWeeks(d(2026, 10, 26), 1), d(2026, 11, 2));
      expect(addWeeks(d(2026, 12, 28), 1), d(2027, 1, 4));
      expect(addWeeks(d(2027, 1, 4), -1), d(2026, 12, 28));
      expect(addWeeks(d(2026, 11, 2), -1), d(2026, 10, 26));
      expect(addWeeks(d(2026, 11, 2), 52).weekday, DateTime.monday);
    });

    test('iso formatting round-trips', () {
      expect(isoDate(d(2026, 1, 5)), '2026-01-05');
      expect(parseIsoDate('2027-12-31'), d(2027, 12, 31));
    });
  });

  group('models', () {
    test('menu items: objects and plain strings, junk skipped', () {
      final m = CafeteriaMeal.fromJson({
        'id': 'm',
        'cafeteria_id': 'c',
        'meal_date': '2026-11-03',
        'meal_type': 'lunch',
        'option_name': 'B코너',
        'option_order': 1,
        'menu_items': [
          {'name_ko': '김치찌개', 'kind': 'main'},
          '쌀밥',
          {'name_ko': ''},
          42,
          {'name_ko': '미역국', 'name_en': 'Seaweed soup', 'kind': 'soup'},
        ],
        'price_krw': 5500,
        'start_time': '11:30:00',
        'end_time': '13:30:00',
        'status': 'published',
        'source_url': 'https://example.org/m',
        'verified_at': '2026-11-02T09:00:00+09:00',
      })!;
      expect(m.items.map((e) => e.nameKo), ['김치찌개', '쌀밥', '미역국']);
      expect(m.items.first.kind, MenuItemKind.main);
      expect(m.items[1].kind, MenuItemKind.other);
      expect(m.startTime, '11:30', reason: 'seconds trimmed');
      expect(m.date, d(2026, 11, 3));
      expect(m.optionName, 'B코너');
    });

    test('unknown meal types or statuses are dropped, never guessed', () {
      expect(
        CafeteriaMeal.fromJson({
          'id': 'm',
          'cafeteria_id': 'c',
          'meal_date': '2026-11-03',
          'meal_type': 'brunch',
          'status': 'published',
          'verified_at': '2026-11-02T00:00:00Z',
        }),
        isNull,
      );
      expect(
        CafeteriaMeal.fromJson({
          'id': 'm',
          'cafeteria_id': 'c',
          'meal_date': '2026-11-03',
          'meal_type': 'lunch',
          'status': 'maybe',
          'verified_at': '2026-11-02T00:00:00Z',
        }),
        isNull,
      );
    });

    test(
      'menu names are not machine translated: verified translation or Korean',
      () {
        const withEn = MenuItem(nameKo: '미역국', nameEn: 'Seaweed soup');
        const none = MenuItem(nameKo: '김치찌개');
        expect(withEn.displayName(const Locale('en')), 'Seaweed soup');
        expect(
          withEn.displayName(const Locale('zh')),
          '미역국',
          reason: 'no verified zh',
        );
        expect(withEn.displayName(const Locale('ko')), '미역국');
        expect(none.displayName(const Locale('en')), '김치찌개');
      },
    );

    test(
      'week options keep every choice, ordered by option_order then name',
      () {
        final week = WeekMeals(d(2026, 11, 2), [
          fakeMeal('2026-11-03', MealType.lunch, option: 'B', order: 1),
          fakeMeal('2026-11-03', MealType.lunch, option: 'A', order: 0),
          fakeMeal('2026-11-03', MealType.dinner),
          fakeMeal('2026-11-04', MealType.lunch),
        ]);
        expect(
          week.options(d(2026, 11, 3), MealType.lunch).map((m) => m.optionName),
          ['A', 'B'],
        );
        expect(week.options(d(2026, 11, 3), MealType.breakfast), isEmpty);
        expect(week.options(d(2026, 11, 5), MealType.lunch), isEmpty);
      },
    );

    test('latest verification', () {
      final a = fakeMeal('2026-11-03', MealType.lunch);
      expect(WeekMeals.latestVerification([a]), a.verifiedAt);
      expect(WeekMeals.latestVerification(const []), isNull);
    });
  });

  group('cafeteria labels never invent names', () {
    final ko = lookupAppLocalizations(const Locale('ko'));
    final en = lookupAppLocalizations(const Locale('en'));
    String label(
      AppLocalizations l,
      String lang,
      CampusCafeteria c,
      List<CampusCafeteria> all,
    ) => cafeteriaLabel(l, Locale(lang), c, all);

    test(
      'official name wins; verified translation per language, else Korean',
      () {
        final c = fakeCafeteria('a', nameKo: '향설관', nameEn: 'Hyangseol Hall');
        expect(label(ko, 'ko', c, [c]), '향설관');
        expect(label(en, 'en', c, [c]), 'Hyangseol Hall');
        expect(label(en, 'zh', c, [c]), '향설관');
      },
    );

    test('nameless cafeteria shows its CATEGORY, localized', () {
      final c = fakeCafeteria('a', kind: CafeteriaKind.dormitory);
      expect(label(ko, 'ko', c, [c]), '기숙사식당');
      expect(label(en, 'en', c, [c]), 'Dormitory cafeteria');
    });

    test('several nameless ones of a category are numbered', () {
      final a = fakeCafeteria('a');
      final b = fakeCafeteria('b');
      final staff = fakeCafeteria('c', kind: CafeteriaKind.staff);
      final all = [a, b, staff];
      expect(label(ko, 'ko', a, all), '학생식당 1');
      expect(label(ko, 'ko', b, all), '학생식당 2');
      expect(label(ko, 'ko', staff, all), '교직원식당');
    });
  });

  group('weekly cache', () {
    test(
      'a week is fetched once while cached, and again after it expires',
      () async {
        final repo = FakeCampusMealRepository(
          meals: [fakeMeal('2026-11-03', MealType.lunch)],
        );
        final container = ProviderContainer(
          overrides: [
            campusMealRepositoryProvider.overrideWithValue(repo),
            campusMealCacheDurationProvider.overrideWithValue(
              const Duration(milliseconds: 80),
            ),
          ],
        );
        addTearDown(container.dispose);
        final key = (cafeteriaId: 'c1', weekStart: DateTime.utc(2026, 11, 2));

        final first = container.listen(campusWeekMealsProvider(key), (_, _) {});
        await container.read(campusWeekMealsProvider(key).future);
        first.close(); // widget left the screen
        await container.read(
          campusWeekMealsProvider(key).future,
        ); // reopened soon after
        expect(repo.weekCalls.length, 1, reason: 'reused from the cache');

        await Future<void>.delayed(
          const Duration(milliseconds: 150),
        ); // cache expired
        await container.read(campusWeekMealsProvider(key).future);
        expect(repo.weekCalls.length, 2, reason: 'refetched after expiry');
      },
    );
  });

  group('which cafeteria is shown', () {
    final dorm = fakeCafeteria('dorm', kind: CafeteriaKind.dormitory);
    final hall = fakeCafeteria('hall');
    final center = fakeCafeteria('center');

    test('none registered: nothing', () {
      expect(chooseCafeteria(const [], null), isNull);
      expect(chooseCafeteria(const [], 'hall'), isNull);
    });

    test('the pick wins when it belongs to the campus', () {
      expect(chooseCafeteria([hall, center], 'center'), center);
      expect(chooseCafeteria([dorm, hall], 'dorm'), dorm);
    });

    test('no pick: the first student cafeteria, not just the first', () {
      expect(chooseCafeteria([dorm, hall, center], null), hall);
    });

    test('a pick that no longer exists falls back the same way', () {
      expect(chooseCafeteria([dorm, hall], 'removed'), hall);
    });

    test('no student cafeteria at all: the first one', () {
      expect(chooseCafeteria([dorm], null), dorm);
    });
  });

  group('which meals get a tab', () {
    final lunchAndDinner = fakeCafeteria(
      'c1',
      mealTypes: const [MealType.lunch, MealType.dinner],
    );
    WeekMeals week(List<CafeteriaMeal> m) => WeekMeals(d(2026, 11, 2), m);

    test('only meals that were entered, in breakfast-lunch-dinner order', () {
      final w = week([
        fakeMeal('2026-11-04', MealType.dinner),
        fakeMeal('2026-11-03', MealType.breakfast),
      ]);
      expect(visibleMealTypes(fakeCafeteria('c1'), w), [
        MealType.breakfast,
        MealType.dinner,
      ]);
    });

    test('entered data wins over the cafeteria\'s own setting', () {
      final w = week([fakeMeal('2026-11-03', MealType.breakfast)]);
      expect(visibleMealTypes(lunchAndDinner, w), [MealType.breakfast]);
    });

    test('every status counts as entered (closed explains itself)', () {
      final w = week([
        fakeMeal(
          '2026-11-03',
          MealType.dinner,
          status: MealStatus.closed,
          items: const [],
        ),
      ]);
      expect(visibleMealTypes(fakeCafeteria('c1'), w), [MealType.dinner]);
    });

    test('an empty or unloaded week falls back to the cafeteria setting', () {
      expect(visibleMealTypes(lunchAndDinner, week(const [])), [
        MealType.lunch,
        MealType.dinner,
      ]);
      expect(visibleMealTypes(lunchAndDinner, null), [
        MealType.lunch,
        MealType.dinner,
      ]);
    });

    test('a wanted meal that is there stays; otherwise the next one', () {
      const lunchDinner = [MealType.lunch, MealType.dinner];
      expect(resolveMealType(MealType.lunch, lunchDinner), MealType.lunch);
      expect(resolveMealType(MealType.breakfast, lunchDinner), MealType.lunch);
      expect(
        resolveMealType(MealType.lunch, [MealType.dinner]),
        MealType.dinner,
      );
    });

    test('after the last meal of the day, the last one that exists', () {
      expect(
        resolveMealType(MealType.dinner, [MealType.breakfast, MealType.lunch]),
        MealType.lunch,
      );
    });
  });
}
