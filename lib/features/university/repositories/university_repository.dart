import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/university.dart';
import '../models/verified_universities.dart';

abstract interface class UniversityRepository {
  Future<List<University>> fetchAll();
}

class SupabaseUniversityRepository implements UniversityRepository {
  SupabaseUniversityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<University>> fetchAll() async {
    try {
      final rows = await _client
          .from('universities')
          .select('id, name_ko, name_en, city, latitude, longitude')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .order('name_ko')
          .timeout(const Duration(seconds: 8));
      final list = [for (final r in rows) University.fromJson(r)];
      if (list.isNotEmpty) return list;
      debugPrint('universities table is empty; using bundled verified list');
    } catch (e) {
      // Typically PGRST205 until the migration has been applied.
      debugPrint('universities fetch failed ($e); using bundled verified list');
    }
    return kVerifiedUniversities;
  }
}
