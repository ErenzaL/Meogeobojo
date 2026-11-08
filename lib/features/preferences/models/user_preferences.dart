import 'package:flutter/foundation.dart';

/// How a budget amount is to be read. "12,000원 이상" is a MINIMUM, which is
/// why the semantics are stored explicitly instead of as a bare number.
enum BudgetType { max, min, any }

enum BudgetOption {
  max8000(BudgetType.max, 8000),
  max10000(BudgetType.max, 10000),
  max12000(BudgetType.max, 12000),
  min12000(BudgetType.min, 12000),
  any(BudgetType.any, null);

  const BudgetOption(this.type, this.amountKrw);

  final BudgetType type;
  final int? amountKrw;

  static BudgetOption? from(String? type, int? amount) {
    for (final o in values) {
      if (o.type.name == type && o.amountKrw == amount) return o;
    }
    return null;
  }
}

enum TravelMode { walk, drive, any }

enum DistanceOption {
  walk5(TravelMode.walk, 5),
  walk10(TravelMode.walk, 10),
  walk15(TravelMode.walk, 15),
  drive10(TravelMode.drive, 10),
  drive15(TravelMode.drive, 15),
  any(TravelMode.any, null);

  const DistanceOption(this.mode, this.minutes);

  final TravelMode mode;
  final int? minutes;

  static DistanceOption? from(String? mode, int? minutes) {
    for (final o in values) {
      if (o.mode.name == mode && o.minutes == minutes) return o;
    }
    return null;
  }
}

/// Stable values for `user_preferences.companion_type`.
enum CompanionType {
  solo('solo'),
  friends('friends_2_3'),
  group('group_4_plus'),
  senior('senior'),
  junior('junior'),
  professor('professor');

  const CompanionType(this.dbValue);
  final String dbValue;

  static CompanionType? fromDb(String? v) {
    for (final c in values) {
      if (c.dbValue == v) return c;
    }
    return null;
  }
}

enum Cuisine {
  korean,
  japanese,
  chinese,
  snack,
  cafe,
  western,
  salad,

  /// "상관없음": mutually exclusive with every other cuisine.
  any;

  static Cuisine? fromDb(String v) {
    for (final c in values) {
      if (c.name == v) return c;
    }
    return null;
  }
}

enum FoodTag {
  spicy,
  hearty,
  value,
  light;

  static FoodTag? fromDb(String v) {
    for (final t in values) {
      if (t.name == v) return t;
    }
    return null;
  }
}

/// Tapping [tapped] in the cuisine chips. "상관없음" clears the rest, and
/// choosing any specific cuisine clears "상관없음".
Set<Cuisine> toggleCuisine(Set<Cuisine> current, Cuisine tapped) {
  if (tapped == Cuisine.any) {
    return current.contains(Cuisine.any) ? <Cuisine>{} : {Cuisine.any};
  }
  final next = {...current}..remove(Cuisine.any);
  if (!next.add(tapped)) next.remove(tapped);
  return next;
}

@immutable
class UserPreferences {
  const UserPreferences({
    this.budget,
    this.distance,
    this.companions = const {},
    this.cuisines = const {},
    this.tags = const {},
    this.prioritizeUntried = false,
    this.universityId,
  });

  /// Required to save (hard conditions).
  final BudgetOption? budget;
  final DistanceOption? distance;

  /// Optional / ranking hints. Several can apply at once ("혼자" and
  /// "교수님과" describe different situations, not one meal); empty = none.
  final Set<CompanionType> companions;
  final Set<Cuisine> cuisines;
  final Set<FoodTag> tags;
  final bool prioritizeUntried;
  final String? universityId;

  bool get isComplete => budget != null && distance != null;

  UserPreferences copyWith({
    BudgetOption? Function()? budget,
    DistanceOption? Function()? distance,
    Set<CompanionType>? companions,
    Set<Cuisine>? cuisines,
    Set<FoodTag>? tags,
    bool? prioritizeUntried,
    String? Function()? universityId,
  }) => UserPreferences(
    budget: budget != null ? budget() : this.budget,
    distance: distance != null ? distance() : this.distance,
    companions: companions ?? this.companions,
    cuisines: cuisines ?? this.cuisines,
    tags: tags ?? this.tags,
    prioritizeUntried: prioritizeUntried ?? this.prioritizeUntried,
    universityId: universityId != null ? universityId() : this.universityId,
  );

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    List<String> list(Object? v) =>
        (v as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    return UserPreferences(
      budget: BudgetOption.from(
        json['budget_type'] as String?,
        (json['budget_amount_krw'] as num?)?.toInt(),
      ),
      distance: DistanceOption.from(
        json['travel_mode'] as String?,
        (json['max_travel_minutes'] as num?)?.toInt(),
      ),
      companions: _companionsFrom(json),
      cuisines: list(json['preferred_cuisines'])
          .map(Cuisine.fromDb)
          .whereType<Cuisine>()
          .toSet(),
      tags: list(json['preferred_tags'])
          .map(FoodTag.fromDb)
          .whereType<FoodTag>()
          .toSet(),
      prioritizeUntried: json['prioritize_untried'] as bool? ?? false,
      universityId: json['university_id'] as String?,
    );
  }

  /// Arguments of `save_user_preferences`. The user id is deliberately absent:
  /// the database takes it from the JWT (`auth.uid()`), never from the client.
  Map<String, dynamic> toRpcParams() {
    assert(isComplete, 'budget and distance are required');
    return {
      'p_university_id': universityId,
      'p_budget_type': budget!.type.name,
      'p_budget_amount_krw': budget!.amountKrw,
      'p_travel_mode': distance!.mode.name,
      'p_max_travel_minutes': distance!.minutes,
      'p_companion_types': (companions.map((c) => c.dbValue).toList()..sort()),
      'p_preferred_cuisines': (cuisines.map((c) => c.name).toList()..sort()),
      'p_preferred_tags': (tags.map((t) => t.name).toList()..sort()),
      'p_prioritize_untried': prioritizeUntried,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is UserPreferences &&
      other.budget == budget &&
      other.distance == distance &&
      setEquals(other.companions, companions) &&
      setEquals(other.cuisines, cuisines) &&
      setEquals(other.tags, tags) &&
      other.prioritizeUntried == prioritizeUntried &&
      other.universityId == universityId;

  @override
  int get hashCode => Object.hash(
    budget,
    distance,
    Object.hashAllUnordered(companions),
    Object.hashAllUnordered(cuisines),
    Object.hashAllUnordered(tags),
    prioritizeUntried,
    universityId,
  );
}

/// Reads `companion_types` (array); falls back to the deprecated single
/// `companion_type` for rows written before the multi-select change.
Set<CompanionType> _companionsFrom(Map<String, dynamic> json) {
  final many = (json['companion_types'] as List<dynamic>? ?? const [])
      .map((e) => CompanionType.fromDb(e.toString()))
      .whereType<CompanionType>()
      .toSet();
  if (many.isNotEmpty) return many;
  final legacy = CompanionType.fromDb(json['companion_type'] as String?);
  return legacy == null ? <CompanionType>{} : {legacy};
}
