import 'dart:math' as math;

import '../../core/utils/geo.dart';
import '../conditions/models/conditions.dart';
import '../preferences/models/user_preferences.dart';
import '../restaurants/models/restaurant.dart';
import 'preference_filter.dart';
import 'restaurant_insight.dart';

/// Why a place is shown first. The UI turns this into localized text.
enum ReasonKind { cuisine, budget, closest, walk }

class RecommendReason {
  const RecommendReason(this.kind, {this.cuisine});

  final ReasonKind kind;

  /// Set for [ReasonKind.cuisine]: the chosen cuisine this place matched.
  final Cuisine? cuisine;
}

class RankedRestaurant {
  const RankedRestaurant({
    required this.restaurant,
    required this.meters,
    required this.walkMinutes,
    required this.insight,
    required this.reason,
  });

  final Restaurant restaurant;

  /// Straight-line distance from the chosen origin.
  final int meters;
  final int walkMinutes;
  final RestaurantInsight insight;
  final RecommendReason reason;
}

/// Walking minutes for a straight-line distance, at least 1. Uses the same
/// assumption as the distance conditions ([walkMetersPerMinute]).
int walkMinutesFor(int meters) =>
    math.max(1, (meters / walkMetersPerMinute).round());

/// Filters by [conditions], measures from ([lat], [lng]) and orders.
///
/// Today "추천순" is distance order: there is no popularity, price or visit
/// data to rank with, so the soft conditions (party, needs, untried first)
/// are stored but do not change the order yet. Nothing is invented.
List<RankedRestaurant> rankRestaurants({
  required List<Restaurant> all,
  required double lat,
  required double lng,
  required Conditions conditions,
  required Map<String, RestaurantInsight> insights,
  required int nowMinutes,
  Set<String> hiddenIds = const {},
}) {
  final maxMeters = maxDistanceMeters(conditions.distance);
  final cuisines = conditions.cuisines;
  final wantsCafe = cuisines.contains(Cuisine.cafe);

  final kept = <({Restaurant r, int meters, RestaurantInsight i})>[];
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
    if (!_passesData(i, conditions, nowMinutes + walkMinutesFor(meters))) {
      continue;
    }
    kept.add((r: r, meters: meters, i: i));
  }

  int byDistance(a, b) {
    final c = a.meters.compareTo(b.meters);
    return c != 0 ? c : a.r.name.compareTo(b.r.name);
  }

  int unknownLast<T extends num>(T? a, T? b, {bool desc = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return desc ? b.compareTo(a) : a.compareTo(b);
  }

  kept.sort(switch (conditions.sort) {
    SortMode.recommended || SortMode.distance => byDistance,
    SortMode.price => (a, b) {
      final c = unknownLast(a.i.minPriceKrw, b.i.minPriceKrw);
      return c != 0 ? c : byDistance(a, b);
    },
    SortMode.rating => (a, b) {
      final c = unknownLast(a.i.rating, b.i.rating, desc: true);
      return c != 0 ? c : byDistance(a, b);
    },
  });

  final closest = kept.isEmpty ? 0 : kept.map((e) => e.meters).reduce(math.min);
  return [
    for (final e in kept)
      RankedRestaurant(
        restaurant: e.r,
        meters: e.meters,
        walkMinutes: walkMinutesFor(e.meters),
        insight: e.i,
        reason: _reasonFor(e.r, e.meters, e.i, conditions, closest),
      ),
  ];
}

/// Hard conditions that need data. Unknown data keeps the place.
bool _passesData(RestaurantInsight i, Conditions c, int arrivalMinutes) {
  final price = i.minPriceKrw;
  final amount = c.budget.amountKrw;
  if (price != null && amount != null) {
    if (c.budget.type == BudgetType.max && price > amount) return false;
    if (c.budget.type == BudgetType.min && price < amount) return false;
  }
  final lastOrder = i.lastOrderMinutes;
  if (c.openNowOnly && lastOrder != null && arrivalMinutes > lastOrder) {
    return false;
  }
  bool ok(bool? v) => v != false; // unknown passes
  for (final a in c.amenities) {
    final pass = switch (a) {
      Amenity.noBreakTime => i.hasBreakTime == null || !i.hasBreakTime!,
      Amenity.parking => ok(i.parking),
      Amenity.localCurrency => ok(i.localCurrency),
      Amenity.fastTurnover => ok(i.fastTurnover),
      Amenity.takeout => ok(i.takeout),
      Amenity.openLate => ok(i.openLate),
    };
    if (!pass) return false;
  }
  return true;
}

/// The strongest reason that is actually true for this place.
RecommendReason _reasonFor(
  Restaurant r,
  int meters,
  RestaurantInsight i,
  Conditions c,
  int closestMeters,
) {
  for (final cuisine in Cuisine.values) {
    if (c.cuisines.contains(cuisine) && cuisineMatches(r, cuisine)) {
      return RecommendReason(ReasonKind.cuisine, cuisine: cuisine);
    }
  }
  if (c.budget != BudgetOption.any && i.minPriceKrw != null) {
    return const RecommendReason(ReasonKind.budget);
  }
  if (meters <= closestMeters) return const RecommendReason(ReasonKind.closest);
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
  walkMinutes: r.walkMinutes,
  nowMinutes: nowMinutes,
);

/// [orderStatus] for a place that is not part of a ranking (the detail page).
OrderStatus orderStatusAt({
  required int? lastOrderMinutes,
  required int walkMinutes,
  required int nowMinutes,
}) {
  final last = lastOrderMinutes;
  if (last == null) return const OrderStatus(OrderStatusKind.unknown);
  final arrival = nowMinutes + walkMinutes;
  final slack = last - arrival;
  final kind = slack < 0
      ? OrderStatusKind.closedBeforeArrival
      : (last - nowMinutes <= 60
            ? OrderStatusKind.closesSoon
            : OrderStatusKind.available);
  return OrderStatus(kind, lastOrderMinutes: last, slackMinutes: slack);
}
