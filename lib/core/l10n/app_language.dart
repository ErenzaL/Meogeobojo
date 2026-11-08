import 'dart:ui';

/// The languages the interface ships in. [code] is the stable value stored
/// locally and in `profiles.preferred_language`.
enum AppLanguage {
  ko('ko', Locale('ko'), '한국어'),
  en('en', Locale('en'), 'English'),
  zhHans(
    'zh-Hans',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    '简体中文',
  );

  const AppLanguage(this.code, this.locale, this.nativeName);

  final String code;
  final Locale locale;

  /// Each language is always shown in its own script, never translated, so a
  /// user who cannot read the current UI language can still find theirs.
  final String nativeName;

  static const fallback = AppLanguage.ko;

  static AppLanguage? fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// Maps a device locale to a supported language, or null when unsupported
  /// (e.g. Japanese, or Traditional Chinese which is not shipped yet).
  static AppLanguage? fromLocale(Locale locale) {
    switch (locale.languageCode) {
      case 'ko':
        return AppLanguage.ko;
      case 'en':
        return AppLanguage.en;
      case 'zh':
        final script = locale.scriptCode;
        final country = locale.countryCode;
        final traditional =
            script == 'Hant' ||
            (script == null && const {'TW', 'HK', 'MO'}.contains(country));
        return traditional ? null : AppLanguage.zhHans;
    }
    return null;
  }

  /// First supported language in the device's preference order, else Korean.
  static AppLanguage fromDevice(List<Locale> deviceLocales) {
    for (final locale in deviceLocales) {
      final match = fromLocale(locale);
      if (match != null) return match;
    }
    return fallback;
  }
}
