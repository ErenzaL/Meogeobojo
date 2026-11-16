import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

const lat = 36.7680, lng = 126.9305;

Restaurant place(String id, double dLat) => Restaurant(
  kakaoId: id,
  name: '식당$id',
  categoryName: '음식점 > 한식',
  categoryGroupCode: 'FD6',
  address: '',
  roadAddress: '',
  phone: '',
  latitude: lat + dLat,
  longitude: lng,
  distanceMeters: 0,
  placeUrl: null,
);

Judgement judge(RestaurantInsight i, BudgetOption b) =>
    judgeRestaurant(i, Conditions(budget: b), 12 * 60);

void main() {
  group('budgets: a shared dish answers "이상", never "이하"', () {
    const chicken = RestaurantInsight(
      menus: [MenuLine(priceKrw: 18000, category: '안주')],
    );
    test('"12,000원 이상": a shared 18,000원 dish confirms it', () {
      expect(judge(chicken, BudgetOption.min12000).verdict, Verdict.match);
    });
    test('"12,000원 이상": a shared dish under the amount does not', () {
      const cheap = RestaurantInsight(
        menus: [MenuLine(priceKrw: 9000, category: '안주')],
      );
      expect(judge(cheap, BudgetOption.min12000).verdict, Verdict.excluded);
    });
    test(
      '"8,000원 이하": a shared dish proves nothing about what one person pays',
      () {
        const shared = RestaurantInsight(
          menus: [MenuLine(priceKrw: 5000, category: '안주')],
        );
        expect(judge(shared, BudgetOption.max8000).verdict, Verdict.unverified);
        expect(
          judge(chicken, BudgetOption.max8000).verdict,
          Verdict.unverified,
        );
      },
    );
    test(
      'drinks, desserts and sides never count for either kind of budget',
      () {
        const drinks = RestaurantInsight(
          menus: [
            MenuLine(priceKrw: 15000, category: '음료'),
            MenuLine(priceKrw: 20000, category: '디저트'),
          ],
        );
        expect(
          judge(drinks, BudgetOption.min12000).verdict,
          isNot(Verdict.match),
        );
      },
    );
  });

  group('conditions nobody can check are not applied', () {
    final pool = [place('a', 0.0010), place('b', 0.0020)];
    test('parking with no data at all is ignored (and named); with some data it applies in full', () {
      const c = Conditions(amenities: {Amenity.parking});
      final none = usableConditions(c, pool, const {});
      expect(none.ignoredAmenities, {Amenity.parking});
      expect(none.conditions.amenities, isEmpty);
      final some = usableConditions(c, pool, {
        'a': const RestaurantInsight(parking: false),
      });
      expect(some.any, isFalse);
      expect(some.conditions.amenities, {Amenity.parking});
    });

    test(
      '"지금 주문 가능" with no hours anywhere is ignored; with hours it applies',
      () {
        const c = Conditions(openNowOnly: true);
        expect(usableConditions(c, pool, const {}).ignoredHours, isTrue);
        expect(
          usableConditions(c, pool, const {}).conditions.openNowOnly,
          isFalse,
        );
        final hours = {
          'a': const RestaurantInsight(
            openMinutes: 600,
            lastOrderMinutes: 1200,
          ),
        };
        expect(usableConditions(c, pool, hours).ignoredHours, isFalse);
      },
    );

    test('a place that is KNOWN to fail still fails (only a condition with no data anywhere is dropped)', () {
      const c = Conditions(amenities: {Amenity.parking});
      final ins = {
        'a': const RestaurantInsight(parking: true),
        'b': const RestaurantInsight(parking: false),
      };
      final u = usableConditions(c, pool, ins);
      final r = rankRestaurants(
        all: pool,
        lat: lat,
        lng: lng,
        conditions: u.conditions,
        insights: ins,
        nowMinutes: 720,
      );
      expect(r.map((e) => e.restaurant.kakaoId), ['a']);
    });
  });

  group('what to relax when nothing is confirmed', () {
    // ~110 m and ~780 m away
    final near = place('near', 0.0010), far = place('far', 0.0070);
    const meal = RestaurantInsight(
      menus: [MenuLine(priceKrw: 7000, category: '식사')],
    );
    const dear = RestaurantInsight(
      menus: [MenuLine(priceKrw: 12000, category: '식사')],
    );

    List<RelaxSuggestion> suggest(
      Conditions c,
      List<Restaurant> pool,
      Map<String, RestaurantInsight> ins, {
      List<Restaurant>? all,
      bool category = false,
    }) => relaxSuggestions(
      pool: pool,
      poolAnyCategory: all ?? pool,
      categoryChosen: category,
      lat: lat,
      lng: lng,
      conditions: c,
      insights: ins,
      nowMinutes: 720,
    );

    test(
      'a wider distance is offered with the nearest step that gives results',
      () {
        final s = suggest(
          const Conditions(distance: DistanceOption.walk5),
          [far],
          {'far': meal},
        );
        expect(s.map((e) => e.kind), [RelaxKind.distance]);
        expect(s.single.distance, DistanceOption.walk10);
        expect(s.single.count, 1);
      },
    );

    test('a place whose meals are all over the budget is offered back when the budget is dropped; nothing is offered when nothing helps', () {
      final s = suggest(
        const Conditions(budget: BudgetOption.max8000),
        [near],
        {'near': dear},
      );
      expect(s.map((e) => e.kind), [RelaxKind.budget]);
      expect(s.single.count, 1);
      // an empty pool: no relaxation can produce a place
      expect(
        suggest(
          const Conditions(
            budget: BudgetOption.max8000,
            distance: DistanceOption.walk5,
          ),
          [],
          const {},
        ),
        isEmpty,
      );
    });

    test('dropping the budget shows the place whose price is simply unknown to the budget (no menu)', () {
      final s = suggest(const Conditions(budget: BudgetOption.max8000), [
        near,
      ], const {});
      expect(s.map((e) => e.kind), [RelaxKind.budget]);
      expect(s.single.count, 1);
      expect(s.single.conditions.budget, BudgetOption.any);
    });

    test('a food type can be relaxed to any food type', () {
      final s = suggest(
        const Conditions(budget: BudgetOption.max8000),
        [],
        {'near': meal},
        all: [near],
        category: true,
      );
      expect(s.map((e) => e.kind), [RelaxKind.category]);
      expect(s.single.clearCategory, isTrue);
      expect(s.single.count, 1);
    });

    test('with nothing chosen there is nothing to relax', () {
      expect(suggest(const Conditions(), [], const {}), isEmpty);
    });
  });
}
