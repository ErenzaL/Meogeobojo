import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/map/utils/map_camera.dart';

void main() {
  group('web campus zoom', () {
    test('the initial web level is campus-sized, never the widest (14 = all of East Asia)', () {
      expect(kWebCampusInitialLevel, inInclusiveRange(2, 6));
      expect(kWebCampusInitialLevel, lessThan(14));
    });

    test('moveCamera uses the plugin\'s mobile scale; it converts to the same web level', () {
      // plugin: webLevel = 15 - mobileLevel (mobile clamped to 6..21)
      expect(15 - kWebCampusMoveLevel, kWebCampusInitialLevel);
      expect(kWebCampusMoveLevel, inInclusiveRange(6, 21));
    });
  });

  group('boundsToFit', () {
    const campus = GeoPoint(36.76999, 126.93150);

    test('no restaurants: nothing to fit, the map stays on the campus', () {
      expect(boundsToFit(campus, const []), isNull);
    });

    test('contains the campus and every nearby restaurant', () {
      final b = boundsToFit(campus, const [
        GeoPoint(36.7715, 126.9340),
        GeoPoint(36.7680, 126.9290),
      ])!;
      expect(b.south, 36.7680);
      expect(b.north, 36.7715);
      expect(b.west, 126.9290);
      expect(b.east, 126.9340);
      expect(b.south <= campus.latitude && campus.latitude <= b.north, isTrue);
      expect(b.west <= campus.longitude && campus.longitude <= b.east, isTrue);
    });

    test('a stray far-away result does not zoom the map out to a region', () {
      final b = boundsToFit(campus, const [
        GeoPoint(36.7715, 126.9340),
        GeoPoint(37.5665, 126.9780), // Seoul, ~90 km away
      ])!;
      expect(b.north, 36.7715);
      expect(b.south, campus.latitude);
      // only far results: nothing to fit
      expect(boundsToFit(campus, const [GeoPoint(37.5665, 126.9780)]), isNull);
    });

    test('non-finite coordinates are ignored', () {
      expect(boundsToFit(campus, [GeoPoint(double.nan, 126.93)]), isNull);
    });
  });
}
