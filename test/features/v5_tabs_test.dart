import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/conditions/providers/conditions_providers.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/profile/screens/profile_screen.dart';
import 'package:meogeobojo/features/records/screens/records_screen.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

Restaurant spot(String name, double dLat) => Restaurant(
  kakaoId: name,
  name: name,
  categoryName: '음식점 > 한식',
  categoryGroupCode: 'FD6',
  address: '',
  roadAddress: '',
  phone: '',
  latitude: 36.7680 + dLat,
  longitude: 126.9305,
  distanceMeters: 0,
  placeUrl: null,
);

Future<Harness> open(
  WidgetTester tester,
  int tab, {
  bool signedIn = false,
  Set<String> favorites = const {},
  Size size = const Size(390, 844),
  List<Restaurant>? places,
}) async {
  final h = await buildHarness(
    auth: signedIn ? FakeAuthGateway(user: fakeUser()) : null,
    profiles: signedIn
        ? FakeProfileRepository(onboardingCompleted: true, nickname: '민수')
        : null,
    favorites: FakeFavoritesRepository(favorites),
    restaurants: FakeRestaurantRepository(
      items:
          places ??
          [spot('가까운집', 0.0005), spot('중간집', 0.0015), spot('먼집', 0.0070)],
    ),
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  h.container.read(shellTabProvider.notifier).select(tab);
  await tester.pumpAndSettle();
  return h;
}

void main() {
  group('지도', () {
    testWidgets(
      'desktop: the places list is a panel beside the map, not a sheet over it',
      (tester) async {
        await open(tester, ShellTabs.map, size: const Size(1440, 900));
        expect(find.byKey(const ValueKey('map-places-panel')), findsOneWidget);
        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(find.textContaining('조건에 맞는'), findsWidgets);
      },
    );

    testWidgets('phone: the places list stays a bottom sheet', (tester) async {
      await open(tester, ShellTabs.map);
      expect(find.byKey(const ValueKey('map-places-panel')), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    });

    testWidgets('V5 header, campus, chips and the matching-places sheet', (
      tester,
    ) async {
      await open(tester, ShellTabs.map);
      expect(find.text('주변 맛집'), findsOneWidget);
      expect(find.textContaining('순천향대학교'), findsWidgets);
      expect(find.text('정문 기준'), findsOneWidget);
      expect(find.text('지금 주문 가능'), findsOneWidget);
      expect(find.text('브레이크타임 없음'), findsOneWidget);
      expect(find.text('조건에 맞는 3곳'), findsOneWidget);
      expect(find.text('추천순'), findsOneWidget);
      expect(find.textContaining('직선거리로 추정'), findsOneWidget);
      expect(find.text('가까운집'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chips edit the SAME conditions as Home and search', (
      tester,
    ) async {
      final h = await open(tester, ShellTabs.map);
      expect(h.container.read(conditionsProvider).openNowOnly, isTrue);
      await tester.tap(find.text('지금 주문 가능'));
      await tester.pumpAndSettle();
      expect(h.container.read(conditionsProvider).openNowOnly, isFalse);
      expect(find.text('지금 주문 가능'), findsNothing);

      await tester.tap(find.text('주차 가능'));
      await tester.pumpAndSettle();
      expect(h.container.read(conditionsProvider).amenities, {Amenity.parking});
    });

    testWidgets('sort menu changes the order; no match shows the empty state', (
      tester,
    ) async {
      final h = await open(tester, ShellTabs.map);
      await tester.tap(find.text('추천순'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가격순').last);
      await tester.pumpAndSettle();
      expect(h.container.read(conditionsProvider).sort, SortMode.price);
      expect(find.text('가격순'), findsOneWidget);

      h.container
          .read(conditionsProvider.notifier)
          .update((c) => c.copyWith(cuisines: {Cuisine.japanese}));
      await tester.pumpAndSettle();
      expect(find.text('조건에 맞는 0곳'), findsOneWidget);
      expect(find.text('조건에 맞는 곳이 없어요'), findsOneWidget);
      // The empty state offers to clear everything; clearing restores the list.
      expect(find.text('모두 풀기'), findsOneWidget);
      h.container.read(conditionsProvider.notifier).clear();
      await tester.pumpAndSettle();
      expect(find.text('조건에 맞는 3곳'), findsOneWidget);
    });

    testWidgets('no overflow on a small phone with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, ShellTabs.map, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
    });
  });

  group('밥수다', () {
    testWidgets('filters, composer and an honest empty feed', (tester) async {
      await open(tester, ShellTabs.community);
      expect(find.text('밥수다'), findsWidgets);
      expect(find.text('순천향대학교 학생 커뮤니티'), findsOneWidget);
      for (final t in ['전체', '맛집 리뷰', '같이 먹어요', '질문']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('오늘 먹은 메뉴를 나눠볼까요?'), findsOneWidget);
      expect(find.text('아직 올라온 이야기가 없어요'), findsOneWidget);
      // selecting a filter moves the check
      await tester.tap(find.text('질문'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('writing says it is coming, it never pretends to post', (
      tester,
    ) async {
      await open(tester, ShellTabs.community);
      await tester.tap(find.text('리뷰 쓰기'));
      await tester.pump();
      expect(find.text('밥수다 글쓰기는 준비 중이에요.'), findsOneWidget);
    });
  });

  group('Records (opened from MY → 내 활동 → 나의 기록)', () {
    Future<void> openRecords(
      WidgetTester tester, {
      Set<String> favorites = const {},
    }) async {
      await open(
        tester,
        ShellTabs.profile,
        signedIn: true,
        favorites: favorites,
        size: const Size(390, 1400),
      );
      // (the stats card has a 나의 기록 label too: the menu row is the last)
      await tester.ensureVisible(find.text('나의 기록').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('나의 기록').last);
      await tester.pumpAndSettle();
    }

    testWidgets('the original Records page opens and keeps its content', (
      tester,
    ) async {
      await openRecords(tester);
      expect(find.byType(RecordsScreen), findsOneWidget);
      expect(find.text('내 기록'), findsOneWidget);
      expect(find.text('나만 볼 수 있는 맛집 일기예요'), findsOneWidget);
      expect(find.text('11월 리포트'), findsOneWidget);
      expect(find.text('아직 남긴 기록이 없어요'), findsOneWidget);
    });

    testWidgets('"가고 싶은 곳" is still the real saved count; add is honest', (
      tester,
    ) async {
      await openRecords(tester, favorites: {'a', 'b'});
      expect(find.text('가고 싶은 곳 2'), findsOneWidget);
      await tester.tap(find.text('기록하기'));
      await tester.pump();
      expect(find.textContaining('준비 중'), findsOneWidget);
    });

    testWidgets('back returns to MY', (tester) async {
      await openRecords(tester);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(RecordsScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('나의 기록'), findsWidgets);
    });

    testWidgets('the bottom nav no longer has a 기록 tab', (tester) async {
      await open(tester, ShellTabs.home);
      expect(find.text('기록'), findsNothing);
      expect(find.text('미션'), findsOneWidget);
    });
  });

  group('MY', () {
    testWidgets(
      'V5 sections: hero, campus, stats, 내 활동 (the 내 조건 block is gone)',
      (tester) async {
        await open(
          tester,
          ShellTabs.profile,
          signedIn: true,
          favorites: {'a'},
          size: const Size(390, 1400),
        );
        expect(find.text('마이페이지'), findsOneWidget);
        expect(find.text('민수'), findsOneWidget);
        expect(find.text('꾸미기'), findsNothing);
        // removed: the heading, the restart link, the "no conditions" line and the origin row
        expect(find.text('내 조건'), findsNothing);
        expect(find.text('처음부터 다시 설정 →'), findsNothing);
        expect(find.text('아직 고른 조건이 없어요. 예산과 거리부터 골라 보세요.'), findsNothing);
        expect(find.text('거리 계산 기준 위치 · 저장한 핀 0개'), findsNothing);
        // everything around it is still there
        expect(find.text('내 활동'), findsOneWidget);
        expect(find.text('1'), findsWidgets); // real saved count
      },
    );

    testWidgets(
      'the 내 조건 block is gone on the website layout too, and the page still lays out',
      (tester) async {
        await open(
          tester,
          ShellTabs.profile,
          signedIn: true,
          favorites: {'a'},
          size: const Size(1280, 1000),
        );
        expect(find.text('내 조건'), findsNothing);
        expect(find.text('처음부터 다시 설정 →'), findsNothing);
        expect(find.text('내 활동'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the walking origin and "start over" are still reachable from Home',
      (tester) async {
        await open(
          tester,
          ShellTabs.home,
          signedIn: true,
          size: const Size(390, 1400),
        );
        await tester.tap(find.text('정문 기준').first);
        await tester.pumpAndSettle();
        expect(find.text('어디서 출발하나요?'), findsOneWidget);
      },
    );
  });
}
