import '../../../core/l10n/l10n.dart';
import '../../home/utils/home_text.dart';
import '../../preferences/models/user_preferences.dart';
import '../../preferences/screens/preference_labels.dart';
import '../models/chat_models.dart';
import '../models/chat_prefs.dart';

/// The words of a line the app wrote itself (not the AI), in the CURRENT app language.
String chatNoteText(AppLocalizations l, ChatNote n) => switch (n.kind) {
  NoteKind.foundCount => _foundText(l, n),
  NoteKind.aiBusy => l.chatAiBusy,
  NoteKind.networkError => l.chatErrNetwork,
  NoteKind.rateLimited => l.chatErrRateLimited(n.number ?? 30),
  NoteKind.genericError => l.chatErrGeneric,
  NoteKind.noMore => l.chatNoMore,
  NoteKind.hoursUnknown => l.chatHoursUnknown,
  NoteKind.menuOpened => l.chatMenuOpened(n.name ?? ''),
  NoteKind.menuNone => l.chatMenuNone,
  NoteKind.cheapest => l.chatCheapest(n.name ?? '', groupedKrw(n.price ?? 0)),
  NoteKind.closest => l.chatClosest(n.name ?? '', n.number ?? 1),
  NoteKind.noPriceData => l.chatNoPriceData,
  NoteKind.noneGeneric => l.chatNoneGeneric,
  NoteKind.noneRaiseBudget => l.chatNoneRaiseBudget,
  NoteKind.noneWiderDistance => l.chatNoneWiderDistance,
  NoteKind.noneAnyCuisine => l.chatNoneAnyCuisine,
  NoteKind.noneDropDish => l.chatNoneDropDish,
};

/// The one-sentence reason on a card: the AI's grounded sentence, otherwise a sentence written from the real data.
String chatReasonText(AppLocalizations l, ChatHit h) {
  final r = h.reason;
  if (r != null && r.isNotEmpty) return r;
  final walk = h.ranked.walkMinutes;
  for (final m in h.matched) {
    final price = m.priceKrw;
    if (price != null) return l.chatReasonMenu(m.name, groupedKrw(price), walk);
  }
  return l.chatReasonWalk(walk);
}

/// "N places found", but saying WHAT they were found for when the user asked for something specific, so even the line the
/// app writes itself (AI unreachable) answers the question instead of announcing a bare count.
String _foundText(AppLocalizations l, ChatNote n) {
  final count = n.number ?? 0;
  final criteria = n.prefs == null ? '' : chatCriteria(l, n.prefs!);
  return criteria.isEmpty
      ? l.chatFoundCount(count)
      : l.chatFoundFor(criteria, count);
}

/// What the user asked for, in a few words and the current app language ("국밥 · 8,000원 이하 · 도보 10분 이내").
/// At most four parts, the hard constraints first. Empty when nothing specific was asked.
String chatCriteria(AppLocalizations l, ChatPrefs p) {
  final dishes = <String>[];
  for (final w in [...p.dishKeywords, ...p.softKeywords]) {
    if (w.isNotEmpty && !dishes.contains(w)) dishes.add(w);
  }
  final parts = <String>[
    ...dishes.take(2),
    for (final c in p.cuisines)
      if (c != Cuisine.any) cuisineLabel(l, c),
    if (p.maxPriceKrw != null) l.chatCritMaxPrice(groupedKrw(p.maxPriceKrw!)),
    if (p.minPriceKrw != null) l.chatCritMinPrice(groupedKrw(p.minPriceKrw!)),
    if (p.maxWalkMinutes != null) l.chatCritWalk(p.maxWalkMinutes!),
    if (p.openNow) l.chatCritOpenNow,
    if (p.avoidSpicy) l.chatCritAvoidSpicy,
    if (p.cheap && p.maxPriceKrw == null) l.chatCritCheap,
    if (p.closer && p.maxWalkMinutes == null) l.chatCritCloser,
  ];
  return parts.take(4).join(' · ');
}
