import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo_features.dart';

abstract interface class DemoFeatureRepository {
  Future<Map<String, DemoFeature>> all();
}

/// Reads the development-only table. A failure (table not created, offline) means "no demo data": the recommendation
/// then simply behaves as in production.
class SupabaseDemoFeatureRepository implements DemoFeatureRepository {
  SupabaseDemoFeatureRepository(this._db);

  final SupabaseClient Function() _db;

  @override
  Future<Map<String, DemoFeature>> all() async {
    try {
      final rows = await _db()
          .from('recommendation_demo_features')
          .select()
          .limit(2000)
          .timeout(const Duration(seconds: 10));
      final out = <String, DemoFeature>{};
      for (final r in rows) {
        final f = DemoFeature.fromJson(r);
        if (f != null) out[f.kakaoId] = f;
      }
      return out;
    } catch (e) {
      debugPrint('recommendation_demo_features unavailable: ${e.runtimeType}');
      return const {};
    }
  }
}
