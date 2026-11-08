import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/utils/geo.dart';

void main() {
  test('formatDistance uses meters below 1km and km above', () {
    expect(formatDistance(257), '257m');
    expect(formatDistance(1000), '1.0km');
    expect(formatDistance(2578), '2.6km');
    expect(formatDistance(12400), '12km');
  });

  test('haversine: same point is zero, 0.01 deg lat is ~1.1km', () {
    expect(haversineMeters(36.77, 126.93, 36.77, 126.93), 0);
    expect(haversineMeters(36.77, 126.93, 36.78, 126.93), closeTo(1112, 5));
  });
}
