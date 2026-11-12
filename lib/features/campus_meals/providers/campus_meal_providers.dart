import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../university/providers/university_providers.dart';
import '../models/campus_meal_models.dart';
import '../repositories/campus_meal_repository.dart';
import '../utils/seoul_date.dart';

final campusMealRepositoryProvider = Provider<CampusMealRepository>(
  (ref) => SupabaseCampusMealRepository(Supabase.instance.client),
);

/// "Now", overridable in tests. Dates derived from it use Asia/Seoul.
final campusMealClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// How long a fetched week is reused. Menus change at most daily, so a short
/// cache avoids refetching while the user flips tabs but stays fresh.
final campusMealCacheDurationProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 5),
);

/// Breakfast before 10:00, lunch until 15:00, dinner after (Seoul time).
MealType defaultMealTypeAt(DateTime now) {
  final h = seoulHour(now);
  if (h < 10) return MealType.breakfast;
  if (h < 15) return MealType.lunch;
  return MealType.dinner;
}

/// The selector shows Monday to Friday, so on a weekend the page opens on the
/// next Monday instead of a day that cannot be selected.
DateTime selectableDay(DateTime date) => switch (date.weekday) {
  DateTime.saturday => DateTime.utc(date.year, date.month, date.day + 2),
  DateTime.sunday => DateTime.utc(date.year, date.month, date.day + 1),
  _ => date,
};

class CampusMealSelection {
  const CampusMealSelection({
    required this.weekStart,
    required this.date,
    required this.mealType,
  });

  final DateTime weekStart;
  final DateTime date;
  final MealType mealType;

  CampusMealSelection copyWith({
    DateTime? weekStart,
    DateTime? date,
    MealType? mealType,
  }) => CampusMealSelection(
    weekStart: weekStart ?? this.weekStart,
    date: date ?? this.date,
    mealType: mealType ?? this.mealType,
  );
}

final campusMealSelectionProvider =
    NotifierProvider.autoDispose<
      CampusMealSelectionController,
      CampusMealSelection
    >(CampusMealSelectionController.new);

class CampusMealSelectionController extends Notifier<CampusMealSelection> {
  @override
  CampusMealSelection build() {
    final now = ref.read(campusMealClockProvider)();
    final start = selectableDay(seoulDate(now));
    return CampusMealSelection(
      weekStart: weekStartOf(start),
      date: start,
      mealType: defaultMealTypeAt(now),
    );
  }

  DateTime get today => seoulDate(ref.read(campusMealClockProvider)());

  void selectDate(DateTime date) =>
      state = state.copyWith(date: date, weekStart: weekStartOf(date));

  void selectMealType(MealType t) => state = state.copyWith(mealType: t);

  /// The cafeteria is remembered per university and shared with Home, so it
  /// lives in [selectedCafeteriaIdProvider], not in this page-only state.
  void selectCafeteria(String id) =>
      ref.read(selectedCafeteriaIdProvider.notifier).select(id);

  /// Moves by whole weeks keeping the same weekday selected.
  void shiftWeek(int weeks) {
    final offset = state.date.difference(state.weekStart).inDays;
    final start = addWeeks(state.weekStart, weeks);
    state = state.copyWith(
      weekStart: start,
      date: DateTime.utc(start.year, start.month, start.day + offset),
    );
  }

  /// "오늘": today's week, today's date and the meal for the current time.
  void goToToday() {
    final now = ref.read(campusMealClockProvider)();
    final t = selectableDay(seoulDate(now));
    state = state.copyWith(
      weekStart: weekStartOf(t),
      date: t,
      mealType: defaultMealTypeAt(now),
    );
  }
}

/// Cafeterias of the selected university. Changing university rebuilds this
/// (and everything below it) while the language is untouched.
final campusCafeteriasProvider =
    FutureProvider.autoDispose<List<CampusCafeteria>>((ref) async {
      final university = await ref.watch(selectedUniversityProvider.future);
      return ref.watch(campusMealRepositoryProvider).cafeterias(university.id);
    });

/// The cafeteria the user picked for the selected university (Home and the
/// weekly page share it), remembered on the device. One pick per university, so
/// choosing at one campus never changes another. Null until the user picks.
final selectedCafeteriaIdProvider =
    NotifierProvider<SelectedCafeteriaController, String?>(
      SelectedCafeteriaController.new,
    );

String selectedCafeteriaPrefsKey(String universityId) =>
    'selected_cafeteria_id:$universityId';

class SelectedCafeteriaController extends Notifier<String?> {
  String? _universityId;

  @override
  String? build() {
    _universityId = ref.watch(
      selectedUniversityProvider.select((u) => u.value?.id),
    );
    final id = _universityId;
    if (id == null) return null;
    return ref
        .read(sharedPreferencesProvider)
        .getString(selectedCafeteriaPrefsKey(id));
  }

  Future<void> select(String cafeteriaId) async {
    final id = _universityId;
    state = cafeteriaId;
    if (id == null) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(selectedCafeteriaPrefsKey(id), cafeteriaId);
  }
}

/// The cafeteria actually shown: the user's pick if it still belongs to the
/// selected university, otherwise the first student cafeteria (see
/// [chooseCafeteria]). Null when there are none.
final effectiveCafeteriaProvider =
    Provider.autoDispose<AsyncValue<CampusCafeteria?>>((ref) {
      final list = ref.watch(campusCafeteriasProvider);
      final pick = ref.watch(selectedCafeteriaIdProvider);
      return list.whenData((all) => chooseCafeteria(all, pick));
    });

typedef WeekKey = ({String cafeteriaId, DateTime weekStart});

final campusWeekMealsProvider = FutureProvider.autoDispose
    .family<WeekMeals, WeekKey>((ref, key) async {
      // Keep the result for a few minutes so tab/day changes and returning to
      // a week do not refetch, then let it expire.
      final link = ref.keepAlive();
      final timer = Timer(
        ref.read(campusMealCacheDurationProvider),
        link.close,
      );
      ref.onDispose(timer.cancel);
      final meals = await ref
          .watch(campusMealRepositoryProvider)
          .weekMeals(cafeteriaId: key.cafeteriaId, weekStart: key.weekStart);
      return WeekMeals(key.weekStart, meals);
    });
