import 'package:flutter/foundation.dart';

import '../../preferences/models/user_preferences.dart';

/// 운영·편의 chips. Applied only to places whose data says so; a place with
/// unknown data is never dropped (same rule as the rest of the app).
enum Amenity {
  noBreakTime,
  parking,
  localCurrency,
  fastTurnover,
  takeout,
  openLate,
}

/// 필요한 것 (soft, ranking only).
enum Need { quietTalk, quickMeal, generousPortion }

enum SortMode { recommended, distance, price, rating }

/// The party sizes offered by the sheet, a subset of [CompanionType].
const kPartyOptions = [
  CompanionType.solo,
  CompanionType.friends,
  CompanionType.group,
];

/// The conditions shared by Home, the map and search.
///
/// "Hard" conditions remove places; "soft" ones only influence the order.
/// Data the app does not have (price, hours, amenities) cannot exclude a
/// place, so those conditions simply keep unknown places.
@immutable
class Conditions {
  const Conditions({
    this.budget = BudgetOption.any,
    this.distance = DistanceOption.any,
    this.openNowOnly = true,
    this.cuisines = const {},
    this.amenities = const {},
    this.party,
    this.needs = const {},
    this.untriedFirst = false,
    this.sort = SortMode.recommended,
  });

  /// Starting point for a signed-in user: their saved onboarding answers.
  factory Conditions.fromPreferences(UserPreferences? p) {
    if (p == null) return const Conditions();
    CompanionType? party;
    for (final c in kPartyOptions) {
      if (p.companions.contains(c)) {
        party = c;
        break;
      }
    }
    return Conditions(
      budget: p.budget ?? BudgetOption.any,
      distance: p.distance ?? DistanceOption.any,
      cuisines: {...p.cuisines}..remove(Cuisine.any),
      party: party,
      needs: {if (p.tags.contains(FoodTag.hearty)) Need.generousPortion},
      untriedFirst: p.prioritizeUntried,
    );
  }

  final BudgetOption budget;
  final DistanceOption distance;
  final bool openNowOnly;

  /// Empty = 전체.
  final Set<Cuisine> cuisines;
  final Set<Amenity> amenities;

  final CompanionType? party;
  final Set<Need> needs;
  final bool untriedFirst;
  final SortMode sort;

  static const defaults = Conditions();

  /// How many condition groups differ from the defaults (Home badge).
  int get activeCount => [
    budget != BudgetOption.any,
    distance != DistanceOption.any,
    openNowOnly != defaults.openNowOnly,
    cuisines.isNotEmpty,
    amenities.isNotEmpty,
    party != null,
    needs.isNotEmpty,
    untriedFirst,
    sort != SortMode.recommended,
  ].where((x) => x).length;

  Conditions copyWith({
    BudgetOption? budget,
    DistanceOption? distance,
    bool? openNowOnly,
    Set<Cuisine>? cuisines,
    Set<Amenity>? amenities,
    CompanionType? Function()? party,
    Set<Need>? needs,
    bool? untriedFirst,
    SortMode? sort,
  }) => Conditions(
    budget: budget ?? this.budget,
    distance: distance ?? this.distance,
    openNowOnly: openNowOnly ?? this.openNowOnly,
    cuisines: cuisines ?? this.cuisines,
    amenities: amenities ?? this.amenities,
    party: party != null ? party() : this.party,
    needs: needs ?? this.needs,
    untriedFirst: untriedFirst ?? this.untriedFirst,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is Conditions &&
      other.budget == budget &&
      other.distance == distance &&
      other.openNowOnly == openNowOnly &&
      setEquals(other.cuisines, cuisines) &&
      setEquals(other.amenities, amenities) &&
      other.party == party &&
      setEquals(other.needs, needs) &&
      other.untriedFirst == untriedFirst &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    budget,
    distance,
    openNowOnly,
    Object.hashAllUnordered(cuisines),
    Object.hashAllUnordered(amenities),
    party,
    Object.hashAllUnordered(needs),
    untriedFirst,
    sort,
  );
}
