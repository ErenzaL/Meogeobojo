import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/university.dart';
import '../models/verified_universities.dart';
import '../repositories/university_repository.dart';

/// Where this device remembers the campus choice (see
/// `universityAccountSyncProvider` for how it follows the account).
const selectedUniversityPrefsKey = 'selected_university_id';

/// Overridden in `main()` with the real instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

final universityRepositoryProvider = Provider<UniversityRepository>(
  (ref) => SupabaseUniversityRepository(Supabase.instance.client),
);

final universityListProvider = FutureProvider<List<University>>(
  (ref) => ref.watch(universityRepositoryProvider).fetchAll(),
);

/// The currently selected university. Everything university-specific
/// (restaurants, search, map) watches this, so a change invalidates it all.
final selectedUniversityProvider =
    AsyncNotifierProvider<SelectedUniversityNotifier, University>(
      SelectedUniversityNotifier.new,
    );

class SelectedUniversityNotifier extends AsyncNotifier<University> {
  @override
  Future<University> build() async {
    final all = await ref.watch(universityListProvider.future);
    final storedId = ref
        .read(sharedPreferencesProvider)
        .getString(selectedUniversityPrefsKey);
    return all.firstWhere(
      (u) => u.id == storedId,
      orElse: () => all.firstWhere(
        (u) => u.id == kDefaultUniversityId || u.nameKo == '순천향대학교',
        orElse: () => all.first,
      ),
    );
  }

  Future<void> select(University university) async {
    if (state.value == university) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(selectedUniversityPrefsKey, university.id);
    state = AsyncData(university);
  }
}
