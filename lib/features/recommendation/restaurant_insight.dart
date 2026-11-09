import 'package:flutter/foundation.dart';

/// Facts about a place that Kakao Local does not provide (price, rating,
/// hours, amenities). EVERY field is optional: unknown means unknown, never a
/// guess, and an unknown value never removes a place from the results.
///
/// There is no data source for these yet (see `restaurantInsightsProvider`).
/// The Home UI, the conditions and the ranking already read them, so they
/// light up as soon as a source is plugged in.
@immutable
class RestaurantInsight {
  const RestaurantInsight({
    this.minPriceKrw,
    this.rating,
    this.reviewCount,
    this.lastOrderMinutes,
    this.mainMenu,
    this.imageUrl,
    this.hasBreakTime,
    this.parking,
    this.localCurrency,
    this.fastTurnover,
    this.takeout,
    this.openLate,
  });

  static const unknown = RestaurantInsight();

  /// Cheapest menu item.
  final int? minPriceKrw;
  final double? rating;
  final int? reviewCount;

  /// Last order, as minutes since 00:00 Seoul time TODAY (may exceed 1440 for
  /// after-midnight closing, e.g. 00:30 = 1470).
  final int? lastOrderMinutes;
  final String? mainMenu;
  final String? imageUrl;
  final bool? hasBreakTime;
  final bool? parking;
  final bool? localCurrency;
  final bool? fastTurnover;
  final bool? takeout;

  /// Open until at least 22:00.
  final bool? openLate;
}
