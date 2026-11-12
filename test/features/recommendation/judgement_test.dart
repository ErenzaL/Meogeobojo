import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';

import '../../support/fakes.dart';

/// 8천 원 이하 + 지금 주문 가능, arriving at 18:00 (dinner).
const _c = Conditions(budget: BudgetOption.max8000, openNowOnly: true);
const _dinner = 18 * 60;
const _hours = (open: 11 * 60, last: 21 * 60);

Judgement _judge(RestaurantInsight i, [Conditions c = _c]) =>
    judgeRestaurant(i, c, _dinner);

void main() {
  group('조건 판정 (the examples of the spec)', () {
    test('7,000원 meal, ordering confirmed → match', () {
      final j = _judge(
        RestaurantInsight(
          openMinutes: _hours.open,
          lastOrderMinutes: _hours.last,
          menus: const [MenuLine(priceKrw: 7000, category: '식사')],
        ),
      );
      expect(j.verdict, Verdict.match);
      expect(j.mealPriceKrw, 7000);
    });

    test('7,000원 meal, no hours → unconfirmed (hours)', () {
      final j = _judge(
        const RestaurantInsight(
          menus: [MenuLine(priceKrw: 7000, category: '식사')],
        ),
      );
      expect(j.verdict, Verdict.unverified);
      expect(j.missing, {MissingInfo.hours});
    });

    test('no price, open → unconfirmed (price)', () {
      final j = _judge(
        RestaurantInsight(
          openMinutes: _hours.open,
          lastOrderMinutes: _hours.last,
        ),
      );
      expect(j.verdict, Verdict.unverified);
      expect(j.missing, {MissingInfo.price});
    });

    test('cheapest meal 10,000원, no hours → fails, not even unconfirmed', () {
      final j = _judge(
        const RestaurantInsight(
          menus: [MenuLine(priceKrw: 10000, category: '식사')],
        ),
      );
      expect(j.verdict, Verdict.excluded);
    });

    test('the 7,000원 meal is lunch only: at dinner it does not count', () {
      final i = RestaurantInsight(
        openMinutes: _hours.open,
        lastOrderMinutes: _hours.last,
        menus: const [
          MenuLine(
            priceKrw: 7000,
            category: '식사',
            servedFrom: 11 * 60,
            servedUntil: 14 * 60,
          ),
          MenuLine(priceKrw: 10000, category: '식사'),
        ],
      );
      expect(_judge(i).verdict, Verdict.excluded);
      expect(judgeRestaurant(i, _c, 12 * 60).verdict, Verdict.match);
    });

    test('a 3,000원 side never makes a place "under 8,000원"', () {
      final sideAndDearMeal = _judge(
        RestaurantInsight(
          minPriceKrw: 3000,
          openMinutes: _hours.open,
          lastOrderMinutes: _hours.last,
          menus: const [
            MenuLine(priceKrw: 3000, category: '사이드'),
            MenuLine(priceKrw: 9000, category: '식사'),
          ],
        ),
      );
      expect(sideAndDearMeal.verdict, Verdict.excluded);
      // Only a cheap price with nothing about what it buys: unconfirmed.
      final cheapUnknown = _judge(
        RestaurantInsight(
          minPriceKrw: 3000,
          openMinutes: _hours.open,
          lastOrderMinutes: _hours.last,
        ),
      );
      expect(cheapUnknown.verdict, Verdict.unverified);
    });

    test('an unclassified line that could still fit keeps it unconfirmed', () {
      final j = _judge(
        RestaurantInsight(
          openMinutes: _hours.open,
          lastOrderMinutes: _hours.last,
          menus: const [
            MenuLine(priceKrw: 9000, category: '식사'),
            MenuLine(priceKrw: 6000),
          ],
        ),
      );
      expect(j.verdict, Verdict.unverified);
    });
  });

  group('지금 주문 가능', () {
    const open = Conditions(openNowOnly: true);
    test('closed, not open yet, on a break or past last order → fails', () {
      for (final i in [
        const RestaurantInsight(closed: true),
        const RestaurantInsight(openMinutes: 19 * 60, lastOrderMinutes: 1300),
        const RestaurantInsight(breakTime: (17 * 60 + 30, 18 * 60 + 30)),
        const RestaurantInsight(lastOrderMinutes: 17 * 60),
      ]) {
        expect(judgeRestaurant(i, open, _dinner).verdict, Verdict.excluded);
      }
    });

    test('hours alone say "open", not "still taking orders"', () {
      final j = judgeRestaurant(
        const RestaurantInsight(openMinutes: 11 * 60),
        open,
        _dinner,
      );
      expect(j.verdict, Verdict.unverified);
    });

    test(
      'after midnight, a place that takes orders until 01:00 still counts',
      () {
        final j = judgeRestaurant(
          const RestaurantInsight(openMinutes: 17 * 60, lastOrderMinutes: 1500),
          open,
          30,
        );
        expect(j.verdict, Verdict.match);
      },
    );
  });

  test('the admin break time is read only when it is a clear range', () {
    expect(breakWindow('15:00-17:00'), (900, 1020));
    expect(breakWindow(' 9:30 ~ 10:00 '), (570, 600));
    expect(breakWindow('평일 3시~5시'), isNull);
    expect(breakWindow('17:00-15:00'), isNull);
  });

  test('Home, the map and search rank with one judgement: same ids, same '
      'verdicts, confirmed first', () {
    final places = [
      fakeRestaurant('ok'),
      fakeRestaurant('unknown'),
      fakeRestaurant('dear'),
    ];
    final insights = {
      'ok': RestaurantInsight(
        openMinutes: _hours.open,
        lastOrderMinutes: _hours.last,
        menus: const [MenuLine(priceKrw: 7000, category: '식사')],
      ),
      'dear': const RestaurantInsight(
        menus: [MenuLine(priceKrw: 10000, category: '면류')],
      ),
    };
    final r = rankRestaurants(
      all: places,
      lat: 36.77,
      lng: 126.93,
      conditions: _c,
      insights: insights,
      nowMinutes: _dinner,
    );
    expect([for (final x in r.confirmed) x.restaurant.kakaoId], ['ok']);
    expect([for (final x in r.unconfirmed) x.restaurant.kakaoId], ['unknown']);
    expect(r.first.reason.kind, ReasonKind.budget);
  });
}
