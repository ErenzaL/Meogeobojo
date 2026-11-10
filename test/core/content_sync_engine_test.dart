import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/sync/content_sync.dart';

/// A stand-in for Supabase Realtime: tests open, drop and re-open subscriptions by hand.
class FakeRealtime {
  final subs = <FakeSub>[];
  int closedCount = 0;

  SyncDisposer subscribe(
    String source,
    void Function(Map<String, dynamic>? record) onEvent,
    void Function(SyncStatus status) onStatus,
  ) {
    final sub = FakeSub(source, onEvent, onStatus);
    subs.add(sub);
    return () {
      sub.closed = true;
      closedCount++;
    };
  }

  Iterable<FakeSub> open(String source) =>
      subs.where((s) => s.source == source && !s.closed);
  FakeSub current(String source) => open(source).single;
  int opened(String source) => subs.where((s) => s.source == source).length;
}

class FakeSub {
  FakeSub(this.source, this.onEvent, this.onStatus);
  final String source;
  final void Function(Map<String, dynamic>? record) onEvent;
  final void Function(SyncStatus status) onStatus;
  bool closed = false;

  void event([Map<String, dynamic>? record]) => onEvent(record);
  void up() => onStatus(SyncStatus.subscribed);
  void down() => onStatus(SyncStatus.down);
}

/// Stream events are delivered on a later microtask.
Future<void> flush() => settle(1);

Future<void> settle([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late FakeRealtime rt;
  late ContentSyncEngine engine;
  late List<ContentChange> got;

  ContentSyncEngine make({
    Duration base = const Duration(milliseconds: 10),
    int attempts = 3,
  }) {
    final e = ContentSyncEngine(
      subscribe: rt.subscribe,
      retryBase: base,
      retryMax: const Duration(milliseconds: 80),
      maxAttempts: attempts,
    );
    e.changes.listen(got.add);
    return e;
  }

  setUp(() {
    rt = FakeRealtime();
    got = [];
    engine = make();
  });
  tearDown(() => engine.dispose());

  group('subscriptions', () {
    test('one subscription per source, never duplicated', () async {
      engine.start();
      engine.start(); // a second start must not open a second set
      for (final s in [...syncedTables, signalSource]) {
        expect(rt.open(s), hasLength(1), reason: s);
      }
      expect(rt.subs, hasLength(syncedTables.length + 1));
    });

    test(
      'app_content is synced, and so is the always-readable signal table',
      () async {
        expect(syncedTables, contains('app_content'));
        expect(signalSource, 'content_sync');
      },
    );

    test(
      'dispose closes every subscription, stops events and cancels retries',
      () async {
        engine.start();
        rt.current('app_content').down(); // a retry is now pending
        final before = rt.opened('app_content');
        await engine.dispose();
        expect(rt.closedCount, greaterThanOrEqualTo(syncedTables.length + 1));
        expect(rt.open('app_content'), isEmpty);
        await settle(60);
        expect(
          rt.opened('app_content'),
          before,
          reason: 'no retry after dispose',
        );
        got.clear();
        for (final s in rt.subs) {
          s.event(); // a late callback from the old connection
        }
        await flush();
        expect(got, isEmpty);
      },
    );

    test('a stale callback from a replaced channel is ignored', () async {
      engine.start();
      final old = rt.current('app_content');
      old.down();
      await settle(40); // retry opened a new channel
      expect(old.closed, isTrue);
      got.clear();
      old.event();
      old.up();
      await flush();
      expect(got, isEmpty);
      rt.current('app_content').event();
      await flush();
      expect(got.map((c) => c.source), ['app_content']);
    });
  });

  group('events', () {
    test('a change of a table emits that table', () async {
      engine.start();
      rt.current('app_content').event({'id': 'x'});
      await flush();
      expect(got.map((c) => c.source), ['app_content']);
    });

    test(
      'identical consecutive events are all delivered as distinct events',
      () async {
        engine.start();
        final s = rt.current('app_content');
        s
          ..event()
          ..event()
          ..event();
        await flush();
        expect(got, hasLength(3));
        await flush();
        expect({for (final c in got) c.seq}, hasLength(3));
        await flush();
        expect(got[0] == got[1], isFalse);
      },
    );

    test(
      'REGRESSION: a Riverpod listener sees every event, not only the first',
      () async {
        // The shell listens through a StreamProvider. A StreamProvider<String> that emits
        // "app_content" three times notified the listener ONCE, so an unpublish that followed
        // a publish never refreshed the app.
        engine.start();
        final provider = StreamProvider<ContentChange>((ref) => engine.changes);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        var calls = 0;
        container.listen(provider, (_, next) {
          if (next.value != null) calls++;
        });
        final s = rt.current('app_content');
        s.event(); // publish
        await settle(5);
        s.event(); // unpublish
        await settle(5);
        s.event(); // delete
        await settle(5);
        expect(calls, 3);
      },
    );

    test('the signal table names the table that changed (an unpublish is announced here)', () async {
      engine.start();
      rt.current(signalSource).event({'source': 'app_content', 'version': 7});
      await flush();
      expect(got.map((c) => c.source), ['app_content']);
    });

    test('a signal without a table means "re-read everything"', () async {
      engine.start();
      rt.current(signalSource).event();
      rt.current(signalSource).event({'version': 1});
      await flush();
      expect(got.every((c) => c.isResync), isTrue);
      await flush();
      expect(got, hasLength(2));
    });
  });

  group('failure isolation, reconnect and retry', () {
    test('one source failing (for example a table missing from the Realtime publication) leaves the others working', () async {
      engine.start();
      rt.current(signalSource).down();
      rt.current('app_content').up();
      rt.current('app_content').event();
      await flush();
      expect(got.map((c) => c.source), ['app_content']);
      expect(engine.connected, contains('app_content'));
      expect(engine.connected, isNot(contains(signalSource)));
    });

    test(
      'the first successful subscription does not trigger a resync',
      () async {
        engine.start();
        for (final s in rt.subs) {
          s.up();
        }
        await flush();
        expect(got, isEmpty);
      },
    );

    test('REALTIME RECONNECT: after a drop and a successful re-subscribe, exactly one resync is announced', () async {
      engine.start();
      rt.current('app_content').up();
      rt.current('app_content').down(); // connection lost
      await settle(40); // the engine re-opens the channel
      rt.current('app_content').up(); // and it is back
      await flush();
      expect(got.where((c) => c.isResync), hasLength(1));
      rt
          .current('app_content')
          .up(); // a repeated "subscribed" is not another reconnect
      await flush();
      expect(got.where((c) => c.isResync), hasLength(1));
    });

    test(
      'retries with a growing delay and gives up after maxAttempts',
      () async {
        engine.start();
        rt.current('app_content').down();
        await settle(30);
        expect(rt.opened('app_content'), 2);
        rt.current('app_content').down();
        await settle(50);
        expect(rt.opened('app_content'), 3);
        rt.current('app_content').down();
        await settle(100);
        expect(rt.opened('app_content'), 4);
        rt.current('app_content').down(); // 3 attempts used: gives up
        await settle(150);
        expect(rt.opened('app_content'), 4, reason: 'stopped retrying');
      },
    );

    test(
      'coming back to the foreground retries what was given up on',
      () async {
        engine.start();
        for (var i = 0; i < 4; i++) {
          rt.current('app_content').down();
          await settle(100);
        }
        final before = rt.opened('app_content');
        engine.retryFailed();
        expect(rt.opened('app_content'), before + 1);
        expect(
          rt.open('app_content'),
          hasLength(1),
          reason: 'the old channel was closed first',
        );
        rt.current('app_content').up();
        await flush();
        expect(got.where((c) => c.isResync), hasLength(1));
      },
    );

    test('retryFailed leaves healthy subscriptions alone', () async {
      engine.start();
      rt.current('app_content').up();
      final before = rt.subs.length;
      engine.retryFailed();
      expect(rt.subs.length, before);
    });
  });
}
