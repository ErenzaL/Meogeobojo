import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mission_models.dart';

/// The two server calls behind the mission system. Progress and rewards are
/// decided entirely in the database; the app can only ask it to recompute and
/// report a few de-duplicated actions.
abstract class MissionRepository {
  /// Recomputes the signed-in user's missions and returns the dashboard.
  Future<MissionDashboard> sync();

  /// Reports one of the supported actions ('recommendation_view',
  /// 'category_explore'); returns whatever that completed.
  Future<List<CompletedMission>> logActivity(String event, {String ref = ''});
}

class SupabaseMissionRepository implements MissionRepository {
  SupabaseMissionRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<MissionDashboard> sync() async {
    final res = await _db
        .rpc<Map<String, dynamic>>('sync_my_missions')
        .timeout(const Duration(seconds: 20));
    return MissionDashboard.fromJson(res);
  }

  @override
  Future<List<CompletedMission>> logActivity(
    String event, {
    String ref = '',
  }) async {
    final res = await _db
        .rpc<List<dynamic>>(
          'log_activity',
          params: {'p_event': event, 'p_ref': ref},
        )
        .timeout(const Duration(seconds: 20));
    return [
      for (final e in res)
        if (e is Map<String, dynamic>) CompletedMission.fromJson(e),
    ];
  }
}
