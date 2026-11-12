import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/utils/geo.dart';

void main() {
  test('formatDistance: 10 m steps below 1 km, one-decimal km above', () {
    expect(formatDistance(257), '260m');
    expect(formatDistance(128), '130m');
    expect(formatDistance(994), '990m');
    expect(formatDistance(996), '1.0km');
    expect(formatDistance(1000), '1.0km');
    expect(formatDistance(2578), '2.6km');
    expect(formatDistance(12400), '12.4km');
  });

  test('haversine: same point is zero, 0.01 deg lat is ~1.1km', () {
    expect(haversineMeters(36.77, 126.93, 36.77, 126.93), 0);
    expect(haversineMeters(36.77, 126.93, 36.78, 126.93), closeTo(1112, 5));
  });
}
