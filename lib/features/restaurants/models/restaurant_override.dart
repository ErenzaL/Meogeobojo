import 'package:flutter/foundation.dart';

import '../../recommendation/restaurant_insight.dart';

/// What the admin dashboard added or changed for a Kakao place
/// (`restaurant_overrides`, keyed by `kakao_place_id`).
@immutable
class RestaurantOverride {
  const RestaurantOverride({
    required this.kakaoId,
    required this.visibility,
    this.description,
    this.insight = RestaurantInsight.unknown,
  });

  final String kakaoId;

  /// published | hidden | archived (drafts are never readable by the app).
  final String visibility;
  final String? description;
  final RestaurantInsight insight;

  /// Hidden or archived places must not be shown in lists.
  bool get isHidden => visibility == 'hidden' || visibility == 'archived';

  static RestaurantOverride? fromJson(Map<String, dynamic> j) {
    final id = j['kakao_place_id'] as String?;
    if (id == null || id.isEmpty) return null;
    int? minutes(Object? t) {
      final s = t as String?;
      if (s == null || s.length < 5) return null;
      final h = int.tryParse(s.substring(0, 2));
      final m = int.tryParse(s.substring(3, 5));
      return (h == null || m == null) ? null : h * 60 + m;
    }

    final desc = (j['description'] as String?)?.trim();
    return RestaurantOverride(
      kakaoId: id,
      visibility: (j['visibility'] as String?) ?? 'published',
      description: (desc == null || desc.isEmpty) ? null : desc,
      insight: RestaurantInsight(
        minPriceKrw: (j['price_min_krw'] as num?)?.toInt(),
        lastOrderMinutes: minutes(j['last_order_time']),
        imageUrl: j['image_url'] as String?,
      ),
    );
  }
}

/// One menu line of a restaurant (`restaurant_menus`).
@immutable
class RestaurantMenuItem {
  const RestaurantMenuItem({
    required this.name,
    this.description,
    this.priceKrw,
    this.imageUrl,
    this.available = true,
    this.representative = false,
  });

  final String name;
  final String? description;
  final int? priceKrw;
  final String? imageUrl;
  final bool available;
  final bool representative;

  static RestaurantMenuItem? fromJson(Map<String, dynamic> j) {
    final name = (j['name_ko'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    return RestaurantMenuItem(
      name: name,
      description: (j['description_ko'] as String?)?.trim(),
      priceKrw: (j['price_krw'] as num?)?.toInt(),
      imageUrl: j['image_url'] as String?,
      available: (j['available'] as bool?) ?? true,
      representative: (j['representative'] as bool?) ?? false,
    );
  }
}
