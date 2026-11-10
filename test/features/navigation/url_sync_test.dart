import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/utils/url_sync.dart';

import '../../support/harness.dart';

class Reported {
  final calls = <(String, bool)>[];
  var multiEntry = 0;
}

Future<(Harness, Reported)> open(
  WidgetTester tester, {
  bool enabled = true,
}) async {
  final r = Reported();
  final h = await buildHarness(
    extraOverrides: [
      urlSyncEnabledProvider.overrideWithValue(enabled),
      urlReporterProvider.overrideWithValue(
        (uri, {required replace}) async => r.calls.add((uri.path, replace)),
      ),
      urlHistoryModeProvider.overrideWithValue(() async => r.multiEntry++),
    ],
  );
  await pumpApp(tester, h, home: const AppShell(), size: const Size(1440, 900));
  await tester.pumpAndSettle();
  return (h, r);
}

NavigatorState nav(WidgetTester tester) =>
    Navigator.of(tester.element(find.byType(AppShell, skipOffstage: false)));

int tab(Harness h) => h.container.read(shellTabProvider);

void main() {
  group('address bar follows the tabs', () {
    testWidgets(
      'on start: multi-entry history, and the first entry names the tab',
      (tester) async {
        final (_, r) = await open(tester);
        expect(r.multiEntry, 1);
        expect(r.calls, [('/home', true)]); // replace, not an extra entry
      },
    );

    for (final e in {
      'Map': ('/map', ShellTabs.map),
      'Missions': ('/missions', ShellTabs.missions),
      'MY': ('/profile', ShellTabs.profile),
    }.entries) {
      testWidgets(
        'choosing ${e.key} reports ${e.value.$1} as a NEW history entry',
        (tester) async {
          final (h, r) = await open(tester);
          r.calls.clear();
          h.container.read(shellTabProvider.notifier).select(e.value.$2);
          await tester.pumpAndSettle();
          expect(r.calls, [(e.value.$1, false)]);
        },
      );
    }

    testWidgets('the header tabs do it too (real clicks)', (tester) async {
      final (h, r) = await open(tester);
      r.calls.clear();
      await tester.tap(find.text('지도').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('미션').first);
      await tester.pumpAndSettle();
      expect(tab(h), ShellTabs.missions);
      expect(r.calls, [('/map', false), ('/missions', false)]);
    });

    testWidgets('disabled (phones, tests): nothing is reported', (
      tester,
    ) async {
      final (h, r) = await open(tester, enabled: false);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.map);
      await tester.pumpAndSettle();
      expect(r.calls, isEmpty);
      expect(r.multiEntry, 0);
    });
  });

  group('browser Back / Forward / typed URL', () {
    testWidgets(
      'a URL change selects its tab and does not write the address bar again',
      (tester) async {
        final (h, r) = await open(tester);
        r.calls.clear();
        nav(tester).pushNamed(
          '/community',
        ); // what the framework does with a browser navigation
        await tester.pumpAndSettle();
        expect(tab(h), ShellTabs.community);
        expect(r.calls, isEmpty);
        expect(
          nav(tester).canPop(),
          isFalse,
        ); // the landing route is gone: no stacked duplicate
        expect(find.byType(AppShell), findsOneWidget);
      },
    );

    testWidgets('Back and Forward walk through the tabs in order', (
      tester,
    ) async {
      final (h, r) = await open(tester);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.map);
      await tester.pumpAndSettle();
      h.container.read(shellTabProvider.notifier).select(ShellTabs.missions);
      await tester.pumpAndSettle();
      r.calls.clear();
      nav(tester).pushNamed('/map'); // Back
      await tester.pumpAndSettle();
      expect(tab(h), ShellTabs.map);
      nav(tester).pushNamed('/home'); // Back
      await tester.pumpAndSettle();
      expect(tab(h), ShellTabs.home);
      nav(tester).pushNamed('/map'); // Forward
      await tester.pumpAndSettle();
      expect(tab(h), ShellTabs.map);
      expect(r.calls, isEmpty);
      expect(nav(tester).canPop(), isFalse);
    });

    testWidgets(
      'Back while a detail screen is open closes it (and switches to the entry\'s tab)',
      (tester) async {
        final (h, r) = await open(tester);
        h.container.read(shellTabProvider.notifier).select(ShellTabs.map);
        await tester.pumpAndSettle();
        r.calls.clear();
        nav(tester).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('DETAIL')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('DETAIL'), findsOneWidget);
        expect(r.calls, [
          ('/map', false),
        ]); // the screen got its own history entry
        nav(tester).pushNamed('/map'); // Back lands on that entry
        await tester.pumpAndSettle();
        expect(find.text('DETAIL'), findsNothing);
        expect(tab(h), ShellTabs.map);
        expect(nav(tester).canPop(), isFalse);
      },
    );

    testWidgets('a mistyped address opens Home, never an error', (
      tester,
    ) async {
      final (h, _) = await open(tester);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
      await tester.pumpAndSettle();
      nav(tester).pushNamed('/no-such-page');
      await tester.pumpAndSettle();
      expect(tab(h), ShellTabs.home);
      expect(tester.takeException(), isNull);
      expect(nav(tester).canPop(), isFalse);
    });

    testWidgets('dialogs and menus do not add history entries', (tester) async {
      final (_, r) = await open(tester);
      r.calls.clear();
      showDialog<void>(
        context: tester.element(find.byType(AppShell)),
        builder: (_) => const AlertDialog(title: Text('x')),
      );
      await tester.pumpAndSettle();
      expect(r.calls, isEmpty);
    });
  });
}
