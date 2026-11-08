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

class CampusMealSelection {
  const CampusMealSelection({
    required this.weekStart,
    required this.date,
    required this.mealType,
    this.cafeteriaId,
  });

  final DateTime weekStart;
  final DateTime date;
  final MealType mealType;

  /// The user's pick; may be stale after a university change, so always go
  /// through [effectiveCafeteriaProvider].
  final String? cafeteriaId;

  CampusMealSelection copyWith({
    DateTime? weekStart,
    DateTime? date,
    MealType? mealType,
    String? Function()? cafeteriaId,
  }) => CampusMealSelection(
    weekStart: weekStart ?? this.weekStart,
    date: date ?? this.date,
    mealType: mealType ?? this.mealType,
    cafeteriaId: cafeteriaId != null ? cafeteriaId() : this.cafeteriaId,
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
    final today = seoulDate(now);
    return CampusMealSelection(
      weekStart: weekStartOf(today),
      date: today,
      mealType: defaultMealTypeAt(now),
    );
  }

  DateTime get today => seoulDate(ref.read(campusMealClockProvider)());

  void selectDate(DateTime date) =>
      state = state.copyWith(date: date, weekStart: weekStartOf(date));

  void selectMealType(MealType t) => state = state.copyWith(mealType: t);

  void selectCafeteria(String id) =>
      state = state.copyWith(cafeteriaId: () => id);

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
    final t = seoulDate(now);
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

/// The cafeteria actually shown: the user's pick if it still belongs to the
/// selected university, otherwise the first one. Null when there are none.
final effectiveCafeteriaProvider =
    Provider.autoDispose<AsyncValue<CampusCafeteria?>>((ref) {
      final list = ref.watch(campusCafeteriasProvider);
      final pick = ref.watch(
        campusMealSelectionProvider.select((s) => s.cafeteriaId),
      );
      return list.whenData((all) {
        if (all.isEmpty) return null;
        return all.firstWhere((c) => c.id == pick, orElse: () => all.first);
      });
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
