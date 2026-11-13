import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../recommendation/restaurant_insight.dart';
import '../../restaurants/models/food_category.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../university/providers/university_providers.dart';

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
  /// Coming back with a recommendation still in use skips straight to it.
  @override
  bool build() => ref.read(activeRecommendationProvider) != null;

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

  /// "다른 후보 보기": the next confirmed match, back to the first after the
  /// last. False when there is no other one (one match shows again, as it
  /// should).
  bool next(HomeRecs recs) {
    if (recs.ranked.length < 2) return false;
    state = recs.ranked[recs.heroRank % recs.ranked.length].restaurant.kakaoId;
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

/// The places Home and the map judge (they share the category choice),
/// before any condition. With nothing chosen (전체) it is the shared nearby
/// list. With categories chosen it is Kakao's results FOR THOSE CATEGORIES
/// (not the nearest places of any kind filtered down, which usually holds
/// only a few of them).
final homePoolProvider = Provider<AsyncValue<List<Restaurant>>>((ref) {
  final categories = ref.watch(homeCategoryProvider);
  if (categories.isEmpty) return ref.watch(allNearbyRestaurantsProvider);
  final lists = [
    for (final c in categories)
      ref.watch(
        categoryRestaurantsProvider(categoryQuery(c, GlobalCuisine.all)),
      ),
  ];
  if (lists.any((l) => l.isLoading) && lists.every((l) => !l.hasError)) {
    return const AsyncLoading();
  }
  if (lists.every((l) => l.hasError)) {
    return AsyncError(
      lists.first.error!,
      lists.first.stackTrace ?? StackTrace.empty,
    );
  }
  final seen = <String>{};
  return AsyncData([
    for (final l in lists)
      for (final r in l.value ?? const <Restaurant>[])
        if (categories.any((c) => c.matches(r)) && seen.add(r.kakaoId)) r,
  ]);
});

/// The admin data [homePoolProvider]'s places are judged on.
final homePoolInsightsProvider = Provider<Map<String, RestaurantInsight>>((
  ref,
) {
  final base = ref.watch(restaurantInsightsProvider);
  if (ref.watch(homeCategoryProvider).isEmpty) return base;
  final ids = [
    for (final r in ref.watch(homePoolProvider).value ?? const <Restaurant>[])
      r.kakaoId,
  ]..sort();
  return {...base, ...?ref.watch(insightsForIdsProvider(ids.join(','))).value};
});

/// [homePoolProvider] judged by the shared conditions on the same data as
/// every other list, so it always agrees with the filters. Confirmed matches
/// come first, then "정보 미확인" ones.
final homePoolRankedProvider = Provider<AsyncValue<List<RankedRestaurant>>>((
  ref,
) {
  if (ref.watch(homeCategoryProvider).isEmpty) {
    return ref.watch(rankedRestaurantsProvider);
  }
  return rankPool(ref, ref.watch(homePoolProvider));
});

/// The confirmed matches on Home and the map (markers, counts, the 조건
/// sheet's button).
final homeMatchesProvider = Provider<AsyncValue<List<RankedRestaurant>>>(
  (ref) => ref.watch(homePoolRankedProvider).whenData((l) => l.confirmed),
);

/// Null data means "no confirmed match" (the "정보 미확인" ones are listed
/// apart, see [homePoolRankedProvider]).
final homeRecsProvider = Provider<AsyncValue<HomeRecs?>>((ref) {
  final restore = ref.watch(restoreHeroProvider);
  final key = ref.watch(homeRecsKeyProvider);
  // The place shown when the user left, until they pick another one, and only
  // while everything it was chosen under is the same again.
  final pick =
      ref.watch(heroPickProvider) ??
      (restore != null && restore.key == key ? restore.heroId : null);
  return ref.watch(homeMatchesProvider).whenData((ranked) {
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

/// Whether the "가격·운영정보 미확인" list is open. Forgotten whenever the
/// filters or the origin change.
final homeShowUnverifiedProvider =
    NotifierProvider<HomeShowUnverifiedNotifier, bool>(
      HomeShowUnverifiedNotifier.new,
    );

class HomeShowUnverifiedNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(originProvider.select((o) => o?.id));
    ref.watch(conditionsProvider);
    ref.watch(homeCategoryProvider);
    return false;
  }

  void show() => state = true;

  void toggle() => state = !state;
}

/// Everything a Home pick depends on (origin, conditions, categories) as one
/// stable string, so a restored pick is used only under the same filters.
/// Null until the origin is known.
final homeRecsKeyProvider = Provider<String?>((ref) {
  final origin = ref.watch(originProvider.select((o) => o?.id));
  if (origin == null) return null;
  final c = ref.watch(conditionsProvider);
  String names(Iterable<Enum> s) =>
      (s.map((e) => e.name).toList()..sort()).join(',');
  return [
    origin,
    c.budget.name,
    c.distance.name,
    c.openNowOnly,
    names(c.cuisines),
    names(c.amenities),
    c.party?.name,
    names(c.needs),
    c.untriedFirst,
    c.sort.name,
    names(ref.watch(homeCategoryProvider)),
  ].join('|');
});

/// The recommendation the user is in the middle of: the place on the Home
/// card, the filters it was picked under and (once 길찾기 was opened) the
/// place they set off to. Kept on the device so coming back opens it again.
class ActiveRecommendation {
  const ActiveRecommendation({
    required this.heroId,
    required this.key,
    required this.at,
    this.went,
  });

  final String heroId;
  final String key;
  final DateTime at;

  /// Where 길찾기 was opened for. Kept whole (not looked up in the ranking),
  /// so "다녀오셨어요?" is still asked after the place closed or dropped out
  /// of the filters.
  final Restaurant? went;

  String? get wentTo => went?.kakaoId;

  Map<String, Object?> toJson() => {
    'hero': heroId,
    'key': key,
    'at': at.millisecondsSinceEpoch,
    'went': went?.kakaoId,
    'wentName': went?.name,
    'wentCategory': went?.categoryName,
  };

  static ActiveRecommendation? fromJson(Object? j) {
    if (j is! Map) return null;
    final hero = j['hero'];
    final key = j['key'];
    final at = j['at'];
    if (hero is! String || key is! String || at is! int) return null;
    final went = j['went'], name = j['wentName'], category = j['wentCategory'];
    return ActiveRecommendation(
      heroId: hero,
      key: key,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      // Only what the meal check needs (the record and the review).
      went: went is String && name is String
          ? Restaurant(
              kakaoId: went,
              name: name,
              categoryName: category is String ? category : '',
              categoryGroupCode: '',
              address: '',
              roadAddress: '',
              phone: '',
              latitude: 0,
              longitude: 0,
              distanceMeters: 0,
              placeUrl: null,
            )
          : null,
    );
  }
}

const activeRecommendationPrefsKey = 'home_active_recommendation';

// ponytail: a fixed 3 h window stands in for "this meal"; tie it to meal
// times if lunch picks start showing up at dinner.
const activeRecommendationTtl = Duration(hours: 3);

final activeRecommendationProvider =
    NotifierProvider<ActiveRecommendationNotifier, ActiveRecommendation?>(
      ActiveRecommendationNotifier.new,
    );

class ActiveRecommendationNotifier extends Notifier<ActiveRecommendation?> {
  @override
  ActiveRecommendation? build() {
    final sp = ref.read(sharedPreferencesProvider);
    final raw = sp.getString(activeRecommendationPrefsKey);
    ActiveRecommendation? saved;
    try {
      saved = raw == null
          ? null
          : ActiveRecommendation.fromJson(jsonDecode(raw));
    } on FormatException {
      saved = null;
    }
    if (saved == null ||
        DateTime.now().difference(saved.at) > activeRecommendationTtl) {
      if (raw != null) sp.remove(activeRecommendationPrefsKey);
      return null;
    }
    return saved;
  }

  void _write(ActiveRecommendation? next) {
    state = next;
    final sp = ref.read(sharedPreferencesProvider);
    if (next == null) {
      sp.remove(activeRecommendationPrefsKey);
    } else {
      sp.setString(activeRecommendationPrefsKey, jsonEncode(next.toJson()));
    }
  }

  /// The pick a meal was logged for: not saved again while it stays on screen.
  (String, String)? _finished;

  /// The card now shows [heroId] under [key].
  void save(String heroId, String key) {
    if (_finished == (heroId, key)) return;
    final s = state;
    if (s != null && s.heroId == heroId && s.key == key) return;
    _write(
      ActiveRecommendation(
        heroId: heroId,
        key: key,
        at: DateTime.now(),
        went: s?.went,
      ),
    );
  }

  /// 길찾기 was opened for [r]. Only while a recommendation is in use.
  void markWent(Restaurant r) {
    final s = state;
    if (s == null || s.wentTo == r.kakaoId) return;
    _write(
      ActiveRecommendation(
        heroId: s.heroId,
        key: s.key,
        at: DateTime.now(),
        went: r,
      ),
    );
  }

  /// "아직이요": stop asking whether they ate there.
  void forgetWent() {
    final s = state;
    if (s == null || s.wentTo == null) return;
    _write(ActiveRecommendation(heroId: s.heroId, key: s.key, at: s.at));
  }

  /// A new recommendation was asked for: the card is saved again, even when
  /// it shows the place a meal was just logged for.
  void startNew() => _finished = null;

  /// Started over: the next visit starts fresh.
  void clear() {
    startNew();
    _write(null);
  }

  /// Ate there: the recommendation is finished; the next visit starts fresh.
  void finish() {
    final s = state;
    if (s != null) _finished = (s.heroId, s.key);
    _write(null);
  }
}

/// The pick to show again after coming back, until it has been shown (it then
/// lives on in [heroPickProvider]) or the user starts over.
final restoreHeroProvider =
    NotifierProvider<RestoreHeroNotifier, ActiveRecommendation?>(
      RestoreHeroNotifier.new,
    );

class RestoreHeroNotifier extends Notifier<ActiveRecommendation?> {
  @override
  ActiveRecommendation? build() => ref.read(activeRecommendationProvider);

  void consume() => state = null;
}
