import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/campus_meals/providers/campus_meal_providers.dart';
import '../../features/content/providers/app_content_providers.dart';
import '../../features/missions/providers/mission_providers.dart';
import '../../features/restaurants/providers/restaurant_providers.dart';
import '../../features/university/providers/university_providers.dart';

/// Tables whose changes should reach a running app without a restart. The
/// subscription uses the signed-in (or anonymous) user's own permissions, so
/// Realtime only delivers rows that user may read: drafts and private data
/// never arrive.
const syncedTables = <String>[
  'restaurant_overrides',
  'restaurant_menus',
  'restaurant_photos',
  'cafeteria_meals',
  'campus_cafeterias',
  'missions',
  'monthly_campaigns',
  'app_content',
  'universities',
];

/// Emits the table name each time a synced table changes. Overridable in
/// tests. When Supabase is not initialised (or Realtime is unavailable) it is
/// simply silent: the app still refreshes on resume, on the mission tab and by
/// pull-to-refresh.
final contentChangesProvider = StreamProvider<String>((ref) {
  final SupabaseClient client;
  try {
    client = Supabase.instance.client;
  } catch (_) {
    return const Stream<String>.empty();
  }
  final controller = StreamController<String>();
  final channel = client.channel('content-sync');
  for (final table in syncedTables) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) {
        if (!controller.isClosed) controller.add(table);
      },
    );
  }
  try {
    channel.subscribe();
  } catch (e) {
    debugPrint('content sync unavailable: ${e.runtimeType}');
  }
  ref.onDispose(() {
    controller.close();
    client.removeChannel(channel);
  });
  return controller.stream;
});

/// Re-reads what [table] feeds. Cheap and idempotent.
void invalidateForTable(ProviderContainer ref, String table) {
  switch (table) {
    case 'restaurant_overrides':
    case 'restaurant_menus':
    case 'restaurant_photos':
      ref.invalidate(restaurantOverridesProvider);
      ref.invalidate(restaurantMenusProvider);
      ref.invalidate(restaurantPhotosProvider);
      // Visibility / name changes are applied when the lists are fetched.
      ref.invalidate(allNearbyRestaurantsProvider);
      ref.invalidate(nearbyRestaurantsProvider);
      ref.invalidate(categoryRestaurantsProvider);
    case 'cafeteria_meals':
    case 'campus_cafeterias':
      ref.invalidate(campusCafeteriasProvider);
      ref.invalidate(campusWeekMealsProvider);
    case 'app_content':
      ref.invalidate(appContentProvider);
    case 'universities':
      // the selected campus is derived from this list, so it follows
      ref.invalidate(universityListProvider);
    case 'missions':
    case 'monthly_campaigns':
      unawaited(ref.read(missionDashboardProvider.notifier).refresh());
  }
}

/// Everything an admin can publish, re-read (app resume).
void refreshAllContent(ProviderContainer ref) {
  for (final t in const [
    'restaurant_overrides',
    'cafeteria_meals',
    'app_content',
    'missions',
    'universities',
  ]) {
    invalidateForTable(ref, t);
  }
}
