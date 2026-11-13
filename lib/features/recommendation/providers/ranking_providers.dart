import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/seoul_clock.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../records/meal_records.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/models/restaurant_override.dart';
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

/// Price / hours / menus / photo per `kakaoId`, from what admins entered
/// (`restaurant_overrides`, `restaurant_menus`) for the places around the
/// campus. Places without an entry stay "unknown".
final restaurantInsightsProvider = Provider<Map<String, RestaurantInsight>>(
  (ref) => insightsFrom(
    ref.watch(restaurantOverridesProvider).value ?? const {},
    ref.watch(nearbyMenusProvider).value ?? const {},
  ),
);

/// Menus of the places around the campus (the budget is judged on them).
final nearbyMenusProvider =
    FutureProvider<Map<String, List<RestaurantMenuItem>>>((ref) async {
      final places = await ref.watch(allNearbyRestaurantsProvider.future);
      return ref.watch(restaurantOverrideRepositoryProvider).menusForPlaces([
        for (final r in places) r.kakaoId,
      ]);
    });

/// Overrides and menus combined into one insight per place.
Map<String, RestaurantInsight> insightsFrom(
  Map<String, RestaurantOverride> overrides,
  Map<String, List<RestaurantMenuItem>> menus,
) => {
  for (final id in {...overrides.keys, ...menus.keys})
    id: (overrides[id]?.insight ?? RestaurantInsight.unknown).withMenus([
      for (final m in menus[id] ?? const <RestaurantMenuItem>[]) m.line,
    ]),
};

/// The same, for an arbitrary list of places (a chosen category, search
/// results), keyed by their Kakao ids joined with ",": every list is judged
/// on exactly the data the others use.
final insightsForIdsProvider = FutureProvider.autoDispose
    .family<Map<String, RestaurantInsight>, String>((ref, idsKey) async {
      if (idsKey.isEmpty) return const {};
      final ids = idsKey.split(',');
      final repo = ref.watch(restaurantOverrideRepositoryProvider);
      final both = await Future.wait([
        repo.forPlaces(ids),
        repo.menusForPlaces(ids),
      ]);
      return insightsFrom(
        both[0] as Map<String, RestaurantOverride>,
        both[1] as Map<String, List<RestaurantMenuItem>>,
      );
    });

/// Places with a meal record ("안 가 본 곳 먼저").
final visitedPlaceIdsProvider = Provider<Set<String>>(
  (ref) => {for (final m in ref.watch(mealRecordsProvider)) m.kakaoId},
);

/// Places an admin hid or archived: never shown in lists.
final hiddenPlaceIdsProvider = Provider<Set<String>>(
  (ref) => {
    for (final o
        in (ref.watch(restaurantOverridesProvider).value ?? const {}).values)
      if (o.isHidden) o.kakaoId,
  },
);

/// Ranks [places] with the shared conditions, measured from the chosen origin.
/// One implementation for every list (Home, map, search, category-filtered Home).
AsyncValue<List<RankedRestaurant>> rankWithSharedConditions(
  Ref ref,
  AsyncValue<List<Restaurant>> places, {
  Map<String, RestaurantInsight> extraInsights = const {},
}) {
  final origin = ref.watch(originProvider);
  final conditions = ref.watch(conditionsProvider);
  final insights = {...ref.watch(restaurantInsightsProvider), ...extraInsights};
  final now = ref.watch(seoulNowProvider);
  final hidden = ref.watch(hiddenPlaceIdsProvider);
  final visited = ref.watch(visitedPlaceIdsProvider);
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
      visitedIds: visited,
      nowMinutes: minutesOfDay(now),
    ),
  );
}

/// [rankWithSharedConditions] for a list that is not the nearby pool: its
/// admin data is fetched first, so the verdicts match every other screen.
AsyncValue<List<RankedRestaurant>> rankPool(
  Ref ref,
  AsyncValue<List<Restaurant>> pool,
) {
  final ids = [for (final r in pool.value ?? const <Restaurant>[]) r.kakaoId]
    ..sort();
  final extra = ref.watch(insightsForIdsProvider(ids.join(',')));
  if (pool.hasValue && !extra.hasValue && !extra.hasError) {
    return const AsyncLoading();
  }
  return rankWithSharedConditions(
    ref,
    pool,
    extraInsights: extra.value ?? const {},
  );
}

/// Places around the campus that pass the shared conditions, measured from
/// the chosen origin and ordered (confirmed matches first).
final rankedRestaurantsProvider = Provider<AsyncValue<List<RankedRestaurant>>>((
  ref,
) {
  final places = ref.watch(allNearbyRestaurantsProvider);
  // Budgets are judged on the menus: ranking before they arrive would list
  // every place as "가격 미확인" and then reorder. Wait for the first read, as
  // [rankPool] does; a refresh keeps the previous menus meanwhile. If they
  // fail, prices really are unchecked and the places say so.
  final menus = ref.watch(nearbyMenusProvider);
  if (places.hasValue && !menus.hasValue && !menus.hasError) {
    return const AsyncLoading();
  }
  return rankWithSharedConditions(ref, places);
});
