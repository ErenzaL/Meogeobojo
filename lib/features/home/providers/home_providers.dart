import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/models/food_category.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/providers/restaurant_providers.dart';

/// What the Home cards show: the hero, and the alternatives under it.
class HomeRecs {
  const HomeRecs({
    required this.ranked,
    required this.hero,
    required this.heroRank,
    required this.alternatives,
  });

  /// Everything that passed the conditions, best first.
  final List<RankedRestaurant> ranked;
  final RankedRestaurant hero;

  /// 1-based position of [hero] in [ranked].
  final int heroRank;

  /// The two best places other than [hero].
  final List<RankedRestaurant> alternatives;

  int get total => ranked.length;
}

/// The categories chosen in the Home category bar (none = 전체). They narrow
/// what Home recommends; the shared conditions are untouched.
final homeCategoryProvider =
    NotifierProvider<HomeCategoryNotifier, Set<FoodCategory>>(
      HomeCategoryNotifier.new,
    );

/// Several categories can be on at once (중복 선택); an empty set is 전체.
class HomeCategoryNotifier extends Notifier<Set<FoodCategory>> {
  @override
  Set<FoodCategory> build() => const {};

  /// Adds [c] or removes it if already chosen. 전체 clears the selection, and
  /// un-choosing the last category falls back to 전체.
  void toggle(FoodCategory c) {
    if (c == FoodCategory.all) {
      state = const {};
      return;
    }
    final next = {...state};
    if (!next.remove(c)) next.add(c);
    state = next;
  }

  void clear() => state = const {};
}

/// True once the user asked for a recommendation ("오늘의 추천 받기").
/// Until then (and with no conditions or category chosen) Home does not
/// preview a pick.
final homeRecsRequestedProvider =
    NotifierProvider<HomeRecsRequestedNotifier, bool>(
      HomeRecsRequestedNotifier.new,
    );

class HomeRecsRequestedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void reset() => state = false;
}

/// Whether Home shows recommendations: asked for, or the user has set any
/// condition (saved preferences count) or picked a category.
final homeShowRecsProvider = Provider<bool>(
  (ref) =>
      ref.watch(homeRecsRequestedProvider) ||
      ref.watch(conditionsProvider).activeCount > 0 ||
      ref.watch(homeCategoryProvider).isNotEmpty,
);

/// A place picked by "하나 골라줘", shown instead of #1. Forgotten whenever the
/// origin or the conditions change, so a fresh ranking starts from #1.
final heroPickProvider = NotifierProvider<HeroPickNotifier, String?>(
  HeroPickNotifier.new,
);

class HeroPickNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(originProvider.select((o) => o?.id));
    ref.watch(conditionsProvider);
    ref.watch(homeCategoryProvider);
    return null;
  }

  /// Back to the top-ranked place for the current filters.
  void reset() => state = null;

  /// Moves the shown pick [delta] places down (+1, "다음 추천") or up (-1)
  /// the current ranking. Stops at the ends.
  bool step(HomeRecs recs, int delta) {
    final i = recs.heroRank - 1 + delta;
    if (i < 0 || i >= recs.ranked.length) return false;
    state = recs.ranked[i].restaurant.kakaoId;
    return true;
  }

  /// Shows the place with [kakaoId] as the top pick (a game's winner).
  void choose(String kakaoId) => state = kakaoId;

  /// Picks a random place other than the one currently shown. Returns false
  /// when there is nothing else to pick.
  bool pickRandom(HomeRecs recs, {Random? random}) {
    final others = [
      for (final r in recs.ranked)
        if (r.restaurant.kakaoId != recs.hero.restaurant.kakaoId) r,
    ];
    if (others.isEmpty) return false;
    final pick = others[(random ?? Random()).nextInt(others.length)];
    state = pick.restaurant.kakaoId;
    return true;
  }
}

/// What Home ranks. With nothing chosen (전체) it is the shared list. With
/// categories chosen it is built from Kakao's results FOR THOSE CATEGORIES
/// (not by filtering the 15 nearest places of any kind, which usually holds
/// only a few places of the chosen category), then ranked by the same
/// conditions, so the result always agrees with the filters.
final homePoolRankedProvider = Provider<AsyncValue<List<RankedRestaurant>>>((
  ref,
) {
  final categories = ref.watch(homeCategoryProvider);
  if (categories.isEmpty) return ref.watch(rankedRestaurantsProvider);
  final lists = [
    for (final c in categories)
      ref.watch(
        categoryRestaurantsProvider(categoryQuery(c, GlobalCuisine.all)),
      ),
  ];
  final AsyncValue<List<Restaurant>> pool;
  if (lists.any((l) => l.isLoading) && lists.every((l) => !l.hasError)) {
    pool = const AsyncLoading();
  } else if (lists.every((l) => l.hasError)) {
    pool = AsyncError(
      lists.first.error!,
      lists.first.stackTrace ?? StackTrace.empty,
    );
  } else {
    final seen = <String>{};
    pool = AsyncData([
      for (final l in lists)
        for (final r in l.value ?? const <Restaurant>[])
          if (categories.any((c) => c.matches(r)) && seen.add(r.kakaoId)) r,
    ]);
  }
  // Prices / hours an admin entered for THESE places (the generic overrides
  // were fetched for the nearby pool only).
  final ids = [for (final r in pool.value ?? const <Restaurant>[]) r.kakaoId]
    ..sort();
  final extra = ref.watch(overridesForIdsProvider(ids.join(',')));
  if (pool.hasValue && extra.isLoading) return const AsyncLoading();
  return rankWithSharedConditions(
    ref,
    pool,
    extraInsights: {
      for (final o in (extra.value ?? const {}).values) o.kakaoId: o.insight,
    },
  );
});

/// Null data means "nothing matches the conditions".
final homeRecsProvider = Provider<AsyncValue<HomeRecs?>>((ref) {
  final pick = ref.watch(heroPickProvider);
  return ref.watch(homePoolRankedProvider).whenData((ranked) {
    if (ranked.isEmpty) return null;
    var index = ranked.indexWhere((r) => r.restaurant.kakaoId == pick);
    if (index < 0) index = 0;
    final hero = ranked[index];
    return HomeRecs(
      ranked: ranked,
      hero: hero,
      heroRank: index + 1,
      alternatives: [
        for (final r in ranked)
          if (r != hero) r,
      ].take(2).toList(),
    );
  });
});
