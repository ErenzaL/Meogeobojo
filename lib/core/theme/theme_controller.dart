import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/university/providers/university_providers.dart'
    show sharedPreferencesProvider;

const themeModePrefsKey = 'theme_mode';

/// The one place that decides Light / Dark / System. Stored on the device
/// only (guests can change it, no network, survives login / logout), and read
/// before the first frame because `main()` loads SharedPreferences first.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

String themeModeToStorage(ThemeMode m) => switch (m) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

/// Unknown / missing values fall back to System Default.
ThemeMode themeModeFromStorage(String? v) => switch (v) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => themeModeFromStorage(
    ref.read(sharedPreferencesProvider).getString(themeModePrefsKey),
  );

  /// Applies immediately; persists afterwards.
  Future<void> select(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString(themeModePrefsKey, themeModeToStorage(mode));
  }
}
