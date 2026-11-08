import 'dart:ui';

import '../../../l10n/app_localizations.dart';
import 'university.dart';

extension UniversityDisplay on University {
  /// Name for the interface language. Korean is the source name; English uses
  /// the English name we hold. We have no verified Chinese names, so Chinese
  /// shows the Korean name rather than an invented translation.
  String displayName(Locale locale) {
    if (locale.languageCode == 'en' && (nameEn?.isNotEmpty ?? false)) {
      return nameEn!;
    }
    return nameKo;
  }
}

/// City names in the university data are Korean; the two cities we ship have
/// standard English / Chinese names. Anything else is shown as stored.
String cityLabel(AppLocalizations l10n, String city) => switch (city) {
  '아산' => l10n.cityAsan,
  '천안' => l10n.cityCheonan,
  _ => city,
};
