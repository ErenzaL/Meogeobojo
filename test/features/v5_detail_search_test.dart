import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/providers/conditions_providers.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/search/providers/search_providers.dart';
import 'package:meogeobojo/features/search/screens/search_screen.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

Restaurant far(String id) => Restaurant(
  kakaoId: id,
  name: '먼식당',
  categoryName: '음식점 > 한식',
  categoryGroupCode: 'FD6',
  address: '',
  roadAddress: '',
  phone: '',
  latitude: 36.82, // several km away: outside a 5-minute walk
  longitude: 126.93,
  distanceMeters: 5000,
  placeUrl: null,
);

void main() {
  group('recent searches', () {
    test(
      'newest first, no duplicates, at most 8, stored on the device',
      () async {
        final h = await buildHarness();
        final n = h.container.read(recentSearchesProvider.notifier);
        n.add('국밥');
        n.add('제육');
        n.add('국밥');
        expect(h.container.read(recentSearchesProvider), ['국밥', '제육']);
        for (var i = 0; i < 10; i++) {
          n.add('q$i');
        }
        expect(h.container.read(recentSearchesProvider), hasLength(8));
        expect(h.container.read(recentSearchesProvider).first, 'q9');
        expect(
          h.container
              .read(sharedPreferencesProvider)
              .getStringList('search_recent'),
          h.container.read(recentSearchesProvider),
        );
        n.clear();
        expect(h.container.read(recentSearchesProvider), isEmpty);
      },
    );
  });

  group('맛집 정보 (V5)', () {
    testWidgets('the 지도 button opens the map tab on this place', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(
        tester,
        h,
        home: RestaurantDetailScreen(restaurant: fakeRestaurant('a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('맛집 정보'), findsOneWidget);
      expect(find.text('카카오맵에서 보기'), findsOneWidget);
      await tester.tap(find.text('지도'));
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.map);
      expect(h.container.read(mapFocusProvider)?.kakaoId, 'a');
    });
  });

  group('검색 (V5)', () {
    testWidgets('before a search: recent searches and suggestions', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const SearchScreen());
      await tester.pumpAndSettle();
      expect(find.text('최근 검색'), findsOneWidget);
      expect(find.text('최근 검색어가 없어요.'), findsOneWidget);
      expect(find.text('이런 건 어때요?'), findsOneWidget);
      expect(find.text('국밥'), findsOneWidget);
    });

    testWidgets(
      'a suggestion searches; places outside the conditions are listed below, dimmed',
      (tester) async {
        final h = await buildHarness(
          restaurants: FakeRestaurantRepository(
            items: [fakeRestaurant('a'), far('b')],
          ),
        );
        h.container
            .read(conditionsProvider.notifier)
            .update((c) => c.copyWith(distance: DistanceOption.walk5));
        await pumpApp(tester, h, home: const SearchScreen());
        await tester.pumpAndSettle();
        await tester.tap(find.text('국밥'));
        await tester.pumpAndSettle();
        expect(find.text('‘국밥’ 검색 결과 2곳 · 지금 조건에 맞는 곳 1곳'), findsOneWidget);
        expect(find.text('조건 밖 식당 · 눌러서 열어볼 수 있어요'), findsOneWidget);
        expect(find.text('먼식당'), findsOneWidget);
        expect(h.container.read(recentSearchesProvider), ['국밥']);
      },
    );
  });
}
