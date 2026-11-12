import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/campus_meals/screens/campus_meal_screen.dart';
import 'package:meogeobojo/features/campus_meals/widgets/campus_meal_widgets.dart';
import 'package:meogeobojo/l10n/app_localizations.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

const univ = '5c0a8f3e-0001-4a6e-9b1d-000000000001';

Future<Harness> openPage(
  WidgetTester tester,
  List<CafeteriaMeal> meals, {
  Size size = const Size(390, 844),
  DateTime? now,
}) async {
  final repo = FakeCampusMealRepository(
    cafeteriasByUniversity: {
      univ: [fakeCafeteria('c1', nameKo: '향설1관')],
    },
    meals: meals,
  );
  final h = await buildHarness(
    meals: repo,
    extraOverrides: [
      // Mon 2026-11-09, 10:00 Seoul unless told otherwise.
      campusMealClockProvider.overrideWithValue(
        () => now ?? DateTime.utc(2026, 11, 9, 1),
      ),
      campusMealCacheDurationProvider.overrideWithValue(Duration.zero),
    ],
  );
  await pumpApp(
    tester,
    h,
    home: const Scaffold(body: CampusMealScreen()),
    size: size,
  );
  return h;
}

void main() {
  group('meal periods', () {
    test('three periods map to the database values and Korean labels', () {
      expect(MealType.values, [
        MealType.breakfast,
        MealType.lunch,
        MealType.dinner,
      ]);
      expect(MealType.fromDb('breakfast'), MealType.breakfast);
      expect(MealType.fromDb('lunch'), MealType.lunch);
      expect(MealType.fromDb('dinner'), MealType.dinner);
      expect(MealType.fromDb('brunch'), isNull);
      final ko = lookupAppLocalizations(const Locale('ko'));
      expect(MealType.values.map((t) => t.label(ko)), ['조식', '중식', '석식']);
      expect(ko.mealBreakfastProgram, '조식 · 천원의 아침밥');
    });

    test('a weekend opens on the next Monday (the selector is Mon-Fri)', () {
      expect(
        selectableDay(DateTime.utc(2026, 11, 7)),
        DateTime.utc(2026, 11, 9),
      );
      expect(
        selectableDay(DateTime.utc(2026, 11, 8)),
        DateTime.utc(2026, 11, 9),
      );
      expect(
        selectableDay(DateTime.utc(2026, 11, 6)),
        DateTime.utc(2026, 11, 6),
      );
    });

    test(
      'an admin photo and notice come from `extra`; only https photos load',
      () {
        CafeteriaMeal parse(Object? extra) => CafeteriaMeal.fromJson({
          'id': 'm',
          'cafeteria_id': 'c',
          'meal_date': '2026-11-10',
          'meal_type': 'lunch',
          'status': 'published',
          'menu_items': [
            {'name_ko': '김치찌개'},
          ],
          'verified_at': '2026-11-09T00:00:00Z',
          'extra': extra,
        })!;
        final m = parse({
          'photo_url': 'https://x.supabase.co/a.webp',
          'notice': ' 방학 중 운영 ',
          'photo_path': 'cafeteria/c1/a.webp',
        });
        expect(m.photoUrl, 'https://x.supabase.co/a.webp');
        expect(m.notice, '방학 중 운영');
        expect(parse({'photo_url': 'http://x/a.webp'}).photoUrl, isNull);
        expect(parse({'photo_url': '  ', 'notice': ''}).photoUrl, isNull);
        expect(parse({}).notice, isNull);
        expect(parse(null).photoUrl, isNull); // rows without extra still parse
      },
    );

    test('an admin-set badge is read from the row, blank means none', () {
      CafeteriaMeal parse(Object? badge) => CafeteriaMeal.fromJson({
        'id': 'm',
        'cafeteria_id': 'c',
        'meal_date': '2026-11-10',
        'meal_type': 'breakfast',
        'status': 'published',
        'menu_items': [
          {'name_ko': '북엇국'},
        ],
        'verified_at': '2026-11-09T00:00:00Z',
        'badge': badge,
      })!;
      expect(parse('천원의 아침밥').badge, '천원의 아침밥');
      expect(parse('  ').badge, isNull);
      expect(parse(null).badge, isNull);
    });
  });

  group('photo and notice from the admin', () {
    testWidgets(
      'the meal card shows the notice and tolerates its photo failing',
      (tester) async {
        await openPage(tester, [
          fakeMeal(
            '2026-11-09',
            MealType.lunch,
            photoUrl: 'https://x.supabase.co/a.webp',
            notice: '방학 중 운영시간이 달라요',
          ),
        ]);
        expect(find.text('방학 중 운영시간이 달라요'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        // the test HTTP client refuses the request: the card must not throw or show a stock photo
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('no photo means no image at all', (tester) async {
      await openPage(tester, [fakeMeal('2026-11-09', MealType.lunch)]);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('조식 · 천원의 아침밥', () {
    testWidgets('shows the price FROM THE DATA, never an assumed ₩1,000', (
      tester,
    ) async {
      final h = await openPage(tester, [
        fakeMeal(
          '2026-11-09',
          MealType.breakfast,
          badge: thousandWonBreakfast,
          price: 1200,
          start: '08:00',
          end: '09:30',
        ),
      ]);
      h.container
          .read(campusMealSelectionProvider.notifier)
          .selectMealType(MealType.breakfast);
      await tester.pumpAndSettle();
      expect(find.text('조식 · 천원의 아침밥'), findsOneWidget);
      expect(find.byType(BreakfastProgramCard), findsOneWidget);
      expect(find.text('1,200원'), findsWidgets);
      expect(find.text('1,000원'), findsNothing);
    });

    testWidgets('no price in the data means no price is shown', (tester) async {
      final h = await openPage(tester, [
        fakeMeal('2026-11-09', MealType.breakfast, badge: thousandWonBreakfast),
      ]);
      h.container
          .read(campusMealSelectionProvider.notifier)
          .selectMealType(MealType.breakfast);
      await tester.pumpAndSettle();
      expect(find.byType(BreakfastProgramCard), findsOneWidget);
      // "천원의 아침밥" is the programme name; a PRICE is digits + 원.
      expect(find.textContaining(RegExp(r'\d원')), findsNothing);
    });

    testWidgets(
      'an ordinary breakfast is NOT labelled 천원의 아침밥: the programme is per date and per option',
      (tester) async {
        final h = await openPage(tester, [
          fakeMeal('2026-11-09', MealType.breakfast, price: 3000),
        ]);
        h.container
            .read(campusMealSelectionProvider.notifier)
            .selectMealType(MealType.breakfast);
        await tester.pumpAndSettle();
        expect(find.byType(BreakfastProgramCard), findsNothing);
        expect(find.text('조식 · 천원의 아침밥'), findsNothing);
        expect(find.text('3,000원'), findsOneWidget);
      },
    );

    testWidgets('no breakfast data: empty state, no program claim', (
      tester,
    ) async {
      // breakfast exists later in the week, not on the opened day
      final h = await openPage(tester, [
        fakeMeal('2026-11-09', MealType.lunch),
        fakeMeal('2026-11-12', MealType.breakfast),
      ]);
      h.container
          .read(campusMealSelectionProvider.notifier)
          .selectMealType(MealType.breakfast);
      await tester.pumpAndSettle();
      expect(find.text('등록된 식단 정보가 없습니다.'), findsOneWidget);
      expect(find.byType(BreakfastProgramCard), findsNothing);
    });

    testWidgets('lunch and dinner have their own views', (tester) async {
      await openPage(tester, [
        fakeMeal(
          '2026-11-09',
          MealType.lunch,
          items: const [MenuItem(nameKo: '김치찌개', kind: MenuItemKind.main)],
        ),
        fakeMeal(
          '2026-11-09',
          MealType.dinner,
          items: const [MenuItem(nameKo: '제육볶음', kind: MenuItemKind.main)],
        ),
      ]);
      expect(find.text('김치찌개'), findsOneWidget);
      expect(find.byType(BreakfastProgramCard), findsNothing);
      await tester.tap(find.text('석식'));
      await tester.pumpAndSettle();
      expect(find.text('제육볶음'), findsOneWidget);
      expect(find.text('김치찌개'), findsNothing);
    });
  });

  group('layout', () {
    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(1280, 800),
    ]) {
      testWidgets('no overflow at $size with long names and 1.6x text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = await openPage(tester, [
          fakeMeal(
            '2026-11-09',
            MealType.breakfast,
            price: 1000,
            start: '08:00',
            end: '09:30',
            option: '아주아주아주 긴 코너 이름 한식뷔페',
            items: const [
              MenuItem(
                nameKo: '아주아주아주 긴 메인 메뉴 이름입니다 정말로',
                kind: MenuItemKind.main,
              ),
              MenuItem(nameKo: '시금치나물'),
            ],
          ),
        ], size: size);
        h.container
            .read(campusMealSelectionProvider.notifier)
            .selectMealType(MealType.breakfast);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
