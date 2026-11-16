import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';

RestaurantMenuItem item(
  String name,
  int? price,
  String? category, {
  bool available = true,
  bool rep = false,
  int? from,
  int? until,
}) => RestaurantMenuItem(
  name: name,
  priceKrw: price,
  category: category,
  available: available,
  representative: rep,
  servedFrom: from,
  servedUntil: until,
);

List<String> names(List<RestaurantMenuItem> xs) => [for (final x in xs) x.name];
const noon = 12 * 60;

void main() {
  final menus = [
    item('제육 정식', 7000, '식사'),
    item('돈가스', 12000, '식사'),
    item('공기밥', 1000, '사이드'),
    item('콜라', 2000, '음료'),
    item('후라이드', 18000, '안주'),
    item('가격 미정', null, '식사'),
    item('품절 정식', 6000, '식사', available: false),
  ];

  group('the dishes of one place that match the conditions', () {
    test('"8,000원 이하": only meals for one at or under the budget (no sides, drinks, shared dishes, sold-out or unpriced)', () {
      expect(
        names(
          menusMatchingConditions(
            menus,
            const Conditions(budget: BudgetOption.max8000),
            noon,
          ),
        ),
        ['제육 정식'],
      );
    });

    test('"12,000원 이상": meals AND shared dishes at or over the amount, cheapest first', () {
      expect(
        names(
          menusMatchingConditions(
            menus,
            const Conditions(budget: BudgetOption.min12000),
            noon,
          ),
        ),
        ['돈가스', '후라이드'],
      );
    });

    test('no budget: the place\'s meals (a dish priced and in stock), cheapest first', () {
      expect(names(menusMatchingConditions(menus, const Conditions(), noon)), [
        '제육 정식',
        '돈가스',
      ]);
    });

    test('a representative dish comes first', () {
      final m = [
        item('비싼 대표', 9000, '식사', rep: true),
        item('싼 메뉴', 5000, '식사'),
      ];
      expect(names(menusMatchingConditions(m, const Conditions(), noon)), [
        '비싼 대표',
        '싼 메뉴',
      ]);
    });

    test('a lunch-only dish is not offered for someone arriving at dinner', () {
      final m = [
        item('런치 정식', 7000, '식사', from: 11 * 60, until: 14 * 60),
        item('저녁 정식', 9000, '식사'),
      ];
      const c = Conditions(budget: BudgetOption.max10000);
      expect(names(menusMatchingConditions(m, c, noon)), ['런치 정식', '저녁 정식']);
      expect(names(menusMatchingConditions(m, c, 19 * 60)), ['저녁 정식']);
    });

    test('a place with nothing that matches gives an empty list (nothing is invented)', () {
      expect(
        menusMatchingConditions(
          [item('콜라', 2000, '음료')],
          const Conditions(budget: BudgetOption.max8000),
          noon,
        ),
        isEmpty,
      );
      expect(
        menusMatchingConditions(const [], const Conditions(), noon),
        isEmpty,
      );
    });

    test('these are exactly the lines judgeRestaurant confirms a place on', () {
      const c = Conditions(budget: BudgetOption.max10000);
      final lines = [for (final m in menus) m.line];
      final j = judgeRestaurant(RestaurantInsight(menus: lines), c, noon);
      final matching = menusMatchingConditions(menus, c, noon);
      expect(j.verdict, Verdict.match);
      expect(j.mealPriceKrw, matching.first.priceKrw);
    });
  });
}
