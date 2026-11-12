import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/map/utils/marker_art.dart';
import 'package:meogeobojo/features/map/utils/marker_image.dart';

void main() {
  testWidgets('place pins: a 44x44 touch box, the chosen one larger', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pin = await renderPlacePin(selected: false, scale: 1);
      final chosen = await renderPlacePin(
        selected: true,
        scale: 1,
        name: '향설식당',
        kind: '한식',
      );
      final origin = await renderOriginPin('정문', scale: 1);
      final sharp = await renderPlacePin(selected: false, scale: 3);
      for (final png in [pin, chosen, origin, sharp]) {
        expect(isSafeMarkerPng(png), isTrue);
      }
      final p = inspectPng(pin)!, c = inspectPng(chosen)!;
      // The drawn pin is small, but its transparent box is a full touch target.
      expect(p.width, kPinTouchSize);
      expect(p.height, kPinTouchSize);
      // The chosen one carries its name above a bigger pin.
      expect(c.height, greaterThan(p.height));
      expect(c.width, greaterThan(p.width));
      expect(inspectPng(origin)!.height, lessThan(64));
      // Android draws at the device pixel ratio: same pin, 3x the pixels.
      expect(inspectPng(sharp)!.height, closeTo(p.height * 3, 3));
    });
  });

  testWidgets('a long name still fits the SDK limit on a dense phone', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // The pin picker allows 20 characters; Android draws at up to ~4x.
      final name = '가' * 20;
      for (final scale in [3.0, 4.0]) {
        for (final png in [
          await renderOriginPin(name, scale: scale),
          await renderPlacePin(
            selected: true,
            scale: scale,
            name: '가' * 40,
            kind: '음식점',
          ),
          await renderPlacePin(selected: false, scale: scale),
        ]) {
          expect(isSafeMarkerPng(png), isTrue, reason: '${inspectPng(png)}');
        }
      }
    });
  });
}
