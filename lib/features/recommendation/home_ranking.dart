import 'dart:math' as math;

import '../../core/utils/geo.dart';
import '../conditions/models/conditions.dart';
import '../preferences/models/user_preferences.dart';
import '../restaurants/models/restaurant.dart';
import 'preference_filter.dart';
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
  const Judgement(this.verdict, {this.missing = const {}, this.mealPriceKrw});

  final Verdict verdict;
  final Set<MissingInfo> missing;

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
  });

  final Restaurant restaurant;

  /// Straight-line distance from the chosen origin.
  final int meters;
  final int walkMinutes;
  final RestaurantInsight insight;
  final RecommendReason reason;

  /// Empty for a confirmed match; otherwise what could not be checked.
  final Set<MissingInfo> missing;

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
  int arrivalMinutes,
) {
  final missing = <MissingInfo>{};
  int? mealPrice;

  final amount = c.budget.amountKrw;
  if (amount != null) {
    final max = c.budget.type == BudgetType.max;
    bool fits(int price) => max ? price <= amount : price >= amount;
    final meals = [
      for (final m in i.menus)
        if (m.available &&
            m.isMeal &&
            m.priceKrw != null &&
            m.servedAt(arrivalMinutes))
          m.priceKrw!,
    ];
    final fitting = meals.where(fits).toList()..sort();
    if (fitting.isNotEmpty) {
      mealPrice = fitting.first;
    } else {
      final cheapest = i.minPriceKrw;
      final unclear = i.menus.any(
        (m) => m.available && (m.priceKrw == null || !m.kindKnown),
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
    // After midnight, a place that closes at 01:00 is still "today".
    var arrival = arrivalMinutes;
    if (last != null && last > 1440 && arrival + 1440 <= last) arrival += 1440;
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
    if (known == null) missing.add(MissingInfo.amenities);
  }

  return Judgement(
    missing.isEmpty ? Verdict.match : Verdict.unverified,
    missing: missing,
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
    if (cuisines.isNotEmpty && !cuisines.any((c) => cuisineMatches(r, c))) {
      continue;
    }
    final i = insights[r.kakaoId] ?? RestaurantInsight.unknown;
    final j = judgeRestaurant(
      i,
      conditions,
      nowMinutes + walkMinutesFor(meters),
    );
    if (j.verdict == Verdict.excluded) continue;
    kept.add((r: r, meters: meters, i: i, j: j));
  }

  int byDistance(_Kept a, _Kept b) {
    final c = a.meters.compareTo(b.meters);
    return c != 0 ? c : a.r.name.compareTo(b.r.name);
  }

  int unknownLast<T extends num>(T? a, T? b, {bool desc = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return desc ? b.compareTo(a) : a.compareTo(b);
  }

  final int Function(_Kept, _Kept) base = switch (conditions.sort) {
    SortMode.recommended || SortMode.distance => byDistance,
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
  final arrival = nowMinutes + walkMinutes;
  if (openMinutes != null && arrival < openMinutes && last <= 1440) {
    return OrderStatus(OrderStatusKind.notOpenYet, lastOrderMinutes: last);
  }
  final slack = last - arrival;
  final kind = slack < 0
      ? OrderStatusKind.closedBeforeArrival
      : (last - nowMinutes <= 60
            ? OrderStatusKind.closesSoon
            : OrderStatusKind.available);
  return OrderStatus(kind, lastOrderMinutes: last, slackMinutes: slack);
}
