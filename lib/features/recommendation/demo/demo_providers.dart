import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../university/providers/university_providers.dart';
import 'demo_features.dart';
import 'demo_repository.dart';

/// Build flag for a demo build: `flutter build ... --dart-define=MEOGEOBOJO_DEMO=true`. A normal (student) release build
/// has no demo switch at all.
const kDemoBuild = bool.fromEnvironment('MEOGEOBOJO_DEMO');

/// Whether the demo switch exists in this build: demo builds and debug runs only.
final demoAvailableProvider = Provider<bool>((ref) => kDemoBuild || kDebugMode);

const _prefKey = 'recommendation_demo_mode';

/// The demo-mode switch. OFF by default; it can only be on when [demoAvailableProvider] is true.
class DemoModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    if (!ref.watch(demoAvailableProvider)) return false;
    try {
      return ref.read(sharedPreferencesProvider).getBool(_prefKey) ?? false;
    } catch (_) {
      return false; // no preferences available (a bare container): the switch is simply off
    }
  }

  Future<void> set(bool on) async {
    if (!ref.read(demoAvailableProvider)) return;
    state = on;
    try {
      await ref.read(sharedPreferencesProvider).setBool(_prefKey, on);
    } catch (_) {}
  }
}

final demoModeProvider = NotifierProvider<DemoModeNotifier, bool>(
  DemoModeNotifier.new,
);

final demoFeatureRepositoryProvider = Provider<DemoFeatureRepository>(
  (ref) => SupabaseDemoFeatureRepository(() => Supabase.instance.client),
);

/// The simulated features by Kakao place id. Empty unless demo mode is on, so nothing reads or applies them otherwise.
final demoFeaturesProvider = FutureProvider<Map<String, DemoFeature>>((
  ref,
) async {
  if (!ref.watch(demoModeProvider)) return const {};
  return ref.watch(demoFeatureRepositoryProvider).all();
});
