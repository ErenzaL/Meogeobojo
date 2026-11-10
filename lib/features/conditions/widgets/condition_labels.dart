import 'package:flutter/material.dart' show IconData, Icons;

import '../../../l10n/app_localizations.dart';
import '../../preferences/models/user_preferences.dart';
import '../models/conditions.dart';

/// Short labels for the Home filter chips (the sheet has its own longer ones).
String partyLabelOf(AppLocalizations l10n, CompanionType t) => switch (t) {
  CompanionType.solo => l10n.companionSolo,
  CompanionType.friends => l10n.condPartyFew,
  _ => l10n.companionGroup,
};

String needLabelOf(AppLocalizations l10n, Need n) => switch (n) {
  Need.quietTalk => l10n.condNeedQuiet,
  Need.quickMeal => l10n.condNeedQuick,
  Need.generousPortion => l10n.condNeedGenerous,
};

String sortLabelOf(AppLocalizations l10n, SortMode s) => switch (s) {
  SortMode.recommended => l10n.condSortRecommended,
  SortMode.distance => l10n.categorySortDistance,
  SortMode.price => l10n.condSortPrice,
  SortMode.rating => l10n.condSortRating,
};

/// How many 운영·편의 settings differ from the defaults.
int opsActiveCount(Conditions c) =>
    (c.openNowOnly != Conditions.defaults.openNowOnly ? 1 : 0) +
    c.amenities.length;

String amenityLabelOf(AppLocalizations l10n, Amenity a) => switch (a) {
  Amenity.noBreakTime => l10n.condAmenityNoBreak,
  Amenity.parking => l10n.condAmenityParking,
  Amenity.localCurrency => l10n.condAmenityLocalCurrency,
  Amenity.fastTurnover => l10n.condAmenityFast,
  Amenity.takeout => l10n.condAmenityTakeout,
  Amenity.openLate => l10n.condAmenityLate,
};

IconData amenityIconOf(Amenity a) => switch (a) {
  Amenity.noBreakTime => Icons.schedule_rounded,
  Amenity.parking => Icons.local_parking_rounded,
  Amenity.localCurrency => Icons.payments_outlined,
  Amenity.fastTurnover => Icons.bolt_rounded,
  Amenity.takeout => Icons.takeout_dining_outlined,
  Amenity.openLate => Icons.dark_mode_outlined,
};
