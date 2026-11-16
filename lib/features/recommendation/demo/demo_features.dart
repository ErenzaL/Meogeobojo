import 'package:flutter/foundation.dart';

import '../../restaurants/models/restaurant_override.dart';
import '../restaurant_insight.dart';

/// One row of `recommendation_demo_features`: SIMULATED hours and amenities for a restaurant, keyed by its Kakao place
/// id. It exists so the recommendation can be demonstrated before real data is entered. It is never verified
/// information, never replaces what an administrator entered, and says nothing about prices (the budget is judged
/// on the published menus only) or position (Kakao's live coordinates are used).
@immutable
class DemoFeature {
  const DemoFeature({
    required this.kakaoId,
    this.openMinutes,
    this.lastOrderMinutes,
    this.breakTime,
    this.noBreakTime,
    this.parking,
    this.localCurrency,
    this.fastTurnover,
    this.takeout,
    this.openLate,
  });

  final String kakaoId;
  final int? openMinutes;
  final int? lastOrderMinutes;
  final (int, int)? breakTime;
  final bool? noBreakTime;
  final bool? parking;
  final bool? localCurrency;
  final bool? fastTurnover;
  final bool? takeout;
  final bool? openLate;

  static DemoFeature? fromJson(Map<String, dynamic> j) {
    final id = (j['kakao_place_id'] as String?)?.trim();
    if (id == null || id.isEmpty) return null;
    // Rows that do not say they are demo data are not demo data: never read them as such.
    if (j['demo_data'] != true) return null;
    final open = clockMinutes(j['open_time']);
    return DemoFeature(
      kakaoId: id,
      openMinutes: open,
      lastOrderMinutes: normalizeLastOrder(
        clockMinutes(j['last_order_time']),
        open,
      ),
      breakTime: breakWindow(j['break_time']),
      noBreakTime: j['no_break_time'] as bool?,
      parking: j['parking'] as bool?,
      localCurrency: j['local_currency'] as bool?,
      fastTurnover: j['fast_turnover'] as bool?,
      takeout: j['takeout'] as bool?,
      openLate: j['open_late'] as bool?,
    );
  }
}

/// [base] (what the database and the administrators say) with the DEMO values filling ONLY what is missing.
///
///  * An administrator's value always wins; the demo never overwrites or mixes with it (opening time and last order
///    come from the demo only when the place has neither of its own).
///  * The result is flagged `demo` when any demo value was used.
///  * Menus and prices are untouched.
RestaurantInsight applyDemo(RestaurantInsight base, DemoFeature? f) {
  if (f == null) return base;
  var used = false;
  T? pick<T>(T? own, T? demo) {
    if (own != null) return own;
    if (demo != null) used = true;
    return demo;
  }

  final hoursOwn = base.openMinutes != null || base.lastOrderMinutes != null;
  final open = hoursOwn ? base.openMinutes : pick(null, f.openMinutes);
  final last = hoursOwn
      ? base.lastOrderMinutes
      : pick<int>(null, f.lastOrderMinutes);
  final pause = pick(base.breakTime, f.breakTime);
  final hasBreak =
      base.hasBreakTime ??
      pick<bool>(
        null,
        base.breakTime != null
            ? true
            : (f.noBreakTime == null ? null : !f.noBreakTime!),
      );
  final out = RestaurantInsight(
    minPriceKrw: base.minPriceKrw,
    rating: base.rating,
    reviewCount: base.reviewCount,
    openMinutes: open,
    lastOrderMinutes: last,
    breakTime: pause,
    closed: base.closed,
    menus: base.menus,
    mainMenu: base.mainMenu,
    imageUrl: base.imageUrl,
    hasBreakTime: hasBreak,
    parking: pick(base.parking, f.parking),
    localCurrency: pick(base.localCurrency, f.localCurrency),
    fastTurnover: pick(base.fastTurnover, f.fastTurnover),
    takeout: pick(base.takeout, f.takeout),
    openLate: pick(base.openLate, f.openLate),
    demo: base.demo || used,
  );
  return out;
}
