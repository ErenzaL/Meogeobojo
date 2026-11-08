import 'dart:math' as math;

/// Great-circle distance in meters (haversine).
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
}

/// "850m" / "1.2km". Straight-line distance, not walking time.
String formatDistance(int meters) {
  if (meters < 1000) return '${meters}m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)}km';
}
