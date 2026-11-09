import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';

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
    return null;
  }

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

/// Null data means "nothing matches the conditions".
final homeRecsProvider = Provider<AsyncValue<HomeRecs?>>((ref) {
  final pick = ref.watch(heroPickProvider);
  return ref.watch(rankedRestaurantsProvider).whenData((ranked) {
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
