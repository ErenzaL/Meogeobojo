import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../models/user_preferences.dart';
import '../repositories/preferences_repository.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => SupabasePreferencesRepository(Supabase.instance.client),
);

/// The signed-in user's saved preferences (null for guests or before the
/// first save). Rebuilt on account switch because it watches the user id.
final userPreferencesProvider =
    AsyncNotifierProvider<UserPreferencesNotifier, UserPreferences?>(
      UserPreferencesNotifier.new,
    );

class UserPreferencesNotifier extends AsyncNotifier<UserPreferences?> {
  @override
  Future<UserPreferences?> build() async {
    final userId = ref.watch(currentUserProvider.select((u) => u?.id));
    if (userId == null) return null;
    return ref.read(preferencesRepositoryProvider).fetch(userId);
  }

  void setSaved(UserPreferences prefs) => state = AsyncData(prefs);

  /// Forgets the answers in memory only (used by "start over"); the saved
  /// row stays in the database.
  void clearLocal() => state = const AsyncData(null);
}
