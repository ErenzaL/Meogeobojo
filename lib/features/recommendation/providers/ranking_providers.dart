import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/seoul_clock.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../records/meal_records.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/models/restaurant_override.dart';
import '../../restaurants/providers/restaurant_providers.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../demo/demo_features.dart';
import '../demo/demo_providers.dart';
import '../home_ranking.dart';
import '../restaurant_insight.dart';
import '../review_signal_repository.dart';

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
    // read the switch itself, not only the loaded rows: turning demo off must take effect at once
    demo: ref.watch(demoModeProvider)
        ? ref.watch(demoFeaturesProvider).value ?? const {}
        : const {},
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
///
/// [demo] (simulated hours and amenities, only while demo mode is on) fills what the database does not have, never
/// what an administrator entered, and marks the insight as demo.
Map<String, RestaurantInsight> insightsFrom(
  Map<String, RestaurantOverride> overrides,
  Map<String, List<RestaurantMenuItem>> menus, {
  Map<String, DemoFeature> demo = const {},
}) => {
  for (final id in {...overrides.keys, ...menus.keys, ...demo.keys})
    id: applyDemo(
      (overrides[id]?.insight ?? RestaurantInsight.unknown).withMenus([
        for (final m in menus[id] ?? const <RestaurantMenuItem>[]) m.line,
      ]),
      demo[id],
    ),
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
      final demo = ref.watch(demoModeProvider)
          ? await ref.watch(demoFeaturesProvider.future)
          : const <String, DemoFeature>{};
      return insightsFrom(
        both[0] as Map<String, RestaurantOverride>,
        both[1] as Map<String, List<RestaurantMenuItem>>,
        demo: demo,
      );
    });

final reviewSignalSourceProvider = Provider<ReviewSignalSource>(
  (ref) => SupabaseReviewSignalSource(() => Supabase.instance.client),
);

/// R (the review signal of the V3 score) per place: from the visible student reviews, or else from the stored review
/// insight (collected reviews). Empty when there are none.
final reviewSignalsProvider = FutureProvider<Map<String, double>>((ref) async {
  final reviews = await ref.watch(reviewSignalSourceProvider).visibleReviews();
  final insights = await ref.watch(reviewInsightsProvider.future);
  return mergeReviewSignals(
    reviewSignalsFrom(reviews, DateTime.now()),
    insights,
  );
});

final reviewInsightSourceProvider = Provider<ReviewInsightSource>(
  (ref) => SupabaseReviewInsightSource(() => Supabase.instance.client),
);

/// Stored review insights (R + AI review summary) per place, from the collected reviews. Empty when there are none.
final reviewInsightsProvider = FutureProvider<Map<String, ReviewInsight>>(
  (ref) => ref.watch(reviewInsightSourceProvider).visibleInsights(),
);

/// Whether places that CANNOT be confirmed against the chosen conditions ("정보 미확인": no price, hours or amenity data)
/// are listed. Off: only places whose every chosen condition is confirmed are shown anywhere (Home, map, search,
/// the recommendation screen). With no conditions chosen every place is confirmed, so nothing disappears.
final showUnverifiedCandidatesProvider = Provider<bool>((ref) => false);

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
  final reviews =
      ref.watch(reviewSignalsProvider).value ?? const <String, double>{};
  final showUnverified = ref.watch(showUnverifiedCandidatesProvider);
  if (origin == null) {
    // No origin yet: either the campus is still loading, or it failed.
    return places.hasError
        ? AsyncError(places.error!, places.stackTrace ?? StackTrace.empty)
        : const AsyncLoading();
  }
  return places.whenData((all) {
    // a 운영·편의 condition nobody has data for is not applied (see usableConditions)
    final ranked = rankRestaurants(
      all: all,
      lat: origin.latitude,
      lng: origin.longitude,
      conditions: usableConditions(conditions, all, insights).conditions,
      insights: insights,
      hiddenIds: hidden,
      visitedIds: visited,
      reviewSignals: reviews,
      nowMinutes: minutesOfDay(now),
    );
    return showUnverified ? ranked : ranked.confirmed;
  });
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
