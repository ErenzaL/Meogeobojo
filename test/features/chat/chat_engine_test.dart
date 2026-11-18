import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/chat/logic/chat_engine.dart';
import 'package:meogeobojo/features/chat/models/chat_models.dart';
import 'package:meogeobojo/features/chat/models/chat_prefs.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';

import 'chat_fixtures.dart';

List<String> ids(ChatSearchResult r) => [for (final h in r.hits) h.id];
List<String> found(ChatPrefs p, {Set<String> exclude = const {}}) =>
    ids(searchForChat(p, Fixture().context(), exclude: exclude));

void main() {
  group('no conditions', () {
    test('every visible restaurant, nearest first; cafes and hidden places are not listed', () {
      expect(found(ChatPrefs.none), ['1', '6', '2', '3', '5']);
    });
    test('a hidden restaurant never appears, even when it would match', () {
      expect(found(const ChatPrefs(maxPriceKrw: 8000)), isNot(contains('7')));
    });
  });

  group('budget (hard)', () {
    test('"under 8,000 won" uses the engine budget: only places with a real dish at or under it', () {
      expect(found(const ChatPrefs(maxPriceKrw: 8000)), ['2', '3', '5']);
    });
    test('the matched dishes are the real lines that fit, not the others', () {
      final r = searchForChat(
        const ChatPrefs(maxPriceKrw: 8000),
        Fixture().context(),
      );
      final chinese = r.hits.firstWhere((h) => h.id == '2');
      expect(chinese.matched.map((m) => m.name), ['짜장면']); // 짬뽕 8,500 is over
    });
    test('an amount that is not one of the app\'s options is checked on the real prices', () {
      final r = searchForChat(
        const ChatPrefs(maxPriceKrw: 6000),
        Fixture().context(),
      );
      expect(ids(r), ['3']);
      expect(r.hits.single.matched.map((m) => m.name), ['김밥', '떡볶이']);
    });
    test('a range: min and max together', () {
      expect(
        found(const ChatPrefs(minPriceKrw: 8000, maxPriceKrw: 10000)),
        ['1', '2'],
      );
    });
    test('"12,000 won or more" counts shared dishes', () {
      expect(found(const ChatPrefs(minPriceKrw: 12000)), ['1', '2']);
    });
    test('drinks and add-on sides are no evidence at a restaurant: a place with only a drink under budget is out', () {
      // 1: 콜라 2,000 and 공기밥 1,000 are cheap but do not count; its meal is 9,000
      expect(found(const ChatPrefs(maxPriceKrw: 6000)), isNot(contains('1')));
    });
    test('at a cafe the drinks are the price', () {
      final p = const ChatPrefs(
        maxPriceKrw: 5000,
        cuisines: {Cuisine.cafe},
      );
      final r = searchForChat(p, Fixture().context());
      expect(ids(r).first, '4');
      expect(r.hits.first.matched.map((m) => m.name), ['아메리카노']);
    });
    test('an unpriced place cannot confirm a price: it is not recommended for one', () {
      expect(found(const ChatPrefs(maxPriceKrw: 8000)), isNot(contains('6')));
    });
  });

  group('distance, cuisine, dish', () {
    test('a walking limit in minutes (any number, not only 5 / 10 / 15)', () {
      expect(found(const ChatPrefs(maxWalkMinutes: 4)), ['1', '6', '2']);
      expect(found(const ChatPrefs(maxWalkMinutes: 2)), ['1', '6']);
    });
    test('a cuisine the user asked for is a hard filter', () {
      expect(found(const ChatPrefs(cuisines: {Cuisine.chinese})), ['2']);
      expect(found(const ChatPrefs(cuisines: {Cuisine.japanese})), isEmpty);
    });
    test('a named dish needs a place that really serves it, by menu or by its own category', () {
      expect(found(const ChatPrefs(dishKeywords: ['국밥'])), ['1']);
      expect(found(const ChatPrefs(dishKeywords: ['라멘'])), isEmpty);
      // the keyword match ignores spaces
      expect(found(const ChatPrefs(dishKeywords: ['순대 국밥'])), ['1']);
    });
    test('a named dish and a price must hold on the SAME dish', () {
      expect(
        found(const ChatPrefs(dishKeywords: ['국밥'], maxPriceKrw: 8000)),
        isEmpty,
      );
      expect(
        found(const ChatPrefs(dishKeywords: ['국밥'], maxPriceKrw: 10000)),
        ['1'],
      );
    });
  });

  group('spicy food', () {
    test('dishes named as spicy are left out, places with no menu cannot be confirmed, and the card says spice is not on record', () {
      final r = searchForChat(
        const ChatPrefs(avoidSpicy: true),
        Fixture().context(),
      );
      expect(ids(r), isNot(contains('6')));
      final bunsik = r.hits.firstWhere((h) => h.id == '3');
      expect(bunsik.matched.map((m) => m.name), ['김밥']); // 떡볶이 left out
      expect(r.hits.every((h) => h.spiceUnrecorded), isTrue);
    });
    test('only names that say spicy count; nothing is ever declared "not spicy"', () {
      expect(spicyByName('불닭볶음면'), isTrue);
      expect(spicyByName('짬뽕'), isTrue);
      expect(spicyByName('백짬뽕'), isFalse);
      expect(spicyByName('순대국밥'), isFalse);
    });
  });

  group('soft preferences only change the order', () {
    test('a mood\'s dishes rank first but nobody is removed', () {
      final r = found(const ChatPrefs(softKeywords: ['국밥', '탕']));
      expect(r.first, '1');
      expect(r.toSet(), {'1', '6', '2', '3', '5'});
    });
    test('"cheap" orders by the cheapest real meal, unknown prices last', () {
      expect(found(const ChatPrefs(cheap: true)), ['3', '2', '5', '1', '6']);
    });
    test('"closer" orders by distance', () {
      expect(found(const ChatPrefs(closer: true)), ['1', '6', '2', '3', '5']);
    });
  });

  group('conversation memory', () {
    test('shown or rejected restaurants are excluded', () {
      expect(found(ChatPrefs.none, exclude: {'1', '6'}), ['2', '3', '5']);
    });
  });

  group('nothing matched: what to offer (never applied silently)', () {
    final c = Fixture().context();
    test('a budget that is too low offers a higher budget', () {
      expect(
        suggestAdjustment(const ChatPrefs(maxPriceKrw: 3000), c),
        NoteKind.noneRaiseBudget,
      );
    });
    test('a cuisine nobody serves offers other kinds of food', () {
      expect(
        suggestAdjustment(const ChatPrefs(cuisines: {Cuisine.japanese}), c),
        NoteKind.noneAnyCuisine,
      );
    });
    test('a dish nobody serves offers other dishes', () {
      expect(
        suggestAdjustment(const ChatPrefs(dishKeywords: ['라멘']), c),
        NoteKind.noneDropDish,
      );
    });
    test('a distance nobody is within offers a wider one', () {
      expect(
        suggestAdjustment(const ChatPrefs(maxWalkMinutes: 1, cuisines: {Cuisine.chinese}), c),
        NoteKind.noneWiderDistance,
      );
    });
    test('when no single change helps it says so', () {
      expect(
        suggestAdjustment(
          const ChatPrefs(maxPriceKrw: 3000, cuisines: {Cuisine.japanese}),
          c,
        ),
        NoteKind.noneGeneric,
      );
    });
  });

  group('preferences', () {
    test('JSON round trip and tolerance of bad input', () {
      const p = ChatPrefs(
        maxPriceKrw: 8000,
        maxWalkMinutes: 5,
        cuisines: {Cuisine.chinese},
        dishKeywords: ['짜장면'],
        avoidSpicy: true,
        softKeywords: ['탕'],
        cheap: true,
        groupSize: 5,
      );
      expect(ChatPrefs.fromJson(p.toJson()), p);
      expect(ChatPrefs.fromJson('x'), ChatPrefs.none);
      expect(
        ChatPrefs.fromJson({'hard': {'cuisines': ['martian', 'korean', 'any']}}).cuisines,
        {Cuisine.korean},
      );
    });
    test('the app\'s own filters become the chat\'s starting point', () {
      final p = ChatPrefs.fromConditions(
        const Conditions(
          budget: BudgetOption.max10000,
          distance: DistanceOption.walk10,
          cuisines: {Cuisine.korean},
        ),
      );
      expect(p.maxPriceKrw, 10000);
      expect(p.maxWalkMinutes, 10);
      expect(p.cuisines, {Cuisine.korean});
    });
  });
}
