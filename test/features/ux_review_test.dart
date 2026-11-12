import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/campus_points.dart';
import 'package:meogeobojo/features/conditions/providers/conditions_providers.dart';
import 'package:meogeobojo/features/home/providers/home_providers.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/map/screens/map_screen.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/utils/url_sync.dart';
import 'package:meogeobojo/features/origin/models/origin.dart';
import 'package:meogeobojo/features/origin/widgets/origin_row.dart';
import 'package:meogeobojo/features/origin/providers/origin_providers.dart';
import 'package:meogeobojo/features/origin/screens/pin_picker_screen.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/restaurants/utils/restaurant_link.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

NavigatorState _nav(WidgetTester tester) =>
    Navigator.of(tester.element(find.byType(AppShell, skipOffstage: false)));

void main() {
  group('출발점 (2)', () {
    testWidgets('changing it from 정문 to 향설생활관 2관 updates Home and the '
        'open details together', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const AppShell());
      final place = fakeRestaurant('1', name: '국수집', distance: 120);
      openRestaurantDetail(tester.element(find.byType(AppShell)), place);
      await tester.pumpAndSettle();
      expect(find.textContaining('정문에서 예상 도보 약'), findsOneWidget);
      expect(find.textContaining('직선거리로 계산한 예상 시간이며'), findsOneWidget);

      await h.container
          .read(originSelectionProvider.notifier)
          .select('dorm_hyangseol_2');
      await tester.pumpAndSettle();
      expect(find.textContaining('향설생활관 2관에서 예상 도보 약'), findsOneWidget);
      // Home under it moved too.
      _nav(tester).pop();
      await tester.pumpAndSettle();
      expect(find.text('향설생활관 2관 기준'), findsOneWidget);
    });

    test('one distance rule: straight-line metres from the same origin', () {
      final o = Origin.fromPoint(campusPointsFor(kDefaultUniversityId).first);
      final r = fakeRestaurant('1', distance: 257);
      final m = metersFromOrigin(o, r)!;
      expect(m, closeTo(257, 2));
      expect(metersFromOrigin(null, r), isNull); // origin still loading
    });
  });

  testWidgets('each start point previews its own nearest match, even one '
      'outside the current distance limit', (tester) async {
    final back = campusPointsFor(kDefaultUniversityId)
        .firstWhere((p) => p.id == 'gate_back');
    final h = await buildHarness(
      restaurants: FakeRestaurantRepository(
        items: [
          Restaurant(
            kakaoId: 'b1',
            name: '후문식당',
            categoryName: '음식점 > 한식',
            categoryGroupCode: 'FD6',
            address: '',
            roadAddress: '',
            phone: '',
            latitude: back.latitude,
            longitude: back.longitude,
            distanceMeters: 0,
            placeUrl: null,
          ),
        ],
      ),
    );
    await pumpApp(tester, h, home: const AppShell());
    // 도보 5분 from 정문 leaves nothing; from 후문 the place is right there.
    h.container
        .read(conditionsProvider.notifier)
        .update((c) => c.copyWith(distance: DistanceOption.walk5));
    await tester.pumpAndSettle();
    expect(h.container.read(homePoolRankedProvider).value, isEmpty);
    await tester.tap(find.text('정문 기준'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is OriginRow && w.origin.id == 'gate_back',
        ),
        matching: find.text('가장 가까운 곳: 후문식당 · 예상 도보 약 1분'),
      ),
      findsOneWidget,
    );
  });

  group('기숙사 7곳 (3)', () {
    test('seven halls, each with a source and the day it was checked', () {
      final halls = [
        for (final p in campusPointsFor(kDefaultUniversityId))
          if (p.kind == CampusPointKind.dorm) p,
      ];
      expect(halls.map((p) => p.name), [
        '향설생활관 1관',
        '향설생활관 2관',
        '향설생활관 3관',
        '글로벌 빌리지',
        '학성사 1관',
        '학성사 2관',
        '학성사 3관',
      ]);
      for (final p in campusPointsFor(kDefaultUniversityId)) {
        expect(p.source, isNotEmpty, reason: p.name);
        expect(p.checkedOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      }
      // The old single 기숙사 point is gone (never mapped to one hall).
      expect(
        campusPointsFor(kDefaultUniversityId).map((p) => p.id),
        isNot(contains(kLegacyDormPointId)),
      );
    });

    testWidgets('a saved 기숙사 asks for the hall and says what is used '
        'meanwhile', (tester) async {
      final h = await buildHarness(
        storage: const {
          'app_language': 'ko',
          'origin_selected_id': kLegacyDormPointId,
        },
      );
      await pumpApp(tester, h, home: const AppShell());
      expect(find.textContaining('기숙사 출발점이 생활관별로 나뉘었어요'), findsOneWidget);
      expect(find.text('다시 고르기 전까지 정문 기준으로 계산해요.'), findsOneWidget);
      expect(h.container.read(originProvider)!.id, 'gate_front');

      await tester.tap(find.text('출발점 다시 고르기'));
      await tester.pumpAndSettle();
      final hall = find.text('향설생활관 1관');
      await tester.scrollUntilVisible(
        hall,
        150,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(hall);
      await tester.pumpAndSettle();
      await tester.tap(hall);
      await tester.pumpAndSettle();
      expect(h.container.read(originProvider)!.id, 'dorm_hyangseol_1');
      expect(find.textContaining('기숙사 출발점이 생활관별로'), findsNothing);
    });
  });

  group('직접 지정한 위치 (4)', () {
    test('a new place starts on the whole campus; an edit at its own zoom', () {
      expect(pinPickerInitialLevel(), 15);
      expect(pinPickerInitialLevel(editingZoom: 18), 18);
    });

    testWidgets('editing keeps the pin (and the selection); the zoom is kept', (
      tester,
    ) async {
      final h = await buildHarness();
      await h.container.read(selectedUniversityProvider.future);
      final pins = h.container.read(savedPinsProvider.notifier);
      final pin = await pins.add(
        universityId: kDefaultUniversityId,
        name: '직접 지정한 위치',
        latitude: 36.77,
        longitude: 126.93,
        zoomLevel: 17,
      );
      await h.container.read(originSelectionProvider.notifier).select(pin.id);
      await pins.edit(
        pin.id,
        name: '동아리방 앞',
        latitude: 36.771,
        longitude: 126.931,
      );
      final saved = h.container.read(savedPinsProvider).single;
      expect(saved.id, pin.id);
      expect(saved.name, '동아리방 앞');
      expect(saved.zoomLevel, 17);
      expect(SavedPin.fromJson(saved.toJson())!.zoomLevel, 17);
      expect(h.container.read(originProvider)!.name, '동아리방 앞');
    });
  });

  group('지도 카드 (7)', () {
    testWidgets('name, menu price, travel, and both actions at 320 px', (
      tester,
    ) async {
      final h = await buildHarness();
      final item = RankedRestaurant(
        restaurant: fakeRestaurant('1', name: '아주긴이름의국수집'),
        meters: 257,
        walkMinutes: 3,
        insight: const RestaurantInsight(minPriceKrw: 7000),
        reason: const RecommendReason(ReasonKind.closest),
      );
      await pumpApp(
        tester,
        h,
        size: const Size(320, 568),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: MapPlaceCard(item: item, onClose: () {}),
            ),
          ),
        ),
      );
      expect(find.text('아주긴이름의국수집1'), findsOneWidget);
      expect(find.text('7,000~'), findsOneWidget);
      expect(find.textContaining('직선 약 260m'), findsOneWidget);
      expect(find.textContaining('예상 도보 약 3분'), findsOneWidget);
      for (final label in ['상세 보기', '길찾기']) {
        final box = tester.getRect(find.text(label));
        expect(box.right, lessThanOrEqualTo(320), reason: label);
        expect(box.bottom, lessThanOrEqualTo(568), reason: label);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('식당 상세 주소 (11)', () {
    test('the link names the place only (never the sender\'s start point)', () {
      final r = fakeRestaurant('123', name: '국수집');
      final path = restaurantPath(r);
      expect(path, startsWith('/restaurant/123?name='));
      expect(path.contains('lat') || path.contains('origin'), isFalse);
      expect(restaurantLinkOf(path), (id: '123', name: '국수집123'));
      expect(restaurantLinkOf('/map'), isNull);
      expect(restaurantLinkOf('/restaurant/abc'), isNull);
      expect(restaurantShareUrl(r), startsWith('$kSiteUrl#/restaurant/123'));
    });

    Future<(Harness, List<(String, bool)>)> open(
      WidgetTester tester, {
      FakeRestaurantOverrideRepository? overrides,
    }) async {
      final calls = <(String, bool)>[];
      final h = await buildHarness(
        overridesRepo: overrides,
        extraOverrides: [
          urlSyncEnabledProvider.overrideWithValue(true),
          urlReporterProvider.overrideWithValue(
            (uri, {required replace}) async => calls.add((uri.path, replace)),
          ),
          urlHistoryModeProvider.overrideWithValue(() async {}),
        ],
      );
      await pumpApp(tester, h, home: const AppShell());
      calls.clear();
      return (h, calls);
    }

    testWidgets('opening a place puts its own address in the bar; the app\'s '
        'back button takes it out again', (tester) async {
      final (_, calls) = await open(tester);
      openRestaurantDetail(
        tester.element(find.byType(AppShell)),
        fakeRestaurant('1', name: '국수집', distance: 120),
      );
      await tester.pumpAndSettle();
      expect(calls, [('/restaurant/1', false)]);
      _nav(tester).pop();
      await tester.pumpAndSettle();
      expect(calls.last, ('/home', true));
    });

    testWidgets('opened cold on a shared link (or refreshed on a detail), '
        'the place opens over Home', (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.defaultRouteNameTestValue = '/restaurant/1?name=x';
      addTearDown(dispatcher.clearDefaultRouteNameTestValue);
      final calls = <(String, bool)>[];
      final h = await buildHarness(
        extraOverrides: [
          urlSyncEnabledProvider.overrideWithValue(true),
          // Like the browser: reporting a path changes the address bar.
          urlReporterProvider.overrideWithValue((
            uri, {
            required replace,
          }) async {
            calls.add((uri.path, replace));
            dispatcher.defaultRouteNameTestValue = uri.toString();
          }),
          urlHistoryModeProvider.overrideWithValue(() async {}),
        ],
      );
      await pumpApp(tester, h, home: const AppShell());
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      expect(calls, [('/home', true), ('/restaurant/1', false)]);
      _nav(tester).pop(); // Back lands on Home
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantDetailScreen), findsNothing);
    });

    testWidgets('a pasted link opens the same place, signed out', (
      tester,
    ) async {
      final (_, calls) = await open(tester);
      _nav(tester).pushNamed('/restaurant/1?name=%EA%B5%AD%EC%88%98%EC%A7%911');
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      expect(find.text('국수집1'), findsWidgets);
      expect(calls, isEmpty, reason: 'the browser already shows it');
    });

    testWidgets('a hidden or removed place says so instead of an error', (
      tester,
    ) async {
      await open(
        tester,
        overrides: FakeRestaurantOverrideRepository(
          overrides: {
            '9': const RestaurantOverride(kakaoId: '9', visibility: 'hidden'),
          },
        ),
      );
      _nav(tester).pushNamed('/restaurant/9');
      await tester.pumpAndSettle();
      expect(find.text('이 식당 정보를 볼 수 없어요'), findsOneWidget);
      expect(find.text('식당이 비공개로 바뀌었어요.'), findsOneWidget);
      _nav(tester).pushNamed('/restaurant/424242?name=없는집');
      await tester.pumpAndSettle();
      expect(find.text('식당이 삭제되었거나 더 이상 찾을 수 없어요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
