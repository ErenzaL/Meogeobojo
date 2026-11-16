import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/models/user_preferences.dart';
import '../preferences/providers/preferences_providers.dart';
import '../restaurants/models/restaurant.dart';
import '../restaurants/providers/restaurant_providers.dart';
import '../university/models/university.dart';
import '../university/providers/university_providers.dart';
import '../../core/utils/seoul_clock.dart';
import '../conditions/models/conditions.dart';
import 'home_ranking.dart';
import 'providers/ranking_providers.dart';

/// What ranking was used. The UI turns this into (localized) text, so the
/// basis of the order is never misrepresented in any language.
enum RecommendationStrategy { proximityBaseline, proximityWithPreferences }

class RecommendationResult {
  const RecommendationResult({
    required this.strategy,
    required this.university,
    required this.restaurants,
    this.candidateCount = 0,
  });

  final RecommendationStrategy strategy;
  final University university;
  final List<Restaurant> restaurants;

  /// How many places were considered before preference filters.
  final int candidateCount;
}

/// Seam for the teammates' ML model: implement this and override
/// [recommendationServiceProvider]; the UI needs no changes.
abstract interface class RecommendationService {
  Future<RecommendationResult> recommend({
    required University university,
    UserPreferences? preferences,
  });
}

/// The V3 recommendation (see `recommendation_score.dart`), the same ranking Home, the map and search use:
/// distance and budget decide who qualifies, then food taste and distance (and reviews, when there are any) order them.
/// Without saved conditions that is simply "nearest first".
class V3RecommendationService implements RecommendationService {
  V3RecommendationService(this._ref);

  final Ref _ref;

  @override
  Future<RecommendationResult> recommend({
    required University university,
    UserPreferences? preferences,
  }) async {
    final all = await _ref.read(allNearbyRestaurantsProvider.future);
    // Prices decide the budget: wait for the menus (a failure just leaves prices unchecked), then judge on them.
    try {
      await _ref.read(nearbyMenusProvider.future);
    } catch (_) {}
    final reviews = await _ref.read(reviewSignalsProvider.future);
    final conditions = preferences == null
        ? const Conditions()
        : Conditions.fromPreferences(preferences);
    final ranked = rankRestaurants(
      all: all,
      lat: university.latitude,
      lng: university.longitude,
      conditions: conditions,
      insights: _ref.read(restaurantInsightsProvider),
      hiddenIds: _ref.read(hiddenPlaceIdsProvider),
      reviewSignals: reviews,
      nowMinutes: minutesOfDay(seoulWall(DateTime.now())),
    );
    final food = all.where((r) => r.categoryGroupCode == 'FD6').length;
    return RecommendationResult(
      strategy: preferences == null
          ? RecommendationStrategy.proximityBaseline
          : RecommendationStrategy.proximityWithPreferences,
      university: university,
      // only places whose chosen conditions are confirmed (see showUnverifiedCandidatesProvider)
      restaurants: [
        for (final r
            in _ref.read(showUnverifiedCandidatesProvider)
                ? ranked
                : ranked.confirmed)
          r.restaurant,
      ],
      candidateCount: food,
    );
  }
}

final recommendationServiceProvider = Provider<RecommendationService>(
  V3RecommendationService.new,
);

/// Argument: whether to apply the signed-in user's saved preferences.
final recommendationProvider =
    FutureProvider.family<RecommendationResult, bool>((
      ref,
      usePreferences,
    ) async {
      final university = await ref.watch(selectedUniversityProvider.future);
      final prefs = usePreferences
          ? await ref.watch(userPreferencesProvider.future)
          : null;
      return ref
          .watch(recommendationServiceProvider)
          .recommend(university: university, preferences: prefs);
    });
