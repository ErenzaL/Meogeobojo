import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/restaurant_override.dart';

/// Admin-managed data for places (descriptions, prices, menus, visibility).
/// Read-only for the app; written by the admin dashboard.
abstract interface class RestaurantOverrideRepository {
  Future<Map<String, RestaurantOverride>> forPlaces(List<String> kakaoIds);
  Future<List<RestaurantMenuItem>> menus(String kakaoId);

  /// Published photos (cover first, then the gallery in order).
  Future<List<RestaurantPhoto>> photos(String kakaoId);
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
            'last_order_time,image_url,name_ko,address,phone,featured,display_order',
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

  /// RLS only lets the public read PUBLISHED photos of PUBLISHED places, so
  /// no draft or archived picture can reach the app. A failure (for instance
  /// the photo table not being deployed yet) just means "no photos".
  @override
  Future<List<RestaurantPhoto>> photos(String kakaoId) async {
    try {
      final rows = await _db
          .from('restaurant_photos')
          .select(
            'url,caption,kind,sort_order,'
            'restaurant_overrides!inner(kakao_place_id)',
          )
          .eq('restaurant_overrides.kakao_place_id', kakaoId)
          .eq('status', 'published')
          .order('sort_order')
          .timeout(const Duration(seconds: 10));
      final out = [for (final r in rows) ?RestaurantPhoto.fromJson(r)];
      // The cover first; the rest keep their admin-chosen order.
      out.sort((a, b) {
        if (a.isCover != b.isCover) return a.isCover ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
      return out;
    } catch (e) {
      debugPrint('restaurant_photos unavailable: ${e.runtimeType}');
      return const [];
    }
  }
}
