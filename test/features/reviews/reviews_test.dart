import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/reviews/models/student_review.dart';
import 'package:meogeobojo/features/reviews/repositories/review_repository.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

StudentReview review(
  String id, {
  String user = 'other',
  int rating = 4,
  String? body = '맛있어요',
  String status = 'visible',
  String place = 'a',
}) => StudentReview(
  id: id,
  userId: user,
  kakaoPlaceId: place,
  rating: rating,
  body: body,
  createdAt: DateTime.utc(2026, 11, 9),
  moderationStatus: status,
);

Future<(Harness, FakeReviewRepository, FakeMissionRepository)> open(
  WidgetTester tester, {
  List<StudentReview>? reviews,
  bool signedIn = true,
  FakeReviewRepository? repo,
}) async {
  final r = repo ?? FakeReviewRepository(reviews);
  final m = FakeMissionRepository();
  final h = await buildHarness(
    auth: signedIn ? FakeAuthGateway(user: fakeUser()) : null,
    profiles: FakeProfileRepository(onboardingCompleted: true, nickname: '민수'),
    reviews: r,
    missions: m,
  );
  await pumpApp(
    tester,
    h,
    home: RestaurantDetailScreen(restaurant: fakeRestaurant('a')),
    size: const Size(390, 1800),
  );
  await tester.pumpAndSettle();
  return (h, r, m);
}

void main() {
  group('model', () {
    test(
      'rows without a valid rating or ids are dropped; the body is trimmed',
      () {
        expect(
          StudentReview.fromJson({
            'id': 'x',
            'user_id': 'u',
            'kakao_place_id': 'p',
            'rating': 6,
            'created_at': '2026-11-09T00:00:00Z',
          }),
          isNull,
        );
        expect(
          StudentReview.fromJson({
            'id': 'x',
            'user_id': 'u',
            'kakao_place_id': 'p',
            'rating': 0,
            'created_at': '2026-11-09T00:00:00Z',
          }),
          isNull,
        );
        final r = StudentReview.fromJson({
          'id': 'x',
          'user_id': 'u',
          'kakao_place_id': 'p',
          'rating': 5,
          'body': '  좋아요  ',
          'created_at': '2026-11-09T00:00:00Z',
        })!;
        expect(r.body, '좋아요');
        expect(r.moderationStatus, 'visible');
      },
    );

    test('the average counts only reviews other students can see', () {
      final s = ReviewSummary.of([
        review('1', rating: 5),
        review('2', rating: 3),
        review('3', rating: 1, status: 'hidden'),
        review('4', rating: 1, status: 'removed'),
      ]);
      expect(s.count, 2);
      expect(s.average, 4.0);
      expect(ReviewSummary.of(const []).count, 0);
    });
  });

  group('on the restaurant page', () {
    testWidgets(
      'shows the average and the visible reviews as "학생", not the hidden ones',
      (tester) async {
        await open(
          tester,
          reviews: [
            review('1', rating: 5, body: '최고'),
            review('2', rating: 3, body: '보통'),
            review('3', rating: 1, body: '숨겨진 글', status: 'hidden'),
          ],
        );
        expect(
          find.text('4.0 · 리뷰 2개 · 한식'),
          findsOneWidget,
        ); // the rating line
        expect(find.text('4.0'), findsOneWidget); // the summary box
        expect(find.text('리뷰 2개'), findsOneWidget);
        expect(find.text('최고'), findsOneWidget);
        expect(find.text('보통'), findsOneWidget);
        expect(find.text('숨겨진 글'), findsNothing);
        expect(find.textContaining('학생 ·'), findsNWidgets(2)); // never a name
      },
    );

    testWidgets('an empty restaurant invites the first review', (tester) async {
      await open(tester, reviews: []);
      expect(find.textContaining('첫 리뷰를 남겨 보세요'), findsOneWidget);
      expect(find.text('리뷰 쓰기'), findsOneWidget);
    });

    testWidgets('only this restaurant\'s reviews are shown', (tester) async {
      await open(
        tester,
        reviews: [
          review('1', body: '여기 글'),
          review('2', place: 'zzz', body: '다른 식당 글'),
        ],
      );
      expect(find.text('여기 글'), findsOneWidget);
      expect(find.text('다른 식당 글'), findsNothing);
    });

    testWidgets(
      'the student\'s own hidden review is shown to them with its status',
      (tester) async {
        await open(
          tester,
          reviews: [review('1', user: 'user-1', status: 'hidden', body: '내 글')],
        );
        expect(find.text('내 리뷰'), findsOneWidget);
        expect(find.textContaining('관리자가 숨겼어요'), findsOneWidget);
        expect(find.text('내 리뷰 수정'), findsOneWidget);
        expect(
          find.textContaining('리뷰 1개', skipOffstage: false),
          findsNothing,
        ); // a hidden review is not counted
        expect(find.text('리뷰 쓰기'), findsNothing); // edit, not a second review
      },
    );

    testWidgets('a guest is asked to sign in before writing', (tester) async {
      final (_, repo, _) = await open(tester, signedIn: false, reviews: []);
      await tester.tap(find.text('리뷰 쓰기'));
      await tester.pumpAndSettle();
      expect(find.text('리뷰와 사진은 로그인한 뒤에 남길 수 있어요.'), findsOneWidget);
      expect(repo.saves, isEmpty);
    });
  });

  group('writing', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.ensureVisible(find.text('리뷰 쓰기'));
      await tester.tap(find.text('리뷰 쓰기'));
      await tester.pumpAndSettle();
    }

    testWidgets('a rating is required', (tester) async {
      final (_, repo, _) = await open(tester, reviews: []);
      await openEditor(tester);
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.text('별점을 선택해 주세요.'), findsOneWidget);
      expect(repo.saves, isEmpty);
    });

    testWidgets(
      'saves the review for this place and the student\'s campus, then asks the server about missions',
      (tester) async {
        final (_, repo, missions) = await open(tester, reviews: []);
        await openEditor(tester);
        await tester.tap(find.bySemanticsLabel('4'));
        await tester.enterText(find.byType(TextField), '  국물이 진해요  ');
        final before = missions.syncs;
        await tester.tap(find.text('저장'));
        await tester.pumpAndSettle();
        expect(repo.saves.single.kakaoId, 'a');
        expect(repo.saves.single.rating, 4);
        expect(repo.saves.single.body, '  국물이 진해요  ');
        expect(repo.saves.single.universityId, isNotNull);
        expect(find.text('리뷰를 저장했어요.'), findsOneWidget);
        expect(
          find.text('내 리뷰'),
          findsOneWidget,
        ); // the page shows it right away
        expect(
          missions.syncs,
          greaterThan(before),
        ); // a review can complete a mission
      },
    );

    testWidgets('a failed save keeps the sheet and says so', (tester) async {
      final repo = FakeReviewRepository([])..saveError = Exception('offline');
      await open(tester, repo: repo);
      await openEditor(tester);
      await tester.tap(find.bySemanticsLabel('5'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
      expect(find.text('저장'), findsOneWidget); // still open
    });

    testWidgets('editing changes the same review; deleting asks first', (
      tester,
    ) async {
      final (_, repo, _) = await open(
        tester,
        reviews: [review('mine', user: 'user-1', rating: 2, body: '별로')],
      );
      await tester.ensureVisible(find.text('내 리뷰 수정'));
      await tester.tap(find.text('내 리뷰 수정'));
      await tester.pumpAndSettle();
      expect(find.text('별로'), findsWidgets); // prefilled
      await tester.tap(find.bySemanticsLabel('5'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(repo.saves.single.rating, 5);
      expect(
        repo.reviews.where((r) => r.userId == 'user-1'),
        hasLength(1),
      ); // not a second one

      await tester.ensureVisible(find.text('내 리뷰 수정'));
      await tester.tap(find.text('내 리뷰 수정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.text('이 리뷰를 삭제할까요?'), findsOneWidget);
      expect(repo.deletes, isEmpty); // nothing before the confirmation
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(repo.deletes, hasLength(1));
      expect(find.text('리뷰를 삭제했어요.'), findsOneWidget);
    });
  });

  group('reporting', () {
    Future<void> startReport(WidgetTester tester) async {
      await tester.ensureVisible(find.text('신고').first);
      await tester.tap(find.text('신고').first);
      await tester.pumpAndSettle();
    }

    testWidgets('sends the chosen reason for that review', (tester) async {
      final (_, repo, _) = await open(
        tester,
        reviews: [review('bad', body: '욕설 글')],
      );
      await startReport(tester);
      expect(find.text('이 리뷰를 신고할까요?'), findsOneWidget);
      await tester.tap(find.text('신고하기')); // nothing chosen yet: disabled
      await tester.pumpAndSettle();
      expect(repo.reports, isEmpty);
      await tester.tap(find.text('욕설·비방'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('신고하기'));
      await tester.pumpAndSettle();
      expect(repo.reports.single, (reviewId: 'bad', reason: '욕설·비방'));
      expect(find.text('신고했어요. 관리자가 확인할게요.'), findsOneWidget);
    });

    testWidgets('reporting the same review again says so instead of failing', (
      tester,
    ) async {
      final repo = FakeReviewRepository([review('bad')])
        ..reportOutcome = ReportOutcome.alreadyReported;
      await open(tester, repo: repo);
      await startReport(tester);
      await tester.tap(find.text('기타'));
      await tester.pump();
      await tester.tap(find.text('신고하기'));
      await tester.pumpAndSettle();
      expect(find.text('이미 신고한 리뷰예요.'), findsOneWidget);
    });

    testWidgets('a guest cannot report', (tester) async {
      final (_, repo, _) = await open(
        tester,
        signedIn: false,
        reviews: [review('bad')],
      );
      await startReport(tester);
      expect(find.text('리뷰와 사진은 로그인한 뒤에 남길 수 있어요.'), findsOneWidget);
      expect(repo.reports, isEmpty);
    });

    testWidgets('your own review has no report button', (tester) async {
      await open(tester, reviews: [review('mine', user: 'user-1')]);
      expect(find.text('신고'), findsNothing);
    });
  });
}
