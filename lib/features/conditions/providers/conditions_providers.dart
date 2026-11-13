import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../preferences/providers/preferences_providers.dart';
import '../../records/meal_records.dart';
import '../models/conditions.dart';

/// The one set of conditions behind Home, the map and search. Starts from the
/// signed-in user's saved preferences; edits made in the sheet apply at once
/// and are not written back (that is what the preferences screen is for).
final conditionsProvider = NotifierProvider<ConditionsNotifier, Conditions>(
  ConditionsNotifier.new,
);

class ConditionsNotifier extends Notifier<Conditions> {
  @override
  Conditions build() {
    // Re-seed when the saved preferences change (sign-in, save, start over).
    // This is a listener, not a watch, and it applies after the current
    // frame: a watch here would rebuild this provider while a widget is
    // mid-build whenever the preferences provider reloads on sign-in.
    ref.listen(userPreferencesProvider.select((a) => a.value), (prev, next) {
      if (prev == next) return;
      scheduleMicrotask(() {
        if (ref.mounted) state = Conditions.fromPreferences(next);
      });
    });
    return Conditions.fromPreferences(ref.read(userPreferencesProvider).value);
  }

  void update(Conditions Function(Conditions c) change) =>
      state = change(state);

  /// "초기화": back to the defaults, ignoring saved preferences.
  void clear() => state = Conditions.defaults;
}

/// How many meals the user has logged ("먹은 기록").
final visitedRecordCountProvider = Provider<int>(
  (ref) => ref.watch(mealRecordsProvider).length,
);
