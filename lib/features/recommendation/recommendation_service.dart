import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/models/user_preferences.dart';
import '../preferences/providers/preferences_providers.dart';
import '../restaurants/models/restaurant.dart';
import '../restaurants/providers/restaurant_providers.dart';
import '../university/models/university.dart';
import '../university/providers/university_providers.dart';
import 'preference_filter.dart';

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

/// Baseline: no popularity / preference-learning signal exists yet, so rank
/// purely by straight-line distance from the university. Saved distance and
/// cuisine conditions are applied when given (see [applyPreferences]).
class ProximityBaselineService implements RecommendationService {
  ProximityBaselineService(this._load);

  final Future<List<Restaurant>> Function() _load;

  @override
  Future<RecommendationResult> recommend({
    required University university,
    UserPreferences? preferences,
  }) async {
    final all = await _load();
    final food = all.where((r) => r.categoryGroupCode == 'FD6').toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    if (preferences == null) {
      return RecommendationResult(
        strategy: RecommendationStrategy.proximityBaseline,
        university: university,
        restaurants: food,
        candidateCount: food.length,
      );
    }
    return RecommendationResult(
      strategy: RecommendationStrategy.proximityWithPreferences,
      university: university,
      restaurants: applyPreferences(all, preferences),
      candidateCount: food.length,
    );
  }
}

final recommendationServiceProvider = Provider<RecommendationService>(
  (ref) => ProximityBaselineService(
    () => ref.read(allNearbyRestaurantsProvider.future),
  ),
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
