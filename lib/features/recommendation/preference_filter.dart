import '../preferences/models/user_preferences.dart';
import '../restaurants/models/restaurant.dart';

/// Rough conversion from "minutes" to straight-line meters. These are
/// ASSUMPTIONS, not routing results: the app has no routing service, so the
/// UI labels distance conditions as approximate.
const walkMetersPerMinute = 80.0;
const driveMetersPerMinute = 500.0;

/// Straight-line radius implied by [option], or null for "상관없어요".
double? maxDistanceMeters(DistanceOption option) {
  final minutes = option.minutes;
  if (minutes == null) return null;
  return switch (option.mode) {
    TravelMode.walk => minutes * walkMetersPerMinute,
    TravelMode.drive => minutes * driveMetersPerMinute,
    TravelMode.any => null,
  };
}

bool cuisineMatches(Restaurant r, Cuisine cuisine) {
  bool has(String token) => r.categoryName.contains(token);
  return switch (cuisine) {
    Cuisine.korean => has('한식'),
    Cuisine.japanese => has('일식'),
    Cuisine.chinese => has('중식'),
    Cuisine.snack => has('분식'),
    Cuisine.western => has('양식'),
    Cuisine.salad => has('샐러드'),
    Cuisine.cafe => r.categoryGroupCode == 'CE7' || has('카페') || has('디저트'),
    Cuisine.any => true,
  };
}

/// Applies only the conditions that real restaurant data can support:
///
///  * travel distance (straight-line approximation from the campus point)
///  * cuisine (Kakao's own `category_name`)
///
/// Budget, companions, tags and "try new first" are NOT applied: Kakao Local
/// provides no prices, capacity or visit history, and nothing is invented.
/// Restaurants are never excluded because of missing metadata.
List<Restaurant> applyPreferences(List<Restaurant> all, UserPreferences prefs) {
  final maxMeters = prefs.distance == null
      ? null
      : maxDistanceMeters(prefs.distance!);
  final cuisines = prefs.cuisines;
  final filterCuisine = cuisines.isNotEmpty && !cuisines.contains(Cuisine.any);

  return all.where((r) {
    // Cafes only appear when the user asked for them, matching the baseline
    // (restaurants first).
    final isFood =
        r.categoryGroupCode == 'FD6' ||
        (cuisines.contains(Cuisine.cafe) && r.categoryGroupCode == 'CE7');
    if (!isFood) return false;
    if (maxMeters != null && r.distanceMeters > maxMeters) return false;
    if (filterCuisine && !cuisines.any((c) => cuisineMatches(r, c))) {
      return false;
    }
    return true;
  }).toList()..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
}
