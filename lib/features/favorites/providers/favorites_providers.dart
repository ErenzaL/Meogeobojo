import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../repositories/favorites_repository.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => SupabaseFavoritesRepository(Supabase.instance.client),
);

/// Ids of the signed-in user's favorites. Empty for guests.
final favoritesProvider = AsyncNotifierProvider<FavoritesNotifier, Set<String>>(
  FavoritesNotifier.new,
);

class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return <String>{};
    return ref.read(favoritesRepositoryProvider).fetchIds();
  }

  /// Saves [id] if it is not saved yet (used to resume a favorite a guest
  /// tried to add before signing in). Never un-saves.
  Future<void> addIfMissing(String id) async {
    final current = await future;
    if (current.contains(id)) return;
    await toggle(id);
  }

  /// Optimistically flips [id]; rolls back and rethrows on failure.
  Future<void> toggle(String id) async {
    final before = {...?state.value};
    final adding = !before.contains(id);
    state = AsyncData(adding ? {...before, id} : ({...before}..remove(id)));
    try {
      final repo = ref.read(favoritesRepositoryProvider);
      adding ? await repo.add(id) : await repo.remove(id);
    } catch (e) {
      debugPrint('favorite toggle failed: $e');
      state = AsyncData(before);
      rethrow;
    }
  }
}
