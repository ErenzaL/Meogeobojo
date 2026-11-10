import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';

import '../../support/fakes.dart';
import 'weekly_sync_test.dart'
    show adminChange, fullWeek, item, open, repo, univ1;

// The same Dart code runs on Flutter Web and on Android/iOS, so these widget and model tests
// cover both platforms; nothing here depends on a platform.

/// Monday lunch of a real university menu table (향설1관 주간메뉴표), placed on the test clock's day.
List<MenuItem> hyangseolLunch() => const [
  MenuItem(nameKo: '치즈닭갈비볶음밥', kind: MenuItemKind.main),
  MenuItem(nameKo: '새우튀김*타르타르', kind: MenuItemKind.side),
  MenuItem(nameKo: '참나물무침', kind: MenuItemKind.side),
  MenuItem(nameKo: '햄감자채볶음', kind: MenuItemKind.side),
  MenuItem(nameKo: '파래무침', kind: MenuItemKind.side),
  MenuItem(nameKo: '계란국', kind: MenuItemKind.soup),
  MenuItem(nameKo: '김치', kind: MenuItemKind.kimchi, shared: true),
  MenuItem(nameKo: '샐러드', kind: MenuItemKind.salad, shared: true),
  MenuItem(nameKo: '후식차', kind: MenuItemKind.dessert, shared: true),
];

Finder within(String key, String text) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));

Future<void> openWith(WidgetTester tester, CafeteriaMeal meal) => open(
  tester,
  fake: FakeCampusMealRepository(
    cafeteriasByUniversity: {
      univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
    },
    meals: [meal],
  ),
);

void main() {
  group('a meal with several dishes', () {
    testWidgets(
      'shows the main dish, the dishes of the day and what is served with every meal',
      (tester) async {
        await openWith(
          tester,
          fakeMeal('2026-11-03', MealType.lunch, items: hyangseolLunch()),
        );
        expect(within('meal-dishes-main', '치즈닭갈비볶음밥'), findsOneWidget);
        for (final d in ['새우튀김*타르타르', '참나물무침', '햄감자채볶음', '파래무침', '계란국']) {
          expect(within('meal-dishes-side', d), findsOneWidget, reason: d);
        }
        for (final d in ['김치', '샐러드', '후식차']) {
          expect(within('meal-dishes-shared', d), findsOneWidget, reason: d);
        }
        expect(find.text('함께 제공'), findsOneWidget);
        // nothing is duplicated between the groups
        expect(find.text('김치'), findsOneWidget);
        expect(find.text('치즈닭갈비볶음밥'), findsOneWidget);
      },
    );

    testWidgets(
      'a dish shared by the day is listed once per meal, and rice/salad that is not flagged still goes under "served with"',
      (tester) async {
        await openWith(
          tester,
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            items: const [
              MenuItem(nameKo: '제육볶음', kind: MenuItemKind.main),
              MenuItem(nameKo: '쌀밥', kind: MenuItemKind.rice),
              MenuItem(nameKo: '콩나물국', kind: MenuItemKind.soup),
              MenuItem(nameKo: '단무지', kind: MenuItemKind.side, shared: true),
            ],
          ),
        );
        expect(within('meal-dishes-side', '콩나물국'), findsOneWidget);
        expect(within('meal-dishes-shared', '쌀밥'), findsOneWidget);
        expect(within('meal-dishes-shared', '단무지'), findsOneWidget);
      },
    );

    testWidgets(
      'an older menu without categories (all "other") looks as it did: no "served with" heading',
      (tester) async {
        await openWith(
          tester,
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            items: const [
              MenuItem(nameKo: '된장찌개'),
              MenuItem(nameKo: '공기밥'),
            ],
          ),
        );
        expect(find.text('된장찌개'), findsOneWidget);
        expect(find.text('공기밥'), findsOneWidget);
        expect(find.text('함께 제공'), findsNothing);
        expect(find.byKey(const ValueKey('meal-dishes-shared')), findsNothing);
      },
    );

    testWidgets('a verified HALAL label shows; none shows nothing', (
      tester,
    ) async {
      await openWith(
        tester,
        fakeMeal(
          '2026-11-03',
          MealType.lunch,
          items: hyangseolLunch(),
          dietaryLabels: const ['HALAL'],
        ),
      );
      expect(find.byKey(const ValueKey('meal-label-HALAL')), findsOneWidget);
      expect(find.text('HALAL'), findsOneWidget);
    });

    testWidgets('the origin statement is collapsed until tapped', (
      tester,
    ) async {
      await openWith(
        tester,
        fakeMeal(
          '2026-11-03',
          MealType.lunch,
          items: hyangseolLunch(),
          origin: '쌀:국내산 / 배추김치:중국산',
        ),
      );
      expect(find.text('원산지 표시사항'), findsOneWidget);
      expect(find.byKey(const ValueKey('meal-origin-text')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('meal-origin-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('쌀:국내산 / 배추김치:중국산'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('meal-origin-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('meal-origin-text')), findsNothing);
    });

    testWidgets('a meal without origin or labels shows neither', (
      tester,
    ) async {
      await openWith(
        tester,
        fakeMeal('2026-11-03', MealType.lunch, items: hyangseolLunch()),
      );
      expect(find.text('원산지 표시사항'), findsNothing);
      expect(find.byKey(const ValueKey('meal-label-HALAL')), findsNothing);
    });

    testWidgets(
      'live sync: a change to the dishes, the shared dishes and the label replaces what is shown, and unpublishing clears it',
      (tester) async {
        await open(
          tester,
          fake: FakeCampusMealRepository(
            cafeteriasByUniversity: {
              univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
            },
            meals: [
              fakeMeal('2026-11-03', MealType.lunch, items: hyangseolLunch()),
            ],
          ),
        );
        expect(find.text('후식차'), findsOneWidget);
        expect(find.byKey(const ValueKey('meal-label-HALAL')), findsNothing);
        repo.meals = [
          fakeMeal(
            '2026-11-03',
            MealType.lunch,
            items: [
              ...hyangseolLunch().where((i) => i.nameKo != '후식차'),
              const MenuItem(
                nameKo: '아산쌀밥',
                kind: MenuItemKind.rice,
                shared: true,
              ),
            ],
            dietaryLabels: const ['HALAL'],
          ),
        ];
        await adminChange(tester, 'cafeteria_meals');
        expect(find.text('후식차'), findsNothing);
        expect(within('meal-dishes-shared', '아산쌀밥'), findsOneWidget);
        expect(find.byKey(const ValueKey('meal-label-HALAL')), findsOneWidget);
        repo.meals = [];
        await adminChange(tester, 'cafeteria_meals');
        expect(find.text('치즈닭갈비볶음밥'), findsNothing);
        expect(find.text('아산쌀밥'), findsNothing);
      },
    );

    testWidgets('the card fits a narrow phone with a long menu (no overflow)', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(320, 1400),
        fake: FakeCampusMealRepository(
          cafeteriasByUniversity: {
            univ1: [fakeCafeteria('c1', nameKo: '학생식당')],
          },
          meals: [
            fakeMeal(
              '2026-11-03',
              MealType.lunch,
              items: [
                ...hyangseolLunch(),
                for (var i = 0; i < 12; i++)
                  MenuItem(nameKo: '아주 긴 이름의 반찬 번호 $i 무침', shared: i.isEven),
              ],
              origin: '쌀:국내산 / ' * 30,
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('meal-origin-toggle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a full week still loads as before', (tester) async {
      await open(tester);
      expect(find.text('lunch 2026-11-03'), findsOneWidget);
      expect(fullWeek().length, 15);
      expect(item('x').kind, MenuItemKind.main);
    });
  });

  group('parsing the dishes (shared by Web and mobile)', () {
    Map<String, dynamic> row(Object? items, Map<String, dynamic> extra) => {
      'id': 'm',
      'cafeteria_id': 'c',
      'meal_date': '2026-11-03',
      'meal_type': 'lunch',
      'status': 'published',
      'menu_items': items,
      'verified_at': '2026-11-02T00:00:00Z',
      'extra': extra,
    };

    test('every category is read, shared dishes are flagged, an unknown category is "other"', () {
      final m = CafeteriaMeal.fromJson(
        row([
          {'name_ko': 'a', 'kind': 'main'},
          {'name_ko': 'b', 'kind': 'soup'},
          {'name_ko': 'c', 'kind': 'kimchi', 'shared': true},
          {'name_ko': 'd', 'kind': 'salad'},
          {'name_ko': 'e', 'kind': 'dessert'},
          {'name_ko': 'f', 'kind': 'drink'},
          {'name_ko': 'g', 'kind': 'rice'},
          {'name_ko': 'h', 'kind': 'from-a-newer-version'},
          {'name_ko': 'i'},
          'j',
        ], {}),
      )!;
      expect(m.items.map((i) => i.kind), [
        MenuItemKind.main,
        MenuItemKind.soup,
        MenuItemKind.kimchi,
        MenuItemKind.salad,
        MenuItemKind.dessert,
        MenuItemKind.drink,
        MenuItemKind.rice,
        MenuItemKind.other,
        MenuItemKind.other,
        MenuItemKind.other,
      ]);
      expect(m.items.where((i) => i.shared).map((i) => i.nameKo), ['c']);
    });

    test('labels count only when the admin confirmed them; unknown labels and wrong types are dropped', () {
      List<String> labels(Map<String, dynamic> extra) => CafeteriaMeal.fromJson(
        row([
          {'name_ko': 'a'},
        ], extra),
      )!.dietaryLabels;
      expect(
        labels({
          'labels': ['HALAL'],
          'labels_verified': true,
        }),
        ['HALAL'],
      );
      expect(
        labels({
          'labels': ['halal', 'VEGAN'],
          'labels_verified': true,
        }),
        ['HALAL', 'VEGAN'],
      );
      expect(
        labels({
          'labels': ['HALAL'],
        }),
        isEmpty,
      ); // not confirmed
      expect(
        labels({
          'labels': ['HALAL'],
          'labels_verified': false,
        }),
        isEmpty,
      );
      expect(
        labels({
          'labels': ['HALAL'],
          'labels_verified': 'true',
        }),
        isEmpty,
      );
      expect(
        labels({
          'labels': ['KOSHER', 7],
          'labels_verified': true,
        }),
        isEmpty,
      );
      expect(labels({'labels': 'HALAL', 'labels_verified': true}), isEmpty);
    });

    test('the origin statement is read and trimmed; blank means none', () {
      String? origin(Object? v) => CafeteriaMeal.fromJson(
        row(
          [
            {'name_ko': 'a'},
          ],
          {'origin': v},
        ),
      )!.origin;
      expect(origin(' 쌀:국내산 '), '쌀:국내산');
      expect(origin('   '), isNull);
      expect(origin(null), isNull);
      expect(origin(42), isNull);
    });
  });
}
