import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/reviews/models/collected_review.dart';
import 'package:meogeobojo/features/reviews/models/student_review.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Future<void> open(
  WidgetTester tester, {
  CollectedReviewSummary summary = CollectedReviewSummary.empty,
  List<CollectedReview> reviews = const [],
  List<StudentReview> students = const [],
}) async {
  final h = await buildHarness(
    reviews: FakeReviewRepository(students),
    collectedReviews: FakeCollectedReviewRepository(
      summaries: {'a': summary},
      reviews: {'a': reviews},
    ),
  );
  await pumpApp(
    tester,
    h,
    home: RestaurantDetailScreen(restaurant: fakeRestaurant('a')),
    size: const Size(390, 1800),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('model', () {
    test('stats rows add up per place; platforms largest first', () {
      final s = CollectedReviewSummary.fromStats([
        {
          'platform': 'kakao',
          'review_count': 2,
          'rated_count': 2,
          'rating_sum': 7.0,
        },
        {
          'platform': 'naver',
          'review_count': 5,
          'rated_count': 1,
          'rating_sum': 4.5,
        },
        {'platform': 'baemin', 'review_count': 0},
      ]);
      expect(s.count, 7);
      expect(s.byPlatform.keys, ['naver', 'kakao']);
      expect(s.average, closeTo(11.5 / 3, 1e-9));
      expect(
        CollectedReviewSummary.fromStats([
          {'platform': 'naver', 'review_count': 3, 'rated_count': 0},
        ]).average,
        isNull,
      );
    });

    test('the rating line counts every review and averages the rated ones', () {
      final collected = CollectedReviewSummary(
        byPlatform: const {'naver': 4, 'kakao': 1},
        ratedCount: 3,
        ratingSum: 12.5,
      );
      final t = reviewTotals(const ReviewSummary(2, 4), collected);
      expect(t.count, 7);
      expect(t.average, closeTo((8 + 12.5) / 5, 1e-9));
      expect(
        reviewTotals(
          const ReviewSummary(0, 0),
          const CollectedReviewSummary(
            byPlatform: {'naver': 3},
            ratedCount: 0,
            ratingSum: 0,
          ),
        ).average,
        isNull,
      );
    });

    test('rows parse; an empty body is no body', () {
      final r = CollectedReview.fromJson({
        'platform': 'baemin',
        'rating': 4.5,
        'body': '  ',
        'reviewed_on': '2026-06-30',
      })!;
      expect(r.rating, 4.5);
      expect(r.body, isNull);
      expect(r.reviewedOn, DateTime(2026, 6, 30));
      expect(CollectedReview.fromJson({'rating': 5}), isNull);
    });
  });

  group('restaurant page', () {
    final summary = CollectedReviewSummary(
      byPlatform: const {'naver': 3, 'baemin': 1},
      ratedCount: 2,
      ratingSum: 9,
    );
    final reviews = [
      for (var i = 0; i < 12; i++)
        CollectedReview(
          platform: i.isEven ? 'naver' : 'baemin',
          rating: i.isEven ? null : 4.5,
          body: '수집리뷰$i',
          reviewedOn: DateTime(2026, 10, 30 - i),
        ),
    ];

    testWidgets(
      'shows the average, the total, the count per app and the reviews',
      (tester) async {
        await open(tester, summary: summary, reviews: reviews);
        expect(find.text('다른 앱 리뷰'), findsOneWidget);
        expect(find.textContaining('4.5 · 리뷰 4개'), findsOneWidget);
        expect(find.text('4.5'), findsOneWidget);
        expect(find.text('리뷰 4개'), findsOneWidget);
        expect(find.text('별점은 2개 리뷰 기준'), findsOneWidget);
        expect(find.text('네이버'), findsOneWidget);
        expect(find.text('배달의민족'), findsOneWidget);
        expect(find.text('배달의민족 · 2026.10.29'), findsOneWidget);
        expect(find.byIcon(Icons.star_half_rounded), findsWidgets);
        expect(find.text('수집리뷰4'), findsOneWidget);
        expect(find.text('수집리뷰5'), findsNothing);

        await tester.ensureVisible(find.text('리뷰 더 보기'));
        await tester.tap(find.text('리뷰 더 보기'));
        await tester.pumpAndSettle();
        expect(find.text('수집리뷰11'), findsOneWidget);
        expect(find.text('리뷰 더 보기'), findsNothing);
      },
    );

    testWidgets('the rating line adds the students\' visible reviews', (
      tester,
    ) async {
      await open(
        tester,
        summary: summary,
        students: [
          StudentReview(
            id: 's1',
            userId: 'other',
            kakaoPlaceId: 'a',
            rating: 3,
            createdAt: DateTime.utc(2026, 11, 9),
          ),
        ],
      );
      // (9 + 3) / 3 rated, 4 collected + 1 student
      expect(find.textContaining('4.0 · 리뷰 5개'), findsOneWidget);
    });

    testWidgets('reviews without any rating: the count, and no average', (
      tester,
    ) async {
      await open(
        tester,
        summary: const CollectedReviewSummary(
          byPlatform: {'naver': 3},
          ratedCount: 0,
          ratingSum: 0,
        ),
      );
      expect(find.textContaining('리뷰 3개 · '), findsOneWidget);
      expect(find.text('별점 없음'), findsOneWidget);
    });

    testWidgets('a place without collected reviews shows no such section', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('다른 앱 리뷰'), findsNothing);
      expect(find.textContaining('아직 리뷰가 없어요 · '), findsOneWidget);
    });
  });
}
