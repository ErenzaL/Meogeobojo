import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/utils/seoul_clock.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/home/utils/next_meal.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

import '../../support/fakes.dart';

// Origin and three places due north of it: ~56 m, ~167 m, ~778 m.
const lat = 36.7680, lng = 126.9305;

Restaurant place(String id, double dLat, {String category = '음식점 > 한식'}) =>
    Restaurant(
      kakaoId: id,
      name: '식당$id',
      categoryName: category,
      categoryGroupCode: 'FD6',
      address: '',
      roadAddress: '',
      phone: '',
      latitude: lat + dLat,
      longitude: lng,
      distanceMeters: 0,
      placeUrl: null,
    );

List<RankedRestaurant> rank(
  List<Restaurant> all, {
  Conditions c = const Conditions(),
  Map<String, RestaurantInsight> insights = const {},
  int now = 18 * 60 + 54,
}) => rankRestaurants(
  all: all,
  lat: lat,
  lng: lng,
  conditions: c,
  insights: insights,
  nowMinutes: now,
);

void main() {
  final a = place('A', 0.0005);
  final b = place('B', 0.0015);
  final c = place('C', 0.0070, category: '음식점 > 중식');

  group('ranking', () {
    test(
      'orders by distance from the chosen origin and measures walk time',
      () {
        final r = rank([c, a, b]);
        expect(r.map((e) => e.restaurant.kakaoId), ['A', 'B', 'C']);
        expect(r.map((e) => e.walkMinutes), [1, 2, 10]);
      },
    );

    test('a different origin re-orders', () {
      final r = rankRestaurants(
        all: [a, b, c],
        lat: lat + 0.0070,
        lng: lng,
        conditions: const Conditions(),
        insights: const {},
        nowMinutes: 0,
      );
      expect(r.first.restaurant.kakaoId, 'C');
    });

    test('distance limit removes far places (walk 5 min = 400 m)', () {
      final r = rank([
        a,
        b,
        c,
      ], c: const Conditions(distance: DistanceOption.walk5));
      expect(r.map((e) => e.restaurant.kakaoId), ['A', 'B']);
    });

    test('cuisine filter keeps only matches and explains the pick', () {
      final r = rank([
        a,
        b,
        c,
      ], c: const Conditions(cuisines: {Cuisine.chinese}));
      expect(r.single.restaurant.kakaoId, 'C');
      expect(r.single.reason.kind, ReasonKind.cuisine);
      expect(r.single.reason.cuisine, Cuisine.chinese);
    });

    test('cafes only appear when 카페 is chosen', () {
      final cafe = Restaurant(
        kakaoId: 'K',
        name: '카페',
        categoryName: '음식점 > 카페',
        categoryGroupCode: 'CE7',
        address: '',
        roadAddress: '',
        phone: '',
        latitude: lat + 0.0001,
        longitude: lng,
        distanceMeters: 0,
        placeUrl: null,
      );
      expect(rank([cafe, a]).map((e) => e.restaurant.kakaoId), ['A']);
      expect(
        rank(
          [cafe, a],
          c: const Conditions(cuisines: {Cuisine.cafe}),
        ).map((e) => e.restaurant.kakaoId),
        ['K'],
      );
    });

    test('unknown price / hours never remove a place', () {
      final r = rank(
        [a, b],
        c: const Conditions(
          budget: BudgetOption.max8000,
          amenities: {Amenity.parking},
        ),
      );
      expect(r, hasLength(2));
    });

    test(
      'known price over budget removes the place; known fit is a reason',
      () {
        final insights = {
          'A': const RestaurantInsight(minPriceKrw: 9000),
          'B': const RestaurantInsight(minPriceKrw: 7000),
        };
        final r = rank(
          [a, b],
          c: const Conditions(budget: BudgetOption.max8000),
          insights: insights,
        );
        expect(r.single.restaurant.kakaoId, 'B');
        expect(r.single.reason.kind, ReasonKind.budget);
      },
    );

    test('"order now only" drops places that close before arrival', () {
      final insights = {
        // arrival = 18:54 + 1 min = 18:55; last order 18:50 is too early
        'A': const RestaurantInsight(lastOrderMinutes: 18 * 60 + 50),
        'B': const RestaurantInsight(lastOrderMinutes: 21 * 60 + 30),
      };
      expect(
        rank([a, b], insights: insights).map((e) => e.restaurant.kakaoId),
        ['B'],
      );
      expect(
        rank(
          [a, b],
          c: const Conditions(openNowOnly: false),
          insights: insights,
        ),
        hasLength(2),
      );
    });

    test('price and rating sorts put unknown values last', () {
      final insights = {
        'B': const RestaurantInsight(minPriceKrw: 5000, rating: 4.1),
        'C': const RestaurantInsight(minPriceKrw: 3000, rating: 4.8),
      };
      List<String> ids(SortMode m) => rank(
        [a, b, c],
        c: Conditions(sort: m),
        insights: insights,
      ).map((e) => e.restaurant.kakaoId).toList();
      expect(ids(SortMode.price), ['C', 'B', 'A']);
      expect(ids(SortMode.rating), ['C', 'B', 'A']);
    });

    test('the nearest place is "closest", others get a walking reason', () {
      final r = rank([a, b]);
      expect(r[0].reason.kind, ReasonKind.closest);
      expect(r[1].reason.kind, ReasonKind.walk);
    });
  });

  group('comparison and status', () {
    RankedRestaurant ranked(Restaurant r, [RestaurantInsight? i]) =>
        rank([r], insights: {r.kakaoId: i ?? RestaurantInsight.unknown}).first;

    test('closer wins first, then cheaper, rating, later', () {
      final top = ranked(c, const RestaurantInsight(minPriceKrw: 9000));
      final near = ranked(a, const RestaurantInsight(minPriceKrw: 5000));
      final cmp = compareAgainst(top, near);
      expect(cmp.kind, CompareKind.closer);
      expect(cmp.value, 9); // 10 min vs 1 min

      final sameSpot = ranked(c, const RestaurantInsight(minPriceKrw: 6000));
      final cheaper = compareAgainst(top, sameSpot);
      expect(cheaper.kind, CompareKind.cheaper);
      expect(cheaper.value, 3000);

      expect(
        compareAgainst(
          ranked(a, const RestaurantInsight(rating: 3.9)),
          ranked(a, const RestaurantInsight(rating: 4.5)),
        ).kind,
        CompareKind.higherRating,
      );
      expect(
        compareAgainst(
          ranked(a, const RestaurantInsight(lastOrderMinutes: 1200)),
          ranked(a, const RestaurantInsight(lastOrderMinutes: 1300)),
        ).kind,
        CompareKind.opensLater,
      );
      expect(compareAgainst(ranked(a), ranked(a)).kind, CompareKind.none);
    });

    test('order status: unknown, available, closing soon, too late', () {
      OrderStatus st(int? last, int now) => orderStatus(
        rank(
          [a],
          c: const Conditions(openNowOnly: false),
          insights: {'A': RestaurantInsight(lastOrderMinutes: last)},
          now: now,
        ).first,
        now,
      );
      expect(st(null, 1134).kind, OrderStatusKind.unknown);
      final ok = st(21 * 60 + 30, 18 * 60 + 54); // 21:30, now 18:54, walk 1
      expect(ok.kind, OrderStatusKind.available);
      expect(ok.slackMinutes, 21 * 60 + 30 - (18 * 60 + 55)); // 2h35m
      expect(st(19 * 60 + 30, 18 * 60 + 54).kind, OrderStatusKind.closesSoon);
      expect(
        st(18 * 60 + 50, 18 * 60 + 54).kind,
        OrderStatusKind.closedBeforeArrival,
      );
    });
  });

  group('conditions', () {
    test('defaults have no active conditions; each change counts once', () {
      expect(const Conditions().activeCount, 0);
      expect(
        const Conditions(
          budget: BudgetOption.max8000,
          cuisines: {Cuisine.korean, Cuisine.chinese},
          openNowOnly: false,
        ).activeCount,
        3,
      );
    });

    test('seeded from saved preferences', () {
      final c = Conditions.fromPreferences(
        const UserPreferences(
          budget: BudgetOption.max10000,
          distance: DistanceOption.walk10,
          companions: {CompanionType.friends, CompanionType.professor},
          cuisines: {Cuisine.any},
          tags: {FoodTag.hearty},
          prioritizeUntried: true,
        ),
      );
      expect(c.budget, BudgetOption.max10000);
      expect(c.distance, DistanceOption.walk10);
      expect(c.party, CompanionType.friends);
      expect(c.cuisines, isEmpty, reason: '상관없음 means 전체');
      expect(c.needs, {Need.generousPortion});
      expect(c.untriedFirst, isTrue);
      expect(Conditions.fromPreferences(null), const Conditions());
    });
  });

  group('clock', () {
    test('Seoul wall clock and day parts', () {
      final w = seoulWall(DateTime.utc(2026, 11, 9, 9, 54));
      expect(formatHm(w), '18:54');
      DayPart at(int h) => DayPart.at(DateTime.utc(2026, 1, 1, h));
      expect(at(4), DayPart.lateNight);
      expect(at(5), DayPart.breakfast);
      expect(at(10), DayPart.lunch);
      expect(at(15), DayPart.dinner);
      expect(at(21), DayPart.lateNight);
      expect(formatMinutesOfDay(24 * 60 + 30), '00:30');
    });
  });

  group('next meal', () {
    final meals = [
      fakeMeal('2026-11-09', MealType.breakfast, start: '08:00', end: '09:30'),
      fakeMeal('2026-11-09', MealType.lunch, start: '11:30', end: '14:00'),
      fakeMeal('2026-11-09', MealType.dinner, start: '17:00', end: '19:30'),
      fakeMeal('2026-11-10', MealType.breakfast),
    ];
    NextMeal? at(int h, int m) =>
        pickNextMeal(meals, DateTime.utc(2026, 11, 9, h, m));

    test('shows the meal being served, then the next one, then tomorrow', () {
      expect(at(8, 30)!.meal.type, MealType.breakfast);
      expect(at(8, 30)!.when, MealWhen.now);
      expect(at(7, 0)!.when, MealWhen.today);
      expect(at(9, 45)!.meal.type, MealType.lunch);
      expect(at(18, 54)!.meal.type, MealType.dinner);
      expect(at(18, 54)!.when, MealWhen.now);
      final n = at(19, 31)!;
      expect(n.meal.type, MealType.breakfast);
      expect(n.when, MealWhen.tomorrow);
    });

    test('nothing when no published meal is coming', () {
      expect(pickNextMeal(const [], DateTime.utc(2026, 11, 9, 12)), isNull);
      final closed = [
        fakeMeal('2026-11-09', MealType.dinner, status: MealStatus.closed),
      ];
      expect(pickNextMeal(closed, DateTime.utc(2026, 11, 9, 12)), isNull);
    });
  });
}
