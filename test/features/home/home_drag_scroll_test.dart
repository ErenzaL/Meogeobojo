import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/home/widgets/home_category_bar.dart';
import 'package:meogeobojo/features/home/widgets/home_filter_bar.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/support/support.dart';

import '../../support/harness.dart';

/// How far the first list inside [of] has scrolled.
double scrolled(WidgetTester tester, Finder of) => tester
    .state<ScrollableState>(
      find.descendant(of: of, matching: find.byType(Scrollable)).first,
    )
    .position
    .pixels;

void main() {
  testWidgets('the category and condition rows slide sideways with a mouse '
      '(the website and its phone preview)', (tester) async {
    final h = await buildHarness(
      extraOverrides: [
        campusMealCacheDurationProvider.overrideWithValue(Duration.zero),
      ],
    );
    await pumpApp(tester, h, home: const AppShell());
    for (final row in [
      find.byType(HomeCategoryBar),
      find.byType(HomeFilterBar),
    ]) {
      expect(scrolled(tester, row), 0);
      await tester.drag(
        row,
        const Offset(-300, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(scrolled(tester, row), greaterThan(0), reason: '$row');
    }
  });

  testWidgets('selectable text keeps the mouse drag for selecting, '
      'a finger still scrolls', (tester) async {
    final h = await buildHarness();
    await pumpApp(tester, h, home: const LegalScreen(LegalDoc.privacy));
    final page = find.byType(LegalScreen);
    // the text is taller than the screen: start on its first lines
    final start =
        tester.getTopLeft(find.byType(SelectableText)) + const Offset(40, 60);
    await tester.dragFrom(
      start,
      const Offset(0, -300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(scrolled(tester, page), 0);
    await tester.dragFrom(start, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrolled(tester, page), greaterThan(0));
  });
}
