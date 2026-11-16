import 'package:flutter/foundation.dart';

import '../../recommendation/restaurant_insight.dart';
import 'restaurant.dart';

/// What the admin dashboard added or changed for a Kakao place
/// (`restaurant_overrides`, keyed by `kakao_place_id`).
@immutable
class RestaurantOverride {
  const RestaurantOverride({
    required this.kakaoId,
    required this.visibility,
    this.description,
    this.name,
    this.address,
    this.phone,
    this.id,
    this.category,
    this.latitude,
    this.longitude,
    this.featured = false,
    this.displayOrder,
    this.insight = RestaurantInsight.unknown,
  });

  /// The restaurant's key everywhere in the app: its Kakao place id, or, for a restaurant added by hand
  /// without one, its own database id (a uuid).
  final String kakaoId;

  /// The database row id (`restaurant_overrides.id`), when the row was read in full.
  final String? id;

  /// Admin-managed category path ("음식점 > 한식") and coordinates. When present they win over Kakao's.
  final String? category;
  final double? latitude;
  final double? longitude;

  /// published | hidden | archived (drafts are never readable by the app).
  final String visibility;
  final String? description;

  /// Admin-managed display fields. When a PUBLISHED override has them they
  /// replace the Kakao source values (see [applyTo]).
  final String? name;
  final String? address;
  final String? phone;

  /// Featured by an admin; [displayOrder] (lower first) orders the featured places.
  final bool featured;
  final int? displayOrder;
  final RestaurantInsight insight;

  /// [r] with this override's non-empty, published display fields applied.
  /// Kakao's id, category path, coordinates and distance are never changed, so
  /// favorites, markers, filtering and ranking keep working on the same place.
  Restaurant applyTo(Restaurant r) {
    if (visibility != 'published') return r;
    final hasCoords = latitude != null && longitude != null;
    return r.copyWith(
      name: name,
      roadAddress: address,
      phone: phone,
      categoryName: category,
      latitude: hasCoords ? latitude : null,
      longitude: hasCoords ? longitude : null,
    );
  }

  /// Hidden or archived places must not be shown in lists.
  bool get isHidden => visibility == 'hidden' || visibility == 'archived';

  static RestaurantOverride? fromJson(Map<String, dynamic> j) {
    String? text(Object? v) {
      final t = (v as String?)?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final rowId = text(j['id']);
    // A restaurant added by hand has no Kakao id: its own database id is its key.
    final id = text(j['kakao_place_id']) ?? rowId;
    if (id == null) return null;
    final status = j['business_status'] as String?;
    final hours = j['opening_hours'];
    // The admin enters it as opening_hours.open ("11:00").
    final open = clockMinutes(hours is Map ? hours['open'] : null);
    final lastOrder = normalizeLastOrder(
      clockMinutes(j['last_order_time']),
      open,
    );
    return RestaurantOverride(
      kakaoId: id,
      visibility: (j['visibility'] as String?) ?? 'published',
      description: text(j['description']),
      name: text(j['name_ko']),
      address: text(j['address']),
      phone: text(j['phone']),
      id: rowId,
      category: text(j['category']),
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      featured: (j['featured'] as bool?) ?? false,
      displayOrder: (j['display_order'] as num?)?.toInt(),
      insight: RestaurantInsight(
        minPriceKrw: (j['price_min_krw'] as num?)?.toInt(),
        openMinutes: open,
        lastOrderMinutes: lastOrder,
        breakTime: breakWindow(j['break_time']),
        closed: status == 'temporarily_closed' || status == 'closed',
        imageUrl: j['image_url'] as String?,
      ),
    );
  }
}

/// Stored as a time of day: a last order after midnight ("01:00") belongs to the evening before, so it goes past 1440
/// (01:00 = 1500). That is any last order before 05:00, or one not after the opening time. The first rule matters for
/// places saved before the opening time existed.
int? normalizeLastOrder(int? lastOrder, int? open) {
  if (lastOrder == null) return null;
  return (lastOrder < kOvernightLastOrderBefore ||
          (open != null && lastOrder <= open))
      ? lastOrder + 1440
      : lastOrder;
}

/// "21:30" / "21:30:00" → minutes since 00:00; null when it is not a time.
int? clockMinutes(Object? t) {
  if (t is! String || t.length < 5) return null;
  final h = int.tryParse(t.substring(0, 2));
  final m = int.tryParse(t.substring(3, 5));
  return (h == null || m == null || h > 23 || m > 59) ? null : h * 60 + m;
}

/// The admin's free-text break time ("15:00-17:00", "15:00~17:00") as
/// (start, end) minutes. Anything else is not guessed at: null.
(int, int)? breakWindow(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*[-~–]\s*(\d{1,2}):(\d{2})\s*$')
      .firstMatch(v);
  if (m == null) return null;
  String pad(String h) => h.padLeft(2, '0');
  final a = clockMinutes('${pad(m[1]!)}:${m[2]}');
  final b = clockMinutes('${pad(m[3]!)}:${m[4]}');
  return (a == null || b == null || b <= a) ? null : (a, b);
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
    this.recommended = false,
    this.category,
    this.servedFrom,
    this.servedUntil,
  });

  final String name;
  final String? description;
  final int? priceKrw;
  final String? imageUrl;
  final bool available;
  final bool representative;
  final bool recommended;
  final String? category;

  /// Served only between these minutes of the day (e.g. a lunch special).
  final int? servedFrom;
  final int? servedUntil;

  /// What the conditions need from this line.
  MenuLine get line => MenuLine(
    priceKrw: priceKrw,
    category: category,
    available: available,
    servedFrom: servedFrom,
    servedUntil: servedUntil,
  );

  static RestaurantMenuItem? fromJson(Map<String, dynamic> j) {
    final name = (j['name_ko'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    // Archived items are kept in the database for the admin but never shown.
    if ((j['status'] as String?) == 'archived') return null;
    final image = (j['image_url'] as String?)?.trim();
    return RestaurantMenuItem(
      name: name,
      description: (j['description_ko'] as String?)?.trim(),
      priceKrw: (j['price_krw'] as num?)?.toInt(),
      imageUrl: (image != null && image.startsWith('https://')) ? image : null,
      available: (j['available'] as bool?) ?? true,
      representative: (j['representative'] as bool?) ?? false,
      recommended: (j['recommended'] as bool?) ?? false,
      category: (j['category'] as String?)?.trim(),
      servedFrom: clockMinutes(j['served_from']),
      servedUntil: clockMinutes(j['served_until']),
    );
  }
}

/// A published photo of a place (`restaurant_photos`): the cover or a
/// gallery picture uploaded by an admin.
@immutable
class RestaurantPhoto {
  const RestaurantPhoto({
    required this.url,
    required this.isCover,
    this.caption,
    this.sortOrder = 0,
  });

  final String url;
  final bool isCover;
  final String? caption;
  final int sortOrder;

  static RestaurantPhoto? fromJson(Map<String, dynamic> j) {
    final url = (j['url'] as String?)?.trim();
    if (url == null || !url.startsWith('https://')) return null;
    final caption = (j['caption'] as String?)?.trim();
    return RestaurantPhoto(
      url: url,
      isCover: j['kind'] == 'cover',
      caption: (caption == null || caption.isEmpty) ? null : caption,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
