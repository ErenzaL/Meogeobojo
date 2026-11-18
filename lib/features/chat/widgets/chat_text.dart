import '../../../core/l10n/l10n.dart';
import '../../home/utils/home_text.dart';
import '../models/chat_models.dart';

/// The words of a line the app wrote itself (not the AI), in the CURRENT app language.
String chatNoteText(AppLocalizations l, ChatNote n) => switch (n.kind) {
  NoteKind.foundCount => l.chatFoundCount(n.number ?? 0),
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
