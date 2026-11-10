import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/sync/content_sync.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/restaurants/providers/restaurant_providers.dart';

import 'package:meogeobojo/features/university/models/university.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';
import 'package:meogeobojo/features/university/repositories/university_repository.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Admin changes reach a running app: live (Realtime), on resume, and by
/// pull-to-refresh. The Realtime source is replaced by a controllable stream;
/// what is tested is "a change event -> the right screens re-read".
class _CountingUniversities implements UniversityRepository {
  int fetches = 0;
  @override
  Future<List<University>> fetchAll() async {
    fetches++;
    return kVerifiedUniversities;
  }
}

void main() {
  late _CountingUniversities universities;
  late StreamController<String> changes;
  late FakeMissionRepository missions;
  late FakeRestaurantOverrideRepository overrides;

  Future<Harness> open(WidgetTester tester) async {
    changes = StreamController<String>.broadcast();
    addTearDown(changes.close);
    universities = _CountingUniversities();
    missions = FakeMissionRepository();
    overrides = FakeRestaurantOverrideRepository(
      overrides: {
        'a': const RestaurantOverride(kakaoId: 'a', visibility: 'published'),
      },
    );
    final h = await buildHarness(
      auth: FakeAuthGateway(user: fakeUser()),
      profiles: FakeProfileRepository(
        onboardingCompleted: true,
        nickname: '민수',
      ),
      restaurants: FakeRestaurantRepository(items: [fakeRestaurant('a')]),
      missions: missions,
      overridesRepo: overrides,
      universities: universities,
      extraOverrides: [
        contentChangesProvider.overrideWith((ref) => changes.stream),
      ],
    );
    await pumpApp(
      tester,
      h,
      home: const AppShell(),
      size: const Size(390, 1200),
    );
    await h.container.read(restaurantOverridesProvider.future);
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('a mission or campaign change re-reads the missions', (
    tester,
  ) async {
    final h = await open(tester);
    h.container.read(shellTabProvider.notifier).select(ShellTabs.missions);
    await tester.pumpAndSettle();
    final before = missions.syncs;
    changes.add('missions');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(missions.syncs, greaterThan(before));
    final mid = missions.syncs;
    changes.add('monthly_campaigns');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(missions.syncs, greaterThan(mid));
  });

  testWidgets('restaurant, menu and photo changes re-read the admin data', (
    tester,
  ) async {
    await open(tester);
    for (final table in [
      'restaurant_overrides',
      'restaurant_menus',
      'restaurant_photos',
    ]) {
      final before = overrides.forPlacesCalls;
      changes.add(table);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(overrides.forPlacesCalls, greaterThan(before), reason: table);
    }
  });

  testWidgets('a burst of changes is one refresh, not one per row', (
    tester,
  ) async {
    await open(tester);
    final before = overrides.forPlacesCalls;
    for (var i = 0; i < 6; i++) {
      changes.add('restaurant_overrides');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // the lists re-fetch once (each fetch asks for overrides once per list provider)
    expect(overrides.forPlacesCalls - before, lessThan(6));
  });

  testWidgets('a published university change re-reads the campus list', (
    tester,
  ) async {
    await open(tester);
    final before = universities.fetches;
    changes.add('universities');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(universities.fetches, greaterThan(before));
  });

  testWidgets('unrelated tables change nothing', (tester) async {
    await open(tester);
    final before = overrides.forPlacesCalls;
    changes.add('some_other_table');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(overrides.forPlacesCalls, before);
  });

  testWidgets('coming back to the app re-reads everything published', (
    tester,
  ) async {
    final h = await open(tester);
    h.container.read(shellTabProvider.notifier).select(ShellTabs.missions);
    await tester.pumpAndSettle();
    final mBefore = missions.syncs;
    final oBefore = overrides.forPlacesCalls;
    final uBefore = universities.fetches;
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
    expect(missions.syncs, greaterThan(mBefore));
    expect(overrides.forPlacesCalls, greaterThan(oBefore));
    expect(universities.fetches, greaterThan(uBefore));
  });

  testWidgets('pull-to-refresh on the mission page asks the server again', (
    tester,
  ) async {
    final h = await open(tester);
    h.container.read(shellTabProvider.notifier).select(ShellTabs.missions);
    await tester.pumpAndSettle();
    final before = missions.syncs;
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(missions.syncs, greaterThan(before));
  });
}
