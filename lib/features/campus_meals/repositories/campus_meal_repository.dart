import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/campus_meal_models.dart';
import '../utils/seoul_date.dart';

/// Read-only access to campus cafeterias and their menus. Menus are written
/// by administrators only (see supabase/cafeteria/); the app never writes.
abstract interface class CampusMealRepository {
  Future<List<CampusCafeteria>> cafeterias(String universityId);

  /// Every option of every meal for one cafeteria for the Monday-Sunday week
  /// starting at [weekStart]: ONE query per week (not per day or per tab).
  Future<List<CafeteriaMeal>> weekMeals({
    required String cafeteriaId,
    required DateTime weekStart,
  });
}

class SupabaseCampusMealRepository implements CampusMealRepository {
  SupabaseCampusMealRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<List<CampusCafeteria>> cafeterias(String universityId) async {
    final rows = await _db
        .from('campus_cafeterias')
        .select()
        .eq('university_id', universityId)
        // oldest first: the cafeteria added first stays on top, each new one goes to the bottom
        .order('created_at')
        .order('id');
    return rows.map(CampusCafeteria.fromJson).toList();
  }

  @override
  Future<List<CafeteriaMeal>> weekMeals({
    required String cafeteriaId,
    required DateTime weekStart,
  }) async {
    final end = weekDays(weekStart).last;
    final rows = await _db
        .from('cafeteria_meals')
        .select()
        .eq('cafeteria_id', cafeteriaId)
        .gte('meal_date', isoDate(weekStart))
        .lte('meal_date', isoDate(end))
        .order('meal_date')
        .order('option_order')
        .order('option_name');
    // Rows the app cannot understand are dropped rather than guessed at.
    return rows.map(CafeteriaMeal.fromJson).whereType<CafeteriaMeal>().toList();
  }
}
