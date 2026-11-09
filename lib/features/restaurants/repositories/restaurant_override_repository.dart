import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/restaurant_override.dart';

/// Admin-managed data for places (descriptions, prices, menus, visibility).
/// Read-only for the app; written by the admin dashboard.
abstract interface class RestaurantOverrideRepository {
  Future<Map<String, RestaurantOverride>> forPlaces(List<String> kakaoIds);
  Future<List<RestaurantMenuItem>> menus(String kakaoId);
}

class SupabaseRestaurantOverrideRepository
    implements RestaurantOverrideRepository {
  SupabaseRestaurantOverrideRepository(this._db);

  final SupabaseClient _db;

  /// Failures (for instance the admin migration not applied yet) must never
  /// break the app: it just shows Kakao data without enrichment.
  @override
  Future<Map<String, RestaurantOverride>> forPlaces(
    List<String> kakaoIds,
  ) async {
    if (kakaoIds.isEmpty) return const {};
    try {
      final rows = await _db
          .from('restaurant_overrides')
          .select(
            'kakao_place_id,visibility,description,price_min_krw,'
            'last_order_time,image_url',
          )
          .inFilter('kakao_place_id', kakaoIds)
          .timeout(const Duration(seconds: 10));
      final out = <String, RestaurantOverride>{};
      for (final r in rows) {
        final o = RestaurantOverride.fromJson(r);
        if (o != null) out[o.kakaoId] = o;
      }
      return out;
    } catch (e) {
      debugPrint('restaurant_overrides unavailable: ${e.runtimeType}');
      return const {};
    }
  }

  @override
  Future<List<RestaurantMenuItem>> menus(String kakaoId) async {
    try {
      final rows = await _db
          .from('restaurant_menus')
          .select()
          .eq('kakao_place_id', kakaoId)
          .order('sort_order')
          .timeout(const Duration(seconds: 10));
      return [for (final r in rows) ?RestaurantMenuItem.fromJson(r)];
    } catch (e) {
      debugPrint('restaurant_menus unavailable: ${e.runtimeType}');
      return const [];
    }
  }
}
