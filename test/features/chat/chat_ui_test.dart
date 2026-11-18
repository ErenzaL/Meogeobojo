import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:math';

import 'package:meogeobojo/core/config/app_assets.dart';
import 'package:meogeobojo/core/l10n/app_language.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/core/widgets/responsive.dart';
import 'package:meogeobojo/features/chat/data/chat_api.dart';
import 'package:meogeobojo/features/chat/providers/chat_controller.dart';
import 'package:meogeobojo/features/chat/widgets/chat_fab.dart';
import 'package:meogeobojo/features/chat/widgets/chat_overlay.dart';
import 'package:meogeobojo/features/chat/widgets/chat_panel.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/widgets/floating_nav_bar.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import 'chat_fixtures.dart';
import 'fake_chat_api.dart';

const kSizes = <Size>[
  Size(320, 568),
  Size(360, 640),
  Size(375, 667),
  Size(390, 844),
  Size(414, 896),
  Size(599, 800),
  Size(600, 900),
  Size(768, 1024),
  Size(959, 700),
  Size(1024, 768),
  Size(1280, 800),
  Size(1440, 900),
  Size(1920, 1080),
];

Future<Harness> shellHarness({
  FakeChatApi? api,
  String language = 'ko',
}) => buildHarness(
  storage: {'app_language': language},
  overridesRepo: FakeRestaurantOverrideRepository(
    menuItems: {
      '1': [
        menu('순대국밥', 9000, '식사', rep: true, description: '진한 육수'),
        menu('수육', 25000, '기타'),
        menu('품절 메뉴', 5000, '식사', available: false),
      ],
    },
  ),
  extraOverrides: [
    chatApiProvider.overrideWithValue(api ?? FakeChatApi()),
    chatContextLoaderProvider.overrideWithValue(
      () async => Fixture().context(),
    ),
  ],
);

Future<void> pumpShell(
  WidgetTester tester,
  Harness h, {
  Size size = const Size(390, 844),
}) => pumpApp(tester, h, home: const AppShell(), size: size);

Finder get fab => find.byKey(const ValueKey('chat-fab'));
/// Text inside the chat only (the Home page under it shows the same restaurants and menus).
Finder inChat(String text) => find.descendant(
  of: find.byType(ChatPanel),
  matching: find.text(text),
);

Finder get input => find.byKey(const ValueKey('chat-input'));

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(input, text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  await tester.pumpAndSettle();
}

void main() {
  group('the mascot button is sized and placed for the screen', () {
    test('size steps: 64 / 72 / 80 / 88', () {
      expect(chatFabSizeFor(320), 64);
      expect(chatFabSizeFor(374), 64);
      expect(chatFabSizeFor(375), 72);
      expect(chatFabSizeFor(599), 72);
      expect(chatFabSizeFor(600), 80);
      expect(chatFabSizeFor(1023), 80);
      expect(chatFabSizeFor(1024), 88);
      expect(chatFabSizeFor(2560), 88);
    });

    test('placement invariants on every size', () {
      for (final s in kSizes) {
        final desktop = s.width >= Breakpoints.desktop;
        final nav = desktop ? 0.0 : 64.0 + 34;
        final p = ChatPlacement.of(
          s,
          safeTop: 47,
          safeBottom: 34,
          navReserved: nav,
        );
        expect(p.fabSize, chatFabSizeFor(s.width), reason: '$s');
        expect(p.fabRight, greaterThanOrEqualTo(16), reason: '$s');
        expect(p.fabRight + p.fabSize, lessThan(s.width), reason: '$s');
        // above the bottom bar on phones and tablets; a comfortable corner margin on a desktop
        expect(p.fabBottom, greaterThanOrEqualTo(desktop ? 24 : nav + 12), reason: '$s');
        expect(p.fabBottom + p.fabSize, lessThan(s.height), reason: '$s');
        if (p.floatingPanel) {
          expect(p.panelWidth, inInclusiveRange(380, desktop ? 400 : 380), reason: '$s');
          expect(p.panelHeight, inInclusiveRange(320, 640), reason: '$s');
          expect(p.panelBottom, greaterThanOrEqualTo(desktop ? 24 : nav + 12), reason: '$s');
          expect(p.panelRight + p.panelWidth, lessThanOrEqualTo(s.width), reason: '$s');
          expect(p.panelTop, lessThanOrEqualTo(s.height - p.panelBottom - p.panelHeight + 0.1), reason: '$s');
        } else {
          expect(p.panelWidth, s.width, reason: '$s');
          expect(p.panelHeight, lessThan(s.height), reason: '$s');
        }
      }
    });

    test('the keyboard lifts the panel instead of hiding the input', () {
      final p = ChatPlacement.of(
        const Size(390, 844),
        safeTop: 47,
        safeBottom: 34,
        navReserved: 98,
        keyboard: 300,
      );
      expect(p.panelBottom, 300);
      expect(p.panelHeight, 844 - 47 - 8 - 300);
    });
  });

  group('on every screen size', () {
    for (final size in kSizes) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}: the mascot is visible, clear of the bar, and the chat opens and minimizes without layout errors', (tester) async {
        final h = await shellHarness();
        await pumpShell(tester, h, size: size);
        expect(fab, findsOneWidget);
        final rect = tester.getRect(fab);
        expect(rect.width, chatFabSizeFor(size.width));
        expect(rect.height, rect.width); // a circle, never squashed
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width - 16 + 0.5));
        expect(rect.bottom, lessThanOrEqualTo(size.height - 12));
        if (size.width < Breakpoints.desktop) {
          final nav = tester.getRect(find.byType(FloatingNavBar));
          expect(rect.bottom, lessThanOrEqualTo(nav.top), reason: 'the button must not cover the bottom bar');
        }

        await tester.tap(fab);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('chat-minimize')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(find.byKey(const ValueKey('chat-minimize')));
        expect(panel.right, lessThanOrEqualTo(size.width));
        expect(panel.bottom, lessThan(size.height));

        await tester.tap(find.byKey(const ValueKey('chat-minimize')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('chat-minimize')), findsNothing);
        expect(fab, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the mascot shows the app\'s own artwork, uncropped, in a circle', (tester) async {
    final h = await shellHarness();
    await pumpShell(tester, h);
    final img = tester.widget<Image>(
      find.descendant(of: fab, matching: find.byType(Image)),
    );
    expect(img.fit, BoxFit.contain);
    expect(AppAssets.chatMascots, contains((img.image as AssetImage).assetName));
    final deco = tester.widget<DecoratedBox>(
      find.ancestor(of: fab, matching: find.byType(DecoratedBox)).first,
    );
    expect((deco.decoration as BoxDecoration).shape, BoxShape.circle);
    // no permanent text label beside it
    expect(find.text('먹어보조 AI에게 물어보기'), findsNothing);
  });

  testWidgets('phones: the mascot steps aside on the map tab (its sheet and place card live there) and is back elsewhere', (tester) async {
    final h = await shellHarness();
    await pumpShell(tester, h);
    expect(fab, findsOneWidget);
    h.container.read(shellTabProvider.notifier).select(ShellTabs.map);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fab, findsNothing);
    h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fab, findsOneWidget);
  });

  testWidgets('desktop keeps the mascot on the map tab (nothing sits in that corner)', (tester) async {
    final h = await shellHarness();
    await pumpShell(tester, h, size: const Size(1440, 900));
    h.container.read(shellTabProvider.notifier).select(ShellTabs.map);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fab, findsOneWidget);
  });

  group('the mascot changes', () {
    String shown(WidgetTester tester) => (tester
            .widget<Image>(find.descendant(of: fab, matching: find.byType(Image)))
            .image as AssetImage)
        .assetName;

    test('the pool is the whole mascot folder, each file once', () {
      expect(AppAssets.chatMascots.toSet(), hasLength(AppAssets.chatMascots.length));
      expect(AppAssets.chatMascots.length, 10);
      for (final a in AppAssets.chatMascots) {
        expect(File(a).existsSync(), isTrue, reason: a);
      }
      final onDisk = Directory('assets/images/mascot')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.png'))
          .toSet();
      expect(onDisk, AppAssets.chatMascots.toSet());
    });

    test('rerolling never repeats the pose that is showing', () async {
      final h = await shellHarness();
      final c = h.container;
      c.read(chatRandomProvider); // default random
      var last = c.read(chatMascotProvider);
      for (var i = 0; i < 200; i++) {
        c.read(chatMascotProvider.notifier).reroll();
        final now = c.read(chatMascotProvider);
        expect(now, isNot(last));
        expect(AppAssets.chatMascots, contains(now));
        last = now;
      }
    });

    test('over many starts every pose shows up', () async {
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        final h = await buildHarness(extraOverrides: [chatRandomProvider.overrideWithValue(Random(i))]);
        seen.add(h.container.read(chatMascotProvider));
      }
      expect(seen, AppAssets.chatMascots.toSet());
    });

    testWidgets('a new pose appears each time the chat goes back to the button, in the same circle', (tester) async {
      final h = await shellHarness();
      await pumpShell(tester, h);
      final first = shown(tester);
      final size = tester.getSize(fab);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-minimize')));
      await tester.pumpAndSettle();
      final second = shown(tester);
      expect(second, isNot(first));
      expect(tester.getSize(fab), size);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-close')));
      await tester.pumpAndSettle();
      expect(shown(tester), isNot(second));
      expect(tester.takeException(), isNull);
    });
  });

  group('the conversation', () {
    testWidgets('welcome, ask, three real cards, expand to the real menu, and the full detail page', (tester) async {
      final h = await shellHarness();
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(find.text('먹어보조 AI'), findsOneWidget);
      expect(find.textContaining('어떤 음식이 당겨요'), findsOneWidget);

      await ask(tester, '든든한 거 추천해줘');
      expect(find.text('Here you go.'), findsOneWidget);
      // three cards, nearest first: 1 (100 m), 6 (150 m), 2 (300 m)
      expect(find.byKey(const ValueKey('chat-card-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-card-6')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-card-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-card-3')), findsNothing);
      expect(find.text('Reason for 1'), findsOneWidget);
      expect(find.textContaining('9,000원부터'), findsWidgets); // a real price from the menu rows

      // the menu is only loaded and shown on tap, and it is the real one
      expect(inChat('순대국밥'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-card-1')));
      await tester.pumpAndSettle();
      expect(inChat('순대국밥'), findsOneWidget);
      expect(inChat('진한 육수'), findsOneWidget);
      expect(inChat('₩9,000'), findsOneWidget);
      expect(inChat('₩25,000'), findsOneWidget);
      expect(inChat('품절 메뉴'), findsOneWidget);
      expect(inChat('품절'), findsOneWidget);

      // close it again
      await tester.tap(find.byKey(const ValueKey('chat-card-1')));
      await tester.pumpAndSettle();
      expect(inChat('수육'), findsNothing);

      // open it and go to the full page; the conversation survives the trip
      await tester.tap(find.byKey(const ValueKey('chat-card-1')));
      await tester.pumpAndSettle();
      final details = find.byKey(const ValueKey('chat-details-1'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(RestaurantDetailScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantDetailScreen), findsNothing);
      expect(h.container.read(chatControllerProvider).messages, hasLength(2));
      expect(find.text('Here you go.'), findsOneWidget);
    });

    testWidgets('minimizing keeps the conversation, the draft and the open menu; closing clears it', (tester) async {
      final h = await shellHarness();
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await ask(tester, '추천해줘');
      await tester.tap(find.byKey(const ValueKey('chat-card-1')));
      await tester.pumpAndSettle();
      await tester.enterText(input, '아직 쓰는 중');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chat-minimize')));
      await tester.pumpAndSettle();
      expect(find.text('Here you go.'), findsNothing); // hidden
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(find.text('Here you go.'), findsOneWidget);
      expect(inChat('순대국밥'), findsOneWidget); // the menu is still open
      expect(find.text('아직 쓰는 중'), findsOneWidget); // so is the draft

      await tester.tap(find.byKey(const ValueKey('chat-close')));
      await tester.pumpAndSettle();
      expect(h.container.read(chatControllerProvider).messages, isEmpty);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(find.text('Here you go.'), findsNothing);
      expect(find.textContaining('어떤 음식이 당겨요'), findsOneWidget);
    });

    testWidgets('"show me the menu of the second one" opens that card with its menu', (tester) async {
      final api = FakeChatApi();
      final h = await shellHarness(api: api);
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await ask(tester, '추천해줘');
      api.onInterpret = (_, _) => const Interpretation(
        intent: ChatIntent.menu,
        targetPositions: [1],
      );
      await ask(tester, '첫 번째 메뉴 보여줘');
      expect(find.textContaining('메뉴예요'), findsOneWidget);
      expect(inChat('순대국밥'), findsOneWidget); // opened by the message, no tap needed
    });

    testWidgets('an error shows a message and Retry, then recovers', (tester) async {
      final api = FakeChatApi()
        ..interpretError = const ChatApiException(ChatFailure.rateLimited, retryAfterSeconds: 12);
      final h = await shellHarness(api: api);
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await ask(tester, '추천해줘');
      expect(find.textContaining('12초'), findsOneWidget);
      api.interpretError = null;
      await tester.tap(find.byKey(const ValueKey('chat-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-retry')), findsNothing);
      expect(find.byKey(const ValueKey('chat-card-1')), findsOneWidget);
    });

    testWidgets('"Show more" appears while more restaurants fit and adds new ones', (tester) async {
      final h = await shellHarness();
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await ask(tester, '추천해줘');
      final more = find.byKey(const ValueKey('chat-more'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-card-3'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-card-5'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-more')), findsNothing); // nothing left
    });

    testWidgets('the send button is off for an empty box', (tester) async {
      final h = await shellHarness();
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('chat-send'));
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.enterText(input, '  ');
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.enterText(input, '국밥');
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    });

    testWidgets('the phone keyboard lifts the panel; the input stays on screen', (tester) async {
      final h = await shellHarness();
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(input).bottom, lessThanOrEqualTo(844 - 300));
      tester.view.resetViewInsets();
    });
  });

  group('language', () {
    for (final (code, title, welcome) in [
      ('ko', '먹어보조 AI', '어떤 음식이 당겨요'),
      ('en', '먹어보조 AI', 'What are you in the mood for'),
      ('zh-Hans', '먹어보조 AI', '今天想吃点什么'),
    ]) {
      testWidgets('$code: the whole chat is in the app language, with no language picker', (tester) async {
        final h = await shellHarness(language: code);
        await pumpShell(tester, h);
        await tester.tap(fab);
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.textContaining(welcome), findsOneWidget);
        expect(find.byType(DropdownButton<AppLanguage>), findsNothing);
      });
    }

    testWidgets('changing the app language updates the open chat at once, including the app\'s own lines', (tester) async {
      final h = await shellHarness(language: 'ko');
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      final api = h.container.read(chatApiProvider) as FakeChatApi;
      api.onExplain = (items) => Explanation(ids: [for (final i in items) i.id]); // no AI words: the app writes them
      await ask(tester, '추천해줘');
      expect(find.text('조건에 맞는 3곳을 찾았어요.'), findsOneWidget);
      await h.container.read(languageProvider.notifier).select(AppLanguage.en);
      await tester.pumpAndSettle();
      expect(find.text('I found 3 places that fit.'), findsOneWidget);
      await h.container.read(languageProvider.notifier).select(AppLanguage.zhHans);
      await tester.pumpAndSettle();
      expect(find.text('找到了3家符合条件的餐厅。'), findsOneWidget);
    });

    testWidgets('the language sent to the assistant is the app\'s language', (tester) async {
      final api = FakeChatApi();
      final h = await shellHarness(language: 'zh-Hans', api: api);
      await pumpShell(tester, h);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await ask(tester, 'hello 추천');
      expect(api.interprets.single.language, 'zh-Hans');
      await h.container.read(languageProvider.notifier).select(AppLanguage.en);
      await tester.pumpAndSettle();
      await ask(tester, 'again');
      expect(api.interprets.last.language, 'en');
    });
  });
}
