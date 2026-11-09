import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/app.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import '../../support/harness.dart' as pump_app;

Future<(ProviderContainer, FakeRestaurantRepository)> pumpApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  FakeRestaurantRepository? repo,
  Map<String, Object> prefs = const {},
}) async {
  final fake =
      repo ??
      FakeRestaurantRepository(
        items: [
          fakeRestaurant('1', name: '국수집', distance: 120),
          fakeRestaurant(
            '2',
            name: '카페',
            category: '음식점 > 카페',
            group: 'CE7',
            distance: 300,
          ),
          fakeRestaurant('3', name: '아주아주아주아주아주긴이름의식당입니다', distance: 900),
        ],
      );
  final h = await buildHarness(
    storage: {'app_language': 'ko', ...prefs},
    restaurants: fake,
  );
  await pump_app.pumpApp(tester, h, home: const AppShell(), size: size);
  return (h.container, fake);
}

void main() {
  testWidgets('splash gate shows the existing splash first, then the shell', (
    tester,
  ) async {
    final h = await buildHarness();
    setPhoneSize(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MeogeobojoApp(
          home: SplashGate(duration: Duration(milliseconds: 100)),
        ),
      ),
    );
    expect(find.byType(AppShell), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('five tabs open and Home scroll position is kept', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('홈'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.text('밥수다'));
    await tester.pumpAndSettle();
    expect(find.text('밥수다는 준비 중이에요'), findsOneWidget);
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    // Food records are account-only: guests get a sign-in gate, not a fake list.
    expect(find.text('로그인하면 먹은 음식을 기록할 수 있어요'), findsOneWidget);
    await tester.tap(find.text('MY'));
    await tester.pumpAndSettle();
    expect(find.text('로그인 / 회원가입'), findsOneWidget);
    expect(find.text('로그인 없이 계속 둘러보기 →'), findsOneWidget);

    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a university re-queries Home and persists', (
    tester,
  ) async {
    final (c, fake) = await pumpApp(tester);
    expect(find.textContaining('정문 출발 기준'), findsOneWidget);

    final hoseo = (await c.read(universityListProvider.future))
        .firstWhere((u) => u.nameKo == '호서대학교');
    await c.read(selectedUniversityProvider.notifier).select(hoseo);
    await tester.pumpAndSettle();

    expect(c.read(selectedUniversityProvider).value!.nameKo, '호서대학교');
    expect(fake.nearbyCalls.last.$1, '호서대학교');
    // No campus points for this campus: the walk starts at its center.
    expect(find.textContaining('캠퍼스 중심 출발 기준'), findsOneWidget);
    expect(
      c.read(sharedPreferencesProvider).getString('selected_university_id'),
      '5c0a8f3e-0002-4a6e-9b1d-000000000002',
    );
  });

  testWidgets(
    'stored university is restored; unknown id falls back to default',
    (tester) async {
      final (c, _) = await pumpApp(
        tester,
        prefs: {
          'selected_university_id': '5c0a8f3e-0003-4a6e-9b1d-000000000003',
        },
      );
      expect(c.read(selectedUniversityProvider).value!.nameKo, '선문대학교');
    },
  );

  testWidgets('unknown stored university falls back to default', (
    tester,
  ) async {
    final (c, _) = await pumpApp(
      tester,
      prefs: {'selected_university_id': 'deleted-id'},
    );
    expect(c.read(selectedUniversityProvider).value!.nameKo, '순천향대학교');
  });
}
