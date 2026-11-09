import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../preferences/screens/preference_labels.dart';
import '../../recommendation/home_ranking.dart';

final _won = NumberFormat.decimalPattern();

/// "5,100" (no currency sign).
String groupedKrw(int v) => _won.format(v);

/// "₩5,100".
String wonSigned(int v) => '₩${_won.format(v)}';

String reasonText(AppLocalizations l10n, RecommendReason r, int walkMinutes) =>
    switch (r.kind) {
      ReasonKind.cuisine => l10n.homeReasonCuisine(
        cuisineLabel(l10n, r.cuisine!),
      ),
      ReasonKind.budget => l10n.homeReasonBudget,
      ReasonKind.closest => l10n.homeReasonClosest,
      ReasonKind.walk => l10n.homeReasonWalk(walkMinutes),
    };

/// The advantage line of an alternative; its own reason when it has none.
String comparisonText(
  AppLocalizations l10n,
  Comparison c,
  RankedRestaurant other,
) => switch (c.kind) {
  CompareKind.closer => l10n.homeCmpCloser(c.value),
  CompareKind.cheaper => l10n.homeCmpCheaper(c.value),
  CompareKind.higherRating => l10n.homeCmpRating,
  CompareKind.opensLater => l10n.homeCmpLater,
  CompareKind.none => reasonText(l10n, other.reason, other.walkMinutes),
};

/// "2시간 29분 여유" / "1시간 여유" / "45분 여유".
String slackText(AppLocalizations l10n, int slackMinutes) {
  final h = slackMinutes ~/ 60;
  final m = slackMinutes % 60;
  if (h > 0 && m > 0) return l10n.homeSlackHM(h, m);
  if (h > 0) return l10n.homeSlackH(h);
  return l10n.homeSlackM(m);
}
