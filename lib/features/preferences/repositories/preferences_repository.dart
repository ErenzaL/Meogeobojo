import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/models/user_profile.dart';
import '../models/user_preferences.dart';

abstract class PreferencesRepository {
  /// The signed-in user's saved preferences, or null if none yet.
  Future<UserPreferences?> fetch(String userId);

  /// Saves preferences AND marks onboarding complete in one database
  /// transaction (`save_user_preferences`). Throws on any failure, in which
  /// case nothing was written.
  Future<UserProfile> save(UserPreferences preferences);
}

class SupabasePreferencesRepository implements PreferencesRepository {
  SupabasePreferencesRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<UserPreferences?> fetch(String userId) async {
    final row = await _db
        .from('user_preferences')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : UserPreferences.fromJson(row);
  }

  @override
  Future<UserProfile> save(UserPreferences preferences) async {
    final res = await _db
        .rpc<Map<String, dynamic>>(
          'save_user_preferences',
          params: preferences.toRpcParams(),
        )
        .timeout(const Duration(seconds: 20));
    return UserProfile.fromJson(res);
  }
}
