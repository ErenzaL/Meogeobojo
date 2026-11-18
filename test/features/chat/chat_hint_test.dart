import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meogeobojo/app.dart';
import 'package:meogeobojo/features/chat/providers/chat_controller.dart';
import 'package:meogeobojo/features/chat/widgets/chat_hint.dart';

import '../../support/harness.dart';

const hint = '오늘 뭐 먹을지 물어보세요';
Finder get bubble => find.byKey(const ValueKey('chat-hint'));

Future<int> mount(WidgetTester tester, Harness h, {Size size = const Size(390, 844)}) async {
  var taps = 0;
  setPhoneSize(tester, size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MeogeobojoApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: ChatHintBubble(fabSize: 72, maxWidth: 250, onTap: () => taps++),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return taps;
}

void main() {
  testWidgets('the invitation waits a moment, shows for a few seconds, then goes by itself', (tester) async {
    final h = await buildHarness();
    await mount(tester, h);
    expect(find.text(hint), findsNothing); // not at once
    await tester.pump(const Duration(milliseconds: 1700));
    expect(find.text(hint), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text(hint), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text(hint), findsNothing);
    expect(bubble, findsNothing);
    // nothing keeps animating forever
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('tapping the bubble opens the chat', (tester) async {
    final h = await buildHarness();
    var opened = 0;
    setPhoneSize(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MeogeobojoApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ChatHintBubble(fabSize: 72, maxWidth: 250, onTap: () => opened++),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.tap(bubble);
    expect(opened, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('a new mascot pose brings typing dots, in place of the text, and they go away too', (tester) async {
    final h = await buildHarness();
    await mount(tester, h);
    await tester.pumpAndSettle(); // the invitation has come and gone
    expect(bubble, findsNothing);
    h.container.read(chatMascotProvider.notifier).reroll();
    await tester.pump(); // the change reaches the bubble
    await tester.pump(const Duration(milliseconds: 400));
    expect(bubble, findsOneWidget);
    expect(find.text(hint), findsNothing);
    expect(find.byType(DecoratedBox), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    expect(bubble, findsNothing);
  });

  testWidgets('the bubble fits a small phone and the longest language', (tester) async {
    final h = await buildHarness(storage: {'app_language': 'en'});
    await mount(tester, h, size: const Size(320, 568));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(tester.takeException(), isNull);
    final r = tester.getRect(bubble);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(320));
    await tester.pumpAndSettle();
  });

  testWidgets('with "reduce motion" on, no bubble is shown', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await buildHarness();
    await mount(tester, h);
    await tester.pump(const Duration(seconds: 3));
    expect(bubble, findsNothing);
    h.container.read(chatMascotProvider.notifier).reroll();
    await tester.pump(const Duration(seconds: 1));
    expect(bubble, findsNothing);
  });
}
