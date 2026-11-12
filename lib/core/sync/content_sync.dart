import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/campus_meals/models/campus_meal_models.dart';
import '../../features/campus_meals/providers/campus_meal_providers.dart';
import '../../features/content/providers/app_content_providers.dart';
import '../../features/missions/providers/mission_providers.dart';
import '../../features/recommendation/providers/ranking_providers.dart';
import '../../features/restaurants/providers/restaurant_providers.dart';
import '../../features/university/models/university.dart';
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

/// A tiny always-readable log (`content_sync`: a table name and a timestamp per
/// row) that the database appends to on EVERY change, including taking something
/// down. Realtime cannot deliver an update that makes a row invisible to the
/// subscriber (row-level security), so an unpublish is announced here instead.
/// Optional: when the table does not exist yet, this one source simply fails
/// quietly and the periodic refresh covers it.
const signalSource = 'content_sync';

/// One Realtime notification. Deliberately WITHOUT value equality: Riverpod
/// drops a state equal to the previous one, so two `app_content` events in a row
/// (publish, then unpublish) used to reach the listener only once.
class ContentChange {
  ContentChange(this.source) : seq = ++_counter;

  /// "Everything may have changed": a reconnect, or a signal without a table.
  ContentChange.resync() : this(resyncSource);

  static const resyncSource = '*';
  static int _counter = 0;

  final String source;
  final int seq;

  bool get isResync => source == resyncSource;

  @override
  String toString() => 'ContentChange($source#$seq)';
}

enum SyncStatus { subscribed, down }

typedef SyncDisposer = void Function();

/// Opens one Realtime subscription for [source] and returns how to close it.
/// [onEvent] gets the changed row when there is one.
typedef SubscribeFn = SyncDisposer Function(
  String source,
  void Function(Map<String, dynamic>? record) onEvent,
  void Function(SyncStatus status) onStatus,
);

/// Keeps ONE subscription per source, so a failing one (a table missing from the
/// Realtime publication, say) cannot take the others down. After a drop it
/// retries with a growing delay, and when the subscription is back it announces
/// a resync, because events were missed in between. Everything is cancelled on
/// [dispose].
class ContentSyncEngine {
  ContentSyncEngine({
    required this.subscribe,
    this.sources = const [...syncedTables, signalSource],
    this.retryBase = const Duration(seconds: 15),
    this.retryMax = const Duration(minutes: 5),
    this.maxAttempts = 5,
  });

  final SubscribeFn subscribe;
  final List<String> sources;
  final Duration retryBase;
  final Duration retryMax;
  final int maxAttempts;

  final _controller = StreamController<ContentChange>.broadcast();
  final _states = <String, _SourceState>{};
  bool _started = false;
  bool _disposed = false;

  Stream<ContentChange> get changes => _controller.stream;

  /// Sources that are currently subscribed (for diagnostics and tests).
  Set<String> get connected => {
    for (final e in _states.entries)
      if (e.value.up) e.key,
  };

  void start() {
    if (_started || _disposed) return;
    _started = true;
    for (final s in sources) {
      _open(s);
    }
  }

  void _open(String source) {
    if (_disposed) return;
    final st = _states.putIfAbsent(source, _SourceState.new);
    st.retry?.cancel();
    st.disposer?.call(); // never two channels for one source
    final generation = ++st.generation;
    st.disposer = subscribe(
      source,
      (record) {
        if (!_disposed && generation == st.generation) {
          _onEvent(source, record);
        }
      },
      (status) {
        if (!_disposed && generation == st.generation) {
          _onStatus(source, st, status);
        }
      },
    );
  }

  void _onEvent(String source, Map<String, dynamic>? record) {
    if (source == signalSource) {
      final table = record?['source'];
      _emit(
        table is String && table.isNotEmpty
            ? ContentChange(table)
            : ContentChange.resync(),
      );
    } else {
      _emit(ContentChange(source));
    }
  }

  void _onStatus(String source, _SourceState st, SyncStatus status) {
    if (status == SyncStatus.subscribed) {
      final reconnected = st.dropped;
      st
        ..up = true
        ..dropped = false
        ..attempts = 0
        ..gaveUp = false
        ..retry?.cancel();
      if (reconnected) _emit(ContentChange.resync());
      return;
    }
    st
      ..up = false
      ..dropped = true;
    _scheduleRetry(source, st);
  }

  void _scheduleRetry(String source, _SourceState st) {
    if (st.retry?.isActive ?? false) return;
    if (st.attempts >= maxAttempts) {
      st.gaveUp = true;
      debugPrint(
        'content sync: giving up on $source (periodic refresh covers it)',
      );
      return;
    }
    final ms = retryBase.inMilliseconds * math.pow(2, st.attempts).toInt();
    st.attempts++;
    st.retry = Timer(
      Duration(milliseconds: math.min(ms, retryMax.inMilliseconds)),
      () => _open(source),
    );
  }

  /// The app came back to the foreground: try again where we gave up.
  void retryFailed() {
    if (_disposed) return;
    for (final e in _states.entries) {
      final st = e.value;
      if (!st.up && (st.gaveUp || st.dropped)) {
        st
          ..attempts = 0
          ..gaveUp = false;
        _open(e.key);
      }
    }
  }

  void _emit(ContentChange c) {
    if (!_controller.isClosed) _controller.add(c);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final st in _states.values) {
      st.retry?.cancel();
      st.disposer?.call();
      st.generation++;
    }
    _states.clear();
    await _controller.close();
  }
}

class _SourceState {
  SyncDisposer? disposer;
  Timer? retry;
  int generation = 0;
  int attempts = 0;
  bool up = false;
  bool dropped = false;
  bool gaveUp = false;
}

/// The real Realtime connection: one channel per source.
SubscribeFn supabaseSubscribe(SupabaseClient client) {
  var n = 0;
  return (source, onEvent, onStatus) {
    final channel = client.channel('content-sync:$source:${++n}');
    channel.onPostgresChanges(
      // the signal log only ever APPENDS; its occasional pruning must not look like a change
      event: source == signalSource
          ? PostgresChangeEvent.insert
          : PostgresChangeEvent.all,
      schema: 'public',
      table: source,
      callback: (payload) =>
          onEvent(payload.newRecord.isEmpty ? null : payload.newRecord),
    );
    try {
      channel.subscribe((status, error) {
        onStatus(
          status == RealtimeSubscribeStatus.subscribed
              ? SyncStatus.subscribed
              : SyncStatus.down,
        );
        if (status != RealtimeSubscribeStatus.subscribed) {
          debugPrint('content sync $source: ${status.name}');
        }
      });
    } catch (e) {
      debugPrint('content sync $source unavailable: ${e.runtimeType}');
      onStatus(SyncStatus.down);
    }
    return () => unawaited(client.removeChannel(channel));
  };
}

/// Null when Supabase is not initialised (tests, previews).
final contentSyncEngineProvider = Provider<ContentSyncEngine?>((ref) {
  final SupabaseClient client;
  try {
    client = Supabase.instance.client;
  } catch (_) {
    return null;
  }
  final engine = ContentSyncEngine(subscribe: supabaseSubscribe(client))
    ..start();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Emits a [ContentChange] for each change of a synced table. Overridable in
/// tests. When Realtime is unavailable it is simply silent: the app still
/// refreshes on resume, periodically, on the mission tab and by pull-to-refresh.
final contentChangesProvider = StreamProvider<ContentChange>(
  (ref) =>
      ref.watch(contentSyncEngineProvider)?.changes ??
      const Stream<ContentChange>.empty(),
);

/// How often the app re-reads the cheap live content while it is in the
/// foreground, as a safety net under Realtime.
final contentPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 60),
);

/// Re-reads what [table] feeds. Cheap and idempotent.
void invalidateForTable(ProviderContainer ref, String table) {
  switch (table) {
    case 'restaurant_overrides':
    case 'restaurant_menus':
    case 'restaurant_photos':
      ref.invalidate(restaurantOverridesProvider);
      ref.invalidate(restaurantMenusProvider);
      ref.invalidate(restaurantPhotosProvider);
      // What the conditions are judged on (prices, hours, menus).
      ref.invalidate(nearbyMenusProvider);
      ref.invalidate(insightsForIdsProvider);
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

/// Everything an admin can publish, re-read (app resume, reconnect).
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

/// The cheap part, for the periodic safety net: plain table reads, no restaurant
/// search (that one calls an external API) and no mission sync.
///
/// It must be INVISIBLE. Invalidating a provider that others watch sends all of
/// them back to loading (the university list feeds the selected campus, which
/// feeds every restaurant list, the map and the meal card), so Home flashed
/// its skeletons and re-ran the restaurant search once a minute. So:
///  - announcements, admin overrides, menus and photos are leaves: they are
///    re-read in place and keep showing what they have meanwhile;
///  - the campus list and the cafeteria list are fetched in the background and
///    only swapped in (a normal reload) when what the server says has changed;
///  - meal weeks are left to their own cache expiry, Realtime, resume and
///    pull-to-refresh, because re-reading them reloads the Home meal card.
void refreshLiveContent(ProviderContainer ref) {
  ref.invalidate(appContentProvider);
  ref.invalidate(restaurantOverridesProvider);
  ref.invalidate(restaurantMenusProvider);
  ref.invalidate(restaurantPhotosProvider);
  ref.invalidate(nearbyMenusProvider);
  ref.invalidate(insightsForIdsProvider);
  unawaited(_reloadUniversitiesIfChanged(ref));
  unawaited(_reloadCafeteriasIfChanged(ref));
}

Future<void> _reloadUniversitiesIfChanged(ProviderContainer ref) async {
  try {
    final fresh = await ref.read(universityRepositoryProvider).fetchAll();
    final shown = ref.read(universityListProvider).value;
    if (shown == null || !_sameUniversities(shown, fresh)) {
      ref.invalidate(universityListProvider);
    }
  } catch (e) {
    // Best effort: a failed background read keeps what is on screen.
    debugPrint('live refresh (universities) skipped: ${e.runtimeType}');
  }
}

Future<void> _reloadCafeteriasIfChanged(ProviderContainer ref) async {
  try {
    final campus = ref.read(selectedUniversityProvider).value;
    final shown = ref.read(campusCafeteriasProvider).value;
    // Nothing on screen to keep fresh.
    if (campus == null || shown == null) return;
    final fresh = await ref
        .read(campusMealRepositoryProvider)
        .cafeterias(campus.id);
    // The campus may have been switched while the read was in flight.
    if (ref.read(selectedUniversityProvider).value?.id != campus.id) return;
    if (!_sameCafeterias(shown, fresh)) {
      ref.invalidate(campusCafeteriasProvider);
    }
  } catch (e) {
    debugPrint('live refresh (cafeterias) skipped: ${e.runtimeType}');
  }
}

// `==` on these models is by id (they are identities), so what changed has to
// be compared field by field.
bool _sameUniversities(List<University> a, List<University> b) =>
    a.length == b.length &&
    [
      for (var i = 0; i < a.length; i++)
        a[i].id == b[i].id &&
            a[i].nameKo == b[i].nameKo &&
            a[i].nameEn == b[i].nameEn &&
            a[i].city == b[i].city &&
            a[i].latitude == b[i].latitude &&
            a[i].longitude == b[i].longitude,
    ].every((same) => same);

bool _sameCafeterias(List<CampusCafeteria> a, List<CampusCafeteria> b) =>
    a.length == b.length &&
    [
      for (var i = 0; i < a.length; i++)
        a[i].id == b[i].id &&
            a[i].universityId == b[i].universityId &&
            a[i].kind == b[i].kind &&
            a[i].nameKo == b[i].nameKo &&
            a[i].nameEn == b[i].nameEn &&
            a[i].nameZh == b[i].nameZh &&
            a[i].locationDescription == b[i].locationDescription &&
            a[i].operatingNote == b[i].operatingNote &&
            a[i].photoUrl == b[i].photoUrl &&
            listEquals(a[i].mealTypes, b[i].mealTypes) &&
            setEquals(a[i].operatingDays, b[i].operatingDays),
    ].every((same) => same);

/// Pull-to-refresh: everything, and wait until the announcements are re-read.
Future<void> refreshAllContentAndWait(ProviderContainer ref) async {
  refreshAllContent(ref);
  try {
    await ref.read(appContentProvider.future);
  } catch (_) {}
}
