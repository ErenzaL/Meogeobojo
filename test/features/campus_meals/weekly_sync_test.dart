import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/sync/content_sync.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/campus_meals/screens/campus_meal_screen.dart';
import 'package:meogeobojo/features/campus_meals/widgets/campus_meal_widgets.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

const univ1 = '5c0a8f3e-0001-4a6e-9b1d-000000000001';
const univ2 = '5c0a8f3e-0002-4a6e-9b1d-000000000002';

/// Tue 2026-11-03 12:00 in Seoul: the week of Mon Nov 2.
DateTime clock() => DateTime.utc(2026, 11, 3, 3);
const week = [
  '2026-11-02',
  '2026-11-03',
  '2026-11-04',
  '2026-11-05',
  '2026-11-06',
];

MenuItem item(String n) => MenuItem(nameKo: n, kind: MenuItemKind.main);

/// A full Monday-Friday week: breakfast, lunch, dinner every day.
List<CafeteriaMeal> fullWeek({String cafeteria = 'c1', String tag = ''}) => [
  for (final d in week)
    for (final t in MealType.values)
      fakeMeal(
        d,
        t,
        cafeteriaId: cafeteria,
        items: [item('${t.name} $d$tag')],
        price: 5000,
      ),
];

late StreamController<ContentChange> changes;
late FakeCampusMealRepository repo;

Future<Harness> open(
  WidgetTester tester, {
  FakeCampusMealRepository? fake,
  Size size = const Size(390, 1400),
  Duration cache = Duration.zero,
}) async {
  changes = StreamController<ContentChange>.broadcast();
  addTearDown(changes.close);
  repo =
      fake ??
      FakeCampusMealRepository(
        cafeteriasByUniversity: {
          univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
        },
        meals: fullWeek(),
      );
  final h = await buildHarness(
    meals: repo,
    extraOverrides: [
      campusMealClockProvider.overrideWithValue(clock),
      // production keeps a week for 5 minutes; by default every request reaches the fake
      campusMealCacheDurationProvider.overrideWithValue(cache),
      contentChangesProvider.overrideWith((ref) => changes.stream),
    ],
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  await tester.pumpAndSettle();
  await goToMeals(tester);
  return h;
}

Future<void> goToMeals(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(AppShell)))
      .push(MaterialPageRoute<void>(builder: (_) => const CampusMealScreen()));
  await tester.pumpAndSettle();
}

/// Opens the cafeteria picker (a popup menu) and returns the names it lists.
Future<List<String>> pickerNames(WidgetTester tester) async {
  await tester.tap(find.byType(CafeteriaSelector));
  await tester.pumpAndSettle();
  final names = [
    for (final w in tester.widgetList<PopupMenuItem<CampusCafeteria>>(
      find.byType(PopupMenuItem<CampusCafeteria>),
    ))
      (((w.child! as Row).children.first as Expanded).child as Text).data!,
  ];
  await tester.tapAt(const Offset(5, 5)); // dismiss
  await tester.pumpAndSettle();
  return names;
}

Future<void> goBack(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(CampusMealScreen))).pop();
  await tester.pumpAndSettle();
}

/// An admin change as the app sees it: the event, then the 0.8 s debounce and the reload.
Future<void> adminChange(WidgetTester tester, String table) async {
  changes.add(ContentChange(table));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  group('Monday-Friday x breakfast / lunch / dinner', () {
    testWidgets(
      'five weekday cells, three meal tabs, each meal shows its own menu',
      (tester) async {
        await open(tester);
        expect(find.byType(MealTabs), findsOneWidget);
        for (final t in ['조식', '중식', '석식']) {
          expect(find.text(t), findsWidgets);
        }
        // lunch is open by default at noon; walk every weekday and every meal
        for (final d in week) {
          await tester.tap(find.byKey(ValueKey('day-$d')));
          await tester.pumpAndSettle();
          for (final t in MealType.values) {
            await tester.tap(
              find
                  .text(
                    const {
                      'breakfast': '조식',
                      'lunch': '중식',
                      'dinner': '석식',
                    }[t.name]!,
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            expect(
              find.text('${t.name} $d'),
              findsOneWidget,
              reason: '$d ${t.name}',
            );
          }
        }
      },
    );

    testWidgets('weekdays only by default: no Saturday or Sunday cell', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const ValueKey('day-2026-11-07')), findsNothing);
      expect(find.byKey(const ValueKey('day-2026-11-08')), findsNothing);
    });

    testWidgets(
      'a cafeteria that opens on Saturday shows Saturday (and its menu)',
      (tester) async {
        await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [
                fakeCafeteria(
                  'c1',
                  nameKo: '학생식당',
                  operatingDays: {1, 2, 3, 4, 5, 6},
                ),
              ],
            },
            meals: [
              fakeMeal('2026-11-07', MealType.lunch, items: [item('토요 특식')]),
            ],
          ),
        );
        expect(find.byKey(const ValueKey('day-2026-11-07')), findsOneWidget);
        expect(find.byKey(const ValueKey('day-2026-11-08')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('day-2026-11-07')));
        await tester.pumpAndSettle();
        expect(find.text('토요 특식'), findsOneWidget);
      },
    );

    testWidgets('only the meals a cafeteria serves have a tab', (tester) async {
      await open(
        tester,
        fake: FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [
              fakeCafeteria('c1', nameKo: '학생식당', mealTypes: [MealType.lunch]),
            ],
          },
          meals: [
            fakeMeal('2026-11-03', MealType.lunch, items: [item('점심만')]),
          ],
        ),
      );
      expect(find.text('중식'), findsWidgets);
      expect(find.text('조식'), findsNothing);
      expect(find.text('석식'), findsNothing);
      expect(find.text('점심만'), findsOneWidget);
    });

    testWidgets('a stale meal pick falls back to a meal the cafeteria serves', (
      tester,
    ) async {
      // 12:00 would open on lunch, but this cafeteria serves breakfast and dinner only
      await open(
        tester,
        fake: FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [
              fakeCafeteria(
                'c1',
                nameKo: '학생식당',
                mealTypes: [MealType.breakfast, MealType.dinner],
              ),
            ],
          },
          meals: [
            fakeMeal('2026-11-03', MealType.breakfast, items: [item('아침만')]),
          ],
        ),
      );
      expect(find.text('중식'), findsNothing);
      expect(find.text('아침만'), findsOneWidget);
    });

    testWidgets(
      'several options for one meal are all listed, each with its own price',
      (tester) async {
        await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
            },
            meals: [
              fakeMeal(
                '2026-11-03',
                MealType.lunch,
                option: 'A코너',
                order: 0,
                price: 5500,
                items: [item('제육볶음')],
              ),
              fakeMeal(
                '2026-11-03',
                MealType.lunch,
                option: 'B코너',
                order: 1,
                price: 6500,
                items: [item('돈까스')],
              ),
            ],
          ),
        );
        expect(find.text('제육볶음'), findsOneWidget);
        expect(find.text('돈까스'), findsOneWidget);
        expect(find.text('5,500원'), findsOneWidget);
        expect(find.text('6,500원'), findsOneWidget);
        expect(find.text('A코너'), findsOneWidget);
        expect(find.text('B코너'), findsOneWidget);
      },
    );
  });

  group('천원의 아침밥 is per date, never assumed', () {
    testWidgets(
      'only the breakfast an admin marked is labelled; the next day is an ordinary breakfast',
      (tester) async {
        final h = await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
            },
            meals: [
              fakeMeal(
                '2026-11-03',
                MealType.breakfast,
                badge: thousandWonBreakfast,
                price: 1000,
                source: 'https://example.org/1000',
                items: [item('북엇국')],
              ),
              fakeMeal(
                '2026-11-04',
                MealType.breakfast,
                price: 3000,
                items: [item('샌드위치')],
              ),
            ],
          ),
        );
        h.container
            .read(campusMealSelectionProvider.notifier)
            .selectMealType(MealType.breakfast);
        await tester.pumpAndSettle();
        expect(find.byType(BreakfastProgramCard), findsOneWidget);
        expect(find.text('1,000원'), findsWidgets);
        await tester.tap(find.byKey(const ValueKey('day-2026-11-04')));
        await tester.pumpAndSettle();
        expect(find.text('샌드위치'), findsOneWidget);
        expect(find.byType(BreakfastProgramCard), findsNothing);
        expect(find.text('조식 · 천원의 아침밥'), findsNothing);
      },
    );
  });

  group('what a menu shows', () {
    testWidgets(
      'price, serving time, photo, description, notice and sold-out',
      (tester) async {
        await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
            },
            meals: [
              fakeMeal(
                '2026-11-03',
                MealType.lunch,
                option: 'A코너',
                price: 5500,
                start: '11:30',
                end: '13:30',
                description: '매콤한 제육',
                notice: '오늘 한정 판매',
                soldOut: true,
                items: [item('제육볶음')],
              ),
            ],
          ),
        );
        expect(find.text('5,500원'), findsOneWidget);
        expect(find.textContaining('11:30'), findsWidgets);
        expect(find.text('매콤한 제육'), findsOneWidget);
        expect(find.text('오늘 한정 판매'), findsOneWidget);
        expect(find.byKey(const ValueKey('meal-sold-out')), findsOneWidget);
        expect(find.textContaining('품절'), findsWidgets);
      },
    );
    testWidgets('an item that is not sold out shows no sold-out label', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const ValueKey('meal-sold-out')), findsNothing);
    });
    testWidgets(
      'closed, no menu, and nothing registered each get their own message',
      (tester) async {
        await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
            },
            meals: [
              fakeMeal(
                '2026-11-03',
                MealType.dinner,
                status: MealStatus.closed,
                items: const [],
              ),
              fakeMeal(
                '2026-11-04',
                MealType.lunch,
                status: MealStatus.noMenu,
                items: const [],
              ),
            ],
          ),
        );
        await tester.tap(find.text('석식').first);
        await tester.pumpAndSettle();
        expect(find.text('이 시간에는 운영하지 않아요'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('day-2026-11-04')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('중식').first);
        await tester.pumpAndSettle();
        expect(find.text('이 시간에는 운영하지 않아요'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('day-2026-11-05')));
        await tester.pumpAndSettle();
        expect(find.text('등록된 식단 정보가 없습니다.'), findsOneWidget);
      },
    );
    testWidgets('the cafeteria photo is shown when there is one', (
      tester,
    ) async {
      await open(
        tester,
        fake: FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [
              fakeCafeteria(
                'c1',
                nameKo: '학생식당',
                photoUrl: 'https://x.supabase.co/p.jpg',
              ),
            ],
          },
          meals: fullWeek(),
        ),
      );
      expect(find.byKey(const ValueKey('cafeteria-photo')), findsOneWidget);
    });
  });

  group('university separation', () {
    testWidgets(
      'only the selected university\'s cafeterias are listed; switching university switches them',
      (tester) async {
        final h = await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [
                fakeCafeteria('c1', nameKo: '순천향 학생식당'),
                fakeCafeteria(
                  'c2',
                  nameKo: '순천향 기숙사식당',
                  kind: CafeteriaKind.dormitory,
                ),
              ],
              univ2: [
                fakeCafeteria('c3', universityId: univ2, nameKo: '호서 학생식당'),
              ],
            },
            meals: [
              fakeMeal(
                '2026-11-03',
                MealType.lunch,
                cafeteriaId: 'c1',
                items: [item('순천향 점심')],
              ),
              fakeMeal(
                '2026-11-03',
                MealType.lunch,
                cafeteriaId: 'c3',
                items: [item('호서 점심')],
              ),
            ],
          ),
        );
        expect(await pickerNames(tester), ['순천향 학생식당', '순천향 기숙사식당']);
        expect(find.text('순천향 점심'), findsOneWidget);
        await h.container
            .read(selectedUniversityProvider.notifier)
            .select(kVerifiedUniversities.firstWhere((u) => u.id == univ2));
        await tester.pumpAndSettle();
        expect(
          find.text('호서 학생식당'),
          findsOneWidget,
        ); // one cafeteria: no picker, just its name
        expect(find.byType(CafeteriaSelector), findsNothing);
        expect(find.text('호서 점심'), findsOneWidget);
        expect(find.text('순천향 점심'), findsNothing);
        expect(repo.cafeteriaCalls, containsAll([univ1, univ2]));
      },
    );
  });

  group('live synchronisation: publish, update, unpublish, delete', () {
    testWidgets('INSERT: a newly published week appears without any refresh', (
      tester,
    ) async {
      await open(
        tester,
        fake: FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
          },
        ),
      );
      expect(
        find.text('등록된 식단 정보가 없습니다.'),
        findsNothing,
      ); // whole week missing: its own message
      repo.meals = fullWeek();
      await adminChange(tester, 'cafeteria_meals');
      expect(find.text('lunch 2026-11-03'), findsOneWidget);
    });

    testWidgets('UPDATE: a changed menu and price replace the old ones', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('lunch 2026-11-03'), findsOneWidget);
      repo.meals = [for (final m in fullWeek(tag: ' (수정)')) m];
      await adminChange(tester, 'cafeteria_meals');
      expect(find.text('lunch 2026-11-03'), findsNothing);
      expect(find.text('lunch 2026-11-03 (수정)'), findsOneWidget);
    });

    testWidgets(
      'UNPUBLISH: an empty server answer clears the week at once (no stale menu)',
      (tester) async {
        await open(tester);
        expect(find.text('lunch 2026-11-03'), findsOneWidget);
        repo.meals = []; // the whole week was unpublished: the server now returns nothing
        await adminChange(tester, 'cafeteria_meals');
        expect(find.text('lunch 2026-11-03'), findsNothing);
        expect(find.text('김치찌개'), findsNothing);
      },
    );

    testWidgets(
      'one removed menu disappears while the rest of the week stays',
      (tester) async {
        await open(tester);
        repo.meals = [
          for (final m in fullWeek())
            if (!(m.date == DateTime.utc(2026, 11, 3) &&
                m.type == MealType.lunch))
              m,
        ];
        await adminChange(tester, 'cafeteria_meals');
        expect(find.text('lunch 2026-11-03'), findsNothing);
        await tester.tap(find.text('석식').first);
        await tester.pumpAndSettle();
        expect(find.text('dinner 2026-11-03'), findsOneWidget);
      },
    );

    testWidgets(
      'REPEATED events for the same table all refresh (publish, then unpublish)',
      (tester) async {
        await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
            },
          ),
        );
        repo.meals = fullWeek();
        await adminChange(tester, 'cafeteria_meals');
        expect(find.text('lunch 2026-11-03'), findsOneWidget);
        repo.meals = [];
        await adminChange(
          tester,
          'cafeteria_meals',
        ); // the same event again: used to be dropped
        expect(find.text('lunch 2026-11-03'), findsNothing);
        repo.meals = fullWeek(tag: ' v3');
        await adminChange(tester, 'cafeteria_meals');
        expect(find.text('lunch 2026-11-03 v3'), findsOneWidget);
      },
    );

    testWidgets('a deactivated or deleted cafeteria disappears from the list', (
      tester,
    ) async {
      await open(
        tester,
        fake: FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [
              fakeCafeteria('c1', nameKo: '학생식당'),
              fakeCafeteria('c2', nameKo: '기숙사식당'),
            ],
          },
          meals: fullWeek(),
        ),
      );
      expect(await pickerNames(tester), ['학생식당', '기숙사식당']);
      repo.cafeteriasByUniversity = {
        univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
      };
      await adminChange(tester, 'campus_cafeterias');
      expect(
        find.byType(CafeteriaSelector),
        findsNothing,
      ); // one left: no picker
      expect(find.text('lunch 2026-11-03'), findsOneWidget);
    });

    testWidgets(
      'when every cafeteria is switched off the screen says so instead of keeping the old list',
      (tester) async {
        await open(tester);
        expect(find.text('학생식당'), findsWidgets);
        repo.cafeteriasByUniversity = {univ1: []};
        await adminChange(tester, 'campus_cafeterias');
        expect(find.text('이 학교의 학식 정보는 아직 등록되지 않았어요.'), findsOneWidget);
        expect(find.byType(MealTabs), findsNothing);
      },
    );

    testWidgets(
      'a change to an unrelated table does not reload the cafeteria',
      (tester) async {
        await open(tester);
        final before = repo.weekCalls.length;
        await adminChange(tester, 'app_content');
        expect(repo.weekCalls.length, before);
      },
    );

    testWidgets('a burst of changes is ONE reload, not one per event', (
      tester,
    ) async {
      await open(tester);
      final before = repo.weekCalls.length;
      for (var i = 0; i < 6; i++) {
        changes.add(ContentChange('cafeteria_meals'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.weekCalls.length - before, 1);
    });
  });

  group('refresh paths when no event arrives', () {
    testWidgets('a Realtime reconnect (resync) re-reads the week', (
      tester,
    ) async {
      await open(tester);
      repo.meals = fullWeek(tag: ' after-reconnect');
      changes.add(ContentChange.resync());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('lunch 2026-11-03 after-reconnect'), findsOneWidget);
    });

    testWidgets('returning to the app (resume) re-reads the week', (
      tester,
    ) async {
      await open(tester);
      repo.meals = fullWeek(tag: ' while-away');
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
      expect(find.text('lunch 2026-11-03 while-away'), findsOneWidget);
    });

    testWidgets('navigating away and back to 학식 re-reads the week', (
      tester,
    ) async {
      final h = await open(
        tester,
        cache: const Duration(minutes: 5),
      ); // the production cache
      await goBack(tester);
      repo.meals = fullWeek(tag: ' revisited');
      final before = repo.weekCalls.length;
      await goToMeals(tester);
      expect(repo.weekCalls.length, greaterThan(before));
      expect(find.text('lunch 2026-11-03 revisited'), findsOneWidget);
      // the production-length cache timers are cancelled with the container
      await tester.pumpWidget(const SizedBox());
      h.container.dispose();
    });

    testWidgets('pull-to-refresh re-reads the week', (tester) async {
      await open(tester);
      repo.meals = fullWeek(tag: ' pulled');
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 500),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('lunch 2026-11-03 pulled'), findsOneWidget);
    });

    testWidgets(
      'a failed reload keeps the last menu; the next successful one (even an empty one) replaces it',
      (tester) async {
        await open(tester);
        repo.weekErrors.add(Exception('offline'));
        await adminChange(tester, 'cafeteria_meals');
        expect(
          find.text('lunch 2026-11-03'),
          findsOneWidget,
          reason: 'an outage is not a take-down',
        );
        expect(find.text('학식 정보를 불러오지 못했어요'), findsNothing);
        repo.meals = [];
        await adminChange(tester, 'cafeteria_meals');
        expect(
          find.text('lunch 2026-11-03'),
          findsNothing,
          reason: 'the server confirmed there is nothing',
        );
      },
    );

    testWidgets('a failed first load of a week still offers a retry', (
      tester,
    ) async {
      await open(tester);
      // another week has never been fetched: its first load fails
      repo.weekErrors.add(Exception('offline'));
      repo.meals = [
        ...fullWeek(),
        fakeMeal('2026-10-27', MealType.lunch, items: [item('지난주 점심')]),
      ];
      await tester.tap(find.byTooltip('이전 주').first);
      await tester.pumpAndSettle();
      expect(find.text('학식 정보를 불러오지 못했어요'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('지난주 점심'), findsOneWidget);
    });
  });

  group('model parsing (the same code runs on mobile and web)', () {
    test('a database without the weekly columns means three meals on Monday-Friday', () {
      final c = CampusCafeteria.fromJson({
        'id': 'c',
        'university_id': 'u',
        'kind': 'student',
      });
      expect(c.mealTypes, MealType.values);
      expect(c.operatingDays, {1, 2, 3, 4, 5});
      expect(c.opensAtWeekend, isFalse);
      expect(c.photoUrl, isNull);
    });
    test('meal periods, weekdays and the photo are read; junk is ignored; the photo must be https', () {
      final c = CampusCafeteria.fromJson({
        'id': 'c',
        'university_id': 'u',
        'kind': 'student',
        'meal_periods': ['dinner', 'lunch', 'brunch'],
        'operating_days': [6, 1, 9, 'x'],
        'photo_url': 'http://insecure/p.jpg',
      });
      expect(c.mealTypes, [MealType.lunch, MealType.dinner]);
      expect(c.operatingDays, {1, 6});
      expect(c.opensAtWeekend, isTrue);
      expect(c.photoUrl, isNull);
      expect(
        CampusCafeteria.fromJson({
          'id': 'c',
          'university_id': 'u',
          'kind': 'student',
          'photo_url': 'https://x/p.jpg',
        }).photoUrl,
        'https://x/p.jpg',
      );
    });
    test('description and sold-out come from extra; a draft row is never understood by the app', () {
      final base = {
        'id': 'm',
        'cafeteria_id': 'c',
        'meal_date': '2026-11-03',
        'meal_type': 'lunch',
        'menu_items': [
          {'name_ko': '제육'},
        ],
        'verified_at': '2026-11-02T00:00:00Z',
      };
      final m = CafeteriaMeal.fromJson({
        ...base,
        'status': 'published',
        'extra': {'description': '매콤', 'sold_out': true},
      })!;
      expect((m.description, m.soldOut), ('매콤', true));
      expect(
        CafeteriaMeal.fromJson({...base, 'status': 'published', 'extra': {}})!
            .soldOut,
        isFalse,
      );
      expect(
        CafeteriaMeal.fromJson({...base, 'status': 'draft', 'extra': {}}),
        isNull,
      );
    });
  });
}
