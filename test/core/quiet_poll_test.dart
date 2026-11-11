import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/sync/content_sync.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/content/providers/app_content_providers.dart';
import 'package:meogeobojo/features/home/providers/home_meal_providers.dart';
import 'package:meogeobojo/features/restaurants/providers/restaurant_providers.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The once-a-minute safety-net poll must be invisible: it may swap in newer
/// data, but it must never put a screen back into its loading state (that is
/// the whole Home "blinking" every minute) and must not call the restaurant
/// search again (that one is an external, rate-limited API).
void main() {
  late FakeRestaurantRepository restaurants;
  late FakeCampusMealRepository meals;
  late ProviderContainer c;
  late List<String> loading;

  /// Everything a screen on Home / Map / the meal page watches.
  Future<void> open() async {
    restaurants = FakeRestaurantRepository(
      items: [fakeRestaurant('a'), fakeRestaurant('b')],
    );
    meals = FakeCampusMealRepository(
      cafeteriasByUniversity: {
        '5c0a8f3e-0001-4a6e-9b1d-000000000001': [fakeCafeteria('c1')],
      },
    );
    final h = await buildHarness(restaurants: restaurants, meals: meals);
    c = h.container;
    loading = [];
    void watch(String name, ProviderListenable<AsyncValue<Object?>> p) {
      c.listen<AsyncValue<Object?>>(p, (prev, next) {
        // What `AsyncValue.when` would show as a spinner / skeleton: loading
        // that is not a plain refresh of data already on screen.
        if (next.isLoading && !next.isRefreshing) loading.add(name);
      });
    }

    watch('selectedUniversity', selectedUniversityProvider);
    watch('universityList', universityListProvider);
    watch('allNearbyRestaurants', allNearbyRestaurantsProvider);
    watch('restaurantOverrides', restaurantOverridesProvider);
    watch('campusCafeterias', campusCafeteriasProvider);
    watch('homeMealSource', homeMealSourceProvider);
    watch('appContent', appContentProvider);

    await c.read(selectedUniversityProvider.future);
    await c.read(allNearbyRestaurantsProvider.future);
    await c.read(restaurantOverridesProvider.future);
    await c.read(campusCafeteriasProvider.future);
    await c.read(homeMealSourceProvider.future);
    await c.read(appContentProvider.future);
    loading.clear();
    restaurants.nearbyCalls.clear();
    meals.cafeteriaCalls.clear();
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('the periodic refresh never shows a loading state', () async {
    await open();
    refreshLiveContent(c);
    await settle();
    expect(loading, isEmpty, reason: 'these went back to loading: $loading');
  });

  test('the periodic refresh does not search restaurants again', () async {
    await open();
    refreshLiveContent(c);
    await settle();
    expect(restaurants.nearbyCalls, isEmpty);
  });

  test('the periodic refresh still reads newer data', () async {
    await open();
    meals.cafeteriasByUniversity = {
      '5c0a8f3e-0001-4a6e-9b1d-000000000001': [
        fakeCafeteria('c1'),
        fakeCafeteria('c2'),
      ],
    };
    refreshLiveContent(c);
    await settle();
    final now = await c.read(campusCafeteriasProvider.future);
    expect(now.map((e) => e.id), ['c1', 'c2']);
    expect(meals.cafeteriaCalls, isNotEmpty);
  });

  test('an edited cafeteria (same id, new note) is still picked up', () async {
    await open();
    meals.cafeteriasByUniversity = {
      '5c0a8f3e-0001-4a6e-9b1d-000000000001': [
        fakeCafeteria('c1', operatingNote: '방학 중 휴무'),
      ],
    };
    refreshLiveContent(c);
    await settle();
    final now = await c.read(campusCafeteriasProvider.future);
    expect(now.single.operatingNote, '방학 중 휴무');
  });

  test('unchanged cafeterias are fetched but not reloaded', () async {
    await open();
    refreshLiveContent(c);
    await settle();
    expect(meals.cafeteriaCalls, isNotEmpty, reason: 'it did look');
    expect(loading, isEmpty);
  });

  test(
    'a real admin change still reloads loudly (unchanged behaviour)',
    () async {
      await open();
      invalidateForTable(c, 'universities');
      await settle();
      expect(loading, contains('selectedUniversity'));
    },
  );
}
