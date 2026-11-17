import 'dart:math' as math;

import '../../core/utils/geo.dart';
import '../conditions/models/conditions.dart';
import '../preferences/models/user_preferences.dart';
import '../restaurants/models/restaurant.dart';
import '../restaurants/models/restaurant_override.dart';
import 'preference_filter.dart';
import 'recommendation_score.dart';
import 'restaurant_insight.dart';

/// Why a place is shown first. Only facts that were actually checked: the
/// UI turns this into localized text.
enum ReasonKind { budget, cuisine, closest, walk }

class RecommendReason {
  const RecommendReason(this.kind, {this.cuisine, this.budget});

  final ReasonKind kind;

  /// Set for [ReasonKind.cuisine]: the chosen cuisine this place matched.
  final Cuisine? cuisine;

  /// Set for [ReasonKind.budget]: the budget a meal on the menu fits.
  final BudgetOption? budget;
}

/// How a place stands against the chosen conditions. Home, the map, search
/// and the 조건 sheet all use this one judgement.
enum Verdict {
  /// Every chosen condition was checked and holds.
  match,

  /// No condition is known to fail, but some data needed to check one is
  /// missing: listed apart, never as a match.
  unverified,

  /// At least one chosen condition clearly fails: shown nowhere.
  excluded,
}

/// What could not be checked for an [Verdict.unverified] place.
enum MissingInfo { price, hours, amenities }

class Judgement {
  const Judgement(
    this.verdict, {
    this.missing = const {},
    this.missingAmenities = const {},
    this.mealPriceKrw,
  });

  final Verdict verdict;
  final Set<MissingInfo> missing;

  /// Which of the chosen 운영·편의 conditions could not be checked (part of [MissingInfo.amenities]).
  final Set<Amenity> missingAmenities;

  /// The cheapest meal for one that fits the budget then (budget chosen only).
  final int? mealPriceKrw;
}

class RankedRestaurant {
  const RankedRestaurant({
    required this.restaurant,
    required this.meters,
    required this.walkMinutes,
    required this.insight,
    required this.reason,
    this.missing = const {},
    this.missingAmenities = const {},
    this.demoBasis = false,
    this.score,
  });

  final Restaurant restaurant;

  /// Straight-line distance from the chosen origin.
  final int meters;
  final int walkMinutes;
  final RestaurantInsight insight;
  final RecommendReason reason;

  /// Empty for a confirmed match; otherwise what could not be checked.
  final Set<MissingInfo> missing;

  /// The chosen amenities that could not be checked for this place.
  final Set<Amenity> missingAmenities;

  /// A condition of this ranking (opening hours, an amenity) was judged on simulated DEMO data: never present it as
  /// verified.
  final bool demoBasis;

  /// The V3 score (0..1) this place was ranked by (see `recommendation_score.dart`).
  final double? score;

  /// A confirmed match ("조건 충족 확인"), not a "정보 미확인" candidate.
  bool get verified => missing.isEmpty;
}

/// Confirmed matches and "정보 미확인" candidates of one ranking.
extension RankedSplit on List<RankedRestaurant> {
  List<RankedRestaurant> get confirmed => [
    for (final r in this)
      if (r.verified) r,
  ];

  List<RankedRestaurant> get unconfirmed => [
    for (final r in this)
      if (!r.verified) r,
  ];
}

/// Walking minutes for a straight-line distance, at least 1. Uses the same
/// assumption as the distance conditions ([walkMetersPerMinute]).
int walkMinutesFor(int meters) =>
    math.max(1, (meters / walkMetersPerMinute).round());

/// A menu line that can be evidence for a budget at [arrivalMinutes]: served then, priced, in stock, and something the place
/// offers ([MenuLine.isOffered]): at a restaurant every dish except drinks and add-on sides (a 안주 or a platter counts
/// too), at a [cafe] the drinks and desserts as well.
bool lineCountsForBudget(
  MenuLine m, {
  required bool max,
  required int arrivalMinutes,
  bool cafe = false,
}) =>
    m.available &&
    m.isOffered(cafe: cafe) &&
    m.priceKrw != null &&
    m.servedAt(arrivalMinutes);

/// The menu lines of ONE place that match [c] for someone arriving at [arrivalMinutes]: with a budget the lines that fit
/// it (the very lines `judgeRestaurant` confirms the place on), without one every dish the place offers. At a restaurant
/// that is everything but drinks and add-on sides; at a [cafe] the drinks too. Representative dishes first, then meals
/// before other dishes, then cheapest first. Empty when the place has no such line.
List<RestaurantMenuItem> menusMatchingConditions(
  List<RestaurantMenuItem> menus,
  Conditions c,
  int arrivalMinutes, {
  bool cafe = false,
}) {
  final amount = c.budget.amountKrw;
  final max = c.budget.type == BudgetType.max;
  final out = [
    for (final m in menus)
      if (amount == null
          ? m.available &&
                m.priceKrw != null &&
                m.line.isOffered(cafe: cafe) &&
                m.line.servedAt(arrivalMinutes)
          : lineCountsForBudget(
                  m.line,
                  max: max,
                  arrivalMinutes: arrivalMinutes,
                  cafe: cafe,
                ) &&
                (max ? m.priceKrw! <= amount : m.priceKrw! >= amount))
        m,
  ];
  out.sort((a, b) {
    if (a.representative != b.representative) return a.representative ? -1 : 1;
    if (a.line.isMeal != b.line.isMeal) return a.line.isMeal ? -1 : 1;
    return a.priceKrw!.compareTo(b.priceKrw!);
  });
  return out;
}

/// Judges one place against [c], for someone arriving at [arrivalMinutes]
/// (Seoul minute of the day).
///
/// Budget: a place fits when a MEAL for one (식사·면류·분식 on the menu,
/// available, served at that time) costs within the budget. A cheap side dish
/// never counts, and neither does a lunch-only dish at dinner. It fails when
/// even the cheapest item is over budget, or when every meal served then is,
/// with no unclassified or unpriced line left that could still fit.
///
/// 지금 주문 가능: fails when the place is marked closed, has not opened yet,
/// is on its break, or takes the last order before arrival. It is confirmed
/// only when both the opening time and the last order are known: hours alone
/// say "open", not "still taking orders".
Judgement judgeRestaurant(
  RestaurantInsight i,
  Conditions c,
  int arrivalMinutes, {
  bool cafe = false,
}) {
  final missing = <MissingInfo>{};
  final missingAmenities = <Amenity>{};
  int? mealPrice;

  final amount = c.budget.amountKrw;
  if (amount != null) {
    final max = c.budget.type == BudgetType.max;
    bool fits(int price) => max ? price <= amount : price >= amount;
    // The evidence is every dish the place offers (see [lineCountsForBudget]): a 안주 or a platter counts as well as a
    // meal, and a cafe's drinks and desserts count at a cafe.
    final meals = [
      for (final m in i.menus)
        if (lineCountsForBudget(
          m,
          max: max,
          arrivalMinutes: arrivalMinutes,
          cafe: cafe,
        ))
          m.priceKrw!,
    ];
    final fitting = meals.where(fits).toList()..sort();
    if (fitting.isNotEmpty) {
      mealPrice = fitting.first;
    } else {
      final cheapest = i.minPriceKrw;
      // Only lines served then could still fit: an unpriced lunch special
      // says nothing about dinner.
      final unclear = i.menus.any(
        (m) =>
            m.available &&
            m.servedAt(arrivalMinutes) &&
            (m.priceKrw == null || !m.kindKnown),
      );
      final overAll = max && cheapest != null && cheapest > amount;
      if (overAll || (meals.isNotEmpty && !unclear)) {
        return const Judgement(Verdict.excluded);
      }
      missing.add(MissingInfo.price);
    }
  }

  if (c.openNowOnly) {
    final last = i.lastOrderMinutes;
    // Before 05:00, a place that takes orders until 01:00 (1500) is still on
    // the evening's timeline: 00:30 is before its last order, 01:30 after.
    var arrival = arrivalMinutes;
    if (last != null && last > 1440 && arrival < kOvernightLastOrderBefore) {
      arrival += 1440;
    }
    final open = i.openMinutes;
    final pause = i.breakTime;
    if (i.closed ||
        (last != null && arrival > last) ||
        (open != null && arrival < open) ||
        (pause != null && arrival >= pause.$1 && arrival < pause.$2)) {
      return const Judgement(Verdict.excluded);
    }
    if (open == null || last == null) missing.add(MissingInfo.hours);
  }

  for (final a in c.amenities) {
    final known = switch (a) {
      Amenity.noBreakTime => i.hasBreakTime == null ? null : !i.hasBreakTime!,
      Amenity.parking => i.parking,
      Amenity.localCurrency => i.localCurrency,
      Amenity.fastTurnover => i.fastTurnover,
      Amenity.takeout => i.takeout,
      Amenity.openLate => i.openLate,
    };
    if (known == false) return const Judgement(Verdict.excluded);
    if (known == null) {
      missing.add(MissingInfo.amenities);
      missingAmenities.add(a);
    }
  }

  return Judgement(
    missing.isEmpty ? Verdict.match : Verdict.unverified,
    missing: missing,
    missingAmenities: missingAmenities,
    mealPriceKrw: mealPrice,
  );
}

/// Filters by [conditions], measures from ([lat], [lng]) and orders: the
/// confirmed matches first, then the "정보 미확인" candidates. Places that
/// clearly fail a condition are dropped.
///
/// "추천순" is distance order: there is no popularity data to rank with.
/// "안 가 본 곳 먼저" puts places without a meal record ([visitedIds]) ahead.
List<RankedRestaurant> rankRestaurants({
  required List<Restaurant> all,
  required double lat,
  required double lng,
  required Conditions conditions,
  required Map<String, RestaurantInsight> insights,
  required int nowMinutes,
  Set<String> hiddenIds = const {},
  Set<String> visitedIds = const {},
  Map<String, double> reviewSignals = const {},
}) {
  final maxMeters = maxDistanceMeters(conditions.distance);
  final cuisines = conditions.cuisines;
  final wantsCafe = cuisines.contains(Cuisine.cafe);

  final kept = <_Kept>[];
  for (final r in all) {
    if (hiddenIds.contains(r.kakaoId)) continue; // hidden by an admin
    final isFood =
        r.categoryGroupCode == 'FD6' ||
        (wantsCafe && r.categoryGroupCode == 'CE7');
    if (!isFood) continue;
    final meters = haversineMeters(lat, lng, r.latitude, r.longitude).round();
    if (maxMeters != null && meters > maxMeters) continue;
    // A food preference is NOT a filter: it adds to the score (V3), so a preferred place ranks higher without
    // hiding the others (the team's model: distance and budget decide who qualifies; taste and distance rank them).
    final i = insights[r.kakaoId] ?? RestaurantInsight.unknown;
    final j = judgeRestaurant(
      i,
      conditions,
      nowMinutes + walkMinutesFor(meters),
      cafe: r.categoryGroupCode == 'CE7',
    );
    if (j.verdict == Verdict.excluded) continue;
    kept.add((r: r, meters: meters, i: i, j: j));
  }

  int byDistance(_Kept a, _Kept b) {
    final c = a.meters.compareTo(b.meters);
    return c != 0 ? c : a.r.name.compareTo(b.r.name);
  }

  // V3: the distance is measured against the chosen radius; with "any distance" the farthest candidate is the scale.
  final scale =
      maxMeters ??
      kept.fold<double>(1, (m, k) => math.max(m, k.meters.toDouble()));
  final preferred = cuisines.isNotEmpty && !cuisines.contains(Cuisine.any);
  final scores = <String, double>{
    for (final k in kept)
      k.r.kakaoId: v3Score(
        preferenceDistanceScore(
          matchesPreference: preferred
              ? cuisines.any((c) => cuisineMatches(k.r, c))
              : null,
          distance: distanceScore(k.meters.toDouble(), scale),
        ),
        reviewSignals[k.r.kakaoId] ?? 0,
      ),
  };
  int byScore(_Kept a, _Kept b) {
    final c = scores[b.r.kakaoId]!.compareTo(scores[a.r.kakaoId]!);
    if (c != 0) return c;
    final d = a.meters.compareTo(b.meters);
    return d != 0 ? d : a.r.kakaoId.compareTo(b.r.kakaoId);
  }

  int unknownLast<T extends num>(T? a, T? b, {bool desc = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return desc ? b.compareTo(a) : a.compareTo(b);
  }

  final int Function(_Kept, _Kept) base = switch (conditions.sort) {
    SortMode.recommended => byScore,
    SortMode.distance => byDistance,
    SortMode.price => (a, b) {
      final c = unknownLast(
        a.j.mealPriceKrw ?? a.i.minPriceKrw,
        b.j.mealPriceKrw ?? b.i.minPriceKrw,
      );
      return c != 0 ? c : byDistance(a, b);
    },
    SortMode.rating => (a, b) {
      final c = unknownLast(a.i.rating, b.i.rating, desc: true);
      return c != 0 ? c : byDistance(a, b);
    },
  };
  int order(_Kept a, _Kept b) {
    if (conditions.untriedFirst) {
      final va = visitedIds.contains(a.r.kakaoId);
      final vb = visitedIds.contains(b.r.kakaoId);
      if (va != vb) return va ? 1 : -1;
    }
    return base(a, b);
  }

  bool ok(_Kept k) => k.j.verdict == Verdict.match;
  kept.sort((a, b) => ok(a) == ok(b) ? order(a, b) : (ok(a) ? -1 : 1));

  final matched = kept.where(ok);
  final closest = matched.isEmpty
      ? 0
      : matched.map((e) => e.meters).reduce(math.min);
  return [
    for (final e in kept)
      RankedRestaurant(
        restaurant: e.r,
        meters: e.meters,
        walkMinutes: walkMinutesFor(e.meters),
        insight: e.i,
        reason: _reasonFor(e, conditions, closest),
        missing: e.j.missing,
        missingAmenities: e.j.missingAmenities,
        demoBasis:
            e.i.demo &&
            (conditions.openNowOnly || conditions.amenities.isNotEmpty),
        score: scores[e.r.kakaoId],
      ),
  ];
}

typedef _Kept = ({Restaurant r, int meters, RestaurantInsight i, Judgement j});

/// The strongest reason that was actually checked for this place. The budget
/// comes first, and only a confirmed meal price gives it.
RecommendReason _reasonFor(_Kept e, Conditions c, int closestMeters) {
  if (e.j.mealPriceKrw != null && c.budget.amountKrw != null) {
    return RecommendReason(ReasonKind.budget, budget: c.budget);
  }
  for (final cuisine in Cuisine.values) {
    if (c.cuisines.contains(cuisine) && cuisineMatches(e.r, cuisine)) {
      return RecommendReason(ReasonKind.cuisine, cuisine: cuisine);
    }
  }
  if (e.j.verdict == Verdict.match && e.meters <= closestMeters) {
    return const RecommendReason(ReasonKind.closest);
  }
  return const RecommendReason(ReasonKind.walk);
}

// ---- Comparison with the top pick ------------------------------------

enum CompareKind { closer, cheaper, higherRating, opensLater, none }

class Comparison {
  const Comparison(this.kind, [this.value = 0]);

  final CompareKind kind;

  /// Minutes (closer) or won (cheaper).
  final int value;
}

/// The single biggest advantage [other] has over [top], in a fixed order:
/// closer, cheaper, better rated, opens later. [CompareKind.none] when it has
/// none (the caller then shows the place's own reason).
Comparison compareAgainst(RankedRestaurant top, RankedRestaurant other) {
  final dMin = top.walkMinutes - other.walkMinutes;
  if (dMin > 0) return Comparison(CompareKind.closer, dMin);
  final tp = top.insight.minPriceKrw;
  final op = other.insight.minPriceKrw;
  if (tp != null && op != null && tp - op > 0) {
    return Comparison(CompareKind.cheaper, tp - op);
  }
  final tr = top.insight.rating;
  final or = other.insight.rating;
  if (tr != null && or != null && or > tr) {
    return const Comparison(CompareKind.higherRating);
  }
  final tl = top.insight.lastOrderMinutes;
  final ol = other.insight.lastOrderMinutes;
  if (tl != null && ol != null && ol > tl) {
    return const Comparison(CompareKind.opensLater);
  }
  return const Comparison(CompareKind.none);
}

// ---- Order status ------------------------------------------------------

enum OrderStatusKind {
  /// No last-order data: the UI says nothing about it.
  unknown,

  /// Arrives before the opening time.
  notOpenYet,
  available,

  /// Closes within an hour, or before the walker would arrive.
  closesSoon,
  closedBeforeArrival,
}

class OrderStatus {
  const OrderStatus(this.kind, {this.lastOrderMinutes, this.slackMinutes});

  final OrderStatusKind kind;
  final int? lastOrderMinutes;

  /// Minutes between arrival and last order (negative when too late).
  final int? slackMinutes;
}

OrderStatus orderStatus(RankedRestaurant r, int nowMinutes) => orderStatusAt(
  lastOrderMinutes: r.insight.lastOrderMinutes,
  openMinutes: r.insight.openMinutes,
  walkMinutes: r.walkMinutes,
  nowMinutes: nowMinutes,
);

/// [orderStatus] for a place that is not part of a ranking (the detail page).
OrderStatus orderStatusAt({
  required int? lastOrderMinutes,
  required int walkMinutes,
  required int nowMinutes,
  int? openMinutes,
}) {
  final last = lastOrderMinutes;
  if (last == null) return const OrderStatus(OrderStatusKind.unknown);
  // Before 05:00, a place taking orders until 01:00 (= 1500) is still on
  // the evening's timeline (so 01:30 is past its last order).
  final now =
      last > 1440 && nowMinutes + walkMinutes < kOvernightLastOrderBefore
      ? nowMinutes + 1440
      : nowMinutes;
  final arrival = now + walkMinutes;
  if (openMinutes != null && arrival < openMinutes) {
    return OrderStatus(OrderStatusKind.notOpenYet, lastOrderMinutes: last);
  }
  final slack = last - arrival;
  final kind = slack < 0
      ? OrderStatusKind.closedBeforeArrival
      : (last - now <= 60
            ? OrderStatusKind.closesSoon
            : OrderStatusKind.available);
  return OrderStatus(kind, lastOrderMinutes: last, slackMinutes: slack);
}

// ---- Conditions nobody can check, and what to relax --------------------------------------------------------------

/// [c] without the 운영·편의 conditions that NO place of [pool] has any data for. Ranking on them would drop every
/// place for lack of data and show an empty list that says nothing about the places. They are named in
/// [UsableConditions.ignoredAmenities] / [UsableConditions.ignoredHours] so the screen can say they were not applied.
/// As soon as some places have the data (an administrator entered it) the condition applies in full again.
class UsableConditions {
  const UsableConditions(
    this.conditions, {
    this.ignoredAmenities = const {},
    this.ignoredHours = false,
  });

  final Conditions conditions;
  final Set<Amenity> ignoredAmenities;

  /// 지금 주문 가능 was chosen but no place has opening hours and a last order.
  final bool ignoredHours;

  bool get any => ignoredAmenities.isNotEmpty || ignoredHours;
}

UsableConditions usableConditions(
  Conditions c,
  Iterable<Restaurant> pool,
  Map<String, RestaurantInsight> insights,
) {
  if (c.amenities.isEmpty && !c.openNowOnly) return UsableConditions(c);
  final infos = [
    for (final r in pool) insights[r.kakaoId] ?? RestaurantInsight.unknown,
  ];
  bool known(Amenity a, RestaurantInsight i) => switch (a) {
    Amenity.noBreakTime => i.hasBreakTime != null,
    Amenity.parking => i.parking != null,
    Amenity.localCurrency => i.localCurrency != null,
    Amenity.fastTurnover => i.fastTurnover != null,
    Amenity.takeout => i.takeout != null,
    Amenity.openLate => i.openLate != null,
  };
  final ignored = {
    for (final a in c.amenities)
      if (!infos.any((i) => known(a, i))) a,
  };
  final noHours =
      c.openNowOnly &&
      !infos.any((i) => i.openMinutes != null && i.lastOrderMinutes != null);
  if (ignored.isEmpty && !noHours) return UsableConditions(c);
  return UsableConditions(
    c.copyWith(
      amenities: {...c.amenities}..removeAll(ignored),
      openNowOnly: noHours ? false : c.openNowOnly,
    ),
    ignoredAmenities: ignored,
    ignoredHours: noHours,
  );
}

enum RelaxKind { distance, budget, hours, amenities, category }

/// One change to the conditions that would turn an empty result into [count] confirmed places.
class RelaxSuggestion {
  const RelaxSuggestion(
    this.kind,
    this.conditions,
    this.count, {
    this.distance,
    this.clearCategory = false,
  });

  final RelaxKind kind;

  /// The conditions after the change.
  final Conditions conditions;
  final int count;

  /// For [RelaxKind.distance]: the wider distance.
  final DistanceOption? distance;

  /// For [RelaxKind.category]: the food-type chips are cleared too.
  final bool clearCategory;
}

const _widerDistances = [
  DistanceOption.walk5,
  DistanceOption.walk10,
  DistanceOption.walk15,
  DistanceOption.drive10,
  DistanceOption.drive15,
  DistanceOption.any,
];

/// For an empty result: each single condition that, relaxed on its own, would give confirmed places (a wider distance
/// the nearest step that does, no budget, no 지금 주문 가능, no 운영·편의, any food type). Only changes with at least
/// one result are returned; nothing is invented.
List<RelaxSuggestion> relaxSuggestions({
  required List<Restaurant> pool,
  required List<Restaurant> poolAnyCategory,
  required bool categoryChosen,
  required double lat,
  required double lng,
  required Conditions conditions,
  required Map<String, RestaurantInsight> insights,
  required int nowMinutes,
  Set<String> hiddenIds = const {},
}) {
  int count(Conditions c, List<Restaurant> places) {
    final u = usableConditions(c, places, insights);
    return rankRestaurants(
      all: places,
      lat: lat,
      lng: lng,
      conditions: u.conditions,
      insights: insights,
      hiddenIds: hiddenIds,
      nowMinutes: nowMinutes,
    ).confirmed.length;
  }

  final out = <RelaxSuggestion>[];
  if (conditions.distance != DistanceOption.any) {
    final from = _widerDistances.indexOf(conditions.distance);
    for (var k = from + 1; k < _widerDistances.length; k++) {
      final c = conditions.copyWith(distance: _widerDistances[k]);
      final n = count(c, pool);
      if (n > 0) {
        out.add(
          RelaxSuggestion(
            RelaxKind.distance,
            c,
            n,
            distance: _widerDistances[k],
          ),
        );
        break;
      }
    }
  }
  void tryOne(RelaxKind kind, Conditions c) {
    final n = count(c, pool);
    if (n > 0) out.add(RelaxSuggestion(kind, c, n));
  }

  if (conditions.budget != BudgetOption.any) {
    tryOne(RelaxKind.budget, conditions.copyWith(budget: BudgetOption.any));
  }
  if (conditions.openNowOnly) {
    tryOne(RelaxKind.hours, conditions.copyWith(openNowOnly: false));
  }
  if (conditions.amenities.isNotEmpty) {
    tryOne(RelaxKind.amenities, conditions.copyWith(amenities: const {}));
  }
  if (categoryChosen) {
    final n = count(conditions, poolAnyCategory);
    if (n > 0) {
      out.add(
        RelaxSuggestion(RelaxKind.category, conditions, n, clearCategory: true),
      );
    }
  }
  return out;
}
