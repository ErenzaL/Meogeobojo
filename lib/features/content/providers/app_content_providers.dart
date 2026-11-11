import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../university/providers/university_providers.dart';
import '../models/app_content.dart';
import '../repositories/app_content_repository.dart';

final appContentRepositoryProvider = Provider<AppContentRepository>(
  (ref) => SupabaseAppContentRepository(Supabase.instance.client),
);

/// Everything an admin currently publishes (all campuses).
///
/// The server's answer is authoritative: when the query succeeds and returns
/// nothing, nothing is shown (an unpublished or deleted announcement disappears).
/// Only a FAILED read (offline, timeout) keeps the last answer we got, so a
/// flaky connection does not blank the banner, and a read that fails before
/// any answer shows nothing rather than an error screen.
final appContentProvider =
    AsyncNotifierProvider<AppContentNotifier, List<AppContent>>(
      AppContentNotifier.new,
    );

class AppContentNotifier extends AsyncNotifier<List<AppContent>> {
  List<AppContent>? _lastConfirmed;

  @override
  Future<List<AppContent>> build() async {
    try {
      final live = await ref.watch(appContentRepositoryProvider).live();
      _lastConfirmed = live; // even when empty: that IS the truth
      return live;
    } catch (e) {
      debugPrint(
        'app_content refresh failed (${e.runtimeType}); keeping the last answer',
      );
      return _lastConfirmed ?? const [];
    }
  }
}

/// The items that apply to the selected campus: its own plus the ones for
/// every campus.
final campusContentProvider = Provider<List<AppContent>>((ref) {
  final all = ref.watch(appContentProvider).value ?? const [];
  final uni = ref.watch(selectedUniversityProvider).value?.id;
  return [
    for (final c in all)
      if (c.universityId == null || c.universityId == uni) c,
  ];
});

/// Notices and banners for Home. Bell-only notifications and featured
/// restaurants are not Home cards.
final homeNoticesProvider = Provider<List<AppContent>>((ref) {
  final items = ref
      .watch(campusContentProvider)
      .where(
        (c) =>
            c.kind == AppContentKind.announcement ||
            c.kind == AppContentKind.banner,
      )
      .toList();
  return items;
});

/// Kakao ids an admin featured through 앱 콘텐츠 (the other source of
/// "featured" is `restaurant_overrides.featured`).
final featuredContentIdsProvider = Provider<List<String>>(
  (ref) => [
    for (final c in ref.watch(campusContentProvider))
      if (c.kind == AppContentKind.featured && c.kakaoPlaceId != null)
        c.kakaoPlaceId!,
  ],
);
