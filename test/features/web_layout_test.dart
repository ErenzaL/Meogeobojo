import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/home/widgets/home_top_bar.dart';
import 'package:meogeobojo/features/home/widgets/home_welcome.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
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

Future<void> open(
  WidgetTester tester,
  int tab,
  Size size, {
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
      items: [spot('가까운집', 0.0005), spot('중간집', 0.0015)],
    ),
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  h.container.read(shellTabProvider.notifier).select(tab);
  await tester.pumpAndSettle();
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
  group('every page fits every width (no overflow, no exception)', () {
    for (final size in sizes) {
      for (final t in tabs.entries) {
        for (final signedIn in const [true, false]) {
          testWidgets(
            '${t.key} ${size.width.toInt()}px ${signedIn ? 'signed in' : 'guest'}',
            (tester) async {
              await open(tester, t.value, size, signedIn: signedIn);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('desktop structure appears on desktop only', () {
    testWidgets(
      '밥수다: the coming-soon message is centred on desktop and phone',
      (tester) async {
        for (final size in const [Size(1440, 900), Size(390, 844)]) {
          await open(tester, ShellTabs.community, size);
          final title = find.text('밥수다는 준비 중이에요');
          expect(title, findsOneWidget);
          expect(
            tester.getCenter(title).dx,
            closeTo(size.width / 2, 2),
            reason: '${size.width}px',
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('MY: account left, activity right on desktop', (tester) async {
      await open(tester, ShellTabs.profile, const Size(1440, 900));
      expect(find.byKey(const ValueKey('my-desktop')), findsOneWidget);
      await open(tester, ShellTabs.profile, const Size(390, 844));
      expect(find.byKey(const ValueKey('my-desktop')), findsNothing);
    });

    testWidgets(
      'Home: the desktop welcome section carries the university selector',
      (tester) async {
        await open(tester, ShellTabs.home, const Size(1440, 900));
        expect(find.byType(HomeWelcome), findsOneWidget);
        expect(find.byType(UniversityButton), findsOneWidget);
      },
    );

    testWidgets(
      'Home: a phone keeps its own top bar, not the welcome section',
      (tester) async {
        await open(tester, ShellTabs.home, const Size(390, 844));
        expect(find.byType(HomeWelcome), findsNothing);
        expect(find.byType(UniversityButton), findsOneWidget);
      },
    );
  });
}
