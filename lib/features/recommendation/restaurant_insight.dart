import 'package:flutter/foundation.dart';

/// One menu line, as far as the conditions need it: what it costs, whether it
/// is a meal for one, and when it is served.
@immutable
class MenuLine {
  const MenuLine({
    this.priceKrw,
    this.category,
    this.available = true,
    this.servedFrom,
    this.servedUntil,
  });

  final int? priceKrw;

  /// The admin's menu category (식사, 면류, 분식, 사이드, 음료 ...). Null or
  /// 기타 means nobody said what kind of dish it is.
  final String? category;
  final bool available;

  /// Served only between these minutes of the day (a lunch-only special).
  /// Null = no limit entered.
  final int? servedFrom;
  final int? servedUntil;

  /// A dish one person eats as a meal. Sides, drinks, desserts and bar
  /// snacks never make a place "within budget".
  bool get isMeal => const {'식사', '면류', '분식'}.contains(category);

  /// Whether we know what kind of dish this is at all.
  bool get kindKnown => category != null && category != '기타';

  /// Served at minute-of-day [m] (a window may run past midnight).
  bool servedAt(int m) {
    final from = servedFrom, until = servedUntil;
    if (from == null || until == null) return true;
    final t = m % 1440;
    return from <= until ? t >= from && t <= until : t >= from || t <= until;
  }
}

/// Until this minute of the day (05:00) it is still the evening before for a
/// place that takes orders past midnight: a last order stored as "01:00" is
/// 1500 (25:00), and a clock reading of 00:30 is 1470 on that timeline.
const kOvernightLastOrderBefore = 5 * 60;

/// Facts about a place that Kakao Local does not provide (price, rating,
/// hours, amenities). EVERY field is optional: unknown means unknown, never a
/// guess. An unknown value never removes a place; it makes it a "정보 미확인"
/// candidate instead of a confirmed match (see `judgeRestaurant`).
@immutable
class RestaurantInsight {
  const RestaurantInsight({
    this.minPriceKrw,
    this.rating,
    this.reviewCount,
    this.openMinutes,
    this.lastOrderMinutes,
    this.breakTime,
    this.closed = false,
    this.menus = const [],
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

  /// Cheapest menu item of any kind (it may be a side dish).
  final int? minPriceKrw;
  final double? rating;
  final int? reviewCount;

  /// Opening time, minutes since 00:00 Seoul time.
  final int? openMinutes;

  /// Last order, as minutes since 00:00 Seoul time TODAY (may exceed 1440 for
  /// after-midnight closing, e.g. 00:30 = 1470).
  final int? lastOrderMinutes;

  /// Break time (start, end) in minutes of the day, when it could be read.
  final (int, int)? breakTime;

  /// An admin marked the place temporarily or permanently closed.
  final bool closed;

  /// The menu lines an admin entered (empty = none known).
  final List<MenuLine> menus;
  final String? mainMenu;
  final String? imageUrl;
  final bool? hasBreakTime;
  final bool? parking;
  final bool? localCurrency;
  final bool? fastTurnover;
  final bool? takeout;

  /// Open until at least 22:00.
  final bool? openLate;

  RestaurantInsight withMenus(List<MenuLine> lines) => RestaurantInsight(
    minPriceKrw: minPriceKrw,
    rating: rating,
    reviewCount: reviewCount,
    openMinutes: openMinutes,
    lastOrderMinutes: lastOrderMinutes,
    breakTime: breakTime,
    closed: closed,
    menus: lines,
    mainMenu: mainMenu,
    imageUrl: imageUrl,
    hasBreakTime: hasBreakTime,
    parking: parking,
    localCurrency: localCurrency,
    fastTurnover: fastTurnover,
    takeout: takeout,
    openLate: openLate,
  );
}
