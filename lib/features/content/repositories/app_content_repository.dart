import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_content.dart';

abstract interface class AppContentRepository {
  Future<List<AppContent>> live();
}

class SupabaseAppContentRepository implements AppContentRepository {
  SupabaseAppContentRepository(this._db);

  final SupabaseClient _db;

  /// Row-level security returns only items that are on and inside their dates,
  /// so drafts and expired items never reach the app. A failure means "no
  /// content", never an error screen.
  @override
  Future<List<AppContent>> live() async {
    try {
      final rows = await _db
          .from('app_content')
          .select()
          .order('sort_order')
          .timeout(const Duration(seconds: 10));
      return [for (final r in rows) ?AppContent.fromJson(r)];
    } catch (e) {
      debugPrint('app_content unavailable: ${e.runtimeType}');
      return const [];
    }
  }
}
