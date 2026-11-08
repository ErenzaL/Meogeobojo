import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/app.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/favorites/providers/favorites_providers.dart';
import 'package:meogeobojo/features/preferences/providers/preferences_providers.dart';
import 'package:meogeobojo/features/restaurants/providers/restaurant_providers.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class Harness {
  Harness({
    required this.container,
    required this.auth,
    required this.profiles,
    required this.prefs,
    required this.restaurants,
    required this.favorites,
    required this.sp,
  });

  final ProviderContainer container;
  final FakeAuthGateway auth;
  final FakeProfileRepository profiles;
  final FakePreferencesRepository prefs;
  final FakeRestaurantRepository restaurants;
  final FakeFavoritesRepository favorites;
  final SharedPreferences sp;
}

/// Builds a fully faked dependency graph. Nothing touches Supabase, Kakao or
/// the network.
Future<Harness> buildHarness({
  Map<String, Object> storage = const {'app_language': 'ko'},
  FakeAuthGateway? auth,
  FakeProfileRepository? profiles,
  FakePreferencesRepository? prefs,
  FakeRestaurantRepository? restaurants,
  FakeFavoritesRepository? favorites,
  List<Locale> deviceLocales = const [Locale('ko')],
  List<Override> extraOverrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(storage);
  final sp = await SharedPreferences.getInstance();
  final a = auth ?? FakeAuthGateway();
  final p = profiles ?? FakeProfileRepository();
  final pr = prefs ?? FakePreferencesRepository();
  final r =
      restaurants ??
      FakeRestaurantRepository(
        items: [
          fakeRestaurant('1', name: '국수집', distance: 120),
          fakeRestaurant('2', name: '라멘', category: '음식점 > 일식', distance: 700),
          fakeRestaurant('3', name: '멀리있는집', distance: 3000),
        ],
      );
  final fav = favorites ?? FakeFavoritesRepository();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      deviceLocalesProvider.overrideWithValue(deviceLocales),
      universityRepositoryProvider.overrideWithValue(
        FakeUniversityRepository(kVerifiedUniversities),
      ),
      restaurantRepositoryProvider.overrideWithValue(r),
      authGatewayProvider.overrideWithValue(a),
      profileRepositoryProvider.overrideWithValue(p),
      preferencesRepositoryProvider.overrideWithValue(pr),
      favoritesRepositoryProvider.overrideWithValue(fav),
      kakaoCallbackGraceProvider.overrideWithValue(
        const Duration(milliseconds: 50),
      ),
      ...extraOverrides,
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  // The app's AuthFlowHost watches the controller from the first frame, so it
  // is always alive (and subscribed to auth events) before anything happens.
  container.listen(authControllerProvider, (_, _) {});
  return Harness(
    container: container,
    auth: a,
    profiles: p,
    prefs: pr,
    restaurants: r,
    favorites: fav,
    sp: sp,
  );
}

void setPhoneSize(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Mounts the real app (theme, localization, language switching) with [home].
Future<void> pumpApp(
  WidgetTester tester,
  Harness h, {
  Widget home = const SplashGate(duration: Duration(milliseconds: 10)),
  Size size = const Size(390, 844),
}) async {
  setPhoneSize(tester, size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MeogeobojoApp(home: home),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

/// Lets queued microtasks / provider futures run.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}
