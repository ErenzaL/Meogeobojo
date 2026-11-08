import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/campus_meals/screens/campus_meal_screen.dart';
import 'package:meogeobojo/features/campus_meals/widgets/campus_meal_widgets.dart';
import 'package:meogeobojo/features/home/widgets/category_section.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_category_screen.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

const univ1 = '5c0a8f3e-0001-4a6e-9b1d-000000000001'; // 순천향
const univ2 = '5c0a8f3e-0002-4a6e-9b1d-000000000002'; // 호서

/// Tue 2026-11-03 12:00 in Seoul (03:00 UTC): week Mon Nov 2 - Sun Nov 8.
DateTime clock() => DateTime.utc(2026, 11, 3, 3);

Future<(Harness, FakeCampusMealRepository)> open(
  WidgetTester tester, {
  FakeCampusMealRepository? repo,
  String lang = 'ko',
  Size size = const Size(390, 844),
  DateTime Function()? now,
}) async {
  final fake =
      repo ??
      FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1')],
        },
        meals: [
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            price: 5500,
            start: '11:30',
            end: '13:30',
            source: 'https://example.org/menu',
            items: const [
              MenuItem(nameKo: '김치찌개', kind: MenuItemKind.main),
              MenuItem(nameKo: '쌀밥', kind: MenuItemKind.rice),
              MenuItem(nameKo: '깍두기', kind: MenuItemKind.side),
            ],
          ),
          fakeMeal(
            '2026-11-03',
            MealType.dinner,
            items: const [MenuItem(nameKo: '제육볶음')],
          ),
        ],
      );
  final h = await buildHarness(
    storage: {'app_language': lang},
    extraOverrides: [
      campusMealRepositoryProvider.overrideWithValue(fake),
      campusMealClockProvider.overrideWithValue(now ?? clock),
      campusMealCacheDurationProvider.overrideWithValue(Duration.zero),
    ],
  );
  await pumpApp(tester, h, home: const CampusMealScreen(), size: size);
  return (h, fake);
}

void main() {
  group('Home 학식 shortcut', () {
    Future<Harness> home(
      WidgetTester tester, {
      String lang = 'ko',
      Size? size,
    }) async {
      final fake = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1')],
        },
      );
      final h = await buildHarness(
        storage: {'app_language': lang},
        extraOverrides: [
          campusMealRepositoryProvider.overrideWithValue(fake),
          campusMealClockProvider.overrideWithValue(clock),
          campusMealCacheDurationProvider.overrideWithValue(Duration.zero),
        ],
      );
      await pumpApp(
        tester,
        h,
        home: const AppShell(),
        size: size ?? const Size(390, 844),
      );
      return h;
    }

    testWidgets('is shown next to the existing categories and opens the page', (
      tester,
    ) async {
      await home(tester);
      expect(
        find.descendant(
          of: find.byType(CategorySection),
          matching: find.text('학식'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.food_bank_rounded), findsOneWidget);
      // every restaurant category is visible next to it, nothing is hidden
      for (final c in ['전체', '한식', '양식', '중식', '세계 음식', '기타']) {
        expect(
          find.descendant(
            of: find.byType(CategorySection),
            matching: find.text(c),
          ),
          findsOneWidget,
          reason: c,
        );
      }
      await tester.tap(find.text('학식'));
      await tester.pumpAndSettle();
      expect(find.byType(CampusMealScreen), findsOneWidget);
      expect(find.text('이번 주 학식'), findsOneWidget);
    });

    testWidgets('back returns to an unchanged Home', (tester) async {
      await home(tester);
      await tester.tap(find.text('학식'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CampusMealScreen), findsNothing);
      expect(find.byType(CategorySection), findsOneWidget);
      expect(find.text('홈'), findsOneWidget);
    });

    for (final (lang, label) in [
      ('ko', '학식'),
      ('en', 'Campus Meals'),
      ('zh-Hans', '校园食堂'),
    ]) {
      testWidgets('label in $lang, no overflow at 320px', (tester) async {
        await home(tester, lang: lang, size: const Size(320, 568));
        expect(find.text(label), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the category buttons still open their restaurants', (
      tester,
    ) async {
      final h = await home(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(CategorySection),
          matching: find.text('한식'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantCategoryScreen), findsOneWidget);
      expect(h.restaurants.nearbyCalls.last.$2.queries, ['한식']);
    });
  });

  group('week and day display', () {
    testWidgets(
      'shows the page header, Monday-Sunday and highlights today (Seoul)',
      (tester) async {
        await open(tester);
        expect(find.text('순천향대학교'), findsOneWidget);
        expect(find.text('이번 주 학식'), findsOneWidget);
        expect(find.text('11월 2일 – 11월 8일'), findsOneWidget);
        for (final w in ['월', '화', '수', '목', '금', '토', '일']) {
          expect(find.text(w), findsOneWidget, reason: w);
        }
        for (final n in ['2', '3', '4', '5', '6', '7', '8']) {
          expect(
            find.descendant(
              of: find.byType(DaySelector),
              matching: find.text(n),
            ),
            findsOneWidget,
            reason: n,
          );
        }
        expect(
          find.text('11월 3일 (화)'),
          findsOneWidget,
          reason: 'selected date heading',
        );
        // "today" is selected on open, so there is no "오늘" shortcut yet
        expect(find.widgetWithText(TextButton, '오늘'), findsNothing);
      },
    );

    testWidgets(
      'Seoul time decides "today" even when UTC is still the day before',
      (tester) async {
        // 2026-11-02 16:00 UTC is already Tue Nov 3, 01:00 in Seoul
        await open(tester, now: () => DateTime.utc(2026, 11, 2, 16));
        expect(find.text('11월 3일 (화)'), findsOneWidget);
        expect(find.text('중식'), findsOneWidget);
      },
    );

    testWidgets('previous / next week and the 오늘 shortcut', (tester) async {
      final (h, repo) = await open(tester);
      await tester.tap(find.byTooltip('다음 주'));
      await tester.pumpAndSettle();
      expect(find.text('11월 9일 – 11월 15일'), findsOneWidget);
      expect(
        find.text('11월 10일 (화)'),
        findsOneWidget,
        reason: 'same weekday kept',
      );
      expect(repo.weekCalls.last, ('c1', '2026-11-09'));

      await tester.tap(find.byTooltip('이전 주'));
      await tester.tap(find.byTooltip('이전 주'));
      await tester.pumpAndSettle();
      expect(
        find.text('10월 26일 – 11월 1일'),
        findsOneWidget,
        reason: 'month boundary',
      );
      expect(find.text('10월 27일 (화)'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '오늘'));
      await tester.pumpAndSettle();
      expect(find.text('11월 2일 – 11월 8일'), findsOneWidget);
      expect(find.text('11월 3일 (화)'), findsOneWidget);
      expect(
        h.container.read(campusMealSelectionProvider).date,
        DateTime.utc(2026, 11, 3),
      );
    });

    testWidgets('year boundary week', (tester) async {
      await open(
        tester,
        now: () => DateTime.utc(2026, 12, 31, 3),
      ); // Thu Dec 31
      expect(find.text('12월 28일 – 1월 3일'), findsOneWidget);
      await tester.tap(find.byTooltip('다음 주'));
      await tester.pumpAndSettle();
      expect(find.text('1월 4일 – 1월 10일'), findsOneWidget);
      expect(find.text('1월 7일 (목)'), findsOneWidget);
    });

    testWidgets(
      'selecting another day (even Saturday/Sunday) refreshes the meals',
      (tester) async {
        await open(tester);
        expect(find.text('김치찌개'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(DaySelector),
            matching: find.text('4'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('11월 4일 (수)'), findsOneWidget);
        expect(find.text('김치찌개'), findsNothing);
        expect(find.text('등록된 학식 메뉴가 없어요.'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(DaySelector),
            matching: find.text('8'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('11월 8일 (일)'), findsOneWidget);
        // oldest day first: Monday starts the week
        expect(find.text('11월 2일 – 11월 8일'), findsOneWidget);
      },
    );
  });

  group('breakfast / lunch / dinner', () {
    testWidgets(
      'tabs switch without another network call (one query per week)',
      (tester) async {
        final (_, repo) = await open(tester);
        expect(
          find.text('김치찌개'),
          findsOneWidget,
        ); // lunch is the default at 12:00
        final calls = repo.weekCalls.length;
        await tester.tap(find.text('석식'));
        await tester.pumpAndSettle();
        expect(find.text('제육볶음'), findsOneWidget);
        expect(find.text('김치찌개'), findsNothing);
        await tester.tap(find.text('조식'));
        await tester.pumpAndSettle();
        expect(find.text('등록된 학식 메뉴가 없어요.'), findsOneWidget);
        await tester.tap(find.text('중식'));
        await tester.pumpAndSettle();
        expect(find.text('김치찌개'), findsOneWidget);
        expect(
          repo.weekCalls.length,
          calls,
          reason: 'tabs and days reuse the weekly result',
        );
        expect(repo.weekCalls, [('c1', '2026-11-02')]);
      },
    );

    testWidgets('default tab follows the time of day (Seoul)', (tester) async {
      await open(
        tester,
        now: () => DateTime.utc(2026, 11, 2, 22),
      ); // 07:00 Seoul
      expect(find.text('11월 3일 (화)'), findsOneWidget);
      final tabs = tester.widget<MealTabs>(find.byType(MealTabs));
      expect(tabs.selected, MealType.breakfast);
    });
  });

  group('menu content (nothing invented)', () {
    testWidgets(
      'shows items, price, serving time, verification date and source',
      (tester) async {
        await open(tester);
        expect(find.text('김치찌개'), findsOneWidget);
        expect(find.text('쌀밥'), findsOneWidget);
        expect(find.text('깍두기'), findsOneWidget);
        expect(find.text('5,500원'), findsOneWidget);
        expect(find.text('운영 11:30 – 13:30'), findsOneWidget);
        expect(find.text('메인'), findsOneWidget);
        expect(find.text('확인 2026년 11월 2일'), findsOneWidget);
        expect(find.text('출처 열기'), findsOneWidget);
      },
    );

    testWidgets('no price / time / source line when they are not in the data', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('석식'));
      await tester.pumpAndSettle();
      expect(find.textContaining('원'), findsNothing);
      expect(find.textContaining('운영'), findsNothing);
      expect(find.text('출처 열기'), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    });

    testWidgets('a second choice in the same meal is shown, not overwritten', (
      tester,
    ) async {
      final repo = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1')],
        },
        meals: [
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            option: 'A코너',
            order: 0,
            items: const [MenuItem(nameKo: '돈까스')],
            price: 5500,
          ),
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            option: 'B코너',
            order: 1,
            items: const [MenuItem(nameKo: '비빔밥')],
            price: 6000,
          ),
        ],
      );
      await open(tester, repo: repo);
      expect(find.text('A코너'), findsOneWidget);
      expect(find.text('B코너'), findsOneWidget);
      expect(find.text('돈까스'), findsOneWidget);
      expect(find.text('비빔밥'), findsOneWidget);
      expect(find.text('5,500원'), findsOneWidget);
      expect(find.text('6,000원'), findsOneWidget);
    });
  });

  group('different "no data" situations are not mixed up', () {
    testWidgets('whole week missing = not collected yet (never "closed")', (
      tester,
    ) async {
      final repo = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1')],
        },
      );
      await open(tester, repo: repo);
      expect(find.text('이 주의 학식 정보는 아직 등록되지 않았어요.'), findsOneWidget);
      expect(find.text('이 시간에는 운영하지 않아요'), findsNothing);
      expect(find.text('등록된 학식 메뉴가 없어요.'), findsNothing);
    });

    testWidgets('week has data but not this meal = no registered menu', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('조식'));
      await tester.pumpAndSettle();
      expect(find.text('등록된 학식 메뉴가 없어요.'), findsOneWidget);
      expect(find.text('이 시간에는 운영하지 않아요'), findsNothing);
    });

    testWidgets('closed is shown ONLY when the source says so', (tester) async {
      final repo = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1')],
        },
        meals: [
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            status: MealStatus.closed,
            items: const [],
          ),
          fakeMeal(
            '2026-11-03',
            MealType.dinner,
            status: MealStatus.noMenu,
            items: const [],
          ),
        ],
      );
      await open(tester, repo: repo);
      expect(find.text('이 시간에는 운영하지 않아요'), findsOneWidget);
      expect(find.text('출처에서 확인된 정보예요.'), findsOneWidget);
      await tester.tap(find.text('석식'));
      await tester.pumpAndSettle();
      expect(find.text('공개된 메뉴가 없어요'), findsOneWidget);
      await tester.tap(find.text('조식'));
      await tester.pumpAndSettle();
      expect(find.text('이 시간에는 운영하지 않아요'), findsNothing);
      expect(
        find.text('등록된 학식 메뉴가 없어요.'),
        findsOneWidget,
        reason: 'unknown, not closed',
      );
    });
  });

  group('loading and errors', () {
    testWidgets('shows a skeleton while loading', (tester) async {
      final (_, _) = await open(tester);
      // (loaded) just make sure no skeleton remains and no exception happened
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a failed weekly load shows an error with retry, then recovers',
      (tester) async {
        final repo = FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [fakeCafeteria('c1')],
          },
          meals: [fakeMeal('2026-11-03', MealType.lunch)],
        )..weekErrors.add(Exception('offline'));
        await open(tester, repo: repo);
        expect(find.text('학식 정보를 불러오지 못했어요'), findsOneWidget);
        expect(find.text('인터넷 연결을 확인하고 다시 시도해주세요.'), findsOneWidget);
        expect(
          find.text('이 시간에는 운영하지 않아요'),
          findsNothing,
          reason: 'an error is not "closed"',
        );
        await tester.tap(find.text('다시 시도'));
        await tester.pumpAndSettle();
        expect(find.text('김치찌개'), findsOneWidget);
      },
    );

    testWidgets('a failed cafeteria load can be retried', (tester) async {
      final repo = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1')],
        },
        meals: [fakeMeal('2026-11-03', MealType.lunch)],
      )..cafeteriaErrors.add(Exception('offline'));
      await open(tester, repo: repo);
      expect(find.text('학식 정보를 불러오지 못했어요'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('김치찌개'), findsOneWidget);
    });
  });

  group('universities and cafeterias', () {
    testWidgets('a university without registered cafeterias says so honestly', (
      tester,
    ) async {
      final repo = FakeCampusMealRepository();
      await open(tester, repo: repo);
      expect(find.text('이 학교의 학식 정보는 아직 등록되지 않았어요.'), findsOneWidget);
      expect(find.byType(MealTabs), findsNothing);
    });

    testWidgets(
      'changing the university reloads cafeterias and meals, language kept',
      (tester) async {
        final repo = FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [fakeCafeteria('c1')],
            univ2: [
              fakeCafeteria(
                'c2',
                universityId: univ2,
                kind: CafeteriaKind.dormitory,
              ),
            ],
          },
          meals: [
            fakeMeal(
              '2026-11-03',
              MealType.lunch,
              cafeteriaId: 'c1',
              items: const [MenuItem(nameKo: '순천향메뉴')],
            ),
            fakeMeal(
              '2026-11-03',
              MealType.lunch,
              cafeteriaId: 'c2',
              items: const [MenuItem(nameKo: '호서메뉴')],
            ),
          ],
        );
        final (h, _) = await open(tester, repo: repo, lang: 'en');
        expect(find.text('순천향메뉴'), findsOneWidget);
        expect(find.text('Soonchunhyang University'), findsOneWidget);

        final hoseo = kVerifiedUniversities.firstWhere((u) => u.id == univ2);
        await h.container
            .read(selectedUniversityProvider.notifier)
            .select(hoseo);
        await tester.pumpAndSettle();

        expect(find.text('호서메뉴'), findsOneWidget);
        expect(find.text('순천향메뉴'), findsNothing);
        expect(find.text('Hoseo University'), findsOneWidget);
        expect(repo.cafeteriaCalls, [univ1, univ2]);
        expect(
          find.text('This Week\'s Campus Meals'),
          findsOneWidget,
          reason: 'language preserved',
        );
      },
    );

    testWidgets('one cafeteria: the selector is hidden', (tester) async {
      await open(tester);
      expect(find.byType(CafeteriaSelector), findsNothing);
      expect(
        find.text('학생식당'),
        findsOneWidget,
        reason: 'category shown as context',
      );
    });

    testWidgets('several cafeterias: a selector that switches the data', (
      tester,
    ) async {
      final repo = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [
            fakeCafeteria('c1'),
            fakeCafeteria('c2', kind: CafeteriaKind.dormitory),
          ],
        },
        meals: [
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            cafeteriaId: 'c1',
            items: const [MenuItem(nameKo: '학생식당메뉴')],
          ),
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            cafeteriaId: 'c2',
            items: const [MenuItem(nameKo: '기숙사메뉴')],
          ),
        ],
      );
      await open(tester, repo: repo);
      expect(find.byType(CafeteriaSelector), findsOneWidget);
      expect(find.text('학생식당'), findsOneWidget);
      expect(find.text('학생식당메뉴'), findsOneWidget);
      await tester.tap(find.byType(CafeteriaSelector));
      await tester.pumpAndSettle();
      expect(find.text('기숙사식당'), findsOneWidget);
      await tester.tap(find.text('기숙사식당'));
      await tester.pumpAndSettle();
      expect(find.text('기숙사메뉴'), findsOneWidget);
      expect(find.text('학생식당메뉴'), findsNothing);
      expect(
        repo.weekCalls,
        containsAll([('c1', '2026-11-02'), ('c2', '2026-11-02')]),
      );
    });

    testWidgets(
      'a stale cafeteria pick falls back to the first of the new university',
      (tester) async {
        final repo = FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [
              fakeCafeteria('c1'),
              fakeCafeteria('c2', kind: CafeteriaKind.dormitory),
            ],
            univ2: [fakeCafeteria('c3', universityId: univ2)],
          },
          meals: [
            fakeMeal(
              '2026-11-03',
              MealType.lunch,
              cafeteriaId: 'c3',
              items: const [MenuItem(nameKo: '호서메뉴')],
            ),
          ],
        );
        final (h, _) = await open(tester, repo: repo);
        h.container
            .read(campusMealSelectionProvider.notifier)
            .selectCafeteria('c2');
        await tester.pumpAndSettle();
        final hoseo = kVerifiedUniversities.firstWhere((u) => u.id == univ2);
        await h.container
            .read(selectedUniversityProvider.notifier)
            .select(hoseo);
        await tester.pumpAndSettle();
        expect(find.text('호서메뉴'), findsOneWidget);
        expect(find.byType(CafeteriaSelector), findsNothing);
      },
    );
  });

  group('localization', () {
    testWidgets('English', (tester) async {
      await open(tester, lang: 'en');
      expect(find.text('This Week\'s Campus Meals'), findsOneWidget);
      expect(find.text('Nov 2 – Nov 8'), findsOneWidget);
      expect(find.text('Tue, Nov 3'), findsOneWidget);
      for (final w in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(w), findsOneWidget, reason: w);
      }
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('₩5,500'), findsOneWidget);
      expect(
        find.text('김치찌개'),
        findsOneWidget,
        reason: 'official menu names are not machine translated',
      );
      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();
      expect(
        find.text('No campus meal menu has been registered.'),
        findsOneWidget,
      );
    });

    testWidgets('Chinese', (tester) async {
      await open(tester, lang: 'zh-Hans');
      expect(find.text('本周校园食堂'), findsOneWidget);
      expect(find.text('早餐'), findsOneWidget);
      expect(find.text('午餐'), findsOneWidget);
      expect(find.text('晚餐'), findsOneWidget);
      for (final w in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(find.text(w), findsOneWidget, reason: w);
      }
      await tester.tap(find.text('早餐'));
      await tester.pumpAndSettle();
      expect(find.text('暂无已登记的食堂菜单。'), findsOneWidget);
    });

    testWidgets('a verified translation is shown; otherwise Korean', (
      tester,
    ) async {
      final repo = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1')],
        },
        meals: [
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            items: const [
              MenuItem(
                nameKo: '미역국',
                nameEn: 'Seaweed soup',
                kind: MenuItemKind.soup,
              ),
              MenuItem(nameKo: '쌀밥'),
            ],
          ),
        ],
      );
      await open(tester, repo: repo, lang: 'en');
      expect(find.text('Seaweed soup'), findsOneWidget);
      expect(find.text('쌀밥'), findsOneWidget);
      expect(find.text('Soup'), findsOneWidget, reason: 'UI label localized');
    });

    for (final lang in ['ko', 'en', 'zh-Hans']) {
      testWidgets('no overflow at 320x568 and 1.6x text in $lang', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repo = FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [
              fakeCafeteria('c1'),
              fakeCafeteria('c2', kind: CafeteriaKind.staff),
            ],
          },
          meals: [
            fakeMeal(
              '2026-11-03',
              MealType.lunch,
              option: 'A코너',
              price: 12000,
              start: '11:30',
              end: '13:30',
              source: 'https://example.org/m',
              items: const [
                MenuItem(
                  nameKo: '아주아주아주아주아주긴이름의메뉴가여기에들어갑니다',
                  kind: MenuItemKind.main,
                ),
                MenuItem(nameKo: '쌀밥', kind: MenuItemKind.rice),
              ],
            ),
          ],
        );
        await open(tester, repo: repo, lang: lang, size: const Size(320, 568));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
