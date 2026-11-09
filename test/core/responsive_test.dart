import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/home/widgets/cafeteria_card.dart';
import 'package:meogeobojo/features/home/widgets/hero_card.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/widgets/floating_nav_bar.dart';

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

  testWidgets('desktop: app column is centred and Home has two columns', (
    tester,
  ) async {
    await open(tester, const Size(1440, 900));
    expect(tester.takeException(), isNull);
    final hero = tester.getRect(find.byType(HeroCard));
    final meals = tester.getRect(find.byType(CafeteriaCard));
    // Recommendations on the left, cafeteria to the right, side by side.
    expect(meals.left, greaterThan(hero.right));
    expect(meals.top, closeTo(hero.top, 1));
    // The whole app sits inside a 1040px centred column.
    expect(hero.left, greaterThanOrEqualTo((1440 - 1040) / 2));
    expect(meals.right, lessThanOrEqualTo((1440 + 1040) / 2));
    // The nav capsule stays phone-sized and centred.
    final nav = tester.getRect(find.byType(FloatingNavBar));
    expect(nav.width, lessThanOrEqualTo(560));
    expect(nav.center.dx, closeTo(720, 1));
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
