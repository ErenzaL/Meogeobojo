import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/theme/theme_controller.dart';
import 'package:meogeobojo/core/widgets/pill_chip.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/home/widgets/cafeteria_card.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/campus_meals/screens/campus_meal_screen.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/conditions/providers/conditions_providers.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/origin/providers/origin_providers.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/providers/ranking_providers.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_repository.dart';
import 'package:meogeobojo/features/search/screens/search_screen.dart';
import 'package:meogeobojo/features/home/screens/outside_compare_screen.dart';
import 'package:meogeobojo/features/home/widgets/alternatives_section.dart';
import 'package:meogeobojo/features/home/widgets/hero_card.dart';
import 'package:meogeobojo/features/home/widgets/home_category_bar.dart';
import 'package:meogeobojo/features/home/games/ladder_game.dart';
import 'package:meogeobojo/features/home/games/game_candidates.dart';
import 'package:meogeobojo/features/home/providers/home_providers.dart';
import 'package:meogeobojo/features/home/widgets/home_filter_bar.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/reviews/models/student_review.dart';

import 'package:meogeobojo/features/campus_meals/widgets/campus_meal_widgets.dart'
    show CafeteriaSelector;
import 'package:meogeobojo/features/university/models/university.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart'
    show sharedPreferencesProvider;

import 'package:meogeobojo/features/restaurants/providers/restaurant_providers.dart'
    show restaurantOverridesProvider;

import '../../support/fakes.dart';
import '../../support/harness.dart';

const univId = '5c0a8f3e-0001-4a6e-9b1d-000000000001';

// 정문 is at (36.769563, 126.92736): these are ~56 m, ~167 m and ~778 m north.
Restaurant spot(String name, double dLat, {String category = '음식점 > 한식'}) =>
    Restaurant(
      kakaoId: name,
      name: name,
      categoryName: category,
      categoryGroupCode: 'FD6',
      address: '',
      roadAddress: '',
      phone: '',
      latitude: 36.769563 + dLat,
      longitude: 126.92736,
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
  RestaurantRepository? repo,
  FakeCampusMealRepository? meals,
  Stream<DateTime>? clock,
  List<dynamic> overrides = const [],
  Map<String, Object> storage = const {'app_language': 'ko'},
  Size size = const Size(390, 844),
  bool recsRequested = true,
  FakeAuthGateway? auth,
  FakeReviewRepository? reviews,
}) async {
  final h = await buildHarness(
    recsRequested: recsRequested,
    auth: auth,
    reviews: reviews,
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

/// Finds [f] inside the top-pick card (the "오늘의 추천" carousel repeats the
/// same places, so plain text finders would match twice).
Finder inHero(Finder f) =>
    find.descendant(of: find.byType(HeroCard), matching: f);

Finder inAlternatives(Finder f) =>
    find.descendant(of: find.byType(AlternativesSection), matching: f);

/// Kakao returns a different list per category keyword: the generic query holds
/// only the 15 nearest places of any kind, the 중식 query holds Chinese places.
class _PerCategoryRepo implements RestaurantRepository {
  _PerCategoryRepo(this.byCategory);

  final Map<FoodCategory, List<Restaurant>> byCategory;
  final calls = <FoodCategory>[];

  @override
  Future<List<Restaurant>> nearby({
    required University university,
    FoodCategory category = FoodCategory.all,
    GlobalCuisine cuisine = GlobalCuisine.all,
  }) async {
    calls.add(category);
    return byCategory[category] ?? const [];
  }

  @override
  Future<List<Restaurant>> search({
    required University university,
    required String query,
  }) async => const [];
}

void main() {
  group('category + conditions stay in sync with the result', () {
    testWidgets(
      'a chosen category is searched in its own results, not in the generic 15 nearest',
      (tester) async {
        final repo = _PerCategoryRepo({
          FoodCategory.all: [
            spot('한식집', 0.0005),
            spot('분식집', 0.0006, category: '음식점 > 분식'),
          ],
          FoodCategory.chinese: [
            spot('짜장집', 0.0010, category: '음식점 > 중식 > 중국요리'),
            spot('짬뽕집', 0.0020, category: '음식점 > 중식'),
          ],
        });
        await openHome(tester, repo: repo);
        expect(find.text('한식집'), findsWidgets); // 전체: the generic pool
        await tester.tap(
          find.descendant(
            of: find.byType(HomeCategoryBar),
            matching: find.text('중식'),
          ),
        );
        await tester.pumpAndSettle();
        expect(repo.calls, contains(FoodCategory.chinese));
        expect(
          find.text('짜장집'),
          findsWidgets,
        ); // the nearest 중식 place, even though none was in the generic pool
        expect(find.text('한식집'), findsNothing);
        expect(find.text('조건에 맞는 곳이 없어요'), findsNothing);
      },
    );

    testWidgets(
      'the budget condition applies on top of the category: an unknown price is unconfirmed, a known one over budget goes',
      (tester) async {
        final repo = _PerCategoryRepo({
          FoodCategory.chinese: [
            spot('짜장집', 0.0010, category: '음식점 > 중식'),
            spot('비싼중식', 0.0020, category: '음식점 > 중식'),
          ],
        });
        final prices = FakeRestaurantOverrideRepository(
          overrides: {
            '비싼중식': const RestaurantOverride(
              kakaoId: '비싼중식',
              visibility: 'published',
              insight: RestaurantInsight(minPriceKrw: 15000),
            ),
          },
        );
        final h = await buildHarness(
          restaurants: repo,
          overridesRepo: prices,
          extraOverrides: [
            campusMealCacheDurationProvider.overrideWithValue(Duration.zero),
          ],
        );
        await pumpApp(tester, h, home: const AppShell());
        await h.container.read(restaurantOverridesProvider.future);
        h.container
            .read(homeCategoryProvider.notifier)
            .toggle(FoodCategory.chinese);
        h.container
            .read(conditionsProvider.notifier)
            .update((c) => c.copyWith(budget: BudgetOption.max8000));
        await tester.pumpAndSettle();
        // Nothing is confirmed, so there is no pick ...
        expect(h.container.read(homeRecsProvider).value, isNull);
        // ... the unknown price is listed apart, the 15,000원 place is gone.
        final pool = h.container.read(homePoolRankedProvider).value!;
        expect(pool.map((r) => r.restaurant.kakaoId), ['짜장집']);
        expect(pool.single.missing, {MissingInfo.price});
      },
    );

    testWidgets(
      '양식 + 중식 with 도보 10분 and 조용한 대화: every result is a 양식 or 중식 place within 10 minutes',
      (tester) async {
        // Real Kakao results around the campus (paths and distances as returned),
        // including 멕시칸 places that Kakao files under 양식 but the app lists as 세계 음식.
        Restaurant at(String name, String path, int meters) =>
            spot(name, meters / 111000.0, category: path);
        final western = [
          at('버거운버거', '음식점 > 양식 > 햄버거', 406),
          at('밀플랜비', '음식점 > 양식 > 멕시칸,브라질', 411),
          at('도스마스', '음식점 > 양식 > 멕시칸,브라질', 439),
          at('스코르피온', '음식점 > 양식', 460),
          at('온달파스타', '음식점 > 양식 > 이탈리안', 483),
          at('케밥하우스', '음식점 > 양식 > 멕시칸,브라질', 674),
          at('우골록', '음식점 > 양식', 829), // beyond 10 minutes
          at('피자스쿨', '음식점 > 양식 > 피자', 2502),
        ];
        final chinese = [
          at('마라취웨이', '음식점 > 중식 > 중국요리', 413),
          at('해피마라탕', '음식점 > 중식', 423),
          at('중국집', '음식점 > 중식 > 중국요리', 491),
          at('짬뽕119', '음식점 > 중식 > 중국요리', 1479),
        ];
        final generic = [
          at('어굿플레이스', '음식점 > 한식', 3),
          at('홍대쌀국수', '음식점 > 아시아음식 > 동남아음식 > 베트남음식', 284),
        ];
        // like the real repository: each category query returns only its own places
        final repo = _PerCategoryRepo({
          FoodCategory.all: generic,
          FoodCategory.western: [
            for (final r in western)
              if (FoodCategory.western.matches(r)) r,
          ],
          FoodCategory.chinese: [
            for (final r in chinese)
              if (FoodCategory.chinese.matches(r)) r,
          ],
        });
        final h = await buildHarness(restaurants: repo);
        await pumpApp(tester, h, home: const AppShell());
        final n = h.container.read(homeCategoryProvider.notifier);
        n.toggle(FoodCategory.western);
        n.toggle(FoodCategory.chinese);
        h.container
            .read(conditionsProvider.notifier)
            .update(
              (c) => c.copyWith(
                distance: DistanceOption.walk10,
                needs: {Need.quietTalk},
              ),
            );
        await tester.pumpAndSettle();
        final recs = h.container.read(homeRecsProvider).value!;
        final names = recs.ranked.map((r) => r.restaurant.name).toList();
        expect(names.toSet(), {
          '버거운버거',
          '스코르피온',
          '온달파스타',
          '마라취웨이',
          '해피마라탕',
          '중국집',
        });
        expect(recs.total, 6);
        for (final r in recs.ranked) {
          expect(r.walkMinutes, lessThanOrEqualTo(10));
          expect(
            FoodCategory.global.matches(r.restaurant),
            isFalse,
          ); // no 세계 음식 / 멕시칸 / 쌀국수
        }
        // the card the student sees is the same list
        expect(find.text('6곳 중 1순위'), findsOneWidget);
        expect(find.text(recs.hero.restaurant.name), findsWidgets);
      },
    );

    testWidgets('only when nothing in the category exists does it say so', (
      tester,
    ) async {
      final repo = _PerCategoryRepo({
        FoodCategory.all: [spot('한식집', 0.0005)],
      });
      await openHome(tester, repo: repo);
      await tester.tap(
        find.descendant(
          of: find.byType(HomeCategoryBar),
          matching: find.text('중식'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('조건에 맞는 곳이 없어요'), findsOneWidget);
    });
  });

  group('다른 후보 보기', () {
    testWidgets(
      'walks through the confirmed matches and comes back to the first',
      (tester) async {
        final h = await openHome(tester, size: const Size(390, 1600));
        final ranked = h.container.read(homeRecsProvider).value!.ranked;
        expect(ranked.length, greaterThan(2));
        Finder inHeroText(String t) =>
            find.descendant(of: find.byType(HeroCard), matching: find.text(t));
        expect(inHeroText(ranked[0].restaurant.name), findsOneWidget);
        // The first button turned into "다른 후보 보기" beside "조건 수정".
        expect(find.text('조건에 맞게 추천받기'), findsNothing);
        expect(find.text('조건 수정'), findsOneWidget);
        for (var i = 1; i <= ranked.length; i++) {
          await tester.tap(find.text('다른 후보 보기'));
          await tester.pumpAndSettle();
          final expected = ranked[i % ranked.length].restaurant.name;
          expect(inHeroText(expected), findsOneWidget, reason: 'step $i');
        }
        expect(h.container.read(homeRecsProvider).value!.heroRank, 1);
      },
    );

    testWidgets('one match shows again, and the reason is said', (
      tester,
    ) async {
      await openHome(
        tester,
        repo: FakeRestaurantRepository(items: [spot('하나뿐', 0.0005)]),
      );
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('다른 후보 보기'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text('조건에 맞는 식당이 이곳뿐이에요'), findsOneWidget);
    });

    testWidgets('changing a condition starts again from the best place', (
      tester,
    ) async {
      final h = await openHome(tester, size: const Size(390, 1600));
      await tester.tap(find.text('다른 후보 보기'));
      await tester.pumpAndSettle();
      expect(h.container.read(homeRecsProvider).value!.heroRank, 2);
      h.container
          .read(conditionsProvider.notifier)
          .update((c) => c.copyWith(distance: DistanceOption.walk15));
      await tester.pumpAndSettle();
      expect(h.container.read(homeRecsProvider).value!.heroRank, 1);
    });
  });

  group('header, title and chips', () {
    testWidgets('header: university, search, categories, filters, button', (
      tester,
    ) async {
      await openHome(tester);
      // The wordmark and the question title are gone; the university leads.
      expect(find.text('먹어보조'), findsNothing);
      expect(find.text('오늘 뭐 먹지?'), findsNothing);
      expect(find.text('순천향대학교'), findsOneWidget);
      expect(find.text('식당, 메뉴, 카테고리 검색'), findsOneWidget);
      // category bar: 전체 and the food categories (학식 has its own card)
      final bar = find.byType(HomeCategoryBar);
      for (final t in ['전체', '한식', '일식', '중식', '양식']) {
        expect(
          find.descendant(of: bar, matching: find.text(t)),
          findsOneWidget,
          reason: t,
        );
      }
      // filter bar: origin, 조건 and one chip per filter group
      expect(find.text('정문 기준'), findsOneWidget);
      expect(find.text('조건'), findsOneWidget);
      for (final t in ['예산', '거리']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      // the rest scroll in from the right
      await tester.drag(find.byType(HomeFilterBar), const Offset(-700, 0));
      await tester.pumpAndSettle();
      for (final t in ['운영·편의', '정렬']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      // Party and purpose have no data behind them: not offered as filters.
      for (final t in ['인원', '목적']) {
        expect(find.text(t), findsNothing, reason: t);
      }
      // A pick is on screen: the next steps are 다른 후보 보기 / 조건 수정.
      expect(find.text('다른 후보 보기'), findsOneWidget);
    });

    testWidgets('categories can be chosen together; 전체 clears them', (
      tester,
    ) async {
      final h = await openHome(tester);
      final bar = find.byType(HomeCategoryBar);
      Future<void> tap(String t) async {
        await tester.tap(find.descendant(of: bar, matching: find.text(t)));
        await tester.pumpAndSettle();
      }

      Set<FoodCategory> chosen() => h.container.read(homeCategoryProvider);
      expect(chosen(), isEmpty);
      await tap('한식');
      await tap('일식');
      expect(chosen(), {FoodCategory.korean, FoodCategory.japanese});
      await tap('한식'); // tapping again un-chooses it
      expect(chosen(), {FoodCategory.japanese});
      await tap('중식');
      expect(chosen(), {FoodCategory.japanese, FoodCategory.chinese});
      await tap('전체');
      expect(chosen(), isEmpty);
      // un-choosing the last one falls back to 전체
      await tap('일식');
      await tap('일식');
      expect(chosen(), isEmpty);
    });

    testWidgets('a filter chip opens only its own setting', (tester) async {
      await openHome(tester);
      await tester.tap(find.text('예산'));
      await tester.pumpAndSettle();
      // the budget choices are there, the other settings are not
      expect(find.text('한 끼 예산'), findsOneWidget);
      expect(find.widgetWithText(PillChip, '10,000원 이하'), findsOneWidget);
      expect(find.text('어디까지 갈까요?'), findsNothing);
      // compact: the sheet hugs its content instead of filling the screen
      expect(tester.getTopLeft(find.text('한 끼 예산')).dy, greaterThan(844 * 0.4));
      expect(find.text('정렬'), findsNothing);
      expect(find.text('처음 화면으로 돌아가 다시 설정'), findsNothing);
      await tester.tap(find.widgetWithText(PillChip, '10,000원 이하'));
      await tester.pumpAndSettle();
      // reset clears just this setting
      await tester.tap(find.text('이 설정 초기화'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == '상관없어요'),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(195, 20)); // scrim
      await tester.pumpAndSettle();
      await tester.tap(find.text('거리'));
      await tester.pumpAndSettle();
      expect(find.text('어디까지 갈까요?'), findsOneWidget);
      expect(find.text('한 끼 예산'), findsNothing);
    });

    testWidgets(
      'moon toggles dark mode; the bell opens the notification list',
      (tester) async {
        final h = await openHome(tester);
        await tester.tap(find.byIcon(Icons.dark_mode_outlined));
        await tester.pumpAndSettle();
        expect(h.container.read(themeModeProvider), ThemeMode.dark);
        expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
        await tester.tap(find.byIcon(Icons.notifications_none_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing); // no more "coming soon"
        expect(find.text('새 알림이 없어요'), findsOneWidget); // an honest empty list
      },
    );

    testWidgets('typing in the search field and submitting opens search', (
      tester,
    ) async {
      await openHome(tester);
      await tester.enterText(find.byType(TextField), '마라탕');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(
        tester.widget<SearchScreen>(find.byType(SearchScreen)).initialQuery,
        '마라탕',
      );
    });

    testWidgets('the university button opens the university sheet', (
      tester,
    ) async {
      await openHome(tester);
      await tester.tap(find.text('순천향대학교'));
      await tester.pumpAndSettle();
      expect(find.text('학교 선택'), findsOneWidget);
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
      expect(inHero(find.text('가까운집')), findsOneWidget);
      expect(find.text('3곳 중 1순위'), findsOneWidget);
      expect(find.text('선택한 출발점에서 가까워요'), findsOneWidget);
      // 18:54 + 1 minute walk
      expect(find.text('18:55'), findsOneWidget);
      expect(find.text('예상 도보 약 1분'), findsOneWidget);
      expect(find.text('길찾기'), findsOneWidget);
      expect(find.text('정보'), findsOneWidget);
    });

    testWidgets('nothing is invented when price / rating / hours are unknown', (
      tester,
    ) async {
      await openHome(tester);
      expect(find.text('—'), findsOneWidget);
      expect(inHero(find.text('정보 없음')), findsOneWidget);
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
      expect(inAlternatives(find.text('중간집')), findsOneWidget);
      expect(inAlternatives(find.text('먼집')), findsOneWidget);
      await tester.tap(find.text('조건에 맞는 3곳 지도에서 보기'));
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.map);
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
      expect(find.text('정문·후문'), findsOneWidget);
      expect(find.text('후문'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.textContaining('가장 가까운 곳: 가까운집 · 예상 도보 약 1분'), findsWidgets);
      // Seven residence halls, one row each, full names (never cut).
      await revealInSheet(tester, find.text('학성사 3관'));
      expect(find.text('기숙사'), findsOneWidget);
      for (final hall in [
        '향설생활관 1관',
        '향설생활관 2관',
        '향설생활관 3관',
        '글로벌 빌리지',
        '학성사 1관',
        '학성사 2관',
        '학성사 3관',
      ]) {
        expect(find.text(hall), findsOneWidget, reason: hall);
      }
      await revealInSheet(tester, find.text('지도에서 직접 지정하기'));
      expect(find.text('주요 건물'), findsOneWidget);
      expect(find.text('공과대학'), findsOneWidget);
      expect(find.text('직접 지정한 위치'), findsOneWidget);
      expect(find.text('아직 직접 지정한 위치가 없어요.'), findsOneWidget);
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
      expect(h.container.read(originSelectionProvider), 'gate_back');
      expect(
        h.sp.getString('origin_selected_id'),
        'gate_back',
        reason: 'persisted',
      );
      // Distances are measured again from the back gate.
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
            longitude: 126.92736,
          );
      await tester.tap(find.text('정문 기준'));
      await tester.pumpAndSettle();
      await revealInSheet(tester, find.text('기숙사 앞'));
      expect(find.text('기숙사 앞'), findsOneWidget);
      await tester.ensureVisible(find.text('기숙사 앞'));
      await tester.pumpAndSettle();
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
      expect(find.text('꼭 지킬 조건'), findsOneWidget); // the sheet is open
      expect(find.text('홈·지도·검색에 똑같이 적용돼요.'), findsNothing);
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
      // Party and needs change nothing yet: not offered.
      expect(find.text('몇 명이 먹나요?'), findsNothing);
      await tester.dragUntilVisible(
        find.text('정렬'),
        find.byType(Scrollable).last,
        const Offset(0, -200),
      );
      expect(find.text('추천순'), findsOneWidget);
      expect(find.text('초기화'), findsOneWidget);
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

    testWidgets('no match disables the button; 초기화 restores', (tester) async {
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
          matching: find.text('초기화'),
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
      await tester.tap(find.text('조건'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('처음 화면으로 돌아가 다시 설정'));
      await tester.pumpAndSettle();
      expect(find.text('처음부터 다시 설정할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(h.container.read(originSelectionProvider), 'gate_back');

      await tester.tap(find.text('처음 화면으로 돌아가 다시 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 설정'));
      await tester.pumpAndSettle();
      expect(h.container.read(originSelectionProvider), isNull);
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
      // The chosen conditions are kept for the retry, and it says so.
      expect(find.text('인터넷 연결을 확인해주세요.\n고른 조건은 그대로 남아 있어요.'), findsOneWidget);
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
      expect(find.text('조건 초기화'), findsWidgets);
    });

    testWidgets('detail opens from 정보 without invented facts', (tester) async {
      await openHome(tester);
      await tester.ensureVisible(find.text('정보'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('정보'));
      await tester.pumpAndSettle();
      expect(find.text('맛집 정보'), findsOneWidget); // the V5 detail page
      // no Kakao link without a place URL, and no invented facts
      expect(find.text('카카오맵에서 보기'), findsNothing);
      expect(find.textContaining('아직 제공되지 않아요'), findsOneWidget);
      expect(find.text('확인된 정보가 없어요'), findsOneWidget);
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
      expect(
        find.text('지금 저녁'),
        findsNothing,
      ); // no "today" chip in the header any more
      expect(find.text('오늘 아침'), findsNothing);
      expect(find.text('내일 식단'), findsNothing);
      expect(find.text('제육볶음'), findsOneWidget);
      expect(find.text('향설1관 한식뷔페'), findsOneWidget);
      expect(find.text('시금치나물 · 햄야채볶음'), findsOneWidget);
      expect(find.text('17:00–19:30'), findsOneWidget);
      expect(find.text('₩6,000'), findsOneWidget);
    });

    testWidgets(
      'lists breakfast, lunch and dinner of today together, with the current one outlined',
      (tester) async {
        await openHome(
          tester,
          meals: repo([
            fakeMeal(
              '2026-11-09',
              MealType.breakfast,
              start: '08:00',
              end: '09:30',
              items: const [
                MenuItem(nameKo: '뼈해장국', kind: MenuItemKind.main),
                MenuItem(nameKo: '만두찜'),
              ],
            ),
            fakeMeal(
              '2026-11-09',
              MealType.lunch,
              start: '11:30',
              end: '14:00',
              price: 5500,
              items: const [
                MenuItem(nameKo: '치즈닭갈비볶음밥', kind: MenuItemKind.main),
                MenuItem(nameKo: '계란국', kind: MenuItemKind.soup),
              ],
            ),
            fakeMeal(
              '2026-11-09',
              MealType.dinner,
              start: '17:00',
              end: '19:30',
              items: const [
                MenuItem(nameKo: '고추장불고기', kind: MenuItemKind.main),
                MenuItem(nameKo: '우동국'),
              ],
            ),
          ]),
        );
        await scrollDown(tester);
        expect(find.byKey(const ValueKey('home-meal-list')), findsOneWidget);
        for (final t in ['breakfast', 'lunch', 'dinner']) {
          expect(
            find.byKey(ValueKey('home-meal-$t')),
            findsOneWidget,
            reason: t,
          );
        }
        expect(find.text('뼈해장국'), findsOneWidget);
        expect(find.text('치즈닭갈비볶음밥'), findsOneWidget);
        expect(find.text('고추장불고기'), findsOneWidget);
        expect(find.text('조식'), findsOneWidget);
        expect(find.text('중식'), findsOneWidget);
        expect(find.text('석식'), findsOneWidget);
        expect(find.text('08:00–09:30'), findsOneWidget);
        expect(find.text('17:00–19:30'), findsOneWidget);
      },
    );

    testWidgets('the 천원의 아침밥 mark sits under 조식, only on a badged breakfast', (
      tester,
    ) async {
      await openHome(
        tester,
        meals: repo([
          fakeMeal(
            '2026-11-09',
            MealType.breakfast,
            start: '08:00',
            end: '09:30',
            price: 1000,
            badge: '천원의 아침밥',
          ),
          fakeMeal(
            '2026-11-09',
            MealType.lunch,
            start: '11:30',
            end: '14:00',
            price: 5500,
          ),
          fakeMeal(
            '2026-11-09',
            MealType.dinner,
            start: '17:00',
            end: '19:30',
            badge: '천원의 아침밥',
          ), // never on a dinner
        ]),
      );
      await scrollDown(tester);
      final mark = find.byKey(const ValueKey('home-thousand-won-mark'));
      expect(mark, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-meal-breakfast')),
          matching: mark,
        ),
        findsOneWidget,
      );
      // under the meal name, not above it
      expect(
        tester.getTopLeft(mark).dy,
        greaterThan(tester.getTopLeft(find.text('조식')).dy),
      );
      expect(
        tester.widget<ThousandWonMark>(mark).label,
        '천원의 아침밥',
      ); // what screen readers say
    });

    group('choosing the cafeteria', () {
      final hall = fakeCafeteria('c1', nameKo: '향설1관');
      final center = fakeCafeteria('c2', nameKo: '학생회관식당');
      final selector = find.byKey(const ValueKey('home-cafeteria-selector'));
      // the weekly page has its own clock: put it on the same Monday evening as Home
      final weeklyClock = campusMealClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 11, 9, 10),
      );

      FakeCampusMealRepository two() => FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univId: [hall, center],
        },
        meals: [
          fakeMeal(
            '2026-11-09',
            MealType.dinner,
            cafeteriaId: 'c1',
            start: '17:00',
            end: '19:30',
            items: const [MenuItem(nameKo: '제육볶음', kind: MenuItemKind.main)],
          ),
          fakeMeal(
            '2026-11-09',
            MealType.dinner,
            cafeteriaId: 'c2',
            start: '17:00',
            end: '19:30',
            items: const [MenuItem(nameKo: '돈가스', kind: MenuItemKind.main)],
          ),
          // the second cafeteria also serves lunch; the first does not
          fakeMeal(
            '2026-11-09',
            MealType.lunch,
            cafeteriaId: 'c2',
            start: '11:30',
            end: '14:00',
            items: const [MenuItem(nameKo: '쌀국수', kind: MenuItemKind.main)],
          ),
        ],
      );

      Future<void> pick(WidgetTester tester, String name) async {
        await reveal(tester, selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      testWidgets('one cafeteria: there is nothing to choose', (tester) async {
        await openHome(
          tester,
          meals: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univId: [hall],
            },
            meals: [fakeMeal('2026-11-09', MealType.dinner, cafeteriaId: 'c1')],
          ),
        );
        await scrollDown(tester);
        expect(find.text('오늘의 학식'), findsOneWidget);
        expect(selector, findsNothing);
      });

      testWidgets('several cafeterias: the first is shown, any can be picked', (
        tester,
      ) async {
        await openHome(tester, meals: two());
        await scrollDown(tester);
        expect(selector, findsOneWidget);
        expect(
          find.descendant(of: selector, matching: find.text('향설1관')),
          findsOneWidget,
        );
        expect(find.text('제육볶음'), findsOneWidget);
        expect(find.text('돈가스'), findsNothing);
        // the first cafeteria has no lunch, so only dinner is listed
        expect(find.byKey(const ValueKey('home-meal-lunch')), findsNothing);

        await pick(tester, '학생회관식당');
        expect(
          find.descendant(of: selector, matching: find.text('학생회관식당')),
          findsOneWidget,
        );
        expect(find.text('돈가스'), findsOneWidget);
        expect(find.text('제육볶음'), findsNothing);
        // this cafeteria also serves lunch: both meals are listed now
        expect(find.byKey(const ValueKey('home-meal-lunch')), findsOneWidget);
        expect(find.text('쌀국수'), findsOneWidget);
      });

      testWidgets('the choice is remembered per university', (tester) async {
        final h = await openHome(tester, meals: two());
        await scrollDown(tester);
        await pick(tester, '학생회관식당');
        expect(h.container.read(selectedCafeteriaIdProvider), 'c2');
        expect(
          h.container
              .read(sharedPreferencesProvider)
              .getString(selectedCafeteriaPrefsKey(univId)),
          'c2',
        );
      });

      testWidgets('a remembered choice is used on the next start', (
        tester,
      ) async {
        await openHome(
          tester,
          meals: two(),
          storage: {
            'app_language': 'ko',
            selectedCafeteriaPrefsKey(univId): 'c2',
          },
        );
        await scrollDown(tester);
        expect(
          find.descendant(of: selector, matching: find.text('학생회관식당')),
          findsOneWidget,
        );
        expect(find.text('돈가스'), findsOneWidget);
        expect(find.text('제육볶음'), findsNothing);
      });

      testWidgets(
        'a remembered cafeteria that is gone falls back to the first',
        (tester) async {
          await openHome(
            tester,
            meals: two(),
            storage: {
              'app_language': 'ko',
              selectedCafeteriaPrefsKey(univId): 'deleted',
            },
          );
          await scrollDown(tester);
          expect(find.text('제육볶음'), findsOneWidget);
        },
      );

      testWidgets(
        'a cafeteria with nothing entered says so and stays pickable',
        (tester) async {
          await openHome(
            tester,
            meals: FakeCampusMealRepository(
              cafeteriasByUniversity: {
                univId: [hall, center],
              },
              meals: [
                fakeMeal('2026-11-09', MealType.dinner, cafeteriaId: 'c1'),
              ],
            ),
          );
          await scrollDown(tester);
          await pick(tester, '학생회관식당');
          expect(find.text('곧 먹을 수 있는 학식 메뉴가 아직 등록되지 않았어요.'), findsOneWidget);
          expect(selector, findsOneWidget);
          await pick(tester, '향설1관');
          expect(
            find.byKey(const ValueKey('home-meal-dinner')),
            findsOneWidget,
          );
        },
      );

      testWidgets('the weekly page opens on the cafeteria chosen on Home', (
        tester,
      ) async {
        await openHome(tester, meals: two(), overrides: [weeklyClock]);
        await scrollDown(tester);
        await pick(tester, '학생회관식당');
        await reveal(tester, find.text('이번 주 식단'));
        await tester.tap(find.text('이번 주 식단'));
        await tester.pumpAndSettle();
        expect(find.byType(CampusMealScreen), findsOneWidget);
        final page = find.byType(CampusMealScreen);
        expect(
          find.descendant(of: page, matching: find.text('학생회관식당')),
          findsWidgets,
        );
        expect(
          find.descendant(of: page, matching: find.text('돈가스')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: page, matching: find.text('제육볶음')),
          findsNothing,
        );
      });

      testWidgets('a choice on the weekly page shows on Home too', (
        tester,
      ) async {
        await openHome(tester, meals: two(), overrides: [weeklyClock]);
        await reveal(tester, find.text('이번 주 식단'));
        await tester.tap(find.text('이번 주 식단'));
        await tester.pumpAndSettle();
        final page = find.byType(CampusMealScreen);
        await tester.tap(
          find.descendant(of: page, matching: find.byType(CafeteriaSelector)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('학생회관식당').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await scrollDown(tester);
        expect(
          find.descendant(of: selector, matching: find.text('학생회관식당')),
          findsOneWidget,
        );
        expect(find.text('돈가스'), findsOneWidget);
      });
    });

    testWidgets('a day with only some meals lists only those', (tester) async {
      await openHome(
        tester,
        meals: repo([
          fakeMeal('2026-11-09', MealType.dinner, start: '17:00', end: '19:30'),
        ]),
      );
      await scrollDown(tester);
      expect(find.byKey(const ValueKey('home-meal-dinner')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-meal-breakfast')), findsNothing);
      expect(find.byKey(const ValueKey('home-meal-lunch')), findsNothing);
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
      expect(find.text('내일 식단'), findsOneWidget); // the list is tomorrow's
      expect(find.byKey(const ValueKey('home-meal-breakfast')), findsOneWidget);
      expect(find.text('₩1,000'), findsOneWidget);
    });

    testWidgets('the 내일 식단 chip sits at the right edge of the card', (
      tester,
    ) async {
      await openHome(
        tester,
        meals: repo([
          fakeMeal('2026-11-09', MealType.dinner, start: '17:00', end: '18:30'),
          fakeMeal('2026-11-10', MealType.breakfast, price: 1000),
        ]),
      );
      await scrollDown(tester);
      final chip = find.ancestor(
        of: find.text('내일 식단'),
        matching: find.byType(Container),
      );
      final chipRight = tester.getRect(chip.first).right;
      final listRight = tester
          .getRect(find.byKey(const ValueKey('home-meal-list')))
          .right;
      expect(chipRight, closeTo(listRight, 0.5));
    });

    testWidgets('no cafeteria data: says so, buttons still work', (
      tester,
    ) async {
      await openHome(tester);
      await reveal(tester, find.text('이번 주 식단'));
      expect(find.text('이 학교의 학식 정보는 아직 등록되지 않았어요.'), findsOneWidget);
      // not enough prices to compare: nothing is drawn, no explanatory text
      expect(find.textContaining('비교할 가격 정보'), findsNothing);
      expect(find.textContaining('점심 한 끼 평균'), findsNothing);
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
      expect(
        find.textContaining('점심 한 끼 평균'),
        findsNothing,
      ); // the basis line is gone
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
                  // all three meals of the day, so the card's list is part of the overflow check
                  fakeMeal(
                    '2026-11-09',
                    MealType.breakfast,
                    start: '08:00',
                    end: '09:30',
                    price: 1000,
                    badge: '천원의 아침밥',
                    items: const [
                      MenuItem(
                        nameKo: '아주아주아주 긴 아침 메인 메뉴 이름입니다',
                        kind: MenuItemKind.main,
                      ),
                      MenuItem(nameKo: '만두찜'),
                    ],
                  ),
                  fakeMeal(
                    '2026-11-09',
                    MealType.lunch,
                    start: '11:30',
                    end: '14:00',
                    price: 5500,
                    items: const [
                      MenuItem(
                        nameKo: '아주아주아주 긴 점심 메인 메뉴 이름입니다',
                        kind: MenuItemKind.main,
                      ),
                      MenuItem(nameKo: '계란국', kind: MenuItemKind.soup),
                    ],
                  ),
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
      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('no preview before asking', () {
    testWidgets('an untouched Home shows a prompt, not a pick', (tester) async {
      await openHome(tester, recsRequested: false);
      expect(find.byType(HeroCard), findsNothing);
      expect(find.byType(AlternativesSection), findsNothing);
      expect(find.text('조건을 고르고 추천받아 보세요'), findsOneWidget);
      expect(find.text('오늘의 학식'), findsOneWidget); // 학식 stays
    });

    testWidgets('오늘의 추천 받기 reveals the pick', (tester) async {
      await openHome(tester, recsRequested: false);
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      expect(find.byType(HeroCard), findsOneWidget);
      expect(find.text('조건을 고르고 추천받아 보세요'), findsNothing);
    });

    testWidgets('choosing a category or a condition reveals it too', (
      tester,
    ) async {
      final h = await openHome(tester, recsRequested: false);
      await tester.tap(
        find.descendant(
          of: find.byType(HomeCategoryBar),
          matching: find.text('한식'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('조건을 고르고 추천받아 보세요'), findsNothing);
      h.container.read(homeCategoryProvider.notifier).clear();
      await tester.pumpAndSettle();
      expect(find.text('조건을 고르고 추천받아 보세요'), findsOneWidget);
      h.container
          .read(conditionsProvider.notifier)
          .update((c) => c.copyWith(budget: BudgetOption.max10000));
      await tester.pumpAndSettle();
      expect(find.text('조건을 고르고 추천받아 보세요'), findsNothing);
    });

    testWidgets('the restart button clears everything back to the prompt', (
      tester,
    ) async {
      final h = await openHome(tester, recsRequested: false);
      expect(find.text('조건 초기화'), findsNothing); // nothing to undo
      await tester.tap(
        find.descendant(
          of: find.byType(HomeCategoryBar),
          matching: find.text('한식'),
        ),
      );
      h.container
          .read(conditionsProvider.notifier)
          .update((c) => c.copyWith(budget: BudgetOption.max10000));
      await tester.pumpAndSettle();
      // No place has a known meal price: nothing is confirmed. The
      // unconfirmed ones are a separate list, never the pick.
      expect(find.byType(HeroCard), findsNothing);
      expect(find.text('조건 충족을 확인한 식당이 없어요'), findsOneWidget);
      final unverified = find.textContaining('미확인 후보');
      await tester.ensureVisible(unverified.first);
      await tester.tap(unverified.first);
      await tester.pumpAndSettle();
      expect(find.textContaining('가격·운영정보 미확인'), findsOneWidget);
      expect(find.text('가격 미확인'), findsWidgets);
      expect(find.byType(HeroCard), findsNothing);
      final restart = find.text('조건 초기화').first;
      await tester.ensureVisible(restart);
      await tester.tap(restart);
      await tester.pumpAndSettle();
      expect(h.container.read(homeCategoryProvider), isEmpty);
      expect(h.container.read(conditionsProvider).activeCount, 0);
      expect(find.byType(HeroCard), findsNothing);
      expect(find.text('조건을 고르고 추천받아 보세요'), findsOneWidget);
      expect(find.text('조건 초기화'), findsNothing);
    });

    testWidgets('after 길찾기 the 다녀오셨어요? card shows both labels whole at 390', (
      tester,
    ) async {
      final h = await openHome(tester, recsRequested: false);
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      final hero = h.container.read(homeRecsProvider).value!.hero.restaurant;
      h.container.read(activeRecommendationProvider.notifier).markWent(hero);
      await tester.pumpAndSettle();
      expect(find.text('${hero.name}에 다녀오셨어요?'), findsOneWidget);
      for (final label in ['먹었어요', '아직이요']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .didExceedMaxLines,
          isFalse,
          reason: '"$label" is cut off',
        );
      }
    });

    testWidgets('다녀오셨어요? is still asked once the place left the ranking', (
      tester,
    ) async {
      final h = await openHome(tester, recsRequested: false);
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      // e.g. it closed while they were eating (the open-now filter drops it).
      h.container
          .read(activeRecommendationProvider.notifier)
          .markWent(spot('문닫은집', 0.001));
      await tester.pumpAndSettle();
      expect(find.text('문닫은집에 다녀오셨어요?'), findsOneWidget);
    });

    testWidgets('먹었어요 opens the editor on the review already written', (
      tester,
    ) async {
      final h = await openHome(
        tester,
        recsRequested: false,
        auth: FakeAuthGateway(user: fakeUser()),
        reviews: FakeReviewRepository([
          StudentReview(
            id: 'mine',
            userId: 'user-1',
            kakaoPlaceId: '가까운집',
            rating: 4,
            body: '국물이 진해요',
            createdAt: DateTime.utc(2026, 11, 9),
            moderationStatus: 'visible',
          ),
        ]),
      );
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      h.container
          .read(activeRecommendationProvider.notifier)
          .markWent(spot('가까운집', 0.0005));
      await tester.pumpAndSettle();
      await tester.tap(find.text('먹었어요'));
      await tester.pumpAndSettle();
      // Saved, said so, and a review is offered, never opened by itself.
      expect(find.text('MY 식사 기록에 저장했어요'), findsOneWidget);
      expect(find.text('기록 보기'), findsOneWidget);
      expect(find.widgetWithText(TextField, '국물이 진해요'), findsNothing);
      expect(find.text('가까운집, 리뷰도 남길까요?'), findsOneWidget);
      // The notice closes by itself (about 3 s), even with its action; the
      // record stays on the device.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('MY 식사 기록에 저장했어요'), findsNothing);
      expect(h.sp.getString('meal_records_user-1'), contains('가까운집'));
      await tester.tap(find.text('리뷰 쓰기'));
      await tester.pumpAndSettle();
      // Not an empty form that would erase the text when saved.
      expect(find.widgetWithText(TextField, '국물이 진해요'), findsOneWidget);
    });

    testWidgets('coming back opens the recommendation still in use', (
      tester,
    ) async {
      final h = await openHome(tester, recsRequested: false);
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      // Asking alone (the ranking itself unchanged) already makes it "in use".
      expect(h.sp.getString(activeRecommendationPrefsKey), isNotNull);
      // 다음 추천 (what the card's button does).
      h.container
          .read(heroPickProvider.notifier)
          .step(h.container.read(homeRecsProvider).value!, 1);
      await tester.pumpAndSettle();
      final shown = h.container.read(homeRecsProvider).value!.hero;
      expect(shown, isNot(h.container.read(homeRecsProvider).value!.ranked[0]));
      final saved = h.sp.getString(activeRecommendationPrefsKey);
      expect(saved, contains(shown.restaurant.kakaoId));

      // A new start of the app with that on the device: straight to the pick.
      final again = await openHome(
        tester,
        recsRequested: false,
        storage: {'app_language': 'ko', activeRecommendationPrefsKey: saved!},
      );
      expect(find.text('조건을 고르고 추천받아 보세요'), findsNothing);
      expect(
        again.container.read(homeRecsProvider).value!.hero.restaurant.kakaoId,
        shown.restaurant.kakaoId,
      );

      // 조건 초기화 ends it.
      final restart = find.text('조건 초기화');
      await tester.ensureVisible(restart);
      await tester.tap(restart);
      await tester.pumpAndSettle();
      expect(again.sp.getString(activeRecommendationPrefsKey), isNull);
    });
  });

  group('게임으로 정하기', () {
    Future<Harness> openGames(WidgetTester tester) async {
      final h = await openHome(tester);
      final button = find.text('게임으로 정하기');
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      return h;
    }

    Future<void> confirmWinner(WidgetTester tester, Harness h) async {
      expect(find.text('오늘은 여기!'), findsOneWidget);
      expect(h.container.read(heroPickProvider), isNull);
      await tester.tap(find.text('여기로 정하기'));
      await tester.pumpAndSettle();
      // the winner is now the top pick and the sheet is gone
      expect(h.container.read(heroPickProvider), isNotNull);
      expect(find.text('오늘 뭐 먹지? 게임으로!'), findsNothing);
    }

    testWidgets('the sheet offers roulette, ladder and card flip', (
      tester,
    ) async {
      await openGames(tester);
      for (final t in ['룰렛', '사다리타기', '카드 뽑기']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('roulette: spin, then the winner can be chosen', (
      tester,
    ) async {
      final h = await openGames(tester);
      await tester.tap(find.text('룰렛'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('돌리기!'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('돌아가는 중…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // the spin
      await tester.pump(const Duration(seconds: 1)); // the short pause
      await tester.pumpAndSettle();
      await confirmWinner(tester, h);
    });

    testWidgets('ladder: pick a line, the walker ends on a place', (
      tester,
    ) async {
      final h = await openGames(tester);
      await tester.tap(find.text('사다리타기'));
      await tester.pumpAndSettle();
      expect(find.text('출발할 줄을 골라요'), findsOneWidget);
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await confirmWinner(tester, h);
    });

    testWidgets('cards: flip one, the rest turn over, then choose', (
      tester,
    ) async {
      final h = await openGames(tester);
      await tester.tap(find.text('카드 뽑기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('?').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await confirmWinner(tester, h);
    });

    testWidgets('play again replays; back returns to the games', (
      tester,
    ) async {
      await openGames(tester);
      await tester.tap(find.text('카드 뽑기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('다른 게임'));
      await tester.pumpAndSettle();
      expect(find.text('룰렛'), findsOneWidget);
      await tester.tap(find.text('카드 뽑기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('?').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('다시 뽑기'));
      await tester.pumpAndSettle();
      expect(find.text('카드를 한 장 골라요'), findsOneWidget);
    });

    testWidgets('every game fits a small screen with large text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHome(tester, size: const Size(320, 568));
      final button = find.text('게임으로 정하기');
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      for (final game in ['룰렛', '사다리타기', '카드 뽑기']) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(game));
        await tester.pumpAndSettle();
        await tester.tap(find.text(game));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: game);
        await tester.tapAt(const Offset(160, 20)); // scrim
        await tester.pumpAndSettle();
      }
    });

    test('a ladder never has touching rungs and is a one-to-one map', () {
      for (var seed = 0; seed < 50; seed++) {
        final rungs = buildLadder(5, 8, Random(seed));
        for (final row in rungs) {
          for (var g = 1; g < row.length; g++) {
            expect(row[g] && row[g - 1], isFalse);
          }
        }
        final ends = {for (var s = 0; s < 5; s++) ladderEnd(rungs, s)};
        expect(ends.length, 5, reason: 'seed $seed');
      }
    });

    test('one list for every game: 2-6 names, no blanks, no duplicates', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final setup = c.read(gameSetupProvider.notifier);
      setup.setMode(GameMode.custom);
      expect(setup.addName('   '), NameProblem.empty);
      expect(setup.addName('학식'), isNull);
      expect(setup.addName(' 학 식 '), NameProblem.duplicate);
      for (final n in ['편의점', '라면', '김밥', '돈가스', '마라탕']) {
        expect(setup.addName(n), isNull);
      }
      expect(setup.addName('일곱번째'), NameProblem.full);
      expect(setup.rename(1, '학식'), NameProblem.duplicate);
      expect(setup.rename(1, 'CU 편의점'), isNull);
      final items = c.read(gameSetupProvider).candidates(const []);
      // All six are played, by every game; none is a place.
      expect(items, hasLength(kGameMax));
      expect(items.every((x) => x.place == null), isTrue);
      expect(items[1].name, 'CU 편의점');
      setup.removeName(0);
      expect(c.read(gameSetupProvider).names, hasLength(5));
    });

    test('recommended places: the first matches, then only what still '
        'matches', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      RankedRestaurant ranked(String id) => RankedRestaurant(
        restaurant: fakeRestaurant(id, name: '식당'),
        meters: 100,
        walkMinutes: 2,
        insight: RestaurantInsight.unknown,
        reason: const RecommendReason(ReasonKind.walk),
      );
      final all = [
        for (final id in ['1', '2', '3', '4', '5']) ranked(id),
      ];
      final setup = c.read(gameSetupProvider.notifier)..syncPlaces(all);
      expect(c.read(gameSetupProvider).placeIds, ['1', '2', '3', '4']);
      setup.togglePlace('5');
      setup.togglePlace('1');
      expect(c.read(gameSetupProvider).placeIds, ['2', '3', '4', '5']);
      // A filter change removed place 3: it leaves the list, nothing else.
      setup.syncPlaces([
        for (final x in all)
          if (x.restaurant.kakaoId != '3') x,
      ]);
      expect(c.read(gameSetupProvider).placeIds, ['2', '4', '5']);
      final items = c.read(gameSetupProvider).candidates(all);
      expect(items.map((x) => x.name), ['식당2', '식당4', '식당5']);
      expect(items.every((x) => x.place != null), isTrue);
    });

    testWidgets('typed names: switching games keeps them, and the result is '
        'only the name', (tester) async {
      await openGames(tester);
      await tester.tap(find.text('직접 입력해서 정하기'));
      await tester.pumpAndSettle();
      for (final n in ['학식', '편의점 도시락']) {
        await tester.enterText(find.byType(TextField), n);
        await tester.tap(find.text('추가'));
        await tester.pumpAndSettle();
      }
      expect(find.text('후보 2개 · 2~6개'), findsOneWidget);
      await tester.tap(find.text('사다리타기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('다른 게임'));
      await tester.pumpAndSettle();
      // Back in the menu: the same two names.
      expect(find.text('학식'), findsOneWidget);
      expect(find.text('편의점 도시락'), findsOneWidget);
      await tester.tap(find.text('카드 뽑기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('?').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('오늘은 여기!'), findsOneWidget);
      // No invented place facts and no "여기로 정하기" for a typed name.
      Finder inSheet(Finder f) =>
          find.descendant(of: find.byType(BottomSheet), matching: f);
      expect(inSheet(find.textContaining('예상 도보')), findsNothing);
      expect(inSheet(find.text('여기로 정하기')), findsNothing);
      expect(find.text('다시 뽑기'), findsOneWidget);
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
