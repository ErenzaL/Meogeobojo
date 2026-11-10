import 'dart:math' as math;

/// Camera rules of the map, kept free of widgets so they can be tested.
///
/// The Kakao *web* map takes its initial level on the JavaScript scale, where 1 is the closest and 14 the
/// widest (all of Korea and beyond). The plugin's moveCamera / setZoomLevel use a "mobile" scale
/// (higher = closer) and convert it. A campus plus the restaurants around it is web level 4.
const int kWebCampusInitialLevel = 4;

/// The same campus zoom on the plugin's mobile scale (web level = 15 - mobile level), used by moveCamera.
const int kWebCampusMoveLevel = 11;

/// Restaurants farther than this from the origin do not stretch the view (a stray result must not zoom the map out
/// to a whole region).
const double kFitRadiusMeters = 2500;

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}

double _meters(GeoPoint a, GeoPoint b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h.toDouble())));
}

/// The box that shows [origin] and the [places] close to it, or null when there is nothing to fit (no places
/// nearby): then the map simply stays on the origin, it never zooms out to a country.
GeoBounds? boundsToFit(GeoPoint origin, Iterable<GeoPoint> places) {
  final near = [
    for (final p in places)
      if (p.latitude.isFinite &&
          p.longitude.isFinite &&
          _meters(origin, p) <= kFitRadiusMeters)
        p,
  ];
  if (near.isEmpty) return null;
  var south = origin.latitude, north = origin.latitude;
  var west = origin.longitude, east = origin.longitude;
  for (final p in near) {
    south = math.min(south, p.latitude);
    north = math.max(north, p.latitude);
    west = math.min(west, p.longitude);
    east = math.max(east, p.longitude);
  }
  return GeoBounds(south: south, west: west, north: north, east: east);
}
