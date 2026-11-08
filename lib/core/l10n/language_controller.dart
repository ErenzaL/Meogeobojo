import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/university/providers/university_providers.dart'
    show sharedPreferencesProvider;
import 'app_language.dart';

const languagePrefsKey = 'app_language';

/// The active language plus whether the user chose it themselves.
/// [explicit] is false while we are only following the device language, which
/// lets an account's saved language be restored on a fresh install without
/// ever overriding a deliberate choice.
@immutable
class LanguageSetting {
  const LanguageSetting(this.language, {required this.explicit});

  final AppLanguage language;
  final bool explicit;

  @override
  bool operator ==(Object other) =>
      other is LanguageSetting &&
      other.language == language &&
      other.explicit == explicit;

  @override
  int get hashCode => Object.hash(language, explicit);
}

/// Device locales, overridable in tests.
final deviceLocalesProvider = Provider<List<Locale>>(
  (ref) => PlatformDispatcher.instance.locales,
);

final languageProvider = NotifierProvider<LanguageController, LanguageSetting>(
  LanguageController.new,
);

/// Convenience: just the language.
final appLanguageProvider = Provider<AppLanguage>(
  (ref) => ref.watch(languageProvider.select((s) => s.language)),
);

/// Local-only: works for guests, needs no network and no account.
class LanguageController extends Notifier<LanguageSetting> {
  @override
  LanguageSetting build() {
    final stored = AppLanguage.fromCode(
      ref.read(sharedPreferencesProvider).getString(languagePrefsKey),
    );
    if (stored != null) return LanguageSetting(stored, explicit: true);
    return LanguageSetting(
      AppLanguage.fromDevice(ref.read(deviceLocalesProvider)),
      explicit: false,
    );
  }

  /// A deliberate user choice. Applies immediately, persists afterwards.
  Future<void> select(AppLanguage language) async {
    state = LanguageSetting(language, explicit: true);
    await ref
        .read(sharedPreferencesProvider)
        .setString(languagePrefsKey, language.code);
  }

  /// Restores the language saved on the user's account. Only used when the
  /// user has not chosen one on this device.
  Future<void> adoptFromAccount(AppLanguage language) async {
    if (state.explicit) return;
    await select(language);
  }
}
