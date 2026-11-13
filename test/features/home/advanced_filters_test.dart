import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/conditions/providers/conditions_providers.dart';
import 'package:meogeobojo/features/home/widgets/advanced_filters.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Restaurant spot(String name, double dLat) => Restaurant(
  kakaoId: name,
  name: name,
  categoryName: '음식점 > 한식',
  categoryGroupCode: 'FD6',
  address: '',
  roadAddress: '',
  phone: '',
  latitude: 36.769563 + dLat,
  longitude: 126.92736,
  distanceMeters: 0,
  placeUrl: null,
);

Future<Harness> open(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  final h = await buildHarness(
    restaurants: FakeRestaurantRepository(
      items: [spot('가까운집', 0.0005), spot('중간집', 0.0015)],
    ),
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  await tester.pumpAndSettle();
  return h;
}

Conditions cond(Harness h) => h.container.read(conditionsProvider);

void main() {
  group('desktop advanced filters', () {
    testWidgets(
      'the 조건 pill expands and collapses the inline panel (no modal sheet)',
      (tester) async {
        await open(tester);
        expect(find.byKey(const ValueKey('advanced-filters')), findsNothing);
        await tester.tap(find.text('조건').first);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('advanced-filters')), findsOneWidget);
        expect(find.text('상세 조건'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.tap(find.text('접기'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('advanced-filters')), findsNothing);
      },
    );

    testWidgets('choices in the panel change the SAME shared conditions', (
      tester,
    ) async {
      final h = await open(tester);
      await tester.tap(find.text('조건').first);
      await tester.pumpAndSettle();
      // Party and needs have no data behind them: not offered.
      expect(find.text('혼자'), findsNothing);
      expect(find.text('조용한 대화'), findsNothing);
      await tester.tap(find.text('8,000원 이하').last);
      await tester.pumpAndSettle();
      expect(cond(h).budget, BudgetOption.max8000);
      await tester.tap(find.text('거리순').last);
      await tester.pumpAndSettle();
      expect(cond(h).sort, SortMode.distance);
    });

    testWidgets(
      'applied conditions show as removable chips; each removes only itself',
      (tester) async {
        final h = await open(tester);
        expect(find.byKey(const ValueKey('applied-filters')), findsNothing);
        h.container
            .read(conditionsProvider.notifier)
            .update(
              (c) => c.copyWith(
                budget: BudgetOption.max10000,
                distance: DistanceOption.walk10,
                cuisines: {Cuisine.korean},
                sort: SortMode.distance,
              ),
            );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('applied-filters')), findsOneWidget);
        expect(find.byType(InputChip), findsNWidgets(4));

        await tester.tap(find.byTooltip('도보 10분 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).distance, DistanceOption.any);
        expect(cond(h).budget, BudgetOption.max10000); // untouched
        expect(find.byType(InputChip), findsNWidgets(3));

        // Home's own empty state has a 초기화 too; this is the chip row's.
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('applied-filters')),
            matching: find.text('초기화'),
          ),
        );
        await tester.pumpAndSettle();
        expect(cond(h), Conditions.defaults);
        expect(find.byKey(const ValueKey('applied-filters')), findsNothing);
      },
    );

    testWidgets(
      'chips and the panel agree: removing a chip un-selects it in the open panel',
      (tester) async {
        // tall window: the chip row sits below the open panel
        final h = await open(tester, size: const Size(1440, 1700));
        await tester.tap(find.text('조건').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('도보 5분').last);
        await tester.pumpAndSettle();
        expect(find.byTooltip('도보 5분 해제'), findsOneWidget);
        await tester.tap(find.byTooltip('도보 5분 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).distance, DistanceOption.any);
      },
    );

    testWidgets(
      'open-now and untried-first appear as chips and reset to their defaults',
      (tester) async {
        final h = await open(tester);
        h.container
            .read(conditionsProvider.notifier)
            .update((c) => c.copyWith(openNowOnly: true, untriedFirst: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('지금 주문 가능 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).openNowOnly, isFalse);
        await tester.tap(find.byTooltip('안 가 본 식당 먼저 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).untriedFirst, isFalse);
      },
    );
  });

  group('phones keep the sheet', () {
    testWidgets(
      'no inline panel and no chip row at 390px; the pill opens the sheet',
      (tester) async {
        final h = await open(tester, size: const Size(390, 844));
        h.container
            .read(conditionsProvider.notifier)
            .update((c) => c.copyWith(budget: BudgetOption.max10000));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('applied-filters')), findsNothing);
        expect(find.byType(AdvancedFilterPanel), findsNothing);
      },
    );
  });
}
