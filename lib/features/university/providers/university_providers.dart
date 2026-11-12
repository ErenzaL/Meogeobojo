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

/// Which schools the app has data for ([isSupportedUniversity]: 순천향대학교
/// only, for now). The others are listed as "준비 중" and never selected.
final supportedUniversityProvider = Provider<bool Function(University)>(
  (_) => isSupportedUniversity,
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
    final sp = ref.read(sharedPreferencesProvider);
    final storedId = sp.getString(selectedUniversityPrefsKey);
    final supported = ref.read(supportedUniversityProvider);
    final fallback = all.firstWhere(
      (u) => u.id == kDefaultUniversityId || u.nameKo == '순천향대학교',
      orElse: () => all.firstWhere(supported, orElse: () => all.first),
    );
    final stored = all.where((u) => u.id == storedId).firstOrNull;
    if (stored == null) return fallback;
    if (supported(stored)) return stored;
    // Saved before only 순천향대 was offered: switch, and say so once.
    await sp.setString(selectedUniversityPrefsKey, fallback.id);
    ref.read(universitySwitchNoticeProvider.notifier).show(stored);
    return fallback;
  }

  /// A school that is still "준비 중" is never selected.
  Future<void> select(University university) async {
    if (!ref.read(supportedUniversityProvider)(university)) return;
    if (state.value == university) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(selectedUniversityPrefsKey, university.id);
    state = AsyncData(university);
  }
}

/// The unsupported school a saved choice pointed to, until the user has seen
/// that the app switched to 순천향대학교.
final universitySwitchNoticeProvider =
    NotifierProvider<UniversitySwitchNotice, University?>(
      UniversitySwitchNotice.new,
    );

class UniversitySwitchNotice extends Notifier<University?> {
  @override
  University? build() => null;

  void show(University from) => state = from;

  void dismiss() => state = null;
}
