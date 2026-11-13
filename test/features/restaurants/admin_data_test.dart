import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/home/widgets/restaurant_art.dart';
import 'package:meogeobojo/features/recommendation/providers/ranking_providers.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/restaurants/providers/restaurant_providers.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/restaurants/widgets/restaurant_photo_placeholder.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Restaurant spot(String id, String name, double dLat) => Restaurant(
  kakaoId: id,
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

void main() {
  group('RestaurantOverride parsing', () {
    test('maps a database row, including HH:MM:SS last order', () {
      final o = RestaurantOverride.fromJson({
        'kakao_place_id': 'k1',
        'visibility': 'published',
        'description': '  맛집  ',
        'price_min_krw': 9000,
        'last_order_time': '21:30:00',
        'image_url': 'https://x/y.png',
      })!;
      expect(o.description, '맛집');
      expect(o.insight.minPriceKrw, 9000);
      expect(o.insight.lastOrderMinutes, 21 * 60 + 30);
      expect(o.isHidden, isFalse);
    });
    test(
      'hidden / archived are hidden; rows without a kakao id are ignored',
      () {
        expect(
          RestaurantOverride.fromJson({
            'kakao_place_id': 'k',
            'visibility': 'hidden',
          })!.isHidden,
          isTrue,
        );
        expect(
          RestaurantOverride.fromJson({
            'kakao_place_id': 'k',
            'visibility': 'archived',
          })!.isHidden,
          isTrue,
        );
        expect(RestaurantOverride.fromJson({'name_ko': 'hand-made'}), isNull);
      },
    );
    test('menu rows need a name', () {
      expect(RestaurantMenuItem.fromJson({'name_ko': ' '}), isNull);
      final m = RestaurantMenuItem.fromJson({
        'name_ko': '비빔밥',
        'price_krw': 9000,
        'available': false,
      })!;
      expect(m.available, isFalse);
      expect(m.priceKrw, 9000);
    });
  });

  group('photos and richer menus', () {
    test('archived menus are dropped; recommended, category and https images parse', () {
      expect(
        RestaurantMenuItem.fromJson({'name_ko': '옛 메뉴', 'status': 'archived'}),
        isNull,
      );
      final m = RestaurantMenuItem.fromJson({
        'name_ko': '제육 정식',
        'recommended': true,
        'category': '식사',
        'status': 'active',
        'image_url': 'https://x.supabase.co/a.webp',
      })!;
      expect(m.recommended, isTrue);
      expect(m.category, '식사');
      expect(m.imageUrl, 'https://x.supabase.co/a.webp');
      // an insecure or blank image link is ignored rather than loaded
      expect(
        RestaurantMenuItem.fromJson({
          'name_ko': 'a',
          'image_url': 'http://x/a.png',
        })!.imageUrl,
        isNull,
      );
      expect(
        RestaurantMenuItem.fromJson({'name_ko': 'a', 'image_url': ' '})!
            .imageUrl,
        isNull,
      );
    });

    test('photo rows need an https url; kind and caption are read', () {
      final p = RestaurantPhoto.fromJson({
        'url': 'https://x/c.webp',
        'kind': 'cover',
        'caption': ' 입구 ',
        'sort_order': 0,
      })!;
      expect(p.isCover, isTrue);
      expect(p.caption, '입구');
      expect(
        RestaurantPhoto.fromJson({'url': 'http://x/c.webp', 'kind': 'gallery'}),
        isNull,
      );
      expect(RestaurantPhoto.fromJson({'kind': 'gallery'}), isNull);
      expect(
        RestaurantPhoto.fromJson({
          'url': 'https://x/g.webp',
          'kind': 'gallery',
          'caption': '',
        })!.caption,
        isNull,
      );
    });

    testWidgets(
      'the detail page shows the uploaded gallery and a recommended menu',
      (tester) async {
        final repo = FakeRestaurantOverrideRepository(
          photoItems: {
            'a': const [
              RestaurantPhoto(url: 'https://x/cover.webp', isCover: true),
              RestaurantPhoto(
                url: 'https://x/g1.webp',
                isCover: false,
                caption: '내부',
              ),
            ],
          },
          menuItems: {
            'a': const [
              RestaurantMenuItem(
                name: '잔치국수',
                priceKrw: 6000,
                recommended: true,
                imageUrl: 'https://x/m.webp',
              ),
            ],
          },
        );
        final h = await buildHarness(
          restaurants: FakeRestaurantRepository(
            items: [spot('a', '국수집', 0.0005)],
          ),
          overridesRepo: repo,
        );
        await pumpApp(
          tester,
          h,
          home: RestaurantDetailScreen(restaurant: spot('a', '국수집', 0.0005)),
        );
        await tester.pumpAndSettle();
        expect(find.text('사진 2장'), findsOneWidget); // the gallery tag
        expect(find.bySemanticsLabel('내부'), findsOneWidget);
        expect(find.text('추천'), findsOneWidget);
        expect(find.text('잔치국수'), findsOneWidget);
        // a broken image link falls back quietly: no exception
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('no uploads: no gallery heading and no invented photo', (
      tester,
    ) async {
      final h = await buildHarness(
        restaurants: FakeRestaurantRepository(
          items: [spot('a', '국수집', 0.0005)],
        ),
        overridesRepo: FakeRestaurantOverrideRepository(),
      );
      await pumpApp(
        tester,
        h,
        home: RestaurantDetailScreen(restaurant: spot('a', '국수집', 0.0005)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'^사진 \d+장$')), findsNothing);
      // the category illustration (as on Home), not a photo
      expect(find.byType(RestaurantArt), findsOneWidget);
      expect(find.byType(RestaurantPhotoPlaceholder), findsNothing);
    });
  });

  testWidgets('coming back to the app re-reads what admins published', (
    tester,
  ) async {
    final repo = FakeRestaurantOverrideRepository(
      overrides: {
        'a': const RestaurantOverride(
          kakaoId: 'a',
          visibility: 'published',
          description: '옛 설명',
        ),
      },
    );
    final h = await buildHarness(
      restaurants: FakeRestaurantRepository(items: [spot('a', '국수집', 0.0005)]),
      overridesRepo: repo,
    );
    await pumpApp(tester, h, home: const AppShell());
    await h.container.read(restaurantOverridesProvider.future);
    await tester.pumpAndSettle();
    final before = repo.forPlacesCalls;
    repo.overrides = {
      'a': const RestaurantOverride(
        kakaoId: 'a',
        visibility:
            'hidden', // an admin hides it while the app is in the background
      ),
    };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await h.container.read(restaurantOverridesProvider.future);
    expect(repo.forPlacesCalls, greaterThan(before));
    expect(h.container.read(hiddenPlaceIdsProvider), contains('a'));
  });

  testWidgets('detail shows the description and menus an admin entered', (
    tester,
  ) async {
    final repo = FakeRestaurantOverrideRepository(
      overrides: {
        'a': const RestaurantOverride(
          kakaoId: 'a',
          visibility: 'published',
          description: '30년 전통 국수집',
        ),
      },
      menuItems: {
        'a': const [
          RestaurantMenuItem(
            name: '잔치국수',
            priceKrw: 6000,
            representative: true,
          ),
          RestaurantMenuItem(name: '비빔국수', priceKrw: 7000, available: false),
        ],
      },
    );
    final h = await buildHarness(
      restaurants: FakeRestaurantRepository(items: [spot('a', '국수집', 0.0005)]),
      overridesRepo: repo,
    );
    await h.container.read(restaurantOverridesProvider.future);
    await pumpApp(
      tester,
      h,
      home: RestaurantDetailScreen(restaurant: spot('a', '국수집', 0.0005)),
    );
    expect(find.text('30년 전통 국수집'), findsOneWidget);
    expect(find.text('잔치국수'), findsOneWidget);
    expect(find.text('6,000원'), findsOneWidget);
    expect(find.text('품절'), findsOneWidget);
    // Data was provided, so the "not provided" notice is gone.
    expect(find.textContaining('아직 제공되지 않아요'), findsNothing);
  });

  testWidgets('an admin edit appears in the app after a refresh', (
    tester,
  ) async {
    final repo = FakeRestaurantOverrideRepository(
      overrides: {
        'a': const RestaurantOverride(
          kakaoId: 'a',
          visibility: 'published',
          description: '옛 설명',
        ),
      },
    );
    final h = await buildHarness(
      restaurants: FakeRestaurantRepository(items: [spot('a', '국수집', 0.0005)]),
      overridesRepo: repo,
    );
    await pumpApp(
      tester,
      h,
      home: RestaurantDetailScreen(restaurant: spot('a', '국수집', 0.0005)),
    );
    await h.container.read(restaurantOverridesProvider.future);
    await tester.pumpAndSettle();
    expect(find.text('옛 설명'), findsOneWidget);

    // The dashboard saves a new description; the app refetches.
    repo.overrides = {
      'a': const RestaurantOverride(
        kakaoId: 'a',
        visibility: 'published',
        description: '새 설명',
      ),
    };
    h.container.invalidate(restaurantOverridesProvider);
    await h.container.read(restaurantOverridesProvider.future);
    await tester.pumpAndSettle();
    expect(find.text('새 설명'), findsOneWidget);
    expect(find.text('옛 설명'), findsNothing);
  });

  testWidgets(
    'Home: an admin-hidden place disappears and prices / hours show',
    (tester) async {
      final repo = FakeRestaurantOverrideRepository(
        overrides: {
          'near': const RestaurantOverride(
            kakaoId: 'near',
            visibility: 'hidden',
          ),
          'mid': const RestaurantOverride(
            kakaoId: 'mid',
            visibility: 'published',
            insight: RestaurantInsight(
              minPriceKrw: 9000,
              lastOrderMinutes: 21 * 60 + 30,
            ),
          ),
        },
      );
      final h = await buildHarness(
        restaurants: FakeRestaurantRepository(
          items: [
            spot('near', '숨긴집', 0.0005),
            spot('mid', '중간집', 0.0015),
            spot('far', '먼집', 0.0070),
          ],
        ),
        overridesRepo: repo,
      );
      await pumpApp(tester, h, home: const AppShell());
      // 숨긴집 is the nearest but hidden by an admin: 중간집 is first, of 2 places.
      expect(find.text('숨긴집'), findsNothing);
      expect(find.text('중간집'), findsWidgets); // top pick + picks list
      expect(find.text('2곳 중 1순위'), findsOneWidget);
      expect(find.text('9,000~'), findsOneWidget);
      expect(find.text('21:30'), findsOneWidget);
    },
  );
}
