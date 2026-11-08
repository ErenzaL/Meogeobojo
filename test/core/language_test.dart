import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/l10n/app_language.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

Future<ProviderContainer> container({
  Map<String, Object> storage = const {},
  List<Locale> device = const [Locale('en', 'US')],
}) async {
  SharedPreferences.setMockInitialValues(storage);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      deviceLocalesProvider.overrideWithValue(device),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('AppLanguage.fromDevice', () {
    test('picks the first supported device language', () {
      expect(
        AppLanguage.fromDevice(const [Locale('ko', 'KR')]),
        AppLanguage.ko,
      );
      expect(
        AppLanguage.fromDevice(const [Locale('en', 'GB')]),
        AppLanguage.en,
      );
      expect(
        AppLanguage.fromDevice(const [Locale('fr'), Locale('en')]),
        AppLanguage.en,
        reason: 'unsupported entries are skipped in preference order',
      );
    });

    test('Simplified Chinese variants map to zh-Hans', () {
      expect(AppLanguage.fromDevice(const [Locale('zh')]), AppLanguage.zhHans);
      expect(
        AppLanguage.fromDevice(const [Locale('zh', 'CN')]),
        AppLanguage.zhHans,
      );
      expect(
        AppLanguage.fromDevice(const [
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        ]),
        AppLanguage.zhHans,
      );
    });

    test('Traditional Chinese and other languages fall back to Korean', () {
      expect(
        AppLanguage.fromDevice(const [Locale('zh', 'TW')]),
        AppLanguage.ko,
      );
      expect(
        AppLanguage.fromDevice(const [
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ]),
        AppLanguage.ko,
      );
      expect(AppLanguage.fromDevice(const [Locale('ja')]), AppLanguage.ko);
      expect(AppLanguage.fromDevice(const []), AppLanguage.ko);
    });

    test('codes round-trip', () {
      for (final l in AppLanguage.values) {
        expect(AppLanguage.fromCode(l.code), l);
      }
      expect(AppLanguage.fromCode('fr'), isNull);
    });
  });

  group('LanguageController', () {
    test('first launch follows the device language, not explicit', () async {
      final c = await container();
      final s = c.read(languageProvider);
      expect(s.language, AppLanguage.en);
      expect(s.explicit, isFalse);
    });

    test('unsupported device language falls back to Korean', () async {
      final c = await container(device: const [Locale('ja', 'JP')]);
      expect(c.read(languageProvider).language, AppLanguage.ko);
    });

    test('saved choice wins over the device and is explicit', () async {
      final c = await container(storage: {'app_language': 'zh-Hans'});
      final s = c.read(languageProvider);
      expect(s.language, AppLanguage.zhHans);
      expect(s.explicit, isTrue);
    });

    test('an invalid stored value is ignored', () async {
      final c = await container(storage: {'app_language': 'klingon'});
      expect(c.read(languageProvider).explicit, isFalse);
    });

    test(
      'select applies immediately and persists (guest, no account)',
      () async {
        final c = await container();
        final future = c
            .read(languageProvider.notifier)
            .select(AppLanguage.zhHans);
        expect(c.read(languageProvider).language, AppLanguage.zhHans);
        await future;
        expect(c.read(languageProvider).explicit, isTrue);
        expect(
          c.read(sharedPreferencesProvider).getString(languagePrefsKey),
          'zh-Hans',
        );
      },
    );

    test(
      'account language is adopted only when the user never chose one',
      () async {
        final fresh = await container();
        await fresh
            .read(languageProvider.notifier)
            .adoptFromAccount(AppLanguage.zhHans);
        expect(fresh.read(languageProvider).language, AppLanguage.zhHans);

        final chosen = await container(storage: {'app_language': 'ko'});
        await chosen
            .read(languageProvider.notifier)
            .adoptFromAccount(AppLanguage.en);
        expect(
          chosen.read(languageProvider).language,
          AppLanguage.ko,
          reason: 'an explicit local choice is never overridden by the account',
        );
      },
    );
  });
}
