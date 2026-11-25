import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/embed/embed_mode.dart';
import 'package:meogeobojo/features/chat/data/chat_api.dart';
import 'package:meogeobojo/features/chat/data/chat_history.dart';
import 'package:meogeobojo/features/chat/models/chat_models.dart';
import 'package:meogeobojo/features/chat/models/chat_prefs.dart';
import 'package:meogeobojo/features/chat/providers/chat_controller.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../../support/harness.dart';
import 'chat_fixtures.dart';
import 'fake_chat_api.dart';

/// 챗봇 기록: every typed question is handed to the history logger together with what the chat answered.
Future<(Harness, FakeChatApi, List<ChatTurnLog>)> setup({
  String language = 'en',
  ChatHistoryLogger? logger,
}) async {
  final fake = FakeChatApi();
  final turns = <ChatTurnLog>[];
  final h = await buildHarness(
    storage: {'app_language': language},
    extraOverrides: [
      chatApiProvider.overrideWithValue(fake),
      chatContextLoaderProvider.overrideWithValue(
        () async => Fixture().context(),
      ),
      chatHistoryLoggerProvider.overrideWithValue(logger ?? turns.add),
    ],
  );
  return (h, fake, turns);
}

ChatController ctl(Harness h) =>
    h.container.read(chatControllerProvider.notifier);
ChatMessage lastAssistant(Harness h) => h.container
    .read(chatControllerProvider)
    .messages
    .lastWhere((m) => m.role == ChatRole.assistant);

void main() {
  test('an answered question is recorded with the restaurants shown, their reasons and the AI sentence', () async {
    final (h, _, turns) = await setup(language: 'ko');
    await ctl(h).send('  뭐 먹지?  ');
    final t = turns.single;
    expect(t.question, '뭐 먹지?');
    expect(t.language, 'ko');
    expect(t.intent, 'search');
    expect(t.outcome, 'answered');
    expect(t.aiStatus, 'ok');
    expect(t.reply, 'Here you go.');
    expect(t.failure, isNull);
    expect(t.restaurants, hasLength(3));
    final shown = lastAssistant(h).hits;
    expect(t.restaurants.first, {
      'id': shown.first.id,
      'name': shown.first.ranked.restaurant.name,
      'reason': 'Reason for ${shown.first.id}',
    });
    expect(
      [for (final r in t.restaurants) r['id']],
      [for (final x in shown) x.id],
      reason: 'the same restaurants, in the order they were shown',
    );
  });

  test('the conditions the AI understood are recorded; nothing asked records none', () async {
    final (h, api, turns) = await setup();
    await ctl(h).send('anything');
    expect(turns.single.prefs, isNull);
    api.onInterpret = (_, _) => const Interpretation(
      intent: ChatIntent.search,
      prefs: ChatPrefs(dishKeywords: ['국밥'], maxPriceKrw: 10000),
    );
    await ctl(h).send('soup under 10000');
    // the same {hard, soft} shape the assistant exchanges, so the admin page reads one format
    final hard = turns.last.prefs?['hard'] as Map<String, dynamic>;
    expect(hard['max_price_krw'], 10000);
    expect(hard['dish_keywords'], ['국밥']);
  });

  test('nothing matched: the outcome is no_result and the app-written line is kept by its kind', () async {
    final (h, api, turns) = await setup();
    api.onInterpret = (_, _) => const Interpretation(
      intent: ChatIntent.search,
      prefs: ChatPrefs(maxPriceKrw: 1000),
    );
    await ctl(h).send('under 1000 won');
    final t = turns.single;
    expect(lastAssistant(h).hits, isEmpty);
    expect(t.outcome, 'no_result');
    expect(t.restaurants, isEmpty);
    expect(t.reply, isNull);
    expect(t.notes, contains(NoteKind.noneRaiseBudget.name));
  });

  test('the AI understood but could not word the answer: status busy, cards without AI reasons', () async {
    final (h, api, turns) = await setup();
    api.explainError = const ChatApiException(ChatFailure.quota);
    await ctl(h).send('recommend');
    final t = turns.single;
    expect(t.outcome, 'answered');
    expect(t.aiStatus, 'busy');
    expect(t.reply, isNull);
    expect(t.notes, containsAll([NoteKind.aiBusy.name, NoteKind.foundCount.name]));
    expect(t.restaurants, hasLength(3));
    expect(t.restaurants.every((r) => !r.containsKey('reason')), isTrue);
  });

  test('the AI was unreachable and the app answered with its own engine: status down', () async {
    final (h, api, turns) = await setup();
    api.interpretError = const ChatApiException(ChatFailure.unavailable);
    await ctl(h).send('show me 2 places');
    final t = turns.single;
    expect(t.aiStatus, 'down');
    expect(t.outcome, 'answered');
    expect(t.restaurants, hasLength(2));
  });

  test('a failed turn is recorded as an error with the kind of the error bubble', () async {
    final (h, api, turns) = await setup();
    api.interpretError = const ChatApiException(
      ChatFailure.rateLimited,
      retryAfterSeconds: 42,
    );
    await ctl(h).send('hello');
    final t = turns.single;
    expect(t.outcome, 'error');
    expect(t.failure, NoteKind.rateLimited.name);
    expect(t.intent, isNull);
    expect(t.aiStatus, 'down');
    expect(t.restaurants, isEmpty);
  });

  test('small talk is recorded as chitchat with the reply', () async {
    final (h, api, turns) = await setup();
    api.onInterpret = (_, _) => const Interpretation(
      intent: ChatIntent.chitchat,
      reply: 'You\'re welcome!',
    );
    await ctl(h).send('thanks');
    expect(turns.single.outcome, 'chitchat');
    expect(turns.single.reply, 'You\'re welcome!');
  });

  test('one row per typed question; the "show more" button is not a question', () async {
    final (h, _, turns) = await setup();
    await ctl(h).send('recommend');
    await ctl(h).showMore();
    expect(turns, hasLength(1));
    await ctl(h).send('something else');
    expect(turns, hasLength(2));
  });

  test('a broken logger never disturbs the chat', () async {
    final (h, _, _) = await setup(
      logger: (_) => throw StateError('history is down'),
    );
    await ctl(h).send('recommend');
    final m = lastAssistant(h);
    expect(m.failed, isFalse);
    expect(m.hits, hasLength(3));
    expect(h.container.read(chatControllerProvider).busy, isFalse);
  });

  test('the phone preview embedded in the website records nothing', () {
    var touchedStorage = false;
    final c = ProviderContainer(
      overrides: [
        embeddedPreviewProvider.overrideWithValue(true),
        sharedPreferencesProvider.overrideWith((ref) {
          touchedStorage = true;
          throw StateError('the preview must not read the device id');
        }),
      ],
    );
    addTearDown(c.dispose);
    c.read(chatHistoryLoggerProvider)(
      const ChatTurnLog(
        language: 'ko',
        question: 'q',
        outcome: 'answered',
        aiStatus: 'ok',
      ),
    );
    expect(touchedStorage, isFalse);
  });

  test('the database call carries every field under the names the function expects, and no account id', () {
    const t = ChatTurnLog(
      language: 'zh-Hans',
      question: '想吃热的',
      intent: 'search',
      prefs: {'max_price_krw': 8000},
      outcome: 'answered',
      aiStatus: 'busy',
      reply: null,
      restaurants: [
        {'id': '111', 'name': '든든 국밥'},
      ],
      notes: ['aiBusy', 'foundCount'],
    );
    final p = t.toRpc('c8000000-0000-4000-8000-00000000c001');
    expect(p.keys.toSet(), {
      'p_client_id',
      'p_language',
      'p_question',
      'p_intent',
      'p_prefs',
      'p_outcome',
      'p_ai_status',
      'p_reply',
      'p_restaurants',
      'p_failure',
      'p_notes',
    });
    expect(p['p_client_id'], 'c8000000-0000-4000-8000-00000000c001');
    expect(p['p_restaurants'], [
      {'id': '111', 'name': '든든 국밥'},
    ]);
    expect(p.keys.any((k) => k.contains('user')), isFalse);
  });
}
