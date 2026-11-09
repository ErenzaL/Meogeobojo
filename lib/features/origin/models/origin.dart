import 'package:flutter/foundation.dart';

import '../../../core/campus_points.dart';
import '../../../l10n/app_localizations.dart';

enum OriginKind { campusCenter, gate, college, building, pin }

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
  });

  factory Origin.fromPoint(CampusPoint p) => Origin(
    id: p.id,
    kind: switch (p.kind) {
      CampusPointKind.gate => OriginKind.gate,
      CampusPointKind.college => OriginKind.college,
      CampusPointKind.building => OriginKind.building,
    },
    name: p.name,
    latitude: p.latitude,
    longitude: p.longitude,
  );

  factory Origin.fromPin(SavedPin p) => Origin(
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

  String label(AppLocalizations l10n) =>
      kind == OriginKind.campusCenter ? l10n.originCampusCenter : name;

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
  });

  final String id;
  final String universityId;
  final String name;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
    'id': id,
    'university_id': universityId,
    'name': name,
    'lat': latitude,
    'lng': longitude,
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
    return SavedPin(
      id: id,
      universityId: uni,
      name: name,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
    );
  }
}
