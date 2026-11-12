import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/map/utils/marker_art.dart';
import 'package:meogeobojo/features/map/utils/marker_image.dart';

void main() {
  testWidgets('map pins are small tags the map SDK can take', (tester) async {
    await tester.runAsync(() async {
      final tag = await renderPlaceTag('8,000~', selected: false, scale: 1);
      final chosen = await renderPlaceTag('8,000~', selected: true, scale: 1);
      final origin = await renderOriginPin('정문', scale: 1);
      final sharp = await renderPlaceTag('8,000~', selected: false, scale: 3);
      for (final png in [tag, chosen, origin, sharp]) {
        expect(isSafeMarkerPng(png), isTrue);
      }
      final t = inspectPng(tag)!, c = inspectPng(chosen)!;
      // The old pin was a 56 px circle; a tag is a short, wide label.
      expect(t.height, lessThan(40));
      expect(t.width, greaterThan(t.height));
      expect(c.height, greaterThan(t.height)); // the chosen one stands out
      expect(inspectPng(origin)!.height, lessThan(64));
      // Android draws at the device pixel ratio: same tag, 3x the pixels.
      expect(inspectPng(sharp)!.height, closeTo(t.height * 3, 3));
    });
  });
}
