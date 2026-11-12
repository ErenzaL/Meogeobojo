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

/// "260m" / "1.2km": the one display rule for every screen. Under 1 km it is
/// rounded to 10 m, from 1 km on it is km with one decimal. It is a
/// straight-line distance: callers say so ("직선 약 260m").
String formatDistance(int meters) {
  final tens = (meters / 10).round() * 10;
  if (tens < 1000) return '${tens}m';
  return '${(meters / 1000).toStringAsFixed(1)}km';
}
