import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/map/widgets/map_places_sheet.dart';

import '../../support/harness.dart';

void main() {
  final handle = find.byKey(const ValueKey('map-sheet-handle'));
  double top(WidgetTester tester) => tester.getTopLeft(handle).dy;

  testWidgets('the bar on top of the places sheet opens and closes it with a '
      'tap or a mouse drag (the website phone preview)', (tester) async {
    final h = await buildHarness();
    await pumpApp(
      tester,
      h,
      home: const Scaffold(body: Stack(children: [MapPlacesSheet()])),
    );
    final middle = top(tester);

    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(top(tester), lessThan(middle - 300)); // fully open

    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(top(tester), closeTo(middle, 1)); // back to the middle

    await tester.drag(
      handle,
      const Offset(0, 200),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(top(tester), greaterThan(middle + 150)); // folded down

    await tester.drag(
      handle,
      const Offset(0, -500),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(top(tester), lessThan(middle - 300)); // dragged fully open
  });
}
