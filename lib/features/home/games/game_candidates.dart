import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recommendation/home_ranking.dart';

/// Every game takes the same number of candidates, and all of them: a ladder
/// never quietly drops the 5th and 6th entry.
const kGameMin = 2;
const kGameMax = 6;

/// How many recommended places a game starts with (the user can add up to
/// [kGameMax]).
const kGameSeed = 4;

/// One thing a game can land on: a real place (with its distance and
/// details) or a name the user typed, which has no location at all.
@immutable
class GameCandidate {
  const GameCandidate(this.name, {this.place});

  final String name;

  /// Null for a typed name: no distance, directions or details exist for it.
  final RankedRestaurant? place;

  String get tag => place?.restaurant.categoryTag ?? '';
}

enum GameMode { places, custom }

enum NameProblem { empty, duplicate, full }

/// The candidates the three games share: changing the game, or playing
/// again, keeps them.
@immutable
class GameSetup {
  const GameSetup({
    this.mode = GameMode.places,
    this.placeIds = const [],
    this.names = const [],
    this.seeded = false,
  });

  final GameMode mode;

  /// Chosen recommended places (Kakao ids), in the order they were added.
  final List<String> placeIds;

  /// Typed candidates.
  final List<String> names;

  /// Whether [placeIds] was filled from the recommendations once already.
  final bool seeded;

  GameSetup copyWith({
    GameMode? mode,
    List<String>? placeIds,
    List<String>? names,
    bool? seeded,
  }) => GameSetup(
    mode: mode ?? this.mode,
    placeIds: placeIds ?? this.placeIds,
    names: names ?? this.names,
    seeded: seeded ?? this.seeded,
  );

  /// What the games play with, in the current mode.
  List<GameCandidate> candidates(List<RankedRestaurant> matches) =>
      switch (mode) {
        GameMode.places => [
          for (final id in placeIds)
            for (final m in matches)
              if (m.restaurant.kakaoId == id)
                GameCandidate(m.restaurant.name, place: m),
        ],
        GameMode.custom => [for (final n in names) GameCandidate(n)],
      };
}

final gameSetupProvider = NotifierProvider<GameSetupNotifier, GameSetup>(
  GameSetupNotifier.new,
);

class GameSetupNotifier extends Notifier<GameSetup> {
  @override
  GameSetup build() => const GameSetup();

  void setMode(GameMode m) => state = state.copyWith(mode: m);

  /// The recommended places start as the first [kGameSeed] matches (or fewer);
  /// afterwards only places that no longer match are dropped.
  void syncPlaces(List<RankedRestaurant> matches) {
    final ids = [for (final m in matches) m.restaurant.kakaoId];
    final next = state.seeded
        ? [
            for (final id in state.placeIds)
              if (ids.contains(id)) id,
          ]
        : ids.take(kGameSeed).toList();
    if (state.seeded && listEquals(next, state.placeIds)) return;
    state = state.copyWith(placeIds: next, seeded: true);
  }

  /// Adds the place [id], or removes it when it is already in.
  bool togglePlace(String id) {
    final ids = [...state.placeIds];
    if (!ids.remove(id)) {
      if (ids.length >= kGameMax) return false;
      ids.add(id);
    }
    state = state.copyWith(placeIds: ids);
    return true;
  }

  /// Null when [raw] was added; otherwise why it was not.
  NameProblem? addName(String raw) {
    final problem = _check(raw, except: null);
    if (problem != null) return problem;
    if (state.names.length >= kGameMax) return NameProblem.full;
    state = state.copyWith(names: [...state.names, raw.trim()]);
    return null;
  }

  NameProblem? rename(int i, String raw) {
    final problem = _check(raw, except: i);
    if (problem != null) return problem;
    state = state.copyWith(
      names: [
        for (var k = 0; k < state.names.length; k++)
          k == i ? raw.trim() : state.names[k],
      ],
    );
    return null;
  }

  void removeName(int i) => state = state.copyWith(
    names: [
      for (var k = 0; k < state.names.length; k++)
        if (k != i) state.names[k],
    ],
  );

  NameProblem? _check(String raw, {required int? except}) {
    final name = raw.trim();
    if (name.isEmpty) return NameProblem.empty;
    final key = name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    for (var k = 0; k < state.names.length; k++) {
      if (k == except) continue;
      final other = state.names[k].toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (other == key) return NameProblem.duplicate;
    }
    return null;
  }
}
