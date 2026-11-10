import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/content/models/app_content.dart';
import 'package:meogeobojo/features/content/providers/app_content_providers.dart';
import 'package:meogeobojo/features/home/widgets/today_picks_section.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/university/models/verified_universities.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

AppContent item(
  String id,
  AppContentKind kind, {
  String? body,
  String? universityId,
  String? place,
  int order = 0,
  String? link,
}) => AppContent(
  id: id,
  kind: kind,
  title: '제목 $id',
  body: body,
  universityId: universityId,
  kakaoPlaceId: place,
  sortOrder: order,
  linkUrl: link,
);

void main() {
  group('parsing', () {
    test(
      'needs an id, a known kind and a title; links and images must be https',
      () {
        expect(
          AppContent.fromJson({'id': 'a', 'kind': 'banner', 'title': ' '}),
          isNull,
        );
        expect(
          AppContent.fromJson({'id': 'a', 'kind': 'popup', 'title': 'x'}),
          isNull,
        );
        final c = AppContent.fromJson({
          'id': 'a',
          'kind': 'banner',
          'title': ' 새 학기 ',
          'body': '',
          'image_url': 'http://x/a.png',
          'link_url': 'https://x/notice',
          'university_id': null,
          'sort_order': 2,
        })!;
        expect(c.title, '새 학기');
        expect(c.body, isNull);
        expect(c.imageUrl, isNull); // insecure image ignored
        expect(c.linkUrl, 'https://x/notice');
        expect(c.sortOrder, 2);
      },
    );
  });

  group('Home notices', () {
    testWidgets(
      'a published notice shows on Home; nothing is shown when there are none',
      (tester) async {
        final h = await buildHarness(
          content: FakeAppContentRepository([
            item('1', AppContentKind.announcement, body: '학식 운영시간이 바뀌어요'),
          ]),
        );
        await pumpApp(tester, h, home: const AppShell());
        await tester.pumpAndSettle();
        expect(find.text('제목 1'), findsOneWidget);
        expect(find.text('학식 운영시간이 바뀌어요'), findsOneWidget);
      },
    );

    testWidgets('no content means no card and no gap', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const AppShell());
      await tester.pumpAndSettle();
      expect(find.textContaining('제목'), findsNothing);
    });

    testWidgets(
      'campus-specific notices only show for that campus; at most two show',
      (tester) async {
        final other = kVerifiedUniversities[1].id;
        final h = await buildHarness(
          content: FakeAppContentRepository([
            item('all', AppContentKind.announcement),
            item(
              'mine',
              AppContentKind.announcement,
              universityId: kDefaultUniversityId,
            ),
            item('elsewhere', AppContentKind.announcement, universityId: other),
            item('third', AppContentKind.banner),
          ]),
        );
        await pumpApp(tester, h, home: const AppShell());
        await tester.pumpAndSettle();
        expect(find.text('제목 elsewhere'), findsNothing);
        expect(find.text('제목 all'), findsOneWidget);
        expect(find.text('제목 mine'), findsOneWidget);
        expect(find.text('제목 third'), findsNothing); // the cap
      },
    );

    testWidgets('featured items are not notices', (tester) async {
      final h = await buildHarness(
        content: FakeAppContentRepository([
          item('f', AppContentKind.featured, place: 'a'),
        ]),
      );
      await pumpApp(tester, h, home: const AppShell());
      await tester.pumpAndSettle();
      expect(find.text('제목 f'), findsNothing);
      expect(h.container.read(featuredContentIdsProvider), ['a']);
    });
  });

  group('featuredFirst', () {
    RankedRestaurant r(String id) => RankedRestaurant(
      restaurant: fakeRestaurant(id),
      meters: 100,
      walkMinutes: 2,
      insight: RestaurantInsight.unknown,
      reason: const RecommendReason(ReasonKind.closest),
    );
    final ranked = [r('1'), r('2'), r('3'), r('4')];

    List<String> ids(List<RankedRestaurant> l) => [
      for (final x in l) x.restaurant.kakaoId,
    ];

    test('nothing featured keeps the recommendation order exactly', () {
      expect(ids(featuredFirst(ranked, {}, const [])), ['1', '2', '3', '4']);
    });

    test(
      'featured places lead, by display order; the rest keep their rank',
      () {
        final out = featuredFirst(ranked, {
          '4': const RestaurantOverride(
            kakaoId: '4',
            visibility: 'published',
            featured: true,
            displayOrder: 2,
          ),
          '3': const RestaurantOverride(
            kakaoId: '3',
            visibility: 'published',
            featured: true,
            displayOrder: 1,
          ),
        }, const []);
        expect(ids(out), ['3', '4', '1', '2']);
      },
    );

    test(
      'a featured content item counts too, after explicit display orders',
      () {
        final out = featuredFirst(
          ranked,
          {
            '2': const RestaurantOverride(
              kakaoId: '2',
              visibility: 'published',
              featured: true,
              displayOrder: 5,
            ),
          },
          const ['4'],
        );
        expect(ids(out), ['2', '4', '1', '3']);
      },
    );

    test(
      'a featured place that is not in the list is simply absent (never added)',
      () {
        expect(ids(featuredFirst(ranked, {}, const ['999'])), [
          '1',
          '2',
          '3',
          '4',
        ]);
      },
    );
  });
}
