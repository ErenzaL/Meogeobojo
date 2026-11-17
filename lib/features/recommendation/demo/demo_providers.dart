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

/// Every stored feature row by Kakao place id (real and simulated). Consumers keep only what applies with
/// [featuresForMode]; the simulated rows must never reach the recommendation while demo mode is off.
final demoFeaturesProvider = FutureProvider<Map<String, DemoFeature>>(
  (ref) => ref.watch(demoFeatureRepositoryProvider).all(),
);

/// The rows that apply: the REAL ones always, the simulated ones only while demo mode is on.
Map<String, DemoFeature> featuresForMode(
  Map<String, DemoFeature> stored,
  bool demoOn,
) => {
  for (final e in stored.entries)
    if (!e.value.demo || demoOn) e.key: e.value,
};
