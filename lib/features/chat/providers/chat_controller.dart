import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/language_controller.dart';
import '../../../core/utils/seoul_clock.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../university/providers/university_providers.dart';
import '../data/chat_api.dart';
import '../logic/chat_engine.dart';
import '../models/chat_models.dart';
import '../models/chat_prefs.dart';

/// How many restaurants are recommended when the user does not say.
const kChatDefaultCount = 3;

/// The longest message the chat accepts (the server enforces the same limit).
const kChatMaxMessageChars = 400;

final chatApiProvider = Provider<ChatApi>(
  (ref) => SupabaseChatApi(Supabase.instance.client),
);

typedef ChatContextLoader = Future<ChatSearchContext> Function();

/// Gathers what Home ranks with. Overridable so tests can search a fixed set of restaurants.
final chatContextLoaderProvider = Provider<ChatContextLoader>((ref) {
  return () async {
    await ref.read(selectedUniversityProvider.future);
    final pool = await ref.read(allNearbyRestaurantsProvider.future);
    // The budget is judged on the menus: wait for them (a failure just means "no prices known").
    Future<void> quietly(Future<Object?> f) async {
      try {
        await f;
      } catch (_) {}
    }

    await quietly(ref.read(nearbyMenusProvider.future));
    await quietly(ref.read(restaurantOverridesProvider.future));
    var reviews = const <String, double>{};
    try {
      reviews = await ref.read(reviewSignalsProvider.future);
    } catch (_) {}
    final origin = ref.read(originProvider);
    if (origin == null) throw StateError('no origin');
    return ChatSearchContext(
      pool: pool,
      insights: ref.read(restaurantInsightsProvider),
      menus: ref.read(nearbyMenusProvider).value ?? const {},
      lat: origin.latitude,
      lng: origin.longitude,
      nowMinutes: minutesOfDay(seoulWall(DateTime.now())),
      hiddenIds: ref.read(hiddenPlaceIdsProvider),
      visitedIds: ref.read(visitedPlaceIdsProvider),
      reviewSignals: reviews,
    );
  };
});

@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.busy = false,
    this.prefs,
    this.lastHits = const [],
    this.shown = const {},
    this.rejected = const {},
    this.hasMore = false,
    this.retryText,
    this.nextId = 1,
  });

  final List<ChatMessage> messages;
  final bool busy;

  /// What the conversation is looking for (the AI returns the full set each turn).
  final ChatPrefs? prefs;

  /// The restaurants of the last answer in the order they were shown ("the second one" = index 1).
  final List<ChatHit> lastHits;

  /// Restaurants shown in the current search (never repeated by "more").
  final Set<String> shown;

  /// Restaurants the user did not like (never recommended again in this conversation).
  final Set<String> rejected;
  final bool hasMore;

  /// The message to send again when an error bubble's retry is tapped.
  final String? retryText;
  final int nextId;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? busy,
    ChatPrefs? Function()? prefs,
    List<ChatHit>? lastHits,
    Set<String>? shown,
    Set<String>? rejected,
    bool? hasMore,
    String? Function()? retryText,
    int? nextId,
  }) => ChatState(
    messages: messages ?? this.messages,
    busy: busy ?? this.busy,
    prefs: prefs != null ? prefs() : this.prefs,
    lastHits: lastHits ?? this.lastHits,
    shown: shown ?? this.shown,
    rejected: rejected ?? this.rejected,
    hasMore: hasMore ?? this.hasMore,
    retryText: retryText != null ? retryText() : this.retryText,
    nextId: nextId ?? this.nextId,
  );
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    // A different campus: the earlier answers belong to other places.
    ref.listen(selectedUniversityProvider.select((a) => a.value?.id), (
      prev,
      next,
    ) {
      if (prev != null && prev != next) {
        state = state.copyWith(
          lastHits: const [],
          shown: const {},
          rejected: const {},
          hasMore: false,
          prefs: () => null,
        );
      }
    });
    return const ChatState();
  }

  /// A new conversation.
  void reset() => state = const ChatState();

  int _take(ChatState s) => s.nextId;

  void _add(ChatMessage Function(int id) make, {ChatState Function(ChatState)? also}) {
    var s = state;
    final msg = make(_take(s));
    s = s.copyWith(messages: [...s.messages, msg], nextId: s.nextId + 1);
    state = also != null ? also(s) : s;
  }

  void _assistant({
    String? text,
    List<ChatNote> notes = const [],
    List<ChatHit> hits = const [],
    Set<String> expand = const {},
    bool failed = false,
  }) => _add(
    (id) => ChatMessage(
      id: id,
      role: ChatRole.assistant,
      text: text,
      notes: notes,
      hits: hits,
      expand: expand,
      failed: failed,
    ),
  );

  /// The user sends [raw]. The answer is added to [ChatState.messages] when it is ready.
  Future<void> send(String raw) async {
    var text = raw.trim();
    if (text.isEmpty || state.busy) return;
    if (text.length > kChatMaxMessageChars) {
      text = text.substring(0, kChatMaxMessageChars);
    }
    _add(
      (id) => ChatMessage(id: id, role: ChatRole.user, text: text),
      also: (s) => s.copyWith(busy: true, retryText: () => null),
    );
    await _answer(text);
  }

  /// The error bubble's "try again": asks the same question again without repeating the user's bubble.
  Future<void> retry() async {
    final text = state.retryText;
    if (text == null || state.busy) return;
    final msgs = [...state.messages];
    if (msgs.isNotEmpty && msgs.last.failed) msgs.removeLast();
    state = state.copyWith(
      messages: msgs,
      busy: true,
      retryText: () => null,
    );
    await _answer(text);
  }

  /// "Show more" under the cards: three more of the same search, without asking the AI to interpret anything.
  Future<void> showMore() async {
    final prefs = state.prefs;
    if (state.busy || prefs == null) return;
    state = state.copyWith(busy: true);
    try {
      await _search(
        prefs: prefs,
        count: kChatDefaultCount,
        excludeShown: true,
        ai: null,
      );
    } on ChatApiException catch (e) {
      _fail(null, e);
    } catch (e) {
      _fail(null, const ChatApiException(ChatFailure.network));
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  // ---- one turn -----------------------------------------------------------------------------------------------

  Future<void> _answer(String text) async {
    try {
      final api = ref.read(chatApiProvider);
      Interpretation? ai;
      var aiDown = false;
      try {
        ai = await api.interpret(
          language: ref.read(appLanguageProvider).code,
          message: text,
          history: _history(),
          prefs: state.prefs,
          lastResult: [for (final h in state.lastHits) h.id],
          shownCount: state.shown.length,
        );
      } on ChatApiException catch (e) {
        if (!e.canFallBack) {
          _fail(text, e);
          return;
        }
        aiDown = true;
      }
      ai ??= _fallbackInterpretation(text);
      await _act(ai, aiDown: aiDown, original: text);
    } on ChatApiException catch (e) {
      _fail(text, e);
    } catch (e, st) {
      debugPrint('chat turn failed: ${e.runtimeType}\n$st');
      _fail(text, const ChatApiException(ChatFailure.network));
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  void _fail(String? text, ChatApiException e) {
    final note = switch (e.failure) {
      ChatFailure.rateLimited => ChatNote(
        NoteKind.rateLimited,
        number: e.retryAfterSeconds ?? 30,
      ),
      ChatFailure.network => const ChatNote(NoteKind.networkError),
      _ => const ChatNote(NoteKind.genericError),
    };
    _assistant(notes: [note], failed: true);
    state = state.copyWith(retryText: () => text);
  }

  List<({bool user, String text})> _history() {
    final out = <({bool user, String text})>[];
    for (final m in state.messages.where((m) => !m.failed)) {
      final names = [for (final h in m.hits) h.ranked.restaurant.name];
      final t = [
        if (m.text != null) m.text!,
        if (names.isNotEmpty) '[${names.join(', ')}]',
      ].join(' ');
      if (t.isNotEmpty) out.add((user: m.role == ChatRole.user, text: t));
    }
    // The server keeps the last six; the current message was just added and is sent separately.
    if (out.isNotEmpty && out.last.user) out.removeLast();
    return out.length > 6 ? out.sublist(out.length - 6) : out;
  }

  /// When the AI cannot be reached the chat still answers, with the same engine and the filters the user set in the
  /// app (or the earlier conversation). Only a count and "more / another" can be read without the AI.
  Interpretation _fallbackInterpretation(String text) {
    final more = RegExp(
      r'more|another|else|different|다른|더 |말고|更多|别的|其他|换',
      caseSensitive: false,
    ).hasMatch(text);
    final n = RegExp(
      r'(?<!\d)(\d{1,2})(?!\d)\s*(곳|개|군데|places?|restaurants?|spots?|家|个|间)',
      caseSensitive: false,
    ).firstMatch(text);
    final count = n == null ? null : int.parse(n.group(1)!).clamp(1, 10);
    final prefs =
        state.prefs ?? ChatPrefs.fromConditions(ref.read(conditionsProvider));
    return Interpretation(
      intent: more && state.prefs != null ? ChatIntent.more : ChatIntent.search,
      count: count,
      prefs: prefs,
    );
  }

  Future<void> _act(
    Interpretation ai, {
    required bool aiDown,
    required String original,
  }) async {
    switch (ai.intent) {
      case ChatIntent.chitchat || ChatIntent.clarify:
        if (ai.reply.isEmpty) {
          _assistant(notes: const [ChatNote(NoteKind.genericError)]);
        } else {
          _assistant(text: ai.reply);
        }
      case ChatIntent.menu:
        _showMenu(ai);
      case ChatIntent.compare:
        _compare(ai);
      case ChatIntent.search || ChatIntent.more || ChatIntent.different:
        var rejected = state.rejected;
        if (ai.intent == ChatIntent.different || ai.rejectAll) {
          rejected = {...rejected, ..._idsAt(ai.rejectPositions, all: true)};
        } else if (ai.rejectPositions.isNotEmpty) {
          rejected = {...rejected, ..._idsAt(ai.rejectPositions)};
        }
        final carry =
            (ai.intent == ChatIntent.more || ai.intent == ChatIntent.different) &&
            ai.prefs.isEmpty &&
            state.prefs != null;
        final prefs = carry ? state.prefs! : ai.prefs;
        state = state.copyWith(rejected: rejected);
        await _search(
          prefs: prefs,
          count: (ai.count ?? kChatDefaultCount).clamp(1, 10),
          excludeShown: ai.intent == ChatIntent.more ||
              ai.intent == ChatIntent.different,
          ai: aiDown ? false : true,
        );
    }
  }

  Set<String> _idsAt(List<int> positions, {bool all = false}) {
    final hits = state.lastHits;
    if (all && positions.isEmpty) return {for (final h in hits) h.id};
    return {
      for (final p in positions)
        if (p >= 1 && p <= hits.length) hits[p - 1].id,
    };
  }

  // ---- menu / compare (answered from the real data of the last result) -----------------------------------------

  void _showMenu(Interpretation ai) {
    final hits = state.lastHits;
    if (hits.isEmpty) {
      _assistant(notes: const [ChatNote(NoteKind.menuNone)]);
      return;
    }
    final picked = [
      for (final p in ai.targetPositions)
        if (p >= 1 && p <= hits.length) hits[p - 1],
    ];
    final target = picked.isEmpty ? [hits.first] : picked;
    _assistant(
      notes: [
        if (target.length == 1)
          ChatNote(NoteKind.menuOpened, name: target.first.ranked.restaurant.name),
      ],
      hits: target,
      expand: {for (final h in target) h.id},
    );
  }

  void _compare(Interpretation ai) {
    final hits = state.lastHits;
    if (hits.isEmpty) {
      _assistant(notes: const [ChatNote(NoteKind.menuNone)]);
      return;
    }
    if (ai.compareBy == 'distance') {
      final best = hits.reduce(
        (a, b) => a.ranked.meters <= b.ranked.meters ? a : b,
      );
      _assistant(
        notes: [
          ChatNote(
            NoteKind.closest,
            name: best.ranked.restaurant.name,
            number: best.ranked.walkMinutes,
          ),
        ],
        hits: [best],
      );
      return;
    }
    ChatHit? best;
    int? bestPrice;
    for (final h in hits) {
      final p = cheapestOffered(h.ranked);
      if (p != null && (bestPrice == null || p < bestPrice)) {
        best = h;
        bestPrice = p;
      }
    }
    if (best == null) {
      _assistant(notes: const [ChatNote(NoteKind.noPriceData)]);
      return;
    }
    _assistant(
      notes: [
        ChatNote(
          NoteKind.cheapest,
          name: best.ranked.restaurant.name,
          price: bestPrice,
        ),
      ],
      hits: [best],
    );
  }

  // ---- search + explanation ------------------------------------------------------------------------------------

  /// [ai]: true = the AI is up (ask it to word the answer), false = it was unreachable (templates + a notice),
  /// null = a "show more" tap (word it with the AI when reachable, but never show a notice).
  Future<void> _search({
    required ChatPrefs prefs,
    required int count,
    required bool excludeShown,
    required bool? ai,
  }) async {
    final ctx = await ref.read(chatContextLoaderProvider)();
    final exclude = {...state.rejected, if (excludeShown) ...state.shown};
    final result = searchForChat(prefs, ctx, exclude: exclude);
    final page = result.hits.take(count).toList();
    final remaining = result.hits.length - page.length;

    if (page.isEmpty) {
      final noMore = excludeShown && state.shown.isNotEmpty;
      _assistant(
        notes: [
          if (ai == false) const ChatNote(NoteKind.aiBusy),
          ChatNote(
            noMore
                ? NoteKind.noMore
                : suggestAdjustment(prefs, ctx, exclude: exclude),
          ),
        ],
      );
      state = state.copyWith(
        prefs: () => prefs,
        hasMore: false,
        lastHits: noMore ? state.lastHits : const [],
      );
      return;
    }

    Explanation? explanation;
    var aiFailed = ai == false;
    if (ai != false) {
      try {
        explanation = await ref.read(chatApiProvider).explain(
          language: ref.read(appLanguageProvider).code,
          items: [
            for (final h in page)
              ExplainItem(
                id: h.id,
                walkMinutes: h.ranked.walkMinutes,
                openStatus: openStatusWire(h.ranked, ctx.nowMinutes),
                matchedMenus: [for (final m in h.matched) m.name],
              ),
          ],
          prefs: prefs,
          hasMore: remaining > 0,
        );
      } on ChatApiException catch (e) {
        if (!e.canFallBack) rethrow;
        aiFailed = true;
      }
    }

    // Only restaurants the server confirmed as published are shown.
    final confirmed = explanation?.ids;
    final shownHits = [
      for (final h in page)
        if (confirmed == null || confirmed.contains(h.id))
          h.withReason(explanation?.reasons[h.id]),
    ];
    if (shownHits.isEmpty) {
      _assistant(notes: const [ChatNote(NoteKind.noneGeneric)]);
      return;
    }
    final text = explanation?.message;
    _assistant(
      text: text,
      hits: shownHits,
      notes: [
        if (aiFailed && ai != null) const ChatNote(NoteKind.aiBusy),
        if (text == null)
          ChatNote(NoteKind.foundCount, number: shownHits.length),
        if (prefs.openNow && result.hoursIgnored)
          const ChatNote(NoteKind.hoursUnknown),
      ],
    );
    state = state.copyWith(
      prefs: () => prefs,
      lastHits: shownHits,
      shown: {...(excludeShown ? state.shown : <String>{}), for (final h in shownHits) h.id},
      hasMore: remaining > 0,
    );
  }
}

/// The cheapest dish the place offers (drinks and add-on sides do not count at a restaurant; a cafe's drinks do).
int? cheapestOffered(RankedRestaurant r) {
  final cafe = r.restaurant.categoryGroupCode == 'CE7';
  int? best;
  for (final m in r.insight.menus) {
    final price = m.priceKrw;
    if (price == null || !m.available || !m.isOffered(cafe: cafe)) continue;
    if (best == null || price < best) best = price;
  }
  return best;
}

/// The random source for the mascot (overridable so tests are deterministic).
final chatRandomProvider = Provider<Random>((ref) => Random());

/// Which mascot the floating button shows: a random one from the mascot folder when the app opens, and a different one
/// every time the chat goes back to the button.
class ChatMascotController extends Notifier<String> {
  @override
  String build() => _pick(null);

  String _pick(String? not) {
    final pool = [
      for (final a in AppAssets.chatMascots)
        if (a != not) a,
    ];
    return pool[ref.read(chatRandomProvider).nextInt(pool.length)];
  }

  void reroll() => state = _pick(state);
}

final chatMascotProvider = NotifierProvider<ChatMascotController, String>(
  ChatMascotController.new,
);

/// The chat panel: shown or minimized to the mascot. Once opened it stays mounted so the scroll position, the draft
/// and the open menus survive a minimize.
@immutable
class ChatPanelState {
  const ChatPanelState({this.open = false, this.everOpened = false});

  final bool open;
  final bool everOpened;
}

class ChatPanelController extends Notifier<ChatPanelState> {
  @override
  ChatPanelState build() => const ChatPanelState();

  void open() => state = const ChatPanelState(open: true, everOpened: true);

  /// Back to the mascot; the conversation is kept.
  void minimize() {
    ref.read(chatMascotProvider.notifier).reroll();
    state = ChatPanelState(open: false, everOpened: state.everOpened);
  }

  /// Back to the mascot and forget the conversation.
  void closeAndClear() {
    ref.read(chatControllerProvider.notifier).reset();
    ref.read(chatMascotProvider.notifier).reroll();
    state = ChatPanelState(open: false, everOpened: state.everOpened);
  }
}

final chatPanelProvider = NotifierProvider<ChatPanelController, ChatPanelState>(
  ChatPanelController.new,
);
