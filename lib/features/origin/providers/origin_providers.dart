import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/campus_points.dart';
import '../../restaurants/models/restaurant.dart';
import '../../university/providers/university_providers.dart';
import '../models/origin.dart';

const _selectionKey = 'origin_selected_id';
const _pinsKey = 'origin_saved_pins';

/// Pins the user saved ("내 핀"), kept on this device.
final savedPinsProvider = NotifierProvider<SavedPinsNotifier, List<SavedPin>>(
  SavedPinsNotifier.new,
);

class SavedPinsNotifier extends Notifier<List<SavedPin>> {
  @override
  List<SavedPin> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_pinsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(SavedPin.fromJson).whereType<SavedPin>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<SavedPin> add({
    required String universityId,
    required String name,
    required double latitude,
    required double longitude,
    int? zoomLevel,
  }) async {
    final pin = SavedPin(
      id: 'pin_${DateTime.now().microsecondsSinceEpoch}',
      universityId: universityId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      zoomLevel: zoomLevel,
    );
    state = [...state, pin];
    await _persist();
    return pin;
  }

  /// Moves or renames the pin [id] (it keeps its id, so a selection stays).
  Future<void> edit(
    String id, {
    required String name,
    required double latitude,
    required double longitude,
    int? zoomLevel,
  }) async {
    state = [
      for (final p in state)
        p.id != id
            ? p
            : SavedPin(
                id: p.id,
                universityId: p.universityId,
                name: name,
                latitude: latitude,
                longitude: longitude,
                zoomLevel: zoomLevel ?? p.zoomLevel,
              ),
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = [
      for (final p in state)
        if (p.id != id) p,
    ];
    await _persist();
    // A deleted pin is not a stale choice to ask about: back to the default.
    if (ref.read(originSelectionProvider) == id) {
      await ref.read(originSelectionProvider.notifier).reset();
    }
  }

  Future<void> _persist() => ref
      .read(sharedPreferencesProvider)
      .setString(_pinsKey, jsonEncode([for (final p in state) p.toJson()]));
}

/// The user's explicit pick (an [Origin.id]); null means "use the default".
final originSelectionProvider =
    NotifierProvider<OriginSelectionNotifier, String?>(
      OriginSelectionNotifier.new,
    );

class OriginSelectionNotifier extends Notifier<String?> {
  @override
  String? build() =>
      ref.read(sharedPreferencesProvider).getString(_selectionKey);

  Future<void> select(String id) async {
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_selectionKey, id);
  }

  Future<void> reset() async {
    state = null;
    await ref.read(sharedPreferencesProvider).remove(_selectionKey);
  }
}

/// Every origin the user can pick on the selected campus, in sheet order:
/// gates, residence halls, buildings, then their own pins. Campuses without campus
/// points get a single "campus center" entry (the university's own landmark).
final originOptionsProvider = Provider<List<Origin>>((ref) {
  final university = ref.watch(selectedUniversityProvider).value;
  if (university == null) return const [];
  final points = campusPointsFor(university.id);
  final pins = ref
      .watch(savedPinsProvider)
      .where((p) => p.universityId == university.id);
  return [
    if (points.isEmpty)
      Origin(
        id: 'campus_center',
        kind: OriginKind.campusCenter,
        name: '',
        latitude: university.latitude,
        longitude: university.longitude,
      ),
    for (final p in points) Origin.fromPoint(p),
    for (final p in pins) Origin.fromPin(p),
  ];
});

/// The origin in effect. Falls back to the first gate (정문) or the campus
/// center when nothing was picked, or when the pick no longer exists (see
/// [staleOriginSelectionProvider]). Null only while the university loads.
final originProvider = Provider<Origin?>((ref) {
  final options = ref.watch(originOptionsProvider);
  if (options.isEmpty) return null;
  final picked = ref.watch(originSelectionProvider);
  for (final o in options) {
    if (o.id == picked) return o;
  }
  return options.firstWhere(
    (o) => o.kind == OriginKind.gate || o.kind == OriginKind.campusCenter,
    orElse: () => options.first,
  );
});

/// The saved pick when it no longer names an origin on this campus: the old
/// single "기숙사" ([kLegacyDormPointId], now one point per residence hall)
/// or a removed point. The app then measures from the default and asks the
/// user to choose again; it never guesses which hall they meant.
final staleOriginSelectionProvider = Provider<String?>((ref) {
  final options = ref.watch(originOptionsProvider);
  final picked = ref.watch(originSelectionProvider);
  if (options.isEmpty || picked == null) return null;
  return options.any((o) => o.id == picked) ? null : picked;
});

/// Straight-line metres from [o] (the chosen origin) to [r]. Null while the
/// origin loads, or for a place kept without coordinates. Never the distance
/// Kakao measured from the campus landmark: every screen measures from the
/// same origin.
int? metersFromOrigin(Origin? o, Restaurant r) =>
    o == null || (r.latitude == 0 && r.longitude == 0)
    ? null
    : o.metersTo(r.latitude, r.longitude);
