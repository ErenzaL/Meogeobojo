import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

/// The server picks university-specific missions from
/// `profiles.selected_university_id`; the app used to remember the campus only
/// on the device, so those missions were never offered. These tests pin the
/// device <-> account sync.
void main() {
  final soonchunhyang = kVerifiedUniversities.first;
  final other = kVerifiedUniversities.firstWhere(
    (u) => u.id != soonchunhyang.id,
  );

  Future<Harness> open(
    WidgetTester tester, {
    required FakeProfileRepository profiles,
    Map<String, Object> storage = const {'app_language': 'ko'},
    bool signedIn = true,
    FakeMissionRepository? missions,
  }) async {
    final h = await buildHarness(
      allCampuses: true,
      storage: storage,
      auth: signedIn ? FakeAuthGateway(user: fakeUser()) : null,
      profiles: profiles,
      missions: missions,
    );
    await pumpApp(tester, h, home: const AppShell());
    await tester.pumpAndSettle();
    return h;
  }

  FakeProfileRepository profile({String? campus}) =>
      FakeProfileRepository(onboardingCompleted: true, nickname: '민수')
        ..selectedUniversityId = campus;

  testWidgets('an account with no campus gets the one the app shows', (
    tester,
  ) async {
    final p = profile();
    await open(tester, profiles: p);
    expect(p.universityWrites, [soonchunhyang.id]);
    expect(p.selectedUniversityId, soonchunhyang.id);
  });

  testWidgets('the device\'s own choice wins and updates the account', (
    tester,
  ) async {
    final p = profile(campus: soonchunhyang.id);
    await open(
      tester,
      profiles: p,
      storage: {'app_language': 'ko', selectedUniversityPrefsKey: other.id},
    );
    expect(p.universityWrites, [other.id]);
  });

  testWidgets('a device that never chose adopts the account\'s campus', (
    tester,
  ) async {
    final p = profile(campus: other.id);
    final h = await open(tester, profiles: p);
    expect(p.universityWrites, isEmpty); // nothing to push
    expect(
      (await h.container.read(selectedUniversityProvider.future)).id,
      other.id,
    );
  });

  testWidgets(
    'picking another campus while signed in saves it to the account',
    (tester) async {
      final p = profile(campus: soonchunhyang.id);
      final h = await open(tester, profiles: p);
      expect(p.universityWrites, isEmpty);
      await h.container.read(selectedUniversityProvider.notifier).select(other);
      await tester.pumpAndSettle();
      expect(p.universityWrites, [other.id]);
      expect(
        h.container.read(authControllerProvider).profile?.selectedUniversityId,
        other.id,
      );
    },
  );

  testWidgets(
    'saving the campus makes the app ask the server for missions again',
    (tester) async {
      final m = FakeMissionRepository();
      final p = profile(campus: soonchunhyang.id);
      final h = await open(tester, profiles: p, missions: m);
      final before = m.syncs;
      await h.container.read(selectedUniversityProvider.notifier).select(other);
      await tester.pumpAndSettle();
      expect(m.syncs, greaterThan(before));
    },
  );

  testWidgets(
    'a failing save never blocks the app and is retried on the next change',
    (tester) async {
      final p = profile(campus: soonchunhyang.id)
        ..universityErrors.add(Exception('offline'));
      final h = await open(tester, profiles: p);
      await h.container.read(selectedUniversityProvider.notifier).select(other);
      await tester.pumpAndSettle();
      expect(p.universityWrites, isEmpty); // the first write failed
      expect(tester.takeException(), isNull);
      await h.container
          .read(selectedUniversityProvider.notifier)
          .select(soonchunhyang);
      await h.container.read(selectedUniversityProvider.notifier).select(other);
      await tester.pumpAndSettle();
      expect(p.universityWrites, [other.id]);
    },
  );

  testWidgets('guests never write anything', (tester) async {
    final p = profile();
    final h = await open(tester, profiles: p, signedIn: false);
    await h.container.read(selectedUniversityProvider.notifier).select(other);
    await tester.pumpAndSettle();
    expect(p.universityWrites, isEmpty);
  });
}
