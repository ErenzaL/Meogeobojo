import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/home/widgets/cafeteria_card.dart';
import 'package:meogeobojo/features/home/widgets/hero_card.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/core/l10n/app_language.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/widgets/floating_nav_bar.dart';
import 'package:meogeobojo/features/navigation/widgets/web_header.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

Future<void> open(WidgetTester tester, Size size) async {
  final h = await buildHarness(
    restaurants: FakeRestaurantRepository(
      items: [fakeRestaurant('1', name: '국수집', distance: 120)],
    ),
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
}

void main() {
  testWidgets('phone: single column, app fills the width', (tester) async {
    await open(tester, const Size(390, 844));
    final hero = tester.getRect(find.byType(HeroCard));
    expect(hero.width, closeTo(390 - 40, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop: header replaces the bottom bar; Home has two columns', (
    tester,
  ) async {
    await open(tester, const Size(1440, 900));
    expect(tester.takeException(), isNull);
    // V5 desktop: brand + tabs in a header, no bottom bar.
    expect(find.byType(WebHeader), findsOneWidget);
    expect(find.byType(FloatingNavBar), findsNothing);
    expect(find.text('먹어보조'), findsWidgets);
    final hero = tester.getRect(find.byType(HeroCard));
    final meals = tester.getRect(find.byType(CafeteriaCard));
    // Recommendations on the left, cafeteria to the right, side by side.
    expect(meals.left, greaterThan(hero.right));
    expect(meals.top, closeTo(hero.top, 1));
    // The whole app sits inside a 1280px centred column.
    expect(hero.left, greaterThanOrEqualTo((1440 - 1280) / 2));
    expect(meals.right, lessThanOrEqualTo((1440 + 1280) / 2));
    final header = tester.getRect(find.byType(WebHeader));
    expect(header.height, WebHeader.height);
    expect(header.width, closeTo(1280, 1));
  });

  testWidgets('desktop header: tabs navigate, language and theme switch', (
    tester,
  ) async {
    final h = await buildHarness(
      restaurants: FakeRestaurantRepository(
        items: [fakeRestaurant('1', name: '국수집', distance: 120)],
      ),
    );
    await pumpApp(
      tester,
      h,
      home: const AppShell(),
      size: const Size(1440, 900),
    );
    Future<void> tab(String label) async {
      await tester.tap(
        find.descendant(of: find.byType(WebHeader), matching: find.text(label)),
      );
      await tester.pumpAndSettle();
    }

    await tab('밥수다');
    expect(h.container.read(shellTabProvider), ShellTabs.community);
    await tab('지도');
    expect(h.container.read(shellTabProvider), ShellTabs.map);
    await tab('홈');
    expect(h.container.read(shellTabProvider), ShellTabs.home);

    // Segmented language control (한국어 / English / 中文).
    await tester.tap(
      find.descendant(
        of: find.byType(WebHeader),
        matching: find.text('English'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.container.read(appLanguageProvider), AppLanguage.en);
    expect(
      find.descendant(of: find.byType(WebHeader), matching: find.text('Home')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet: still readable, no overflow', (tester) async {
    await open(tester, const Size(820, 1180));
    expect(tester.takeException(), isNull);
    expect(find.byType(HeroCard), findsOneWidget);
  });

  testWidgets('desktop with large text does not overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, const Size(1280, 800));
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
