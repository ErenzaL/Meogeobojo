import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/home/providers/home_providers.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/records/meal_records.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

Future<ProviderContainer> containerWith(
  Map<String, Object> storage, {
  bool signedIn = false,
}) async {
  SharedPreferences.setMockInitialValues(storage);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      currentUserProvider.overrideWithValue(signedIn ? fakeUser() : null),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

String saved(DateTime at) => jsonEncode(
  ActiveRecommendation(
    heroId: 'A',
    key: 'k',
    at: at,
    went: fakeRestaurant('B'),
  ).toJson(),
);

void main() {
  group('미확인 후보', () {
    // Same spot: the tie breaks by name, so distance order alone puts A first.
    final a = fakeRestaurant('A');
    final b = fakeRestaurant('B');

    List<RankedRestaurant> rank(Conditions c) => rankRestaurants(
      all: [a, b],
      lat: 36.77,
      lng: 126.93,
      conditions: c,
      insights: {
        'B': const RestaurantInsight(
          menus: [MenuLine(priceKrw: 7000, category: '식사')],
        ),
      },
      nowMinutes: 12 * 60,
    );

    test('no data condition: every place is confirmed, order unchanged', () {
      final r = rank(const Conditions());
      expect(r.every((x) => x.verified), isTrue);
    });

    test('a budget puts the place with a known meal price first', () {
      final r = rank(const Conditions(budget: BudgetOption.max8000));
      expect([for (final x in r) x.restaurant.kakaoId], ['B', 'A']);
      expect([for (final x in r) x.verified], [true, false]);
    });

    test('an amenity nobody has data for leaves only unconfirmed places', () {
      final r = rank(const Conditions(amenities: {Amenity.parking}));
      expect(r, hasLength(2));
      expect(r.any((x) => x.verified), isFalse);
    });
  });

  group('현재 이용 중인 추천', () {
    test(
      'a recent one is restored and opens Home on the recommendation',
      () async {
        final c = await containerWith({
          activeRecommendationPrefsKey: saved(DateTime.now()),
        });
        final active = c.read(activeRecommendationProvider);
        expect(active?.heroId, 'A');
        expect(active?.wentTo, 'B');
        // The meal check needs the place even if it is no longer ranked.
        expect(active?.went?.name, '테스트식당B');
        expect(c.read(restoreHeroProvider)?.heroId, 'A');
        expect(c.read(homeRecsRequestedProvider), isTrue);
      },
    );

    test('an old one is dropped and Home starts fresh', () async {
      final c = await containerWith({
        activeRecommendationPrefsKey: saved(
          DateTime.now().subtract(const Duration(hours: 4)),
        ),
      });
      expect(c.read(activeRecommendationProvider), isNull);
      expect(c.read(homeRecsRequestedProvider), isFalse);
      final sp = c.read(sharedPreferencesProvider);
      expect(sp.getString(activeRecommendationPrefsKey), isNull);
    });

    test(
      'a logged meal is not saved again until a new recommendation',
      () async {
        final c = await containerWith(const {});
        final active = c.read(activeRecommendationProvider.notifier);
        active.save('A', 'k');
        active.finish();
        active.save('A', 'k'); // the same card is still on screen
        expect(c.read(activeRecommendationProvider), isNull);
        active.startNew(); // "오늘의 추천 받기"
        active.save('A', 'k');
        expect(c.read(activeRecommendationProvider)?.heroId, 'A');
      },
    );

    test('clear() forgets it on the device', () async {
      final c = await containerWith({
        activeRecommendationPrefsKey: saved(DateTime.now()),
      });
      c.read(activeRecommendationProvider.notifier).clear();
      final sp = c.read(sharedPreferencesProvider);
      expect(sp.getString(activeRecommendationPrefsKey), isNull);
    });
  });

  test('먹었어요 is kept per account and survives a restart', () async {
    final c = await containerWith(const {}, signedIn: true);
    expect(
      await c.read(mealRecordsProvider.notifier).add(fakeRestaurant('A')),
      isTrue,
    );
    expect(c.read(mealRecordsProvider).single.kakaoId, 'A');

    final sp = c.read(sharedPreferencesProvider);
    final again = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        currentUserProvider.overrideWithValue(fakeUser()),
      ],
    );
    addTearDown(again.dispose);
    expect(again.read(mealRecordsProvider).single.name, '테스트식당A');

    final guest = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        currentUserProvider.overrideWithValue(null),
      ],
    );
    addTearDown(guest.dispose);
    expect(guest.read(mealRecordsProvider), isEmpty);
  });
}
