import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/restaurants/repositories/merged_restaurant_repository.dart';
import 'package:meogeobojo/features/university/models/university.dart';

import '../../support/fakes.dart';

const uni = University(
  id: 'u',
  nameKo: '순천향대학교',
  latitude: 36.77,
  longitude: 126.93,
);

void main() {
  final kakao = [
    fakeRestaurant('1', name: '국수집'),
    fakeRestaurant('2', name: '라멘'),
    fakeRestaurant('3', name: '카페'),
  ];

  OverrideAwareRestaurantRepository repo(
    Map<String, RestaurantOverride> overrides,
  ) => OverrideAwareRestaurantRepository(
    FakeRestaurantRepository(items: kakao),
    FakeRestaurantOverrideRepository(overrides: overrides),
  );

  test('with no admin data the Kakao result is returned untouched', () async {
    final out = await repo({}).nearby(university: uni);
    expect(out.map((r) => r.kakaoId), ['1', '2', '3']);
    expect(out.first.name, '국수집1');
  });

  test('hidden and archived places are dropped; drafts are not a thing the app can read', () async {
    final r = repo({
      '1': const RestaurantOverride(kakaoId: '1', visibility: 'hidden'),
      '2': const RestaurantOverride(kakaoId: '2', visibility: 'archived'),
      '3': const RestaurantOverride(kakaoId: '3', visibility: 'published'),
    });
    expect((await r.nearby(university: uni)).map((e) => e.kakaoId), ['3']);
    // search goes through the same merge
    expect(
      (await r.search(university: uni, query: '국수')).map((e) => e.kakaoId),
      ['3'],
    );
  });

  test('a published override replaces name, address and phone; ids, category and coordinates stay', () async {
    final out = await repo({
      '1': const RestaurantOverride(
        kakaoId: '1',
        visibility: 'published',
        name: '진짜 국수집',
        address: '관리자 주소 1',
        phone: '041-111-2222',
      ),
    }).nearby(university: uni);
    final r = out.firstWhere((e) => e.kakaoId == '1');
    expect(r.name, '진짜 국수집');
    expect(r.displayAddress, '관리자 주소 1');
    expect(r.phone, '041-111-2222');
    // untouched: what favorites, markers, filters and ranking rely on
    expect(r.categoryName, '음식점 > 한식');
    expect(r.latitude, 36.77);
    expect(r.distanceMeters, 100);
    expect(r.placeUrl, 'https://place.map.kakao.com/1');
  });

  test('empty admin fields fall back to Kakao per field', () async {
    final out = await repo({
      '2': const RestaurantOverride(
        kakaoId: '2',
        visibility: 'published',
        name: '새 이름',
      ),
    }).nearby(university: uni);
    final r = out.firstWhere((e) => e.kakaoId == '2');
    expect(r.name, '새 이름');
    expect(
      r.displayAddress,
      '충남 아산시 순천향로 1',
    ); // Kakao's, since the admin left it empty
  });

  test('order and the unmanaged places are preserved', () async {
    final out = await repo({
      '2': const RestaurantOverride(kakaoId: '2', visibility: 'hidden'),
    }).nearby(university: uni, category: FoodCategory.korean);
    expect(out.map((e) => e.kakaoId), ['1', '3']);
  });

  test('parsing: blank admin fields are ignored; the insight is kept', () {
    final o = RestaurantOverride.fromJson({
      'kakao_place_id': 'k',
      'visibility': 'published',
      'name_ko': '  ',
      'address': ' 주소 ',
      'phone': null,
      'price_min_krw': 8000,
    })!;
    expect(o.name, isNull);
    expect(o.address, '주소');
    expect(o.phone, isNull);
    expect(o.insight, isA<RestaurantInsight>());
    expect(o.insight.minPriceKrw, 8000);
  });
}
