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
  latitude: 36.7680 + dLat,
  longitude: 126.9305,
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
      await tester.tap(find.text('혼자').last);
      await tester.pumpAndSettle();
      expect(cond(h).party, CompanionType.solo);
      await tester.tap(find.text('조용한 대화').last);
      await tester.pumpAndSettle();
      expect(cond(h).needs, {Need.quietTalk});
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
                party: () => CompanionType.solo,
                needs: {Need.quietTalk, Need.quickMeal},
                sort: SortMode.distance,
              ),
            );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('applied-filters')), findsOneWidget);
        expect(find.byType(InputChip), findsNWidgets(5));

        await tester.tap(find.byTooltip('혼자 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).party, isNull);
        expect(cond(h).budget, BudgetOption.max10000); // untouched
        expect(cond(h).needs, {Need.quietTalk, Need.quickMeal});

        await tester.tap(find.byTooltip('조용한 대화 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).needs, {Need.quickMeal});
        expect(find.byType(InputChip), findsNWidgets(3));

        await tester.tap(find.text('모두 풀기').last);
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
        await tester.tap(find.text('혼자').last);
        await tester.pumpAndSettle();
        expect(find.byTooltip('혼자 해제'), findsOneWidget);
        await tester.tap(find.byTooltip('혼자 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).party, isNull);
      },
    );

    testWidgets(
      'open-now off and untried-first appear as chips and reset to their defaults',
      (tester) async {
        final h = await open(tester);
        h.container
            .read(conditionsProvider.notifier)
            .update((c) => c.copyWith(openNowOnly: false, untriedFirst: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('주문 마감 후에도 표시 해제'));
        await tester.pumpAndSettle();
        expect(cond(h).openNowOnly, isTrue);
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
