import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/sync/content_sync.dart';
import 'package:meogeobojo/features/content/models/app_content.dart';
import 'package:meogeobojo/features/content/providers/app_content_providers.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

/// An announcement as the Admin's 앱 콘텐츠 page publishes it.
AppContent notice(String title, [String body = 'test']) => AppContent(
  id: 'n-$title',
  kind: AppContentKind.announcement,
  title: title,
  body: body,
);

/// Regression tests for "I took the announcement down in Admin but the app kept showing it".
///
/// Two independent causes:
///  1. Riverpod drops a state equal to the previous one, and the shell was fed the bare table name,
///     so after the first `app_content` event every later one (the unpublish) never reached the listener.
///  2. Realtime never delivers an update that makes a row invisible under row-level security, and an
///     unpublish (`active = false`) is exactly that. The database now also announces every change
///     through an always-readable signal table, and the app additionally re-reads on resume, on a
///     timer and on pull-to-refresh.
void main() {
  late StreamController<ContentChange> changes;
  late FakeAppContentRepository repo;

  Future<Harness> open(
    WidgetTester tester, {
    List<AppContent> items = const [],
    Duration? poll,
  }) async {
    changes = StreamController<ContentChange>.broadcast();
    addTearDown(changes.close);
    repo = FakeAppContentRepository(items);
    final h = await buildHarness(
      content: repo,
      extraOverrides: [
        contentChangesProvider.overrideWith((ref) => changes.stream),
        if (poll != null) contentPollIntervalProvider.overrideWithValue(poll),
      ],
    );
    await pumpApp(
      tester,
      h,
      home: const AppShell(),
      size: const Size(390, 1200),
    );
    await tester.pumpAndSettle();
    return h;
  }

  /// An event, then the 800 ms debounce and the reload.
  Future<void> adminChange(
    WidgetTester tester, [
    String table = 'app_content',
  ]) async {
    changes.add(ContentChange(table));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  group('live changes (Realtime)', () {
    testWidgets('publish -> the announcement appears without any refresh', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Test'), findsNothing);
      repo.items = [notice('Test')];
      await adminChange(tester);
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('test'), findsOneWidget);
    });

    testWidgets('update -> the text changes', (tester) async {
      await open(tester, items: [notice('Test', 'before')]);
      expect(find.text('before'), findsOneWidget);
      repo.items = [notice('Test', 'after')];
      await adminChange(tester);
      expect(find.text('before'), findsNothing);
      expect(find.text('after'), findsOneWidget);
    });

    testWidgets('unpublish -> the announcement is removed', (tester) async {
      await open(tester, items: [notice('Test')]);
      expect(find.text('Test'), findsOneWidget);
      repo.items = [];
      await adminChange(tester);
      expect(find.text('Test'), findsNothing);
      expect(find.text('test'), findsNothing);
    });

    testWidgets('delete -> the announcement is removed', (tester) async {
      await open(tester, items: [notice('Test')]);
      repo.items = [];
      // a DELETE carries no row: it is just another event for the table
      await adminChange(tester);
      expect(find.text('Test'), findsNothing);
    });

    testWidgets(
      'REGRESSION: publish then unpublish, both announced as "app_content", ends with NO banner',
      (tester) async {
        await open(tester);
        repo.items = [notice('Test')];
        await adminChange(tester); // the first event always worked
        expect(find.text('Test'), findsOneWidget);
        repo.items = [];
        await adminChange(
          tester,
        ); // the identical second event used to be dropped
        expect(find.text('Test'), findsNothing);
        repo.items = [notice('Test again')];
        await adminChange(tester); // and so was every one after it
        expect(find.text('Test again'), findsOneWidget);
      },
    );

    testWidgets('an empty API response means no banner and no error widget', (
      tester,
    ) async {
      await open(tester, items: const []);
      expect(find.text('Test'), findsNothing);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a failed read keeps the banner; a confirmed empty read removes it',
      (tester) async {
        await open(tester, items: [notice('Test')]);
        repo.failing = true; // the network drops
        await adminChange(tester);
        expect(
          find.text('Test'),
          findsOneWidget,
          reason: 'an outage is not a take-down',
        );
        repo.failing = false;
        repo.items = [];
        await adminChange(tester);
        expect(
          find.text('Test'),
          findsNothing,
          reason: 'the server confirmed there is nothing',
        );
      },
    );

    testWidgets(
      'rapid publish/unpublish settles on the LAST state with one or two reads',
      (tester) async {
        await open(tester);
        final before = repo.loads;
        for (var i = 0; i < 8; i++) {
          repo.items = i.isEven ? [notice('Test')] : [];
          changes.add(ContentChange('app_content'));
          await tester.pump(const Duration(milliseconds: 60));
        }
        // 8th flip (i = 7) was an unpublish
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Test'), findsNothing);
        expect(
          repo.loads - before,
          lessThanOrEqualTo(2),
          reason: 'a burst is debounced, not one request per event',
        );

        for (var i = 0; i < 5; i++) {
          repo.items = i.isEven ? [notice('Test')] : [];
          changes.add(ContentChange('app_content'));
          await tester.pump(const Duration(milliseconds: 60));
        }
        // 5th flip (i = 4) was a publish
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Test'), findsOneWidget);
      },
    );

    testWidgets(
      'a Realtime reconnect (resync) re-reads what was missed while offline',
      (tester) async {
        await open(tester);
        repo.items = [notice('Missed')];
        final before = repo.loads;
        changes.add(ContentChange.resync());
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(repo.loads, greaterThan(before));
        expect(find.text('Missed'), findsOneWidget);
      },
    );
  });

  group('fallbacks when no event arrives', () {
    testWidgets('coming back to the app (resume) re-reads the announcements', (
      tester,
    ) async {
      await open(tester);
      repo.items = [
        notice('While away'),
      ]; // changed while the app was in the background
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
      expect(find.text('While away'), findsOneWidget);
    });

    testWidgets(
      'a timer re-reads while the app is open, with no event at all',
      (tester) async {
        await open(tester, poll: const Duration(seconds: 5));
        repo.items = [notice('By timer')];
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text('By timer'), findsOneWidget);
        repo.items = []; // an unpublish that Realtime never announced
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text('By timer'), findsNothing);
      },
    );

    testWidgets('the timer is silent while the app is in the background', (
      tester,
    ) async {
      await open(tester, poll: const Duration(seconds: 5));
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      final before = repo.loads;
      await tester.pump(const Duration(seconds: 20));
      expect(repo.loads, before, reason: 'no requests while backgrounded');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.loads, greaterThan(before));
    });

    testWidgets('pull-to-refresh on Home re-reads the announcements', (
      tester,
    ) async {
      await open(tester);
      repo.items = [notice('Pulled')];
      await tester.drag(
        find.byKey(const PageStorageKey('home-scroll')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pulled'), findsOneWidget);
    });

    testWidgets('switching campus re-reads the announcements', (tester) async {
      final h = await open(tester);
      repo.items = [notice('After switching')];
      await h.container
          .read(selectedUniversityProvider.notifier)
          .select(kVerifiedUniversities[1]);
      await tester.pumpAndSettle();
      expect(find.text('After switching'), findsOneWidget);
    });

    testWidgets('going back to the Home tab re-reads the announcements', (
      tester,
    ) async {
      final h = await open(tester);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
      await tester.pumpAndSettle();
      repo.items = [notice('Seen on return')];
      h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
      await tester.pumpAndSettle();
      expect(find.text('Seen on return'), findsOneWidget);
    });
  });

  group('appContentProvider', () {
    Future<ProviderContainer> container(FakeAppContentRepository r) async {
      final h = await buildHarness(content: r);
      return h.container;
    }

    test('a failed first read shows nothing, not an error', () async {
      final r = FakeAppContentRepository()..failing = true;
      final c = await container(r);
      expect(await c.read(appContentProvider.future), isEmpty);
      expect(c.read(appContentProvider).hasError, isFalse);
    });

    test('a failure after an answer keeps that answer', () async {
      final r = FakeAppContentRepository([notice('Test')]);
      final c = await container(r);
      expect((await c.read(appContentProvider.future)).single.title, 'Test');
      r.failing = true;
      c.invalidate(appContentProvider);
      expect((await c.read(appContentProvider.future)).single.title, 'Test');
    });

    test('a confirmed empty answer replaces what was shown', () async {
      final r = FakeAppContentRepository([notice('Test')]);
      final c = await container(r);
      await c.read(appContentProvider.future);
      r.items = [];
      c.invalidate(appContentProvider);
      expect(await c.read(appContentProvider.future), isEmpty);
      expect(c.read(homeNoticesProvider), isEmpty);
    });

    test('publish, update and unpublish seen one after another', () async {
      final r = FakeAppContentRepository();
      final c = await container(r);
      Future<List<String>> titles() async {
        c.invalidate(appContentProvider);
        await c.read(appContentProvider.future);
        return [for (final n in c.read(homeNoticesProvider)) n.title];
      }

      expect(await titles(), isEmpty);
      r.items = [notice('Test')];
      expect(await titles(), ['Test']);
      r.items = [notice('Test (edited)')];
      expect(await titles(), ['Test (edited)']);
      r.items = [];
      expect(await titles(), isEmpty);
    });
  });
}
