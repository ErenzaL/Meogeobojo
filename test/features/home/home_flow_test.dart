import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/app.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_repository.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import '../../support/harness.dart' as pump_app;

/// Nearby/menu sections sit below the fold in the lazy Home list.
Future<void> scrollToNearby(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('학교 주변 맛집'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
  await tester.pumpAndSettle();
}

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

  for (final size in const [Size(320, 568), Size(375, 812), Size(430, 932)]) {
    testWidgets('Home renders real content without overflow at $size', (
      tester,
    ) async {
      await pumpApp(tester, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('순천향대학교'), findsWidgets);
      expect(find.text('메뉴, 식당, 키워드로 검색해보세요'), findsOneWidget);
      expect(find.text('추천 보러가기'), findsOneWidget);
      await scrollToNearby(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('학교 주변 맛집'), findsOneWidget);
      expect(find.text('국수집1'), findsOneWidget);
      // Nothing fabricated: no ratings / prices on cards.
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.textContaining('원'), findsNothing);
    });
  }

  testWidgets('Home survives large system text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(375, 812));
    expect(tester.takeException(), isNull);
    await scrollToNearby(tester);
    expect(tester.takeException(), isNull);
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

  testWidgets('selecting a university updates Home, requeries and persists', (
    tester,
  ) async {
    final (c, fake) = await pumpApp(tester);
    await tester.tap(find.text('순천향대학교').first);
    await tester.pumpAndSettle();
    expect(find.text('학교 선택'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '호서');
    await tester.pumpAndSettle();
    expect(find.text('선문대학교'), findsNothing);
    await tester.tap(find.text('호서대학교'));
    await tester.pumpAndSettle();

    expect(find.text('학교 선택'), findsNothing); // sheet closed
    expect(c.read(selectedUniversityProvider).value!.nameKo, '호서대학교');
    expect(fake.nearbyCalls.last.$1, '호서대학교');
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

  testWidgets('API failure shows an error with retry, not fake data', (
    tester,
  ) async {
    final (_, fake) = await pumpApp(
      tester,
      repo: FakeRestaurantRepository(
        error: const RestaurantException(RestaurantErrorKind.network),
      ),
    );
    await scrollToNearby(tester);
    expect(find.text('맛집을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('인터넷 연결을 확인해주세요.'), findsOneWidget);
    final before = fake.nearbyCalls.length;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(fake.nearbyCalls.length, greaterThan(before));
  });

  testWidgets('empty result shows the searching mascot message', (
    tester,
  ) async {
    await pumpApp(tester, repo: FakeRestaurantRepository());
    await scrollToNearby(tester);
    expect(find.text('아직 주변 맛집을 찾지 못했어요'), findsOneWidget);
    expect(find.text('학교 바꾸기'), findsOneWidget);
  });

  testWidgets('guest tapping a heart gets a sign-in prompt', (tester) async {
    await pumpApp(tester);
    await scrollToNearby(tester);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('로그인하면 맛집을 저장할 수 있어요'), findsOneWidget);
  });

  testWidgets('restaurant card opens detail without invented facts', (
    tester,
  ) async {
    await pumpApp(tester);
    await scrollToNearby(tester);
    await tester.tap(find.text('국수집1'));
    await tester.pumpAndSettle();
    expect(find.text('카카오맵에서 보기'), findsOneWidget);
    expect(find.text('등록된 전화번호가 없어요'), findsOneWidget);
    expect(
      find.textContaining('평점'),
      findsOneWidget,
    ); // only in the "not provided" notice
    expect(find.textContaining('아직 제공되지 않아요'), findsOneWidget);
  });
}
