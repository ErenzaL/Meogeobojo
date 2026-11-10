import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../models/mission_models.dart';
import '../repositories/mission_repository.dart';

final missionRepositoryProvider = Provider<MissionRepository>(
  (ref) => SupabaseMissionRepository(Supabase.instance.client),
);

/// Missions just completed, waiting to be celebrated once (see
/// `MissionCelebrationHost`).
final missionCelebrationProvider =
    NotifierProvider<MissionCelebrationNotifier, List<CompletedMission>>(
      MissionCelebrationNotifier.new,
    );

class MissionCelebrationNotifier extends Notifier<List<CompletedMission>> {
  @override
  List<CompletedMission> build() => const [];

  void add(List<CompletedMission> done) {
    if (done.isNotEmpty) state = [...state, ...done];
  }

  void clear() => state = const [];
}

/// The signed-in user's missions, computed by the server from real data.
/// Null for guests. Rebuilds on sign-in / sign-out, so rewards come back
/// after logging in again (they live in the database, not the app).
final missionDashboardProvider =
    AsyncNotifierProvider<MissionDashboardNotifier, MissionDashboard?>(
      MissionDashboardNotifier.new,
    );

class MissionDashboardNotifier extends AsyncNotifier<MissionDashboard?> {
  Timer? _debounce;

  @override
  Future<MissionDashboard?> build() async {
    final user = ref.watch(currentUserProvider);
    ref.onDispose(() => _debounce?.cancel());
    // Saving or un-saving a place can move a mission: ask the server to
    // recompute shortly after (de-bounced so a burst is one call).
    ref.listen(favoritesProvider.select((a) => a.value?.length), (prev, next) {
      if (prev != null && prev != next) _scheduleRefresh();
    });
    if (user == null) return null;
    try {
      final dash = await ref.read(missionRepositoryProvider).sync();
      ref.read(missionCelebrationProvider.notifier).add(dash.newlyCompleted);
      return dash;
    } catch (e) {
      // The usual cause on a fresh project: the missions migration has not
      // been applied, so `sync_my_missions` does not exist yet.
      debugPrint('mission sync failed: $e');
      rethrow;
    }
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), refresh);
  }

  /// Recomputes without flashing a spinner; keeps the old data on failure.
  Future<void> refresh() async {
    if (ref.read(currentUserProvider) == null) return;
    try {
      final dash = await ref.read(missionRepositoryProvider).sync();
      if (!ref.mounted) return;
      ref.read(missionCelebrationProvider.notifier).add(dash.newlyCompleted);
      state = AsyncData(dash);
    } catch (e) {
      debugPrint('mission refresh failed: $e');
      if (ref.mounted && !state.hasValue) {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }
}

/// Reports an action to the mission system. Fire and forget: guests and
/// failures are ignored, because a mission must never get in the way of the
/// action itself.
Future<void> logMissionActivity(
  WidgetRef ref,
  String event, {
  String key = '',
}) async {
  if (ref.read(currentUserProvider) == null) return;
  try {
    final done = await ref
        .read(missionRepositoryProvider)
        .logActivity(event, ref: key);
    if (done.isNotEmpty) {
      ref.read(missionCelebrationProvider.notifier).add(done);
    }
    // Keep the mission page honest without refetching on every tap.
    if (done.isNotEmpty || ref.read(missionDashboardProvider).hasValue) {
      unawaited(ref.read(missionDashboardProvider.notifier).refresh());
    }
  } catch (e) {
    debugPrint('mission activity failed: $e');
  }
}
