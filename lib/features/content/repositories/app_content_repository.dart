import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_content.dart';

abstract interface class AppContentRepository {
  /// What is live right now. An EMPTY list is a confirmed answer ("nothing is
  /// published"); a failure (network, timeout) THROWS, so callers can tell the
  /// two apart and never mistake an outage for a take-down.
  Future<List<AppContent>> live();
}

class SupabaseAppContentRepository implements AppContentRepository {
  SupabaseAppContentRepository(this._db);

  final SupabaseClient _db;

  /// Row-level security returns only items that are on and inside their dates,
  /// so drafts and expired items never reach the app.
  @override
  Future<List<AppContent>> live() async {
    final rows = await _db
        .from('app_content')
        .select()
        .order('sort_order')
        .timeout(const Duration(seconds: 10));
    return [for (final r in rows) ?AppContent.fromJson(r)];
  }
}
