import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/l10n/l10n.dart';
import 'package:meogeobojo/core/l10n/rich_text.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_repository.dart';
import 'package:meogeobojo/features/university/models/university.dart';
import 'package:meogeobojo/features/university/models/university_display.dart';

import '../support/fakes.dart';
import '../support/category_host.dart';
import '../support/harness.dart';

Map<String, dynamic> arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Iterable<String> messageKeys(Map<String, dynamic> m) =>
    m.keys.where((k) => !k.startsWith('@'));

Set<String> placeholdersIn(String message) =>
    RegExp(r'\{(\w+)')
        .allMatches(message)
        .map((m) => m.group(1)!)
        // ICU keywords that follow `{count, plural, ...}` are not placeholders.
        .where((p) => !const {'plural', 'other'}.contains(p))
        // Plural branches look like `=1{1 result}`; digits are text, not names.
        .where((p) => !RegExp(r'^\d+$').hasMatch(p))
        .toSet();

void main() {
  group('ARB files', () {
    final ko = arb('ko');
    final en = arb('en');
    final zh = arb('zh');

    test('all three languages define exactly the same keys', () {
      expect(messageKeys(en).toSet(), messageKeys(ko).toSet());
      expect(messageKeys(zh).toSet(), messageKeys(ko).toSet());
    });

    test('no translation is empty', () {
      for (final m in [ko, en, zh]) {
        for (final k in messageKeys(m)) {
          expect(
            (m[k] as String).trim(),
            isNotEmpty,
            reason: '$k in ${m['@@locale']}',
          );
        }
      }
    });

    test('every language uses the same placeholders for each message', () {
      for (final k in messageKeys(ko)) {
        final expected = placeholdersIn(ko[k] as String);
        expect(placeholdersIn(en[k] as String), expected, reason: 'en: $k');
        expect(placeholdersIn(zh[k] as String), expected, reason: 'zh: $k');
      }
    });

    test('placeholders are declared with types in the template', () {
      for (final k in messageKeys(ko)) {
        final ph = placeholdersIn(ko[k] as String);
        if (ph.isEmpty) continue;
        final declared = ((ko['@$k'] as Map?)?['placeholders'] as Map?)?.keys
            .toSet();
        expect(declared, ph, reason: k);
      }
    });

    test('the brand name 먹어보조 is never translated', () {
      for (final m in [en, zh]) {
        for (final k in messageKeys(m)) {
          final v = m[k] as String;
          expect(v.contains('Meogeobojo'), isFalse, reason: k);
        }
      }
      expect(en['authWelcomeTitle'], 'Welcome to 먹어보조!');
      expect(zh['authWelcomeTitle'], '欢迎来到 먹어보조！');
    });

    test('Kakao / currency wording matches the product requirements', () {
      expect(ko['authContinueKakao'], '카카오로 계속하기');
      expect(en['authContinueKakao'], 'Continue with Kakao');
      expect(zh['authContinueKakao'], '使用 Kakao 继续');
      expect(en['navCommunity'], 'Food Talk');
      expect(zh['navCommunity'], '美食交流');
      // KRW is kept (no currency conversion)
      expect(en['onbBudgetMax'], contains('₩'));
      expect(zh['onbBudgetMax'], contains('₩'));
    });
  });

  group('generated localizations', () {
    testWidgets('same screen renders in ko, en and zh from one code path', (
      tester,
    ) async {
      final seen = <String>{};
      for (final lang in ['ko', 'en', 'zh-Hans']) {
        final h = await buildHarness(storage: {'app_language': lang});
        await pumpApp(tester, h, home: const AppShell());
        final labels = [
          'navHome',
          'navCommunity',
          'navMap',
          'navRecords',
          'navProfile',
        ];
        final l10n = tester.element(find.byType(AppShell)).l10n;
        final texts = [
          l10n.navHome,
          l10n.navCommunity,
          l10n.navMap,
          l10n.navRecords,
          l10n.navProfile,
        ];
        for (final t in texts) {
          expect(find.text(t), findsOneWidget, reason: '$lang $t');
        }
        seen.add(texts.join('|'));
        expect(labels.length, texts.length);
      }
      expect(seen.length, 3, reason: 'three distinct translations');
      expect(seen, contains('홈|밥수다|지도|기록|MY'));
      expect(seen, contains('Home|Food Talk|Map|Records|My'));
      expect(seen, contains('首页|美食交流|地图|记录|我的'));
    });

    for (final lang in ['en', 'zh-Hans']) {
      for (final size in const [Size(320, 568), Size(390, 844)]) {
        testWidgets(
          'Home in $lang has no overflow at $size (incl. 1.6x text)',
          (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = 1.6;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final h = await buildHarness(storage: {'app_language': lang});
            await pumpApp(tester, h, home: const AppShell(), size: size);
            expect(tester.takeException(), isNull);
            for (var i = 0; i < 6; i++) {
              await tester.drag(
                find.byType(Scrollable).first,
                const Offset(0, -350),
              );
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('Home shows translated content, Korean place names intact', (
      tester,
    ) async {
      final h = await buildHarness(
        storage: {'app_language': 'en'},
        restaurants: FakeRestaurantRepository(
          items: [fakeRestaurant('1', name: '국수집')],
        ),
      );
      await pumpApp(tester, h, home: const AppShell());
      expect(find.text('What should I eat today?'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.textContaining('from Main gate'), findsNothing);
      await tester.scrollUntilVisible(
        find.text("Today's cafeteria"),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text("Today's cafeteria"), findsOneWidget);
      // Kakao-sourced names are left exactly as received.
      expect(find.text('국수집1'), findsOneWidget);
    });

    testWidgets('Chinese Home', (tester) async {
      final h = await buildHarness(storage: {'app_language': 'zh-Hans'});
      await pumpApp(tester, h, home: const AppShell());
      expect(find.text('今天吃什么？'), findsOneWidget);
      expect(find.text('条件'), findsOneWidget);
    });

    testWidgets('category chips are localized but still search in Korean', (
      tester,
    ) async {
      final h = await buildHarness(storage: {'app_language': 'en'});
      await pumpApp(tester, h, home: const CategoryHost());
      expect(find.text('Korean'), findsOneWidget);
      await tester.tap(find.text('Korean'));
      await tester.pumpAndSettle();
      expect(h.restaurants.nearbyCalls.last.$2.queries, ['한식']);
    });

    test('restaurant errors are localized per language', () {
      const e = RestaurantException(RestaurantErrorKind.network);
      final texts = [
        for (final loc in ['ko', 'en', 'zh'])
          lookupAppLocalizations(Locale(loc)).restaurantErrNetwork,
      ];
      expect(texts.toSet().length, 3);
      expect(
        e.localizedMessage(lookupAppLocalizations(const Locale('en'))),
        'Check your internet connection.',
      );
    });
  });

  group('university names', () {
    const univ = University(
      id: 'u',
      nameKo: '순천향대학교',
      nameEn: 'Soonchunhyang University',
      latitude: 0,
      longitude: 0,
    );

    test(
      'English uses the English name; Korean and Chinese keep the Korean name',
      () {
        expect(
          univ.displayName(const Locale('en')),
          'Soonchunhyang University',
        );
        expect(univ.displayName(const Locale('ko')), '순천향대학교');
        expect(
          univ.displayName(const Locale('zh')),
          '순천향대학교',
          reason: 'no verified Chinese name exists, so none is invented',
        );
      },
    );

    test('missing English name falls back to Korean', () {
      const noEn = University(
        id: 'x',
        nameKo: '한국대',
        latitude: 0,
        longitude: 0,
      );
      expect(noEn.displayName(const Locale('en')), '한국대');
    });
  });

  group('highlightPlaceholder', () {
    test('keeps the translator\'s word order', () {
      final ko = highlightPlaceholder(
        (m) => '$m 주변에서',
        '순천향대',
        const TextStyle(),
      );
      expect(ko.map((s) => (s as TextSpan).text), ['순천향대', ' 주변에서']);
      final en = highlightPlaceholder(
        (m) => 'Around $m',
        'Univ',
        const TextStyle(),
      );
      expect(en.map((s) => (s as TextSpan).text), ['Around ', 'Univ']);
    });
  });
}
