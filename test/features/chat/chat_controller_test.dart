import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/chat/data/chat_api.dart';
import 'package:meogeobojo/features/chat/models/chat_models.dart';
import 'package:meogeobojo/features/chat/models/chat_prefs.dart';
import 'package:meogeobojo/features/chat/providers/chat_controller.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/conditions/providers/conditions_providers.dart';

import '../../support/harness.dart';
import 'chat_fixtures.dart';
import 'fake_chat_api.dart';

Future<(Harness, FakeChatApi)> setup({
  FakeChatApi? api,
  String language = 'en',
}) async {
  final fake = api ?? FakeChatApi();
  final h = await buildHarness(
    storage: {'app_language': language},
    extraOverrides: [
      chatApiProvider.overrideWithValue(fake),
      chatContextLoaderProvider.overrideWithValue(
        () async => Fixture().context(),
      ),
    ],
  );
  return (h, fake);
}

ChatState chat(Harness h) => h.container.read(chatControllerProvider);
ChatController ctl(Harness h) =>
    h.container.read(chatControllerProvider.notifier);
ChatMessage lastAssistant(Harness h) =>
    chat(h).messages.lastWhere((m) => m.role == ChatRole.assistant);
List<String> hitIds(ChatMessage m) => [for (final x in m.hits) x.id];

void main() {
  test('a plain request answers with THREE restaurants, worded by the AI, and sends the app language', () async {
    final (h, api) = await setup(language: 'en');
    await ctl(h).send('recommend something good');
    final m = lastAssistant(h);
    expect(m.hits, hasLength(3));
    expect(m.text, 'Here you go.');
    expect(m.hits.first.reason, startsWith('Reason for'));
    expect(api.interprets.single.language, 'en');
    expect(api.explains.single, hasLength(3));
    expect(chat(h).busy, isFalse);
  });

  test('the language follows the app: Korean app, Chinese app', () async {
    for (final (code, want) in [('ko', 'ko'), ('zh-Hans', 'zh-Hans')]) {
      final (h, api) = await setup(language: code);
      await ctl(h).send('hi');
      expect(api.interprets.single.language, want);
    }
  });

  test('"show me 5" gives five, "your best pick" one, and never more than exist', () async {
    final (h, api) = await setup();
    api.onInterpret = (msg, _) => Interpretation(
      intent: ChatIntent.search,
      count: msg.contains('best') ? 1 : (msg.contains('10') ? 10 : 5),
    );
    await ctl(h).send('show me 5');
    expect(lastAssistant(h).hits, hasLength(5));
    await ctl(h).send('your best pick');
    expect(lastAssistant(h).hits, hasLength(1));
    await ctl(h).send('10 places');
    // only five restaurants are eligible: nothing is invented to reach ten
    expect(lastAssistant(h).hits, hasLength(5));
  });

  test('"show more" never repeats, and runs out honestly', () async {
    final (h, api) = await setup();
    await ctl(h).send('something');
    final first = hitIds(lastAssistant(h));
    expect(chat(h).hasMore, isTrue);
    api.onInterpret = (_, _) => const Interpretation(intent: ChatIntent.more);
    await ctl(h).send('more');
    final second = hitIds(lastAssistant(h));
    expect(second, hasLength(2)); // five eligible in all
    expect(second.toSet().intersection(first.toSet()), isEmpty);
    expect(chat(h).hasMore, isFalse);
    final explainsBefore = api.explains.length;
    await ctl(h).send('more again');
    expect(lastAssistant(h).hits, isEmpty);
    expect(lastAssistant(h).notes.single.kind, NoteKind.noMore);
    expect(api.explains.length, explainsBefore); // no AI call for an empty answer
  });

  test('the "Show more" button asks nothing of the AI and keeps the same search', () async {
    final (h, api) = await setup();
    api.onInterpret = (_, _) => const Interpretation(
      intent: ChatIntent.search,
      count: 2,
      prefs: ChatPrefs(maxPriceKrw: 8000),
    );
    await ctl(h).send('cheap');
    expect(hitIds(lastAssistant(h)), ['2', '3']);
    final calls = api.interprets.length;
    await ctl(h).showMore();
    expect(api.interprets.length, calls);
    expect(hitIds(lastAssistant(h)), ['5']);
  });

  test('"something different" drops what was shown and keeps the earlier conditions', () async {
    final (h, api) = await setup();
    api.onInterpret = (msg, _) => msg == 'cheap'
        ? const Interpretation(
            intent: ChatIntent.search,
            count: 1,
            prefs: ChatPrefs(maxPriceKrw: 8000),
          )
        : const Interpretation(intent: ChatIntent.different);
    await ctl(h).send('cheap');
    expect(hitIds(lastAssistant(h)), ['2']);
    await ctl(h).send('I don\'t like that, something else');
    // the AI returned no preferences: the conversation's own are kept, so it is still under 8,000
    expect(hitIds(lastAssistant(h)), ['3', '5']);
    expect(chat(h).rejected, contains('2'));
    await ctl(h).send('cheap'); // a NEW search: the rejected place stays out
    expect(hitIds(lastAssistant(h)), isNot(contains('2')));
  });

  test('a follow-up keeps the earlier requirements: the AI is given the previous preferences', () async {
    final (h, api) = await setup();
    api.onInterpret = (msg, call) => msg == 'cheap chinese'
        ? const Interpretation(
            intent: ChatIntent.search,
            prefs: ChatPrefs(cuisines: {Cuisine.chinese}, cheap: true),
          )
        : Interpretation(
            intent: ChatIntent.search,
            prefs: ChatPrefs(
              cuisines: call.prefs!.cuisines,
              cheap: call.prefs!.cheap,
              closer: true,
            ),
          );
    await ctl(h).send('cheap chinese');
    expect(hitIds(lastAssistant(h)), ['2']);
    await ctl(h).send('actually closer');
    expect(api.interprets.last.prefs!.cuisines, {Cuisine.chinese});
    expect(chat(h).prefs!.closer, isTrue);
    expect(hitIds(lastAssistant(h)), ['2']);
  });

  test('"the second one\'s menu" opens the second restaurant of the last answer', () async {
    final (h, api) = await setup();
    await ctl(h).send('recommend');
    final shown = hitIds(lastAssistant(h));
    api.onInterpret = (_, _) => const Interpretation(
      intent: ChatIntent.menu,
      targetPositions: [2],
    );
    await ctl(h).send('show me the menu of the second restaurant');
    final m = lastAssistant(h);
    expect(hitIds(m), [shown[1]]);
    expect(m.expand, {shown[1]});
    expect(m.notes.single.kind, NoteKind.menuOpened);
    // answered from the data: no new ranking, no AI wording
    expect(api.explains, hasLength(1));
  });

  test('"which one is cheaper / closer" compares the real data', () async {
    final (h, api) = await setup();
    api.onInterpret = (msg, _) => msg == 'go'
        ? const Interpretation(intent: ChatIntent.search, prefs: ChatPrefs(maxPriceKrw: 8000), count: 3)
        : Interpretation(
            intent: ChatIntent.compare,
            compareBy: msg.contains('cheaper') ? 'price' : 'distance',
          );
    await ctl(h).send('go'); // shows 2 (짜장면 7000), 3 (김밥 4000), 5 (백반 7000)
    await ctl(h).send('which is cheaper');
    var n = lastAssistant(h).notes.single;
    expect(n.kind, NoteKind.cheapest);
    expect(n.price, 4000);
    await ctl(h).send('which is closer');
    n = lastAssistant(h).notes.single;
    expect(n.kind, NoteKind.closest);
    expect(hitIds(lastAssistant(h)), ['2']);
  });

  test('menu and compare before any recommendation ask for one first', () async {
    final (h, api) = await setup();
    api.onInterpret = (_, _) => const Interpretation(intent: ChatIntent.menu);
    await ctl(h).send('menu please');
    expect(lastAssistant(h).notes.single.kind, NoteKind.menuNone);
  });

  test('chit-chat and clarification show the AI\'s words', () async {
    final (h, api) = await setup();
    api.onInterpret = (_, _) => const Interpretation(intent: ChatIntent.chitchat, reply: 'You\'re welcome!');
    await ctl(h).send('thanks');
    expect(lastAssistant(h).text, 'You\'re welcome!');
    expect(api.explains, isEmpty);
  });

  test('nothing matched: a plain offer, no AI call, and the condition is NOT relaxed', () async {
    final (h, api) = await setup();
    api.onInterpret = (_, _) => const Interpretation(
      intent: ChatIntent.search,
      prefs: ChatPrefs(maxPriceKrw: 3000),
    );
    await ctl(h).send('under 3000 won');
    final m = lastAssistant(h);
    expect(m.hits, isEmpty);
    expect(m.notes.single.kind, NoteKind.noneRaiseBudget);
    expect(api.explains, isEmpty);
    expect(chat(h).prefs!.maxPriceKrw, 3000); // still 3,000 until the user says otherwise
  });

  group('when the AI is not available', () {
    test('quota: the same engine answers with the user\'s own filters, with a notice and real-data reasons', () async {
      final (h, api) = await setup();
      api.interpretError = const ChatApiException(ChatFailure.quota);
      h.container.read(conditionsProvider.notifier).update(
        (c) => c.copyWith(budget: BudgetOption.max8000),
      );
      await ctl(h).send('cheap food please');
      final m = lastAssistant(h);
      expect(hitIds(m), ['2', '3', '5']);
      expect(m.notes.map((n) => n.kind), contains(NoteKind.aiBusy));
      expect(m.hits.every((x) => x.reason == null), isTrue); // the card writes a templated reason
      expect(api.explains, isEmpty);
    });

    test('without the AI a count in the message and "more" still work', () async {
      final (h, api) = await setup();
      api.interpretError = const ChatApiException(ChatFailure.unavailable);
      await ctl(h).send('show me 2 places');
      expect(lastAssistant(h).hits, hasLength(2));
      await ctl(h).send('more');
      expect(lastAssistant(h).hits, hasLength(3));
      expect(chat(h).shown, hasLength(5));
    });

    test('the AI worded nothing (explain failed): cards still appear with real-data reasons', () async {
      final (h, api) = await setup();
      api.explainError = const ChatApiException(ChatFailure.quota);
      await ctl(h).send('recommend');
      final m = lastAssistant(h);
      expect(m.hits, hasLength(3));
      expect(m.hits.every((x) => x.reason == null), isTrue);
      expect(m.notes.map((n) => n.kind), containsAll([NoteKind.aiBusy, NoteKind.foundCount]));
    });
  });

  group('errors', () {
    test('too many messages: an error bubble with the wait, and Retry sends the same question', () async {
      final (h, api) = await setup();
      api.interpretError = const ChatApiException(
        ChatFailure.rateLimited,
        retryAfterSeconds: 42,
      );
      await ctl(h).send('hello');
      var m = lastAssistant(h);
      expect(m.failed, isTrue);
      expect(m.notes.single.kind, NoteKind.rateLimited);
      expect(m.notes.single.number, 42);
      expect(api.explains, isEmpty);
      api.interpretError = null;
      await ctl(h).retry();
      m = lastAssistant(h);
      expect(m.failed, isFalse);
      expect(m.hits, hasLength(3));
      // the user's bubble is not repeated and the error bubble is gone
      expect(chat(h).messages.where((x) => x.role == ChatRole.user), hasLength(1));
      expect(chat(h).messages.where((x) => x.failed), isEmpty);
    });

    test('a thrown search (no network) is an error bubble, never a crash, and recovers', () async {
      final (h, _) = await setup();
      var fail = true;
      final h2 = await buildHarness(
        extraOverrides: [
          chatApiProvider.overrideWithValue(FakeChatApi()),
          chatContextLoaderProvider.overrideWithValue(() async {
            if (fail) throw Exception('offline');
            return Fixture().context();
          }),
        ],
      );
      await ctl(h2).send('hi');
      expect(lastAssistant(h2).failed, isTrue);
      expect(lastAssistant(h2).notes.single.kind, NoteKind.networkError);
      fail = false;
      await ctl(h2).retry();
      expect(lastAssistant(h2).hits, hasLength(3));
      expect(chat(h).busy, isFalse);
    });
  });

  test('only restaurants the server confirms as published are shown', () async {
    final (h, api) = await setup();
    api.onExplain = (items) => Explanation(
      message: 'Two for you.',
      reasons: {for (final i in items) i.id: 'ok'},
      ids: [items.first.id, items.last.id],
    );
    await ctl(h).send('recommend');
    expect(lastAssistant(h).hits, hasLength(2));
  });

  test('the AI is told only what is needed: ids, minutes, real dish names (a few), the app\'s walk times', () async {
    final (h, api) = await setup();
    api.onInterpret = (_, _) => const Interpretation(
      intent: ChatIntent.search,
      prefs: ChatPrefs(maxPriceKrw: 8000),
      count: 1,
    );
    await ctl(h).send('cheap');
    final item = api.explains.single.single;
    expect(item.id, '2');
    expect(item.walkMinutes, 4);
    expect(item.matchedMenus, ['짜장면']);
  });

  test('history sent to the AI is capped at six turns and starts a new chat cleanly', () async {
    final (h, api) = await setup();
    for (var i = 0; i < 6; i++) {
      await ctl(h).send('message $i');
    }
    expect(api.interprets.last.history.length, lessThanOrEqualTo(6));
    ctl(h).reset();
    expect(chat(h).messages, isEmpty);
    expect(chat(h).prefs, isNull);
  });

  test('over-long input is cut to the limit and blank input is ignored', () async {
    final (h, api) = await setup();
    await ctl(h).send('   ');
    expect(api.interprets, isEmpty);
    await ctl(h).send('a' * 1000);
    expect(api.interprets.single.message.length, kChatMaxMessageChars);
  });

  test('a message is ignored while an answer is still being written', () async {
    final (h, api) = await setup();
    final first = ctl(h).send('one');
    final second = ctl(h).send('two');
    await Future.wait([first, second]);
    expect(api.interprets, hasLength(1));
  });
}
