import 'package:supabase_flutter/supabase_flutter.dart';

/// Favorites are stored as the user's own `kakao_place_id` list. Only the
/// opaque place id is persisted, not Kakao's place data (see migration).
abstract interface class FavoritesRepository {
  Future<Set<String>> fetchIds();
  Future<void> add(String kakaoPlaceId);
  Future<void> remove(String kakaoPlaceId);
}

class SupabaseFavoritesRepository implements FavoritesRepository {
  SupabaseFavoritesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> fetchIds() async {
    final rows = await _client.from('favorites').select('kakao_place_id');
    return {for (final r in rows) r['kakao_place_id'] as String};
  }

  @override
  Future<void> add(String kakaoPlaceId) async {
    // user_id defaults to auth.uid() and is enforced by RLS.
    await _client
        .from('favorites')
        .upsert(
          {'kakao_place_id': kakaoPlaceId},
          onConflict: 'user_id,kakao_place_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> remove(String kakaoPlaceId) async {
    await _client.from('favorites').delete().eq('kakao_place_id', kakaoPlaceId);
  }
}
