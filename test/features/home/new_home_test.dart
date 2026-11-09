import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/theme/theme_controller.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/campus_meals/screens/campus_meal_screen.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/conditions/providers/conditions_providers.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/origin/providers/origin_providers.dart';
import 'package:meogeobojo/features/recommendation/providers/ranking_providers.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_repository.dart';
import 'package:meogeobojo/features/search/screens/search_screen.dart';
import 'package:meogeobojo/features/home/screens/outside_compare_screen.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

const univId = '5c0a8f3e-0001-4a6e-9b1d-000000000001';

// 정문 is at (36.7680, 126.9305): these are ~56 m, ~167 m and ~778 m north.
Restaurant spot(String name, double dLat, {String category = '음식점 > 한식'}) =>
    Restaurant(
      kakaoId: name,
      name: name,
      categoryName: category,
      categoryGroupCode: 'FD6',
      address: '',
      roadAddress: '',
      phone: '',
      latitude: 36.7680 + dLat,
      longitude: 126.9305,
      distanceMeters: 0,
      placeUrl: null,
    );

final _places = [
  spot('먼집', 0.0070, category: '음식점 > 중식 > 마라탕'),
  spot('가까운집', 0.0005),
  spot('중간집', 0.0015, category: '음식점 > 일식'),
];

Future<Harness> openHome(
  WidgetTester tester, {
  FakeRestaurantRepository? repo,
  FakeCampusMealRepository? meals,
  Stream<DateTime>? clock,
  List<dynamic> overrides = const [],
  Map<String, Object> storage = const {'app_language': 'ko'},
  Size size = const Size(390, 844),
}) async {
  final h = await buildHarness(
    storage: storage,
    restaurants: repo ?? FakeRestaurantRepository(items: _places),
    meals: meals,
    clock: clock,
    extraOverrides: [
      // No 5-minute keep-alive timer left pending when the test ends.
      campusMealCacheDurationProvider.overrideWithValue(Duration.zero),
      for (final o in overrides) o,
    ],
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  return h;
}

/// Scrolls the Home list until [f] is built and on screen.
Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // Clear the floating nav bar that overlaps the bottom edge.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -140));
  await tester.pumpAndSettle();
}

/// Same, inside the open bottom sheet.
Future<void> revealInSheet(WidgetTester tester, Finder f) =>
    tester.scrollUntilVisible(
      f,
      150,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Future<void> scrollDown(WidgetTester tester, [double dy = -700]) async {
  await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  group('header, title and chips', () {
    testWidgets('shows wordmark, title, subtitle with meal/time/origin', (
      tester,
    ) async {
      await openHome(tester);
      expect(find.text('먹어보조'), findsOneWidget);
      expect(find.text('오늘 뭐 먹지?'), findsOneWidget);
      // Fixed clock in the harness: 18:54 Seoul.
      expect(find.text('저녁 · 18:54 · 정문 출발 기준'), findsOneWidget);
      expect(find.text('정문 기준'), findsOneWidget);
      expect(find.text('조건'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('the clock moves the subtitle every minute', (tester) async {
      final ticks = StreamController<DateTime>();
      // Not awaited: close() only completes once the provider has unsubscribed.
      addTearDown(() {
        unawaited(ticks.close());
      });
      await openHome(tester, clock: ticks.stream);
      ticks.add(DateTime.utc(2026, 11, 9, 9, 54));
      await tester.pumpAndSettle();
      expect(find.textContaining('18:54'), findsOneWidget);
      ticks.add(DateTime.utc(2026, 11, 9, 9, 55));
      await tester.pumpAndSettle();
      expect(find.textContaining('18:55'), findsOneWidget);
      expect(find.textContaining('18:54'), findsNothing);
    });

    testWidgets('search icon opens search; moon toggles dark mode', (
      tester,
    ) async {
      final h = await openHome(tester);
      await tester.tap(find.byIcon(Icons.dark_mode_outlined));
      await tester.pumpAndSettle();
      expect(h.container.read(themeModeProvider), ThemeMode.dark);
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('profile icon goes to MY', (tester) async {
      final h = await openHome(tester);
      await tester.tap(find.byIcon(Icons.person_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.profile);
    });
  });

  group('hero and alternatives', () {
    testWidgets('top pick shows rank, reason and arrival from the clock', (
      tester,
    ) async {
      await openHome(tester);
      expect(find.text('가까운집'), findsOneWidget);
      expect(find.text('3곳 중 1순위'), findsOneWidget);
      expect(find.text('가장 가까워요'), findsOneWidget);
      // 18:54 + 1 minute walk
      expect(find.text('18:55'), findsOneWidget);
      expect(find.text('도보 약 1분'), findsOneWidget);
      expect(find.text('길찾기'), findsOneWidget);
      expect(find.text('정보'), findsOneWidget);
    });

    testWidgets('nothing is invented when price / rating / hours are unknown', (
      tester,
    ) async {
      await openHome(tester);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('정보 없음'), findsOneWidget);
      expect(find.textContaining('★'), findsNothing);
      expect(find.textContaining('리뷰'), findsNothing);
      expect(find.textContaining('~'), findsNothing);
      expect(find.text('주문 가능'), findsNothing);
    });

    testWidgets('known facts appear: price, rating, last order and slack', (
      tester,
    ) async {
      await openHome(
        tester,
        overrides: [
          restaurantInsightsProvider.overrideWithValue({
            '가까운집': const RestaurantInsight(
              minPriceKrw: 12000,
              rating: 3.9,
              reviewCount: 25,
              lastOrderMinutes: 21 * 60 + 30,
              mainMenu: '마라탕',
            ),
          }),
        ],
      );
      expect(find.text('12,000~'), findsOneWidget);
      expect(find.textContaining('★ 3.9'), findsOneWidget);
      expect(find.textContaining('리뷰 25'), findsOneWidget);
      expect(find.text('21:30'), findsOneWidget);
      // 21:30 - 18:55 = 2h35m
      expect(find.text('2시간 35분 여유'), findsOneWidget);
    });

    testWidgets('arrival after last order says it closes before arrival', (
      tester,
    ) async {
      await openHome(
        tester,
        overrides: [
          restaurantInsightsProvider.overrideWithValue({
            '가까운집': const RestaurantInsight(lastOrderMinutes: 18 * 60 + 30),
          }),
          // the "order now" filter would otherwise hide this place
          conditionsProvider.overrideWith(
            () => _FixedConditions(openNow: false),
          ),
        ],
      );
      expect(find.text('도착 전에 마감돼요'), findsOneWidget);
    });

    testWidgets('alternatives are #2 and #3 and the map link counts all', (
      tester,
    ) async {
      final h = await openHome(tester);
      await reveal(tester, find.text('조건에 맞는 3곳 지도에서 보기'));
      expect(find.text('마음에 안 들면'), findsOneWidget);
      expect(find.text('중간집'), findsOneWidget);
      expect(find.text('먼집'), findsOneWidget);
      await tester.tap(find.text('조건에 맞는 3곳 지도에서 보기'));
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.map);
    });

    testWidgets('"하나 골라줘" swaps in another place and shows its rank', (
      tester,
    ) async {
      await openHome(tester);
      await scrollDown(tester, -300);
      await tester.tap(find.text('하나 골라줘'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.text('3곳 중 1순위'), findsNothing);
      expect(find.textContaining('3곳 중'), findsOneWidget);
    });
  });

  group('origin sheet', () {
    testWidgets('lists groups, marks the current one and re-ranks on pick', (
      tester,
    ) async {
      final h = await openHome(tester);
      await tester.tap(find.text('정문 기준'));
      await tester.pumpAndSettle();
      expect(find.text('어디서 출발하나요?'), findsOneWidget);
      expect(find.text('출입문'), findsOneWidget);
      expect(find.text('후문'), findsOneWidget);
      expect(find.text('단과대학'), findsOneWidget);
      expect(find.text('공과대학'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.textContaining('가장 가까운 곳: 가까운집 · 도보 1분'), findsWidgets);
      await revealInSheet(tester, find.text('지도에서 직접 찍기'));
      expect(find.text('내 핀'), findsOneWidget);
      expect(find.text('아직 저장한 핀이 없어요.'), findsOneWidget);
      // Back to the top to pick the back gate.
      await tester.drag(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('후문'));
      await tester.pumpAndSettle();
      expect(find.text('어디서 출발하나요?'), findsNothing);
      expect(find.text('후문 기준'), findsOneWidget);
      expect(find.textContaining('후문 출발 기준'), findsOneWidget);
      expect(h.container.read(originSelectionProvider), 'gate_back');
      expect(
        h.sp.getString('origin_selected_id'),
        'gate_back',
        reason: 'persisted',
      );
      // From the back gate (36.772) 먼집 (36.775) is now nearest.
      expect(find.text('먼집'), findsWidgets);
    });

    testWidgets('saved pins are listed, selectable and removable', (
      tester,
    ) async {
      final h = await openHome(tester);
      final pin = await h.container
          .read(savedPinsProvider.notifier)
          .add(
            universityId: univId,
            name: '기숙사 앞',
            latitude: 36.7700,
            longitude: 126.9305,
          );
      await tester.tap(find.text('정문 기준'));
      await tester.pumpAndSettle();
      await revealInSheet(tester, find.text('기숙사 앞'));
      expect(find.text('기숙사 앞'), findsOneWidget);
      await tester.tap(find.text('기숙사 앞'));
      await tester.pumpAndSettle();
      expect(find.text('기숙사 앞 기준'), findsOneWidget);
      expect(h.container.read(originProvider)!.id, pin.id);

      await h.container.read(savedPinsProvider.notifier).remove(pin.id);
      await tester.pumpAndSettle();
      // The deleted pin falls back to the default instead of dangling.
      expect(find.text('정문 기준'), findsOneWidget);
    });
  });

  group('conditions sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('조건'));
      await tester.pumpAndSettle();
      expect(find.text('홈·지도·검색에 똑같이 적용돼요.'), findsOneWidget);
    }

    testWidgets('shows both groups and the live count', (tester) async {
      await openHome(tester);
      await openSheet(tester);
      expect(find.text('꼭 지킬 조건'), findsOneWidget);
      expect(find.text('넘는 식당은 빼요'), findsOneWidget);
      expect(find.text('8,000원 이하'), findsOneWidget);
      expect(find.text('도보 5분'), findsOneWidget);
      expect(find.text('3곳 보기'), findsOneWidget);
      await revealInSheet(tester, find.text('지금 주문 가능한 곳만'));
      expect(find.text('정문 기준'), findsWidgets);
      expect(find.text('바꾸기 ›'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('추천 순서에 반영'),
        find.byType(Scrollable).last,
        const Offset(0, -200),
      );
      expect(find.text('몇 명이 먹나요?'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('정렬'),
        find.byType(Scrollable).last,
        const Offset(0, -200),
      );
      expect(find.text('추천순'), findsOneWidget);
      expect(find.text('모두 풀기'), findsOneWidget);
      expect(find.text('처음 화면으로 돌아가 다시 설정'), findsOneWidget);
    });

    testWidgets('a condition updates the count, badge, rank and map link', (
      tester,
    ) async {
      await openHome(tester);
      await openSheet(tester);
      await tester.tap(find.text('도보 5분')); // drops 먼집 (~778 m)
      await tester.pumpAndSettle();
      expect(find.text('2곳 보기'), findsOneWidget);

      await tester.tap(find.text('2곳 보기'));
      await tester.pumpAndSettle();
      expect(find.text('2곳 중 1순위'), findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: 'badge on 조건');
      await scrollDown(tester, -300);
      expect(find.text('조건에 맞는 2곳 지도에서 보기'), findsOneWidget);
      expect(find.text('먼집'), findsNothing);
    });

    testWidgets('no match disables the button; 모두 풀기 restores', (tester) async {
      final h = await openHome(tester);
      await openSheet(tester);
      await tester.tap(find.text('도보 5분'));
      // 중식 is only available far away (the chip itself is below the fold).
      h.container
          .read(conditionsProvider.notifier)
          .update((c) => c.copyWith(cuisines: {Cuisine.chinese}));
      await tester.pumpAndSettle();
      expect(find.text('조건에 맞는 곳이 없어요'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('조건에 맞는 곳이 없어요').last,
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('모두 풀기'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3곳 보기'), findsOneWidget);
    });

    testWidgets('바꾸기 opens the origin sheet', (tester) async {
      await openHome(tester);
      await openSheet(tester);
      await tester.tap(find.text('바꾸기 ›'));
      await tester.pumpAndSettle();
      expect(find.text('어디서 출발하나요?'), findsOneWidget);
    });

    testWidgets('start over asks first, then resets (guest)', (tester) async {
      final h = await openHome(tester);
      await h.container
          .read(originSelectionProvider.notifier)
          .select('gate_back');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(find.text('처음부터 다시 설정할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(h.container.read(originSelectionProvider), 'gate_back');

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 설정'));
      await tester.pumpAndSettle();
      expect(h.container.read(originSelectionProvider), isNull);
      expect(find.text('정문 기준'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('API failure shows an error with retry, not fake data', (
      tester,
    ) async {
      final repo = FakeRestaurantRepository(
        error: const RestaurantException(RestaurantErrorKind.network),
      );
      await openHome(tester, repo: repo);
      expect(find.text('맛집을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('인터넷 연결을 확인해주세요.'), findsOneWidget);
      final before = repo.nearbyCalls.length;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(repo.nearbyCalls.length, greaterThan(before));
    });

    testWidgets('no places: friendly empty state that can clear conditions', (
      tester,
    ) async {
      await openHome(tester, repo: FakeRestaurantRepository());
      expect(find.text('조건에 맞는 곳이 없어요'), findsOneWidget);
      expect(find.text('모두 풀기'), findsOneWidget);
    });

    testWidgets('detail opens from 정보 without invented facts', (tester) async {
      await openHome(tester);
      await tester.tap(find.text('정보'));
      await tester.pumpAndSettle();
      expect(find.text('카카오맵에서 보기'), findsOneWidget);
      expect(find.textContaining('아직 제공되지 않아요'), findsOneWidget);
    });
  });

  group('오늘의 학식', () {
    final cafeteria = fakeCafeteria('c1', nameKo: '향설1관');
    FakeCampusMealRepository repo(List<CafeteriaMeal> meals) =>
        FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univId: [cafeteria],
          },
          meals: meals,
        );

    testWidgets('shows the meal being served with its facts', (tester) async {
      await openHome(
        tester,
        meals: repo([
          fakeMeal(
            '2026-11-09',
            MealType.dinner,
            option: '한식뷔페',
            price: 6000,
            start: '17:00',
            end: '19:30',
            items: const [
              MenuItem(nameKo: '제육볶음', kind: MenuItemKind.main),
              MenuItem(nameKo: '시금치나물'),
              MenuItem(nameKo: '햄야채볶음'),
            ],
          ),
        ]),
      );
      await scrollDown(tester);
      expect(find.text('오늘의 학식'), findsOneWidget);
      expect(find.text('지금 저녁'), findsOneWidget);
      expect(find.text('제육볶음'), findsOneWidget);
      expect(find.text('향설1관 한식뷔페'), findsOneWidget);
      expect(find.text('시금치나물 · 햄야채볶음'), findsOneWidget);
      expect(find.text('17:00–19:30'), findsOneWidget);
      expect(find.text('₩6,000'), findsOneWidget);
    });

    testWidgets('shows the admin-set 천원의 아침밥 badge', (tester) async {
      await openHome(
        tester,
        meals: repo([
          fakeMeal('2026-11-09', MealType.dinner, start: '17:00', end: '18:30'),
          fakeMeal(
            '2026-11-10',
            MealType.breakfast,
            price: 1000,
            badge: '천원의 아침밥',
            items: const [MenuItem(nameKo: '북엇국', kind: MenuItemKind.main)],
          ),
        ]),
      );
      await reveal(tester, find.text('이번 주 식단'));
      expect(find.text('천원의 아침밥'), findsOneWidget);
      expect(find.text('북엇국'), findsOneWidget);
    });

    testWidgets('after tonight it shows tomorrow morning', (tester) async {
      await openHome(
        tester,
        meals: repo([
          fakeMeal('2026-11-09', MealType.dinner, start: '17:00', end: '18:30'),
          fakeMeal('2026-11-10', MealType.breakfast, price: 1000),
        ]),
      );
      await scrollDown(tester);
      expect(find.text('내일 아침'), findsOneWidget);
      expect(find.text('₩1,000'), findsOneWidget);
    });

    testWidgets('no cafeteria data: says so, buttons still work', (
      tester,
    ) async {
      await openHome(tester);
      await reveal(tester, find.text('이번 주 식단'));
      expect(find.text('이 학교의 학식 정보는 아직 등록되지 않았어요.'), findsOneWidget);
      expect(
        find.text('비교할 가격 정보가 아직 부족해요. 학식과 바깥 식당 가격이 모두 있어야 비교할 수 있어요.'),
        findsOneWidget,
      );
      await tester.tap(find.text('이번 주 식단'));
      await tester.pumpAndSettle();
      expect(find.byType(CampusMealScreen), findsOneWidget);
    });

    testWidgets('compare button opens the placeholder page', (tester) async {
      await openHome(tester);
      await reveal(tester, find.text('바깥 식당과 비교'));
      await tester.tap(find.text('바깥 식당과 비교'));
      await tester.pumpAndSettle();
      expect(find.byType(OutsideCompareScreen), findsOneWidget);
    });

    testWidgets('bars and monthly saving come from real averages', (
      tester,
    ) async {
      await openHome(
        tester,
        meals: repo([
          fakeMeal('2026-11-09', MealType.lunch, price: 5000),
          fakeMeal('2026-11-10', MealType.lunch, price: 5200, option: 'B'),
          fakeMeal('2026-11-09', MealType.dinner, start: '17:00', end: '19:30'),
        ]),
        overrides: [
          restaurantInsightsProvider.overrideWithValue({
            '가까운집': const RestaurantInsight(minPriceKrw: 9000),
            '중간집': const RestaurantInsight(minPriceKrw: 9200),
            // 먼집 has no price and is ignored.
          }),
        ],
      );
      await scrollDown(tester);
      expect(find.text('점심 한 끼 평균 · 학생회관에서 도보 15분 안 식당 기준'), findsOneWidget);
      expect(find.text('₩5,100'), findsOneWidget);
      expect(find.text('₩9,100'), findsOneWidget);
      // (9,100 - 5,100) * 20
      expect(find.textContaining('80,000', findRichText: true), findsOneWidget);
      expect(find.textContaining('한 달 20끼를 학식으로 먹으면'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final size in const [Size(320, 568), Size(390, 844), Size(430, 932)]) {
      for (final lang in const ['ko', 'en', 'zh-Hans']) {
        for (final dark in const [false, true]) {
          testWidgets('no overflow: $lang $size ${dark ? 'dark' : 'light'}', (
            tester,
          ) async {
            tester.platformDispatcher.textScaleFactorTestValue = 1.6;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await openHome(
              tester,
              size: size,
              storage: {
                'app_language': lang,
                'theme_mode': dark ? 'dark' : 'light',
              },
              meals: FakeCampusMealRepository(
                cafeteriasByUniversity: {
                  univId: [fakeCafeteria('c1', nameKo: '향설1관')],
                },
                meals: [
                  fakeMeal(
                    '2026-11-09',
                    MealType.dinner,
                    option: '아주아주아주아주 긴 코너 이름 한식뷔페',
                    price: 6000,
                    start: '17:00',
                    end: '19:30',
                    items: const [
                      MenuItem(
                        nameKo: '아주아주아주 긴 메인 메뉴 이름입니다',
                        kind: MenuItemKind.main,
                      ),
                      MenuItem(nameKo: '시금치나물'),
                      MenuItem(nameKo: '햄야채볶음'),
                    ],
                  ),
                ],
              ),
              repo: FakeRestaurantRepository(
                items: [
                  spot('아주아주아주아주아주 긴 이름의 식당입니다 정말로', 0.0005),
                  spot('중간집', 0.0015),
                  spot('먼집', 0.0070),
                ],
              ),
            );
            for (var i = 0; i < 6; i++) {
              await tester.drag(
                find.byType(Scrollable).first,
                const Offset(0, -350),
              );
              await tester.pump();
            }
            await tester.pumpAndSettle(); // lets zero-length timers fire
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('both sheets fit at 320px with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHome(tester, size: const Size(320, 568));
      await tester.tap(find.byIcon(Icons.place_outlined).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(160, 20)); // scrim
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  });
}

/// Conditions with a fixed "order now only" switch, for time-sensitive tests.
class _FixedConditions extends ConditionsNotifier {
  _FixedConditions({required this.openNow});

  final bool openNow;

  @override
  Conditions build() => super.build().copyWith(openNowOnly: openNow);
}
