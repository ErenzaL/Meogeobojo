import 'package:flutter/foundation.dart';

import '../../../core/campus_points.dart';
import '../../../core/utils/geo.dart';
import '../../../l10n/app_localizations.dart';

enum OriginKind { campusCenter, gate, dorm, building, pin }

/// Where the walk starts. Everything distance-related on Home, the map and
/// the sheets is measured from here (straight line, like the rest of the app).
@immutable
class Origin {
  const Origin({
    required this.id,
    required this.kind,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.zoomLevel,
  });

  factory Origin.fromPoint(CampusPoint p) => Origin(
    id: p.id,
    kind: switch (p.kind) {
      CampusPointKind.gate => OriginKind.gate,
      CampusPointKind.dorm => OriginKind.dorm,
      CampusPointKind.building => OriginKind.building,
    },
    name: p.name,
    latitude: p.latitude,
    longitude: p.longitude,
  );

  factory Origin.fromPin(SavedPin p) => Origin(
    zoomLevel: p.zoomLevel,
    id: p.id,
    kind: OriginKind.pin,
    name: p.name,
    latitude: p.latitude,
    longitude: p.longitude,
  );

  final String id;
  final OriginKind kind;

  /// Proper name ("정문", a pin's name). Empty for [OriginKind.campusCenter],
  /// whose label is localized: use [label].
  final String name;
  final double latitude;
  final double longitude;

  /// The map zoom a pin was placed at (pins only), so editing it starts there.
  final int? zoomLevel;

  String label(AppLocalizations l10n) =>
      kind == OriginKind.campusCenter ? l10n.originCampusCenter : name;

  /// Straight-line metres from here to ([lat], [lng]): the one way every
  /// screen measures a place.
  int metersTo(double lat, double lng) =>
      haversineMeters(latitude, longitude, lat, lng).round();

  @override
  bool operator ==(Object other) => other is Origin && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A place the user dropped on the map. Stored on the device only.
@immutable
class SavedPin {
  const SavedPin({
    required this.id,
    required this.universityId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.zoomLevel,
  });

  final String id;
  final String universityId;
  final String name;
  final double latitude;
  final double longitude;

  /// The map zoom it was placed at (null for pins saved before it was kept).
  final int? zoomLevel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'university_id': universityId,
    'name': name,
    'lat': latitude,
    'lng': longitude,
    'zoom': ?zoomLevel,
  };

  static SavedPin? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final uni = j['university_id'];
    final name = j['name'];
    final lat = j['lat'];
    final lng = j['lng'];
    if (id is! String || uni is! String || name is! String) return null;
    if (lat is! num || lng is! num) return null;
    final zoom = j['zoom'];
    return SavedPin(
      id: id,
      universityId: uni,
      name: name,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      zoomLevel: zoom is int ? zoom : null,
    );
  }
}
