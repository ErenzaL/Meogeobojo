// TEMPORARY, not committed: runs the real app, but adds a pretend second
// cafeteria (lunch + dinner only, no breakfast) to the campus so the new
// cafeteria picker and the optional-meals behaviour can be seen in a simulator.
// Production data is only read, never written.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'features/campus_meals/models/campus_meal_models.dart';
import 'features/campus_meals/providers/campus_meal_providers.dart';
import 'features/campus_meals/repositories/campus_meal_repository.dart';
import 'features/campus_meals/utils/seoul_date.dart';
import 'features/university/providers/university_providers.dart';

const _previewId = 'preview-2';

class _PreviewRepo implements CampusMealRepository {
  _PreviewRepo(this.real);
  final CampusMealRepository real;

  @override
  Future<List<CampusCafeteria>> cafeterias(String universityId) async {
    final list = await real.cafeterias(universityId);
    if (list.isEmpty) return list;
    return [
      ...list,
      CampusCafeteria(
        id: _previewId,
        universityId: universityId,
        kind: CafeteriaKind.student,
        nameKo: '학생회관식당 (미리보기)',
        mealTypes: const [MealType.lunch, MealType.dinner],
      ),
    ];
  }

  @override
  Future<List<CafeteriaMeal>> weekMeals({
    required String cafeteriaId,
    required DateTime weekStart,
  }) async {
    if (cafeteriaId != _previewId) {
      return real.weekMeals(cafeteriaId: cafeteriaId, weekStart: weekStart);
    }
    CafeteriaMeal meal(DateTime d, MealType t, String main, int price) =>
        CafeteriaMeal(
          id: '$_previewId-${isoDate(d)}-${t.name}',
          cafeteriaId: _previewId,
          date: d,
          type: t,
          optionName: '',
          optionOrder: 0,
          items: [
            MenuItem(nameKo: main, kind: MenuItemKind.main),
            const MenuItem(nameKo: '김치', kind: MenuItemKind.kimchi),
          ],
          status: MealStatus.published,
          priceKrw: price,
          startTime: t == MealType.lunch ? '11:00' : '17:00',
          endTime: t == MealType.lunch ? '14:00' : '19:00',
          verifiedAt: DateTime.utc(2026, 11, 1),
        );
    return [
      for (var i = 0; i < 5; i++) ...[
        meal(
          DateTime.utc(weekStart.year, weekStart.month, weekStart.day + i),
          MealType.lunch,
          '돈가스 정식',
          5500,
        ),
        meal(
          DateTime.utc(weekStart.year, weekStart.month, weekStart.day + i),
          MealType.dinner,
          '비빔밥',
          5000,
        ),
      ],
    ];
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        campusMealRepositoryProvider.overrideWithValue(
          _PreviewRepo(SupabaseCampusMealRepository(Supabase.instance.client)),
        ),
      ],
      child: const MeogeobojoApp(),
    ),
  );
}
