import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/map/widgets/map_overlay_shield.dart';

void main() {
  testWidgets(
    'shield preserves overlay interaction and adds a web hit target',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapOverlayShield(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('overlay'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('overlay'));
      expect(taps, 1);
      expect(
        find.byType(HtmlElementView),
        kIsWeb ? findsOneWidget : findsNothing,
      );
    },
  );
}
