import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_repository.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';

Map<String, dynamic> doc(String id, String cat, String group, String dist) => {
  'id': id,
  'place_name': '가게$id',
  'category_name': cat,
  'category_group_code': group,
  'distance': dist,
  'x': '126.93',
  'y': '36.77',
  'address_name': '',
  'road_address_name': '',
  'phone': '',
  'place_url': 'http://place.map.kakao.com/$id',
};

void main() {
  final univ = kVerifiedUniversities.first;

  test(
    'sends query + numeric coordinates of the selected university',
    () async {
      late Map<String, dynamic> sent;
      final repo = KakaoRestaurantRepository((b) async {
        sent = b;
        return {'success': true, 'restaurants': []};
      });
      await repo.nearby(university: univ);
      expect(sent, {
        'query': '음식점',
        'latitude': univ.latitude,
        'longitude': univ.longitude,
      });
    },
  );

  test('dedupes, drops non-food and sorts by distance', () async {
    final repo = KakaoRestaurantRepository(
      (b) async => {
        'success': true,
        'restaurants': [
          doc('2', '음식점 > 한식', 'FD6', '300'),
          doc('1', '음식점 > 카페', 'CE7', '100'),
          doc('2', '음식점 > 한식', 'FD6', '300'),
          doc('9', '교육 > 학교', 'SC4', '10'),
        ],
      },
    );
    final out = await repo.nearby(university: univ);
    expect(out.map((r) => r.kakaoId), ['1', '2']);
  });

  test(
    'category chips query each keyword and filter by Kakao category',
    () async {
      final queries = <String>[];
      final repo = KakaoRestaurantRepository((b) async {
        queries.add(b['query'] as String);
        return {
          'success': true,
          'restaurants': b['query'] == '카페'
              ? [doc('1', '음식점 > 카페', 'CE7', '50')]
              : [
                  doc('2', '음식점 > 한식', 'FD6', '20'),
                ], // keyword hit, wrong cuisine
        };
      });
      final out = await repo.nearby(
        university: univ,
        category: FoodCategory.cafe,
      );
      expect(queries, ['카페', '디저트']);
      expect(out.map((r) => r.kakaoId), ['1']);
    },
  );

  test('caches identical queries for the TTL', () async {
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final repo = KakaoRestaurantRepository((b) async {
      calls++;
      return {'success': true, 'restaurants': []};
    }, clock: () => now);
    await repo.nearby(university: univ);
    await repo.nearby(university: univ);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 6));
    await repo.nearby(university: univ);
    expect(calls, 2);
  });

  test('maps timeout, bad payload and gateway errors', () async {
    final slow = KakaoRestaurantRepository(
      (b) => Completer<Map<String, dynamic>>().future,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      slow.nearby(university: univ),
      throwsA(
        isA<RestaurantException>().having(
          (e) => e.kind,
          'kind',
          RestaurantErrorKind.timeout,
        ),
      ),
    );

    final bad = KakaoRestaurantRepository((b) async => {'unexpected': 1});
    await expectLater(
      bad.nearby(university: univ),
      throwsA(
        isA<RestaurantException>().having(
          (e) => e.kind,
          'kind',
          RestaurantErrorKind.upstream,
        ),
      ),
    );

    final quota = KakaoRestaurantRepository(
      (b) async => throw const RestaurantException(RestaurantErrorKind.quota),
    );
    await expectLater(
      quota.search(university: univ, query: '돈까스'),
      throwsA(
        isA<RestaurantException>().having(
          (e) => e.kind,
          'kind',
          RestaurantErrorKind.quota,
        ),
      ),
    );
  });

  test(
    'multi-keyword category returns partial results if one query fails',
    () async {
      final repo = KakaoRestaurantRepository((b) async {
        if (b['query'] == '간식') {
          throw const RestaurantException(RestaurantErrorKind.upstream);
        }
        return {
          'success': true,
          'restaurants': [doc('7', '음식점 > 도시락', 'FD6', '5')],
        };
      });
      final out = await repo.nearby(
        university: univ,
        category: FoodCategory.etc,
      );
      expect(out.map((r) => r.kakaoId), ['7']);
    },
  );

  group('세계 음식', () {
    test('queries every validated keyword, dedupes by Kakao id', () async {
      final sent = <String>[];
      final repo = KakaoRestaurantRepository((b) async {
        sent.add(b['query'] as String);
        return {
          'success': true,
          'restaurants': [
            doc('1', '음식점 > 아시아음식 > 동남아음식 > 베트남음식', 'FD6', '300'),
            doc('2', '음식점 > 아시아음식 > 인도음식', 'FD6', '100'),
            doc('3', '음식점 > 한식', 'FD6', '50'), // search noise
            doc('4', '음식점 > 양식 > 멕시칸,브라질', 'FD6', '200'),
          ],
        };
      });
      final out = await repo.nearby(
        university: univ,
        category: FoodCategory.global,
      );
      expect(sent.toSet(), FoodCategory.global.queries.toSet());
      // same ids returned by every query -> listed once, nearest first
      expect(out.map((r) => r.kakaoId), ['2', '4', '1']);
    });

    test('a cuisine sends only its own keyword and filters by path', () async {
      final sent = <String>[];
      final repo = KakaoRestaurantRepository((b) async {
        sent.add(b['query'] as String);
        return {
          'success': true,
          'restaurants': [
            doc('1', '음식점 > 아시아음식 > 동남아음식 > 태국음식', 'FD6', '300'),
            doc('2', '음식점 > 아시아음식 > 동남아음식 > 베트남음식', 'FD6', '100'),
            doc('3', '음식점 > 아시아음식 > 인도음식', 'FD6', '50'),
          ],
        };
      });
      final out = await repo.nearby(
        university: univ,
        category: FoodCategory.global,
        cuisine: GlobalCuisine.thai,
      );
      expect(sent, ['태국음식']);
      expect(out.map((r) => r.kakaoId), ['1']);
    });

    test(
      'a fallback hit for an absent cuisine is not shown as that cuisine',
      () async {
        // Kakao answers "태국음식" with a Vietnamese place when no Thai place
        // is nearby (seen live) -> must be an empty list, not a fake Thai one.
        final repo = KakaoRestaurantRepository(
          (b) async => {
            'success': true,
            'restaurants': [
              doc('1', '음식점 > 아시아음식 > 동남아음식 > 베트남음식', 'FD6', '300'),
            ],
          },
        );
        final out = await repo.nearby(
          university: univ,
          category: FoodCategory.global,
          cuisine: GlobalCuisine.thai,
        );
        expect(out, isEmpty);
      },
    );

    test('other = global places without a named cuisine', () async {
      final repo = KakaoRestaurantRepository(
        (b) async => {
          'success': true,
          'restaurants': [
            doc('1', '음식점 > 아시아음식', 'FD6', '10'),
            doc('2', '음식점 > 아시아음식 > 튀르키예음식', 'FD6', '20'),
            doc('3', '음식점 > 아시아음식 > 인도음식', 'FD6', '30'),
          ],
        },
      );
      final out = await repo.nearby(
        university: univ,
        category: FoodCategory.global,
        cuisine: GlobalCuisine.other,
      );
      expect(out.map((r) => r.kakaoId), ['1', '2']);
    });

    test('cuisine is ignored outside 세계 음식', () async {
      final sent = <String>[];
      final repo = KakaoRestaurantRepository((b) async {
        sent.add(b['query'] as String);
        return {'success': true, 'restaurants': []};
      });
      await repo.nearby(
        university: univ,
        category: FoodCategory.korean,
        cuisine: GlobalCuisine.thai,
      );
      expect(sent, ['한식']);
    });

    test(
      'partial failure keeps the other keywords; total failure throws',
      () async {
        final partial = KakaoRestaurantRepository((b) async {
          if (b['query'] == '태국음식') {
            throw const RestaurantException(RestaurantErrorKind.upstream);
          }
          return {
            'success': true,
            'restaurants': [doc('1', '음식점 > 아시아음식 > 인도음식', 'FD6', '5')],
          };
        });
        final out = await partial.nearby(
          university: univ,
          category: FoodCategory.global,
        );
        expect(out.map((r) => r.kakaoId), ['1']);

        final down = KakaoRestaurantRepository(
          (b) async =>
              throw const RestaurantException(RestaurantErrorKind.network),
        );
        expect(
          () => down.nearby(university: univ, category: FoodCategory.global),
          throwsA(isA<RestaurantException>()),
        );
      },
    );
  });

  test('blank search returns empty without a network call', () async {
    var calls = 0;
    final repo = KakaoRestaurantRepository((b) async {
      calls++;
      return {'success': true, 'restaurants': []};
    });
    expect(await repo.search(university: univ, query: '   '), isEmpty);
    expect(calls, 0);
  });
}
