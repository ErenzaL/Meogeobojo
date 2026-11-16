import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/analytics/app_events.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/search/screens/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  group('사용 지표 events', () {
    testWidgets('a finished search records its words', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const SearchScreen());
      await tester.tap(find.text('국밥'));
      await tester.pumpAndSettle();
      expect(h.events, ['search:국밥']);
    });

    testWidgets('a restaurant page records a view, and 길찾기 a directions click', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(
        tester,
        h,
        home: RestaurantDetailScreen(restaurant: fakeRestaurant('a')),
      );
      expect(h.events, ['restaurant_view:a']);
      final directions = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('길찾기') ?? false),
      );
      await tester.ensureVisible(directions);
      await tester.tap(directions);
      await tester.pumpAndSettle();
      expect(h.events, ['restaurant_view:a', 'directions_click:a']);
    });

    test('the device id is a random UUID, created once and kept', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final id = analyticsClientId(prefs);
      expect(
        id,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(analyticsClientId(prefs), id);
      expect(prefs.getString(analyticsClientIdKey), id);
    });

    test('sending never throws, even with no backend', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(() => sendAppEvent(() => prefs, AppEvent.appOpen), returnsNormally);
      expect(
        () => sendAppEvent(() => throw StateError('no prefs'), AppEvent.appOpen),
        returnsNormally,
      );
    });
  });
}
