import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

/// "오늘의 추천 받기" shows the pick where it is; it must not scroll the page.
void main() {
  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  for (final size in const [Size(390, 844), Size(360, 640)]) {
    testWidgets('tapping 오늘의 추천 받기 leaves the scroll position alone '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      final h = await buildHarness(
        recsRequested: false,
        restaurants: FakeRestaurantRepository(
          items: [fakeRestaurant('1', name: '국수집', distance: 120)],
        ),
      );
      await pumpApp(tester, h, home: const AppShell(), size: size);
      await tester.pumpAndSettle();

      final button = find.text('오늘의 추천 받기');
      expect(button, findsOneWidget);
      // Park the page a little way down, as a user who has scrolled to the button.
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -120));
      await tester.pumpAndSettle();
      final before = offset(tester);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(offset(tester), before);
      expect(find.text('오늘의 추천 받기'), findsOneWidget);
    });
  }
}
