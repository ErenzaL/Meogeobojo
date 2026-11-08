import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

abstract class ProfileRepository {
  /// Returns the signed-in user's profile, creating an empty one if the
  /// account predates the signup trigger. Never overwrites an existing row.
  Future<UserProfile> loadOrCreate(User user);

  /// Saves the user's chosen app nickname through `set_nickname()`, which
  /// validates it on the server and marks it as custom. The user is always
  /// auth.uid(); no id is sent.
  Future<UserProfile> setNickname(String nickname);

  /// Best-effort account sync of the interface language.
  Future<void> updateLanguage(String userId, String languageCode);
}

const _maxNicknameLength = 30;

/// First usable display name Supabase got from the provider (Kakao puts it in
/// `name` / `full_name`). Email sign-ups have none, and we do not derive one
/// from the email address.
String? nicknameFromMetadata(Map<String, dynamic>? metadata) {
  if (metadata == null) return null;
  for (final key in const [
    'nickname',
    'name',
    'full_name',
    'preferred_username',
  ]) {
    final v = metadata[key];
    if (v is String && v.trim().isNotEmpty) {
      final t = v.trim();
      return t.length > _maxNicknameLength
          ? t.substring(0, _maxNicknameLength)
          : t;
    }
  }
  return null;
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._db);

  final SupabaseClient _db;

  Future<Map<String, dynamic>?> _select(String id) =>
      _db.from('profiles').select().eq('id', id).maybeSingle();

  @override
  Future<UserProfile> loadOrCreate(User user) async {
    final existing = await _select(user.id);
    if (existing != null) return UserProfile.fromJson(existing);

    // ON CONFLICT DO NOTHING: safe if the signup trigger (or another device)
    // creates the row between our select and insert. RLS requires id = uid.
    await _db
        .from('profiles')
        .upsert(
          {'id': user.id, 'nickname': nicknameFromMetadata(user.userMetadata)},
          onConflict: 'id',
          ignoreDuplicates: true,
        );
    final created = await _select(user.id);
    if (created == null) {
      throw const PostgrestException(message: 'profile row missing');
    }
    return UserProfile.fromJson(created);
  }

  @override
  Future<UserProfile> setNickname(String nickname) async {
    final row = await _db
        .rpc<Map<String, dynamic>>(
          'set_nickname',
          params: {'p_nickname': nickname},
        )
        .timeout(const Duration(seconds: 20));
    return UserProfile.fromJson(row);
  }

  @override
  Future<void> updateLanguage(String userId, String languageCode) async {
    await _db
        .from('profiles')
        .update({'preferred_language': languageCode})
        .eq('id', userId);
  }
}
