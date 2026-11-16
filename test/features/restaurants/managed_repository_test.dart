import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/restaurants/repositories/managed_restaurant_repository.dart';
import 'package:meogeobojo/features/university/models/university.dart';

import '../../support/fakes.dart';

const uni = University(
  id: 'u',
  nameKo: '순천향대학교',
  latitude: 36.77,
  longitude: 126.93,
);

class FakeInventory implements ManagedInventory {
  FakeInventory(this.rows, {this.fail = false});
  List<RestaurantOverride> rows;
  final bool fail;
  int reads = 0;

  @override
  Future<List<RestaurantOverride>> publishedFor(String universityId) async {
    reads++;
    if (fail) throw StateError('offline');
    return rows;
  }
}

/// A Kakao that knows [docs] by id; counts how it was asked.
class FakeResolver {
  FakeResolver(this.docs, {this.fail = false, this.partial = false});
  final Map<String, Map<String, dynamic>> docs;
  final bool fail;
  final bool partial;
  final asked = <List<({String id, String name})>>[];

  Future<ResolvedPlaces> call(
    University u,
    List<({String id, String name})> places,
  ) async {
    asked.add(places);
    if (fail) throw StateError('resolve_places down');
    return (docs: [for (final p in places) ?docs[p.id]], partial: partial);
  }
}

Map<String, dynamic> kdoc(
  String id,
  String name, {
  String cat = '음식점 > 한식',
  String distance = '200',
  String y = '36.771',
}) => {
  'id': id,
  'place_name': name,
  'category_name': cat,
  'category_group_code': 'FD6',
  'address_name': '지번 $id',
  'road_address_name': '카카오 도로 $id',
  'phone': '041-000-0000',
  'x': '126.931',
  'y': y,
  'distance': distance,
  'place_url': 'http://place.map.kakao.com/$id',
};

RestaurantOverride managed(
  String key, {
  String? name,
  String? category,
  double? lat,
  double? lng,
  String visibility = 'published',
}) => RestaurantOverride(
  kakaoId: key,
  id: 'db-$key',
  visibility: visibility,
  name: name ?? '관리 $key',
  category: category,
  latitude: lat,
  longitude: lng,
);

void main() {
  late FakeRestaurantRepository kakaoOnly;
  setUp(
    () => kakaoOnly = FakeRestaurantRepository(
      items: [fakeRestaurant('900', name: '카카오에만 있는 식당')],
    ),
  );

  ManagedRestaurantRepository repo(FakeInventory inv, FakeResolver res) =>
      ManagedRestaurantRepository(
        inventory: inv,
        resolver: res.call,
        fallback: kakaoOnly,
      );

  test('the published restaurants ARE the list: a Kakao place that is not published never appears', () async {
    final inv = FakeInventory([managed('1'), managed('2')]);
    final res = FakeResolver({
      '1': kdoc('1', '카카오 1', distance: '300'),
      '2': kdoc('2', '카카오 2', distance: '100'),
      '900': kdoc('900', '카카오에만 있는 식당'),
    });
    final out = await repo(inv, res).nearby(university: uni);
    expect(out.map((r) => r.kakaoId), ['2', '1']); // nearest first
    expect(out.any((r) => r.kakaoId == '900'), isFalse);
    expect(
      kakaoOnly.nearbyCalls,
      isEmpty,
    ); // Kakao discovery was not used for this campus
    expect(res.asked, hasLength(1)); // ONE lookup for all of them
    expect(res.asked.single.map((p) => p.id), ['1', '2']);
  });

  test('managed name, address, phone and category win over Kakao; the id, the Kakao position and distance stay', () async {
    final inv = FakeInventory([
      RestaurantOverride(
        kakaoId: '1',
        id: 'db-1',
        visibility: 'published',
        name: '내가 정한 이름',
        address: '내 주소',
        category: '음식점 > 중식',
      ),
    ]);
    final out = await repo(
      inv,
      FakeResolver({'1': kdoc('1', '카카오 이름', distance: '321')}),
    ).nearby(university: uni);
    final r = out.single;
    expect(
      [r.kakaoId, r.name, r.roadAddress, r.categoryName],
      ['1', '내가 정한 이름', '내 주소', '음식점 > 중식'],
    );
    expect(r.distanceMeters, 321);
    expect(r.latitude, closeTo(36.771, 1e-9));
    expect(
      r.phone,
      '041-000-0000',
    ); // nothing managed for the phone: Kakao's live value shows
  });

  test('a restaurant without Kakao match is still shown when it has coordinates of its own (no Kakao Place ID needed)', () async {
    final inv = FakeInventory([
      managed(
        '3f2c0f6e-1111-4222-8333-444455556666',
        name: '직접 등록집',
        category: '음식점 > 한식',
        lat: 36.772,
        lng: 126.931,
      ),
    ]);
    final res = FakeResolver({});
    final out = await repo(inv, res).nearby(university: uni);
    expect(out.single.name, '직접 등록집');
    expect(out.single.latitude, 36.772);
    expect(out.single.distanceMeters, inInclusiveRange(100, 400));
    expect(res.asked, isEmpty); // nothing to look up at Kakao
  });

  test('a published restaurant whose position is unknown is left out of the list (never shown at a made-up place)', () async {
    final inv = FakeInventory([
      managed('1'),
      managed('77'),
    ]); // 77: Kakao does not know it
    final out = await repo(
      inv,
      FakeResolver({'1': kdoc('1', 'k')}),
    ).nearby(university: uni);
    expect(out.map((r) => r.kakaoId), ['1']);
    expect(out.every((r) => r.latitude != 0 && r.longitude != 0), isTrue);
  });

  test('unpublishing removes it: the next read no longer has it (nothing is cached between reads)', () async {
    final inv = FakeInventory([managed('1'), managed('2')]);
    final res = FakeResolver({'1': kdoc('1', 'a'), '2': kdoc('2', 'b')});
    final r = repo(inv, res);
    expect((await r.nearby(university: uni)).map((e) => e.kakaoId).toSet(), {
      '1',
      '2',
    });
    inv.rows = [managed('1')]; // the admin unpublished 2
    expect((await r.nearby(university: uni)).map((e) => e.kakaoId), ['1']);
    expect((await r.search(university: uni, query: 'b')), isEmpty);
  });

  test('a renamed restaurant shows its new name straight away (managed data is read fresh)', () async {
    final inv = FakeInventory([managed('1', name: '옛 이름')]);
    final r = repo(inv, FakeResolver({'1': kdoc('1', 'k')}));
    expect((await r.nearby(university: uni)).single.name, '옛 이름');
    inv.rows = [managed('1', name: '새 이름')];
    expect((await r.nearby(university: uni)).single.name, '새 이름');
  });

  test(
    'providers asking at the same moment share ONE read and ONE lookup',
    () async {
      final inv = FakeInventory([managed('1')]);
      final res = FakeResolver({'1': kdoc('1', 'k')});
      final r = repo(inv, res);
      await Future.wait([
        r.nearby(university: uni),
        r.nearby(university: uni, category: FoodCategory.korean),
        r.search(university: uni, query: '관리'),
      ]);
      expect(inv.reads, 1);
      expect(res.asked, hasLength(1));
    },
  );

  test('categories filter the managed list by the (managed or Kakao) category path', () async {
    final inv = FakeInventory([
      managed('1'),
      managed('2', category: '음식점 > 일식'),
    ]);
    final res = FakeResolver({
      '1': kdoc('1', 'a', cat: '음식점 > 한식'),
      '2': kdoc('2', 'b', cat: '음식점 > 한식'),
    });
    final r = repo(inv, res);
    expect(
      (await r.nearby(
        university: uni,
        category: FoodCategory.korean,
      )).map((e) => e.kakaoId),
      ['1'],
    );
    expect(
      (await r.nearby(
        university: uni,
        category: FoodCategory.japanese,
      )).map((e) => e.kakaoId),
      ['2'],
    ); // the managed category wins
  });

  test('search looks only inside the published restaurants', () async {
    final inv = FakeInventory([
      managed('1', name: '국수집'),
      managed('2', name: '라멘집'),
    ]);
    final res = FakeResolver({'1': kdoc('1', 'k1'), '2': kdoc('2', 'k2')});
    final out = await repo(inv, res).search(university: uni, query: ' 국수 ');
    expect(out.map((e) => e.kakaoId), ['1']);
    expect(kakaoOnly.nearbyCalls, isEmpty);
  });

  test('a campus with nothing published keeps the Kakao discovery (it is not empty before the first publish)', () async {
    final out = await repo(
      FakeInventory([]),
      FakeResolver({}),
    ).nearby(university: uni);
    expect(out.map((r) => r.kakaoId), ['900']);
  });

  test('if the published list cannot be read, or Kakao cannot be asked, the earlier behaviour answers instead of an empty app', () async {
    expect(
      (await repo(
        FakeInventory([], fail: true),
        FakeResolver({}),
      ).nearby(university: uni)).map((r) => r.kakaoId),
      ['900'],
    );
    expect(
      (await repo(
        FakeInventory([managed('1')]),
        FakeResolver({}, fail: true),
      ).nearby(university: uni)).map((r) => r.kakaoId),
      ['900'],
    );
  });

  test('drafts, hidden and archived rows are never part of the inventory the repository trusts', () async {
    // the Supabase inventory only returns published rows; a row that still says otherwise is not listed either
    final inv = FakeInventory([
      managed('1', visibility: 'hidden'),
      managed('2'),
    ]);
    final out = await repo(
      inv,
      FakeResolver({'1': kdoc('1', 'a'), '2': kdoc('2', 'b')}),
    ).nearby(university: uni);
    expect(out.map((e) => e.kakaoId), ['2']);
  });
}
