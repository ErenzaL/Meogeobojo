import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/widgets/responsive.dart';
import 'package:meogeobojo/core/widgets/web_footer.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Restaurant _spot(int i) => Restaurant(
  kakaoId: 'r$i',
  name: '식당$i',
  categoryName: '음식점 > 한식',
  categoryGroupCode: 'FD6',
  address: '',
  roadAddress: '',
  phone: '',
  latitude: 36.7680 + 0.0004 * (i + 1),
  longitude: 126.9305,
  distanceMeters: 0,
  placeUrl: null,
);

/// "오늘의 추천 받기" shows the pick where it is; it must not scroll the page,
/// on phones and on the website's wider layouts alike.
void main() {
  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  final cases = <(String, Size, bool)>[
    ('phone', const Size(390, 844), false),
    ('small phone', const Size(360, 640), false),
    ('web 768', const Size(768, 700), true),
    ('web 1024', const Size(1024, 700), true),
    ('web 1280', const Size(1280, 700), true),
    ('web 1440', const Size(1440, 700), true),
    ('web 1920', const Size(1920, 800), true),
  ];

  for (final (name, size, web) in cases) {
    for (final scrolled in [0.0, 120.0]) {
      testWidgets('$name: tapping 오늘의 추천 받기 leaves the scroll position '
          'alone (page scrolled ${scrolled.toInt()})', (tester) async {
        final h = await buildHarness(
          recsRequested: false,
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(
            onboardingCompleted: true,
            nickname: '민수',
          ),
          restaurants: FakeRestaurantRepository(
            items: [for (var i = 0; i < 8; i++) _spot(i)],
          ),
          extraOverrides: [
            webFullWidthProvider.overrideWithValue(web),
            webFooterEnabledProvider.overrideWithValue(web),
          ],
        );
        await pumpApp(tester, h, home: const AppShell(), size: size);
        await tester.pumpAndSettle();

        final button = find.text('오늘의 추천 받기');
        expect(button, findsOneWidget);
        if (scrolled > 0) {
          await tester.drag(
            find.byType(Scrollable).first,
            Offset(0, -scrolled),
          );
          await tester.pumpAndSettle();
        }
        final before = offset(tester);

        await tester.tap(button);
        await tester.pump();
        expect(offset(tester), before, reason: 'right after the tap');
        await tester.pumpAndSettle();
        expect(offset(tester), before, reason: 'after the result is shown');
        // and the result really did appear
        expect(find.byType(RichText), findsWidgets);
      });
    }
  }
}
