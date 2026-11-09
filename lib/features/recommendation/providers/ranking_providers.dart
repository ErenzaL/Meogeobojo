import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/seoul_clock.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../home_ranking.dart';
import '../restaurant_insight.dart';

/// Emits "now" immediately and again at every minute boundary, so times on
/// screen (arrival, time left to order) stay correct. Overridable in tests.
final minuteTickProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  Timer? timer;
  void tick() {
    final now = DateTime.now();
    controller.add(now);
    final intoMinute = now.second * 1000 + now.millisecond;
    timer = Timer(Duration(milliseconds: 60000 - intoMinute + 50), tick);
  }

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  tick();
  return controller.stream;
});

/// Current Seoul wall-clock time (see [seoulWall]), updated every minute.
final seoulNowProvider = Provider.autoDispose<DateTime>(
  (ref) => seoulWall(ref.watch(minuteTickProvider).value ?? DateTime.now()),
);

/// Price / hours / photo per `kakaoId`, from what admins entered
/// (`restaurant_overrides`). Places without an entry stay "unknown".
final restaurantInsightsProvider = Provider<Map<String, RestaurantInsight>>(
  (ref) => {
    for (final o
        in (ref.watch(restaurantOverridesProvider).value ?? const {}).values)
      o.kakaoId: o.insight,
  },
);

/// Places an admin hid or archived: never shown in lists.
final hiddenPlaceIdsProvider = Provider<Set<String>>(
  (ref) => {
    for (final o
        in (ref.watch(restaurantOverridesProvider).value ?? const {}).values)
      if (o.isHidden) o.kakaoId,
  },
);

/// Places that pass the shared conditions, measured from the chosen origin
/// and ordered. Home, the map and search all read this one list.
final rankedRestaurantsProvider = Provider<AsyncValue<List<RankedRestaurant>>>((
  ref,
) {
  final places = ref.watch(allNearbyRestaurantsProvider);
  final origin = ref.watch(originProvider);
  final conditions = ref.watch(conditionsProvider);
  final insights = ref.watch(restaurantInsightsProvider);
  final now = ref.watch(seoulNowProvider);
  final hidden = ref.watch(hiddenPlaceIdsProvider);
  if (origin == null) {
    // No origin yet: either the campus is still loading, or it failed.
    return places.hasError
        ? AsyncError(places.error!, places.stackTrace ?? StackTrace.empty)
        : const AsyncLoading();
  }
  return places.whenData(
    (all) => rankRestaurants(
      all: all,
      lat: origin.latitude,
      lng: origin.longitude,
      conditions: conditions,
      insights: insights,
      hiddenIds: hidden,
      nowMinutes: minutesOfDay(now),
    ),
  );
});

/// Same list without the ranking details (map markers, search filtering).
final filteredRestaurantsProvider = Provider<AsyncValue<List<Restaurant>>>(
  (ref) => ref
      .watch(rankedRestaurantsProvider)
      .whenData((l) => [for (final r in l) r.restaurant]),
);
