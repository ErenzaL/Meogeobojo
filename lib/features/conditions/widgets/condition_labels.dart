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
