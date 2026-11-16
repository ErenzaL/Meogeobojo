import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/providers/ranking_providers.dart';
import 'package:meogeobojo/features/recommendation/recommendation_score.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/recommendation/review_signal_repository.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

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
  Conditions c = const Conditions(distance: DistanceOption.walk15),
  Map<String, RestaurantInsight> insights = const {},
  Map<String, double> reviews = const {},
}) => rankRestaurants(
  all: all,
  lat: lat,
  lng: lng,
  conditions: c,
  insights: insights,
  reviewSignals: reviews,
  nowMinutes: 12 * 60,
);

void main() {
  group('the V3 formula (the team\'s 순천향대 example)', () {
    test('자유식당: 한식 (C=1), 410.34 m of a 1 km radius, no reviews -> V3 = V1 = 0.7948', () {
      final d = distanceScore(410.34, 1000);
      expect(d, closeTo(0.5897, 1e-4));
      final v1 = preferenceDistanceScore(matchesPreference: true, distance: d);
      expect(v1, closeTo(0.7948, 5e-5));
      expect(v3Score(v1, 0), closeTo(0.7948, 5e-5));
    });

    test('the other rows of the example table: 콩불파삼 422 m -> 0.7889, 신전떡볶이 428 m -> 0.7860, 궁중화로 615 m -> 0.6925', () {
      double v(double m) => v3Score(
        preferenceDistanceScore(
          matchesPreference: true,
          distance: distanceScore(m, 1000),
        ),
        0,
      );
      expect(v(422.2), closeTo(0.7889, 1e-4));
      expect(v(428), closeTo(0.786, 1e-3));
      expect(v(615), closeTo(0.6925, 1e-3));
    });

    test('V1 = D when no food preference is chosen; D is 0 at and beyond the radius; V3 is clipped to 0..1', () {
      expect(
        preferenceDistanceScore(matchesPreference: null, distance: 0.6),
        0.6,
      );
      expect(distanceScore(1000, 1000), 0);
      expect(distanceScore(1500, 1000), 0);
      expect(distanceScore(0, 1000), 1);
      expect(v3Score(0.95, 1), 1);
      expect(v3Score(0.05, -1), 0);
    });

    test(
      'V0 (distance only) is the baseline: a nearer place always scores higher',
      () {
        expect(distanceScore(100, 1000), greaterThan(distanceScore(200, 1000)));
      },
    );
  });

  group('the review signal R', () {
    final now = DateTime(2026, 11, 16);

    test('a review loses half its weight every 90 days', () {
      expect(reviewWeight(now, now), 1);
      expect(
        reviewWeight(now.subtract(const Duration(days: 90)), now),
        closeTo(0.5, 1e-9),
      );
      expect(
        reviewWeight(now.subtract(const Duration(days: 180)), now),
        closeTo(0.25, 1e-9),
      );
      expect(
        reviewWeight(now.add(const Duration(days: 3)), now),
        1,
      ); // a clock skew never gives more than 1
    });

    test('with no review R is 0', () {
      expect(reviewSignal(reviews: const [], now: now, overallRating: 4), 0);
    });

    test('one 5-star review barely moves a place (20 imaginary average reviews): R = (4.0476 - 4) / 4', () {
      final r = reviewSignal(
        reviews: [ReviewSample(rating: 5, at: now)],
        now: now,
        overallRating: 4,
      );
      expect(r, closeTo(((20 * 4 + 5) / 21 - 4) / 4, 1e-9));
    });

    test('many recent good reviews push R up, many bad ones push it down', () {
      List<ReviewSample> many(int stars) => [
        for (var i = 0; i < 60; i++) ReviewSample(rating: stars, at: now),
      ];
      final good = reviewSignal(reviews: many(5), now: now, overallRating: 3.5);
      final bad = reviewSignal(reviews: many(1), now: now, overallRating: 3.5);
      expect(good, greaterThan(0.2));
      expect(bad, lessThan(-0.3));
    });

    test('old reviews count less than recent ones', () {
      final recent = reviewSignal(
        reviews: [
          for (var i = 0; i < 30; i++) ReviewSample(rating: 5, at: now),
        ],
        now: now,
        overallRating: 3,
      );
      final old = reviewSignal(
        reviews: [
          for (var i = 0; i < 30; i++)
            ReviewSample(
              rating: 5,
              at: now.subtract(const Duration(days: 360)),
            ),
        ],
        now: now,
        overallRating: 3,
      );
      expect(recent, greaterThan(old));
    });

    test('stars count 0.7 and text 0.3 when both exist; with only stars, the stars alone', () {
      final starsOnly = reviewSignal(
        reviews: [
          for (var i = 0; i < 40; i++) ReviewSample(rating: 5, at: now),
        ],
        now: now,
        overallRating: 3,
      );
      final both = reviewSignal(
        reviews: [
          for (var i = 0; i < 40; i++)
            ReviewSample(rating: 5, at: now, text: 0.75),
        ],
        now: now,
        overallRating: 3,
        overallText: 0.5,
      );
      expect(both, isNot(starsOnly));
      final adjStars = ((20 * 3 + 40 * 5) / 60 - 3) / 4;
      final adjText = (20 * 0.5 + 40 * 0.75) / 60 - 0.5;
      expect(both, closeTo(0.7 * adjStars + 0.3 * adjText, 1e-9));
      expect(starsOnly, closeTo(adjStars, 1e-9));
    });

    test('reviewSignalsFrom: the overall average is over all reviews; a place without reviews is left out', () {
      final out = reviewSignalsFrom([
        (placeId: 'A', sample: ReviewSample(rating: 5, at: now)),
        (placeId: 'A', sample: ReviewSample(rating: 5, at: now)),
        (placeId: 'B', sample: ReviewSample(rating: 1, at: now)),
      ], now);
      expect(out.keys.toSet(), {'A', 'B'});
      expect(out['A'], greaterThan(0));
      expect(out['B'], lessThan(0));
      expect(reviewSignalsFrom(const [], now), isEmpty);
    });
  });

  group('ranking by V3', () {
    final near = place(
      'near',
      0.0005,
      category: '음식점 > 중식',
    ); // ~56 m, not preferred
    final far = place(
      'far',
      0.0090,
    ); // ~1000 m but 한식 (preferred); beyond walk15 (1200 m)? ~1 km: inside

    test('without a food preference the order is by distance (V3 = D)', () {
      final r = rank([far, near]);
      expect(r.map((e) => e.restaurant.kakaoId), ['near', 'far']);
      expect(r.first.score, greaterThan(r.last.score!));
    });

    test('a preferred food class can lift a farther place above a nearer one (C adds 0.5)', () {
      final mid = place('mid', 0.0040); // ~445 m, 한식
      final nearOther = place(
        'nearOther',
        0.0010,
        category: '음식점 > 중식',
      ); // ~111 m
      final r = rank(
        [nearOther, mid],
        c: const Conditions(
          distance: DistanceOption.walk15,
          cuisines: {Cuisine.korean},
        ),
      );
      expect(r.map((e) => e.restaurant.kakaoId), ['mid', 'nearOther']);
      // V1(mid) = 0.5 + 0.5 * (1 - 445/1200) ~ 0.81 vs V1(nearOther) = 0.5 * (1 - 111/1200) ~ 0.45
      expect(r.first.score, greaterThan(0.75));
      expect(r.last.score, lessThan(0.5));
    });

    test(
      'confirmed matches stay ahead of "정보 미확인" places however high the score',
      () {
        final known = place(
          'known',
          0.0080,
        ); // far, but its meal fits the budget
        final unknown = place('unknown', 0.0005); // near, no price data
        final r = rank(
          [unknown, known],
          c: const Conditions(
            distance: DistanceOption.walk15,
            budget: BudgetOption.max8000,
          ),
          insights: {
            'known': RestaurantInsight(
              menus: const [MenuLine(priceKrw: 7000, category: '식사')],
            ),
          },
        );
        expect(r.map((e) => e.restaurant.kakaoId), ['known', 'unknown']);
        expect(r.first.verified, isTrue);
        expect(r.last.verified, isFalse);
      },
    );

    test('a place whose meals are all over the budget is dropped; unknown prices are kept as unconfirmed', () {
      final dear = place('dear', 0.0005);
      final unknown = place('unknown', 0.0010);
      final r = rank(
        [dear, unknown],
        c: const Conditions(
          distance: DistanceOption.walk15,
          budget: BudgetOption.max8000,
        ),
        insights: {
          'dear': RestaurantInsight(
            menus: const [MenuLine(priceKrw: 12000, category: '식사')],
          ),
        },
      );
      expect(r.map((e) => e.restaurant.kakaoId), ['unknown']);
    });

    test('equal scores: the nearer place, then the smaller place id', () {
      final a = place('2', 0.0010);
      final b = place('1', 0.0010);
      final r = rank([a, b]);
      expect(r.map((e) => e.restaurant.kakaoId), ['1', '2']);
    });

    test(
      'a strong review signal lifts a place over an equally distant one',
      () {
        final a = place('A', 0.0050);
        final b = place('B', 0.0050);
        final r = rank([a, b], reviews: {'B': 0.6});
        expect(r.map((e) => e.restaurant.kakaoId), ['B', 'A']);
        expect(r.first.score! - r.last.score!, closeTo(0.2 * 0.6, 1e-9));
      },
    );

    test('a review cannot pull a far place past 1 or below 0 (clip)', () {
      final r = rank([place('A', 0.0001)], reviews: {'A': 1});
      expect(r.single.score, lessThanOrEqualTo(1));
    });

    test('sorting by distance, price or rating still works and ignores V3', () {
      final a = place('A', 0.0005, category: '음식점 > 중식');
      final b = place('B', 0.0040);
      final r = rank(
        [b, a],
        c: const Conditions(
          distance: DistanceOption.walk15,
          cuisines: {Cuisine.korean},
          sort: SortMode.distance,
        ),
      );
      expect(r.map((e) => e.restaurant.kakaoId), ['A', 'B']);
    });

    test('with any distance the farthest candidate is the scale', () {
      final r = rank([
        place('A', 0.0010),
        place('B', 0.0100),
      ], c: const Conditions());
      expect(r.last.score, closeTo(0, 1e-9)); // the farthest one has D = 0
      expect(r.first.score, greaterThan(0.8));
    });

    test('the same request always gives the same order (deterministic)', () {
      final all = [
        for (var i = 0; i < 12; i++) place('$i', 0.0005 * (i % 4 + 1)),
      ];
      final a = rank(all).map((e) => e.restaurant.kakaoId).toList();
      final b = rank(all.reversed.toList())
          .map((e) => e.restaurant.kakaoId)
          .toList();
      expect(a, b);
    });
  });

  group('review signals from the visible student reviews', () {
    test('the provider turns the reviews into R per place; a failing source means no signal, not an error', () async {
      final now = DateTime.now();
      final good = ProviderContainer(
        overrides: [
          reviewSignalSourceProvider.overrideWithValue(
            _FakeReviews([
              for (var i = 0; i < 30; i++)
                (placeId: 'A', sample: ReviewSample(rating: 5, at: now)),
              for (var i = 0; i < 30; i++)
                (placeId: 'B', sample: ReviewSample(rating: 2, at: now)),
            ]),
          ),
        ],
      );
      addTearDown(good.dispose);
      final r = await good.read(reviewSignalsProvider.future);
      expect(r['A'], greaterThan(0));
      expect(r['B'], lessThan(0));
      expect(r.containsKey('C'), isFalse);

      final empty = ProviderContainer(
        overrides: [
          reviewSignalSourceProvider.overrideWithValue(_FakeReviews(const [])),
        ],
      );
      addTearDown(empty.dispose);
      expect(await empty.read(reviewSignalsProvider.future), isEmpty);
    });
  });
}

class _FakeReviews implements ReviewSignalSource {
  _FakeReviews(this.rows);
  final List<({String placeId, ReviewSample sample})> rows;

  @override
  Future<List<({String placeId, ReviewSample sample})>>
  visibleReviews() async => rows;
}
