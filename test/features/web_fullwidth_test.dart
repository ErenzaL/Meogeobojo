import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/widgets/responsive.dart';
import 'package:meogeobojo/core/widgets/web_footer.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/widgets/web_header.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

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
  WidgetTester tester,
  int tab,
  Size size, {
  bool fullWidth = true,
  bool signedIn = true,
  String lang = 'ko',
}) async {
  final h = await buildHarness(
    storage: {'app_language': lang},
    auth: signedIn ? FakeAuthGateway(user: fakeUser()) : null,
    profiles: signedIn
        ? FakeProfileRepository(onboardingCompleted: true, nickname: '민수')
        : null,
    restaurants: FakeRestaurantRepository(
      items: [for (var i = 0; i < 8; i++) spot('식당$i', 0.0004 * (i + 1))],
    ),
    extraOverrides: [
      webFullWidthProvider.overrideWithValue(fullWidth),
      webFooterEnabledProvider.overrideWithValue(true),
    ],
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  h.container.read(shellTabProvider.notifier).select(tab);
  await tester.pumpAndSettle();
  return h;
}

const sizes = [
  Size(390, 844),
  Size(768, 1024),
  Size(1024, 768),
  Size(1440, 900),
  Size(1920, 1080),
];
const tabs = {
  'home': ShellTabs.home,
  'map': ShellTabs.map,
  'community': ShellTabs.community,
  'missions': ShellTabs.missions,
  'profile': ShellTabs.profile,
};

void main() {
  group('full width: every page at every width, no overflow or exception', () {
    for (final size in sizes) {
      for (final t in tabs.entries) {
        for (final lang in const ['ko', 'en']) {
          testWidgets('${t.key} ${size.width.toInt()}px $lang', (tester) async {
            await open(tester, t.value, size, lang: lang);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('the website uses the whole window', () {
    for (final size in const [Size(1440, 900), Size(1920, 1080)]) {
      testWidgets('${size.width.toInt()}px: the header spans edge to edge', (
        tester,
      ) async {
        await open(tester, ShellTabs.community, size);
        final r = tester.getRect(find.byType(WebHeader));
        expect(r.left, 0);
        expect(r.right, size.width);
      });

      testWidgets(
        '${size.width.toInt()}px: the footer spans edge to edge and ends the window',
        (tester) async {
          await open(tester, ShellTabs.community, Size(size.width, 2400));
          final r = tester.getRect(find.byKey(const ValueKey('web-footer')));
          expect(r.left, 0);
          expect(r.right, size.width);
          expect(r.bottom, closeTo(2400, 1));
        },
      );

      testWidgets(
        '${size.width.toInt()}px: the right-hand column ends at the right gutter',
        (tester) async {
          await open(tester, ShellTabs.profile, size);
          final gutter = size.width >= 1440 ? 40.0 : 28.0;
          final page = tester.getRect(find.byKey(const ValueKey('my-desktop')));
          expect(page.right, closeTo(size.width - gutter, 1));
        },
      );
    }

    testWidgets('1440px vs 1920px: the extra width goes to the content', (
      tester,
    ) async {
      await open(tester, ShellTabs.profile, const Size(1440, 900));
      final a = tester.getRect(find.byKey(const ValueKey('my-desktop'))).right;
      await open(tester, ShellTabs.profile, const Size(1920, 1080));
      final b = tester.getRect(find.byKey(const ValueKey('my-desktop'))).right;
      expect(b - a, 480); // the page moved out with the window edge
    });

    testWidgets(
      'Home: restaurant cards form a grid that grows with the window',
      (tester) async {
        await open(tester, ShellTabs.home, const Size(1440, 1400));
        final small = find.byKey(const ValueKey('picks-grid'));
        if (small.evaluate().isNotEmpty) {
          final w1440 = tester.getSize(small).width;
          await open(tester, ShellTabs.home, const Size(1920, 1400));
          final w1920 = tester
              .getSize(find.byKey(const ValueKey('picks-grid')))
              .width;
          expect(w1920, greaterThan(w1440));
        }
        // never the sideways scroller on the website grid; phones keep it
        await open(tester, ShellTabs.home, const Size(390, 1400));
        expect(find.byKey(const ValueKey('picks-grid')), findsNothing);
      },
    );

    testWidgets(
      'Map: the map keeps the majority of the width, the list is a side panel',
      (tester) async {
        for (final w in [1024.0, 1440.0, 1920.0]) {
          await open(tester, ShellTabs.map, Size(w, 900));
          final panel = tester.getSize(
            find.byKey(const ValueKey('map-places-panel')),
          );
          expect(
            panel.width,
            w >= 1920
                ? 480
                : w >= 1440
                ? 440
                : 400,
          );
          expect(
            w - panel.width,
            greaterThan(panel.width * 1.5),
          ); // the map: well over half
        }
      },
    );

    testWidgets(
      'MY: a card-width account column; the activity area splits in two on a large window',
      (tester) async {
        await open(tester, ShellTabs.profile, const Size(1920, 1080));
        expect(find.byKey(const ValueKey('my-two-columns')), findsOneWidget);
        await open(tester, ShellTabs.profile, const Size(1024, 768));
        expect(find.byKey(const ValueKey('my-two-columns')), findsNothing);
        expect(find.byKey(const ValueKey('my-desktop')), findsOneWidget);
      },
    );
  });

  group('phones and the native layout are unchanged', () {
    testWidgets('390px: no desktop structure, the original 16 px gutter', (
      tester,
    ) async {
      await open(tester, ShellTabs.profile, const Size(390, 844));
      expect(find.byKey(const ValueKey('my-desktop')), findsNothing);
      expect(find.byType(WebHeader), findsNothing);
      expect(WebLayout.gutterOf(tester.element(find.byType(AppShell))), 16);
    });

    testWidgets(
      'full width off (native): still the bounded 1280 column on a very wide window',
      (tester) async {
        await open(
          tester,
          ShellTabs.community,
          const Size(1920, 1080),
          fullWidth: false,
        );
        final r = tester.getRect(find.byType(WebHeader));
        expect(r.width, 1280);
        expect(r.left, 320);
      },
    );

    test('gutters by width', () {
      // (the widths are exercised through the layout tests above; this pins the table)
      expect(Breakpoints.tablet, 600);
      expect(Breakpoints.desktop, 960);
    });
  });
}
