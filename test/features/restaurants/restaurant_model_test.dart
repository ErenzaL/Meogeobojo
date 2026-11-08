import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

import '../../support/fakes.dart';

void main() {
  // Shape copied from a real search_restaurants response.
  const kakao = {
    'address_name': '충남 아산시 신창면 읍내리 662-22',
    'category_group_code': 'FD6',
    'category_name': '음식점 > 한식 > 국수',
    'distance': '257',
    'id': '52934791',
    'phone': '041-544-3334',
    'place_name': '국제냉밀면',
    'place_url': 'http://place.map.kakao.com/52934791',
    'road_address_name': '충남 아산시 신창면 온천대로 753',
    'x': '126.929146689255',
    'y': '36.7714261564853',
  };

  test('fromKakao parses fields, upgrades url to https', () {
    final r = Restaurant.fromKakao(kakao, originLat: 36.77, originLng: 126.93)!;
    expect(r.name, '국제냉밀면');
    expect(r.categoryTag, '한식');
    expect(r.distanceMeters, 257);
    expect(r.placeUrl, 'https://place.map.kakao.com/52934791');
    expect(r.displayAddress, '충남 아산시 신창면 온천대로 753');
  });

  test('fromKakao computes distance when missing and rejects bad rows', () {
    final r = Restaurant.fromKakao(
      {...kakao, 'distance': ''},
      originLat: 36.7698,
      originLng: 126.9312,
    )!;
    expect(r.distanceMeters, greaterThan(0));
    expect(
      Restaurant.fromKakao({...kakao, 'x': 'oops'}, originLat: 0, originLng: 0),
      isNull,
    );
    expect(
      Restaurant.fromKakao(
        {...kakao}..remove('id'),
        originLat: 0,
        originLng: 0,
      ),
      isNull,
    );
  });

  group('FoodCategory.matches only trusts Kakao classification', () {
    final korean = fakeRestaurant('1', category: '음식점 > 한식 > 국수');
    final cafe = fakeRestaurant('2', category: '음식점 > 카페', group: 'CE7');
    final chicken = fakeRestaurant('3', category: '음식점 > 치킨');
    final school = fakeRestaurant('4', category: '교육,학문 > 학교', group: 'SC4');

    test('cuisine chips', () {
      expect(FoodCategory.korean.matches(korean), isTrue);
      expect(FoodCategory.japanese.matches(korean), isFalse);
      expect(FoodCategory.cafe.matches(cafe), isTrue);
      expect(FoodCategory.cafe.matches(korean), isFalse);
    });

    test('chicken and fast food are their own categories', () {
      final fast = fakeRestaurant('5', category: '음식점 > 패스트푸드 > 롯데리아');
      expect(FoodCategory.chicken.matches(chicken), isTrue);
      expect(FoodCategory.chicken.matches(fast), isFalse);
      expect(FoodCategory.fastFood.matches(fast), isTrue);
      expect(FoodCategory.fastFood.matches(chicken), isFalse);
      expect(FoodCategory.korean.matches(chicken), isFalse);
    });

    test(
      'etc is everything Kakao lists under 음식점 that has no category above',
      () {
        final asian = fakeRestaurant('6', category: '음식점 > 아시아음식 > 베트남음식');
        final bakery = fakeRestaurant('7', category: '음식점 > 간식 > 제과,베이커리');
        final buffet = fakeRestaurant('8', category: '음식점 > 뷔페');
        final fast = fakeRestaurant('9', category: '음식점 > 패스트푸드');
        for (final r in [bakery, buffet]) {
          expect(FoodCategory.etc.matches(r), isTrue, reason: r.categoryName);
        }
        // Asian / global places are listed under 세계 음식, never twice.
        for (final r in [asian, chicken, fast, korean, cafe]) {
          expect(FoodCategory.etc.matches(r), isFalse, reason: r.categoryName);
        }
      },
    );

    test('every food place has at most one specific category (plus 전체)', () {
      final samples = [
        korean,
        cafe,
        chicken,
        fakeRestaurant('a', category: '음식점 > 일식 > 초밥,롤'),
        fakeRestaurant('b', category: '음식점 > 분식 > 떡볶이'),
        fakeRestaurant('c', category: '음식점 > 패스트푸드'),
        fakeRestaurant('d', category: '음식점 > 아시아음식'),
        fakeRestaurant('e', category: '음식점 > 중식 > 중국요리'),
        fakeRestaurant('f', category: '음식점 > 양식 > 햄버거'),
      ];
      for (final r in samples) {
        final hits = FoodCategory.values
            .where((c) => c != FoodCategory.all && c.matches(r))
            .toList();
        expect(hits.length, 1, reason: '${r.categoryName} -> $hits');
        expect(FoodCategory.all.matches(r), isTrue);
      }
    });

    test('the display order of the eleven restaurant categories', () {
      expect(FoodCategory.values.map((c) => c.name), [
        'all',
        'korean',
        'western',
        'chinese',
        'japanese',
        'snack',
        'cafe',
        'chicken',
        'fastFood',
        'global',
        'etc',
      ]);
    });

    group('세계 음식', () {
      Restaurant r(String id, String path) =>
          fakeRestaurant(id, category: path);
      final viet = r('v', '음식점 > 아시아음식 > 동남아음식 > 베트남음식');
      final vietBrand = r('vb', '음식점 > 아시아음식 > 동남아음식 > 베트남음식 > 에머이');
      final thai = r('t', '음식점 > 아시아음식 > 동남아음식 > 태국음식');
      final indian = r('i', '음식점 > 아시아음식 > 인도음식');
      final mexican = r('m', '음식점 > 양식 > 멕시칸,브라질');
      final turkish = r('k', '음식점 > 아시아음식 > 튀르키예음식');
      final seAsia = r('s', '음식점 > 아시아음식 > 동남아음식');
      final plainAsian = r('a', '음식점 > 아시아음식');
      final all = [
        viet,
        vietBrand,
        thai,
        indian,
        mexican,
        turkish,
        seAsia,
        plainAsian,
      ];

      test('global matches what Kakao files as Asian or Mexican', () {
        for (final x in all) {
          expect(
            FoodCategory.global.matches(x),
            isTrue,
            reason: x.categoryName,
          );
          expect(GlobalCuisine.all.matches(x), isTrue);
        }
      });

      test('each cuisine matches only its own Kakao path', () {
        expect(GlobalCuisine.vietnamese.matches(viet), isTrue);
        expect(GlobalCuisine.vietnamese.matches(vietBrand), isTrue);
        expect(GlobalCuisine.thai.matches(thai), isTrue);
        expect(GlobalCuisine.indian.matches(indian), isTrue);
        expect(GlobalCuisine.mexican.matches(mexican), isTrue);
        for (final (c, ok) in [
          (GlobalCuisine.vietnamese, [viet, vietBrand]),
          (GlobalCuisine.thai, [thai]),
          (GlobalCuisine.indian, [indian]),
          (GlobalCuisine.mexican, [mexican]),
          (GlobalCuisine.other, [turkish, seAsia, plainAsian]),
        ]) {
          for (final x in all) {
            expect(
              c.matches(x),
              ok.contains(x),
              reason: '${c.name} ${x.categoryName}',
            );
          }
        }
      });

      test('never classifies by restaurant name', () {
        // A Korean place named after Thailand / India / Vietnam / Mexico.
        for (final name in ['방콕', '인도', '베트남쌀국수', '멕시칸치킨', '타코']) {
          final x = fakeRestaurant('n', name: name, category: '음식점 > 한식');
          expect(FoodCategory.global.matches(x), isFalse, reason: name);
          for (final c in GlobalCuisine.values) {
            expect(c.matches(x), isFalse, reason: '$name ${c.name}');
          }
        }
      });

      test('non-food places and other cuisines do not match', () {
        expect(FoodCategory.global.matches(school), isFalse);
        expect(FoodCategory.global.matches(korean), isFalse);
        expect(
          FoodCategory.global.matches(r('it', '음식점 > 양식 > 이탈리안')),
          isFalse,
        );
        expect(FoodCategory.global.matches(cafe), isFalse);
      });

      test('Mexican is listed under 세계 음식 only, not also 양식', () {
        expect(FoodCategory.western.matches(mexican), isFalse);
        expect(
          FoodCategory.western.matches(r('it', '음식점 > 양식 > 이탈리안')),
          isTrue,
        );
      });

      test('queries are the validated Kakao keywords', () {
        expect(FoodCategory.global.queries, [
          '아시아음식',
          '베트남음식',
          '태국음식',
          '인도음식',
          '멕시칸',
          '튀르키예음식',
        ]);
        expect(GlobalCuisine.vietnamese.queries, ['베트남음식']);
        expect(GlobalCuisine.thai.queries, ['태국음식']);
        expect(GlobalCuisine.indian.queries, ['인도음식']);
        expect(GlobalCuisine.mexican.queries, ['멕시칸']);
      });
    });

    test('chicken queries are the ones verified against the live function', () {
      expect(FoodCategory.chicken.queries, ['치킨집', '양념치킨']);
    });

    test('non-food places never match any chip', () {
      for (final c in FoodCategory.values) {
        expect(c.matches(school), isFalse, reason: c.name);
      }
    });
  });
}
