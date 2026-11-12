import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../missions/providers/mission_providers.dart';
import 'university_providers.dart';

/// Keeps the campus the student chose (kept on the device) and
/// `profiles.selected_university_id` (kept on the account) the same.
///
/// Why it matters: the server decides which university-specific missions a
/// student gets from the ACCOUNT's campus. The app only ever remembered the
/// choice locally, so those missions were never offered, and a second device
/// started on a different campus.
///
/// Rules (same spirit as the language setting):
///  * the account has no campus yet -> save the one the app is showing;
///  * the device has its own explicit choice that differs -> the device wins
///    and the account is updated;
///  * the device never chose, the account did -> the device adopts the account's.
/// It is best effort: a failure never blocks the app, and guests do nothing.
final universityAccountSyncProvider = Provider<void>((ref) {
  Future<void> push(String universityId) async {
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    final profile = auth.profile;
    if (user == null || profile == null) return;
    if (profile.selectedUniversityId == universityId) return;
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateUniversity(user.id, universityId);
      final current = ref.read(authControllerProvider).profile;
      if (current != null && current.id == user.id) {
        ref
            .read(authControllerProvider.notifier)
            .applyProfile(current.copyWith(selectedUniversityId: universityId));
      }
      // Eligibility for campus missions changed: ask the server again.
      unawaited(ref.read(missionDashboardProvider.notifier).refresh());
    } catch (e) {
      debugPrint('campus not saved to the account: ${e.runtimeType}');
    }
  }

  Future<void> reconcile() async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile == null) return;
    try {
      final selected = await ref.read(selectedUniversityProvider.future);
      final stored = ref
          .read(sharedPreferencesProvider)
          .getString(selectedUniversityPrefsKey);
      final remote = profile.selectedUniversityId;
      final all = await ref.read(universityListProvider.future);
      final supported = ref.read(supportedUniversityProvider);
      final remoteSupported = all.any((u) => u.id == remote && supported(u));
      if (remote == null || !remoteSupported) {
        // Never adopt a school that is still "준비 중": the account follows the
        // campus the app really shows.
        await push(selected.id);
      } else if (stored != null && stored != remote) {
        await push(stored);
      } else if (stored == null && remote != selected.id) {
        final adopted = all.where((u) => u.id == remote).firstOrNull;
        if (adopted != null) {
          await ref.read(selectedUniversityProvider.notifier).select(adopted);
        }
      }
    } catch (e) {
      debugPrint('campus sync skipped: ${e.runtimeType}');
    }
  }

  // A profile arrived or changed (sign-in, another device wrote it).
  ref.listen(
    authControllerProvider.select(
      (s) => s.profile == null
          ? null
          : (s.profile!.id, s.profile!.selectedUniversityId),
    ),
    (prev, next) {
      if (next != null && next != prev) unawaited(reconcile());
    },
    fireImmediately: true,
  );

  // The student picked another campus while signed in.
  ref.listen(selectedUniversityProvider.select((a) => a.value?.id), (
    prev,
    next,
  ) {
    if (next != null && prev != null && prev != next) unawaited(push(next));
  });
});
