import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/campus_meals/screens/campus_meal_screen.dart';
import 'package:meogeobojo/features/home/widgets/category_section.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/providers/restaurant_providers.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_repository.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_category_screen.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/restaurants/widgets/category_tile.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../../support/fakes.dart';
import '../../support/category_host.dart';
import '../../support/harness.dart';

Finder inSection(Finder f) =>
    find.descendant(of: find.byType(CategorySection), matching: f);

Finder tile(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(CategoryTile));

Finder heading(String t) => find.textContaining(t, findRichText: true);

Finder inTabs(String label) => find.descendant(
  of: find.byType(SingleChildScrollView),
  matching: find.text(label),
);

Future<Harness> openHome(
  WidgetTester tester, {
  Map<String, Object> storage = const {'app_language': 'ko'},
  FakeRestaurantRepository? repo,
  Size size = const Size(390, 844),
}) async {
  final h = await buildHarness(storage: storage, restaurants: repo);
  await pumpApp(tester, h, home: const CategoryHost(), size: size);
  return h;
}

Future<void> openCategory(WidgetTester tester, String label) async {
  await tester.tap(inSection(find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  const labels = [
    '학식', '전체', '한식', '양식', '중식', '일식', '분식', '카페·디저트', //
    '치킨', '패스트푸드', '세계 음식', '기타',
  ];

  group('Home category section', () {
    testWidgets('all twelve categories are visible immediately, in order', (
      tester,
    ) async {
      await openHome(tester);
      double? lastY;
      double? lastX;
      for (final c in labels) {
        final f = inSection(find.text(c));
        expect(f, findsOneWidget, reason: c);
        final at = tester.getTopLeft(f);
        if (lastY != null) {
          // reading order: next row, or same row further right
          expect(
            at.dy > lastY + 1 || (at.dy - lastY).abs() <= 1 && at.dx > lastX!,
            isTrue,
            reason: c,
          );
        }
        lastY = at.dy;
        lastX = at.dx;
      }
    });

    testWidgets('has no expand / collapse control at all', (tester) async {
      await openHome(tester);
      for (final t in ['더보기', '접기']) {
        expect(inSection(find.text(t)), findsNothing, reason: t);
      }
      expect(
        inSection(find.byIcon(Icons.keyboard_arrow_down_rounded)),
        findsNothing,
      );
      expect(
        inSection(find.byIcon(Icons.keyboard_arrow_up_rounded)),
        findsNothing,
      );
      expect(inSection(find.byType(AnimatedSize)), findsNothing);
    });

    testWidgets('five columns, wrapping to three rows, equal tiles', (
      tester,
    ) async {
      await openHome(tester);
      final rects = [for (final c in labels) tester.getRect(tile(c))];
      final rows = rects.map((r) => r.top.round()).toSet().toList()..sort();
      expect(rows.length, 3);
      expect(rects.where((r) => r.top.round() == rows[0]).length, 5);
      expect(rects.where((r) => r.top.round() == rows[1]).length, 5);
      expect(rects.where((r) => r.top.round() == rows[2]).length, 2);
      // identical widths, consistent gaps
      expect(rects.map((r) => r.width.toStringAsFixed(1)).toSet().length, 1);
      final firstRow = rects.take(5).toList();
      final gaps = [
        for (var i = 1; i < 5; i++)
          (firstRow[i].left - firstRow[i - 1].right).toStringAsFixed(1),
      ];
      expect(gaps.toSet().length, 1);
      // never wider than the screen
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(390));
      }
    });

    testWidgets('never scrolls horizontally or on its own', (tester) async {
      await openHome(tester);
      expect(
        find.descendant(
          of: find.byType(CategorySection),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
    });

    for (final (size, scale) in [
      (const Size(320, 640), 1.0),
      (const Size(320, 640), 1.6),
      (const Size(390, 844), 1.6),
    ]) {
      for (final lang in ['ko', 'en', 'zh-Hans']) {
        testWidgets('no overflow: $lang ${size.width.toInt()}px ${scale}x', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await openHome(tester, storage: {'app_language': lang}, size: size);
          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: find.byType(CategorySection),
              matching: find.byType(CategoryTile),
            ),
            findsNWidgets(12),
          );
        });
      }
    }

    for (final (label, cat) in [
      ('전체', FoodCategory.all),
      ('한식', FoodCategory.korean),
      ('양식', FoodCategory.western),
      ('중식', FoodCategory.chinese),
      ('일식', FoodCategory.japanese),
      ('분식', FoodCategory.snack),
      ('카페·디저트', FoodCategory.cafe),
      ('치킨', FoodCategory.chicken),
      ('패스트푸드', FoodCategory.fastFood),
      ('세계 음식', FoodCategory.global),
      ('기타', FoodCategory.etc),
    ]) {
      testWidgets('$label opens the category screen for that category', (
        tester,
      ) async {
        final h = await openHome(tester);
        await openCategory(tester, label);
        final screen = tester.widget<RestaurantCategoryScreen>(
          find.byType(RestaurantCategoryScreen),
        );
        expect(screen.initialCategory, cat);
        expect(h.restaurants.nearbyCalls.last.$2, cat);
      });
    }

    testWidgets('학식 opens the campus meals page, not a restaurant list', (
      tester,
    ) async {
      final h = await openHome(tester);
      await openCategory(tester, '학식');
      expect(find.byType(CampusMealScreen), findsOneWidget);
      expect(find.byType(RestaurantCategoryScreen), findsNothing);
      expect(
        h.restaurants.nearbyCalls.where((c) => c.$2 != FoodCategory.all),
        isEmpty,
      );
    });
  });

  group('Navigation behaviour', () {
    testWidgets(
      'back returns to Home: scroll kept, university and category untouched',
      (tester) async {
        final h = await openHome(tester);
        await tester.drag(find.byType(ListView).first, const Offset(0, -40));
        await tester.pumpAndSettle();
        final before = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels;
        final universityBefore = (await h.container.read(
          selectedUniversityProvider.future,
        )).nameKo;

        await openCategory(tester, '한식');
        expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
        // Home is not filtered by the category screen.
        expect(h.container.read(selectedCategoryProvider), FoodCategory.all);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(RestaurantCategoryScreen), findsNothing);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          before,
        );
        expect(
          h.container.read(selectedUniversityProvider).value!.nameKo,
          universityBefore,
        );
        expect(h.container.read(selectedCategoryProvider), FoodCategory.all);
        expect(find.byType(CategorySection), findsOneWidget); // host is back
      },
    );

    testWidgets('system back gesture also returns to Home', (tester) async {
      await openHome(tester);
      await openCategory(tester, '한식');
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      expect(await nav.maybePop(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantCategoryScreen), findsNothing);
      expect(find.byType(CategorySection), findsOneWidget);
    });
  });

  group('RestaurantCategoryScreen', () {
    testWidgets('shows header, location line, tabs and real results', (
      tester,
    ) async {
      await openHome(tester);
      await openCategory(tester, '한식');
      expect(find.text('학교 주변 맛집'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.text('순천향대학교 · 아산'), findsOneWidget);
      expect(heading('한식 음식점'), findsOneWidget);
      expect(find.textContaining('곳'), findsWidgets);
      expect(find.text('국수집1'), findsOneWidget);
      expect(find.text('거리순'), findsOneWidget);
      // nothing invented: no ratings, prices or walking times
      expect(find.textContaining('★'), findsNothing);
      expect(find.textContaining('원'), findsNothing);
      expect(find.textContaining('도보'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tabs switch category in place and re-query', (tester) async {
      final h = await openHome(tester);
      await openCategory(tester, '한식');
      await tester.tap(inTabs('일식'));
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
      expect(heading('일식 음식점'), findsOneWidget);
      expect(h.restaurants.nearbyCalls.last.$2, FoodCategory.japanese);
      // 치킨 sits past the right edge: scroll the strip like a user would.
      await tester.ensureVisible(inTabs('치킨'));
      await tester.pumpAndSettle();
      await tester.tap(inTabs('치킨'));
      await tester.pumpAndSettle();
      expect(heading('치킨 음식점'), findsOneWidget);
      expect(h.restaurants.nearbyCalls.last.$2, FoodCategory.chicken);
    });

    testWidgets('a far-right initial category is scrolled into view', (
      tester,
    ) async {
      await openHome(tester, size: const Size(320, 640));
      await openCategory(tester, '기타');
      final tab = tester.getRect(inTabs('기타'));
      final screenW =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tab.left, greaterThanOrEqualTo(0));
      expect(tab.right, lessThanOrEqualTo(screenW));
    });

    testWidgets('selecting a far tab keeps it visible', (tester) async {
      await openHome(tester, size: const Size(320, 640));
      await openCategory(tester, '전체');
      await tester.tap(find.byTooltip('카테고리 전체 보기'));
      await tester.pumpAndSettle();
      expect(find.text('전체 카테고리'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('패스트푸드'),
        ),
      );
      await tester.pumpAndSettle();
      expect(heading('패스트푸드 음식점'), findsOneWidget);
      final tab = tester.getRect(inTabs('패스트푸드'));
      expect(tab.left, greaterThanOrEqualTo(0));
      expect(tab.right, lessThanOrEqualTo(320));
    });

    testWidgets('chevron sheet lists all eleven categories once', (
      tester,
    ) async {
      await openHome(tester);
      await openCategory(tester, '한식');
      await tester.tap(find.byTooltip('카테고리 전체 보기'));
      await tester.pumpAndSettle();
      for (final c in FoodCategory.values) {
        final label = {
          FoodCategory.all: '전체',
          FoodCategory.korean: '한식',
          FoodCategory.western: '양식',
          FoodCategory.chinese: '중식',
          FoodCategory.japanese: '일식',
          FoodCategory.snack: '분식',
          FoodCategory.cafe: '카페·디저트',
          FoodCategory.chicken: '치킨',
          FoodCategory.fastFood: '패스트푸드',
          FoodCategory.global: '세계 음식',
          FoodCategory.etc: '기타',
        }[c]!;
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('sorting by name reorders; distance is the default', (
      tester,
    ) async {
      final repo = FakeRestaurantRepository(
        items: [
          fakeRestaurant('1', name: '다식당', distance: 100),
          fakeRestaurant('2', name: '가식당', distance: 300),
          fakeRestaurant('3', name: '나식당', distance: 200),
        ],
      );
      await openHome(tester, repo: repo);
      await openCategory(tester, '한식');
      double y(String n) => tester.getTopLeft(find.text(n)).dy;
      expect(y('다식당1'), lessThan(y('나식당3')));
      expect(y('나식당3'), lessThan(y('가식당2')));

      await tester.tap(find.text('거리순'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이름순').last);
      await tester.pumpAndSettle();
      expect(y('가식당2'), lessThan(y('나식당3')));
      expect(y('나식당3'), lessThan(y('다식당1')));
    });

    testWidgets('results open the detail page', (tester) async {
      await openHome(tester);
      await openCategory(tester, '한식');
      await tester.tap(find.text('국수집1'));
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
    });

    testWidgets('changing university refreshes results and keeps category', (
      tester,
    ) async {
      final h = await openHome(tester);
      await openCategory(tester, '일식');
      expect(h.restaurants.nearbyCalls.last.$1, '순천향대학교');

      await tester.tap(find.text('순천향대학교 · 아산'));
      await tester.pumpAndSettle();
      expect(find.text('학교 선택'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '호서');
      await tester.pumpAndSettle();
      await tester.tap(find.text('호서대학교'));
      await tester.pumpAndSettle();

      expect(
        h.container.read(selectedUniversityProvider).value!.nameKo,
        '호서대학교',
      );
      expect(h.restaurants.nearbyCalls.last.$1, '호서대학교');
      expect(h.restaurants.nearbyCalls.last.$2, FoodCategory.japanese);
      expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
      expect(heading('일식 음식점'), findsOneWidget);
      expect(find.textContaining('호서대학교'), findsWidgets);
    });

    testWidgets('empty result shows the friendly message', (tester) async {
      await openHome(tester, repo: FakeRestaurantRepository(items: const []));
      await openCategory(tester, '한식');
      expect(find.text('해당 카테고리의 맛집을 찾지 못했어요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('error shows retry and never mock data', (tester) async {
      final repo = FakeRestaurantRepository(
        error: const RestaurantException(RestaurantErrorKind.network),
      );
      await openHome(tester, repo: repo);
      await openCategory(tester, '한식');
      expect(find.text('국수집1'), findsNothing);
      final retry = find.text('다시 시도');
      expect(retry, findsOneWidget);
      final before = repo.nearbyCalls.length;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repo.nearbyCalls.length, greaterThan(before));
    });

    testWidgets('does not overflow at 320px with 1.6x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHome(tester, size: const Size(320, 640));
      await openCategory(tester, '한식');
      expect(tester.takeException(), isNull);
    });
  });

  group('세계 음식 (Global Cuisine)', () {
    Finder chip(String label) => find.descendant(
      of: find.byKey(const ValueKey('cuisine-chips')),
      matching: find.text(label),
    );

    Restaurant r(String id, String name, String path, int d) =>
        fakeRestaurant(id, name: name, category: path, distance: d);

    testWidgets('opens with Global Cuisine selected and the cuisine chips', (
      tester,
    ) async {
      final h = await openHome(tester);
      await openCategory(tester, '세계 음식');
      expect(h.restaurants.nearbyCalls.last.$2, FoodCategory.global);
      expect(h.restaurants.cuisineCalls.last, GlobalCuisine.all);
      expect(heading('세계 음식'), findsWidgets);
      for (final c in [
        '전체',
        '베트남 음식',
        '태국 음식',
        '인도 음식',
        '멕시코 음식',
        '기타 세계 음식',
      ]) {
        expect(chip(c), findsOneWidget, reason: c);
      }
      // the honest coverage note, not the generic one
      expect(find.textContaining('가게 이름으로 나라를 추측하지 않으며'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chips only exist under 세계 음식', (tester) async {
      await openHome(tester);
      await openCategory(tester, '한식');
      expect(find.text('베트남 음식'), findsNothing);
      expect(find.text('기타 세계 음식'), findsNothing);
    });

    testWidgets('selecting a cuisine re-queries with it, in place', (
      tester,
    ) async {
      final h = await openHome(tester);
      await openCategory(tester, '세계 음식');
      await tester.tap(chip('태국 음식'));
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
      expect(h.restaurants.nearbyCalls.last.$2, FoodCategory.global);
      expect(h.restaurants.cuisineCalls.last, GlobalCuisine.thai);
      expect(heading('태국 음식'), findsWidgets);
      await tester.tap(chip('전체'));
      await tester.pumpAndSettle();
      expect(h.restaurants.cuisineCalls.last, GlobalCuisine.all);
    });

    testWidgets('leaving and returning to 세계 음식 starts at 전체', (tester) async {
      final h = await openHome(tester);
      await openCategory(tester, '세계 음식');
      await tester.tap(chip('인도 음식'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(inTabs('한식'));
      await tester.pumpAndSettle();
      await tester.tap(inTabs('한식'));
      await tester.pumpAndSettle();
      expect(h.restaurants.cuisineCalls.last, GlobalCuisine.all);
      await tester.ensureVisible(inTabs('세계 음식'));
      await tester.pumpAndSettle();
      await tester.tap(inTabs('세계 음식'));
      await tester.pumpAndSettle();
      expect(h.restaurants.cuisineCalls.last, GlobalCuisine.all);
    });

    testWidgets('shows the real results, nearest first, and opens details', (
      tester,
    ) async {
      final repo = FakeRestaurantRepository(
        items: [
          r('1', '쌀국수집', '음식점 > 아시아음식 > 동남아음식 > 베트남음식', 400),
          r('2', '커리집', '음식점 > 아시아음식 > 인도음식', 150),
        ],
      );
      await openHome(tester, repo: repo);
      await openCategory(tester, '세계 음식');
      expect(find.text('커리집2'), findsOneWidget);
      expect(find.text('쌀국수집1'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('커리집2')).dy,
        lessThan(tester.getTopLeft(find.text('쌀국수집1')).dy),
      );
      await tester.tap(find.text('커리집2'));
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
    });

    testWidgets('empty cuisine shows the friendly coverage message', (
      tester,
    ) async {
      await openHome(tester, repo: FakeRestaurantRepository(items: const []));
      await openCategory(tester, '세계 음식');
      await tester.tap(chip('태국 음식'));
      await tester.pumpAndSettle();
      expect(find.text('해당 카테고리의 맛집을 찾지 못했어요.'), findsOneWidget);
      expect(find.textContaining('검색 범위 밖'), findsOneWidget);
      // switching to another cuisine still works from the empty state
      await tester.tap(chip('전체'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('university change keeps 세계 음식 and the cuisine', (
      tester,
    ) async {
      final h = await openHome(tester);
      await openCategory(tester, '세계 음식');
      await tester.tap(chip('베트남 음식'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('순천향대학교 · 아산'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '호서');
      await tester.pumpAndSettle();
      await tester.tap(find.text('호서대학교'));
      await tester.pumpAndSettle();
      expect(h.restaurants.nearbyCalls.last.$1, '호서대학교');
      expect(h.restaurants.nearbyCalls.last.$2, FoodCategory.global);
      expect(h.restaurants.cuisineCalls.last, GlobalCuisine.vietnamese);
    });

    for (final (lang, title, cuisines) in [
      (
        'en',
        'Global Cuisine',
        ['Vietnamese', 'Thai', 'Indian', 'Mexican', 'Other global'],
      ),
      ('zh-Hans', '世界美食', ['越南菜', '泰国菜', '印度菜', '墨西哥菜', '其他世界美食']),
    ]) {
      testWidgets('localized in $lang without overflow at 320px', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openHome(
          tester,
          storage: {'app_language': lang},
          size: const Size(320, 640),
        );
        expect(inSection(find.text(title)), findsOneWidget);
        await tester.tap(inSection(find.text(title)));
        await tester.pumpAndSettle();
        for (final c in cuisines) {
          expect(chip(c), findsOneWidget, reason: c);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dark mode renders the chips without errors', (tester) async {
      await openHome(
        tester,
        storage: {'app_language': 'ko', 'theme_mode': 'dark'},
      );
      await openCategory(tester, '세계 음식');
      expect(tester.takeException(), isNull);
      expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
    });
  });

  group('Theme and localization', () {
    testWidgets('light background is pure white, dark is charcoal', (
      tester,
    ) async {
      await openHome(
        tester,
        storage: {'app_language': 'ko', 'theme_mode': 'light'},
      );
      await openCategory(tester, '한식');
      final light = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(RestaurantCategoryScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(
        Theme.of(tester.element(find.byType(RestaurantCategoryScreen)))
            .scaffoldBackgroundColor,
        const Color(0xFFFFFFFF),
      );
      expect(light, isNotNull);
    });

    testWidgets('dark mode uses the charcoal background', (tester) async {
      await openHome(
        tester,
        storage: {'app_language': 'ko', 'theme_mode': 'dark'},
      );
      await openCategory(tester, '한식');
      expect(
        Theme.of(tester.element(find.byType(RestaurantCategoryScreen)))
            .scaffoldBackgroundColor,
        const Color(0xFF121212),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('English labels and heading', (tester) async {
      final h = await openHome(tester, storage: {'app_language': 'en'});
      expect(inSection(find.text('Korean')), findsOneWidget);
      expect(inSection(find.text('Global Cuisine')), findsOneWidget);
      await tester.tap(inSection(find.text('Korean')));
      await tester.pumpAndSettle();
      expect(heading('Korean restaurants'), findsOneWidget);
      expect(h.restaurants.nearbyCalls.last.$2.queries, ['한식']);
    });

    testWidgets('Chinese labels', (tester) async {
      await openHome(tester, storage: {'app_language': 'zh-Hans'});
      expect(inSection(find.text('韩餐')), findsOneWidget);
      await tester.tap(inSection(find.text('韩餐')));
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
