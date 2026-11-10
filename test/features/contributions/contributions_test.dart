import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/contributions/models/contribution.dart';
import 'package:meogeobojo/features/contributions/screens/my_contributions_screen.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_detail_screen.dart';
import 'package:meogeobojo/features/reviews/models/student_review.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

/// A real 1x1 PNG (so the preview decodes), padded to the wanted size.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
);

PickedPhoto photo({int bytes = 1000, String mime = 'image/jpeg'}) {
  final data = Uint8List(bytes < _png.length ? _png.length : bytes)
    ..setRange(0, _png.length, _png);
  return PickedPhoto(bytes: data, mime: mime, name: 'menu.jpg');
}

Contribution contribution(
  String id, {
  String status = 'pending',
  ContributionKind kind = ContributionKind.restaurantPhoto,
  String? note,
  String? caption,
}) => Contribution(
  id: id,
  kind: kind,
  kakaoPlaceId: 'a',
  status: status,
  createdAt: DateTime.utc(2026, 11, 9),
  caption: caption,
  reviewNote: note,
  path: 'user-1/$id.jpg',
);

void main() {
  group('model', () {
    test(
      'photo kinds parse; corrections and junk are not photo submissions',
      () {
        final c = Contribution.fromJson({
          'id': 'x',
          'kind': 'menu_photo',
          'kakao_place_id': 'a',
          'status': 'rejected',
          'review_note': ' 흐려요 ',
          'created_at': '2026-11-09T00:00:00Z',
          'payload': {'path': 'u/1.jpg', 'caption': ' 제육 '},
        })!;
        expect(c.kind, ContributionKind.menuPhoto);
        expect(c.reviewNote, '흐려요');
        expect(c.caption, '제육');
        expect(c.isPending, isFalse);
        expect(
          Contribution.fromJson({
            'id': 'x',
            'kind': 'info_correction',
            'kakao_place_id': 'a',
            'created_at': '2026-11-09T00:00:00Z',
          }),
          isNull,
        );
        expect(Contribution.fromJson({'kind': 'menu_photo'}), isNull);
      },
    );

    test('the picked photo gets the right extension', () {
      expect(photo(mime: 'image/png').extension, 'png');
      expect(photo(mime: 'image/webp').extension, 'webp');
      expect(photo().extension, 'jpg');
    });
  });

  group('photo upload from the restaurant page', () {
    Future<(FakeContributionRepository, FakePhotoPicker, FakeMissionRepository)>
    open(
      WidgetTester tester, {
      bool signedIn = true,
      PickedPhoto? pick,
      FakeContributionRepository? repo,
    }) async {
      final r = repo ?? FakeContributionRepository();
      final picker = FakePhotoPicker(pick);
      final m = FakeMissionRepository();
      final h = await buildHarness(
        auth: signedIn ? FakeAuthGateway(user: fakeUser()) : null,
        profiles: FakeProfileRepository(
          onboardingCompleted: true,
          nickname: '민수',
        ),
        contributions: r,
        photoPicker: picker,
        missions: m,
      );
      await pumpApp(
        tester,
        h,
        home: RestaurantDetailScreen(restaurant: fakeRestaurant('a')),
        size: const Size(390, 1800),
      );
      await tester.pumpAndSettle();
      return (r, picker, m);
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.ensureVisible(find.text('사진 올리기'));
      await tester.tap(find.text('사진 올리기'));
      await tester.pumpAndSettle();
    }

    testWidgets('a guest is asked to sign in first', (tester) async {
      final (repo, picker, _) = await open(tester, signedIn: false);
      await openSheet(tester);
      expect(find.text('리뷰와 사진은 로그인한 뒤에 남길 수 있어요.'), findsOneWidget);
      expect(picker.picks, 0);
      expect(repo.submissions, isEmpty);
    });

    testWidgets(
      'submit stays off until a photo is chosen AND the student agrees to publication',
      (tester) async {
        final (repo, picker, _) = await open(tester, pick: photo());
        await openSheet(tester);
        FilledButton submit() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '제출하기'),
        );
        expect(submit().onPressed, isNull);
        await tester.tap(find.text('사진 고르기'));
        await tester.pumpAndSettle();
        expect(picker.picks, 1);
        expect(find.byType(Image), findsWidgets); // a preview
        expect(find.text('다른 사진 고르기'), findsOneWidget);
        expect(submit().onPressed, isNull); // no consent yet
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        expect(submit().onPressed, isNotNull);
        expect(repo.submissions, isEmpty); // nothing sent before pressing it
        expect(find.text('검토가 끝나기 전에는 나만 볼 수 있어요.'), findsOneWidget);
      },
    );

    testWidgets(
      'submits a restaurant photo with its caption and refreshes the missions',
      (tester) async {
        final (repo, _, missions) = await open(
          tester,
          pick: photo(bytes: 2048),
        );
        await openSheet(tester);
        await tester.tap(find.text('사진 고르기'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), ' 입구 ');
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        final before = missions.syncs;
        await tester.tap(find.text('제출하기'));
        await tester.pumpAndSettle();
        expect(repo.submissions.single.kind, ContributionKind.restaurantPhoto);
        expect(repo.submissions.single.kakaoPlaceId, 'a');
        expect(repo.submissions.single.caption, '입구');
        expect(repo.submissions.single.bytes, 2048);
        expect(find.text('제출했어요. 관리자가 확인한 뒤 공개돼요.'), findsOneWidget);
        expect(missions.syncs, greaterThan(before));
      },
    );

    testWidgets('a menu photo is its own kind', (tester) async {
      final (repo, _, _) = await open(tester, pick: photo());
      await openSheet(tester);
      await tester.tap(find.text('메뉴 사진'));
      await tester.pump();
      await tester.tap(find.text('사진 고르기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('제출하기'));
      await tester.pumpAndSettle();
      expect(repo.submissions.single.kind, ContributionKind.menuPhoto);
    });

    testWidgets('a photo over 5 MB is refused before anything is uploaded', (
      tester,
    ) async {
      final (repo, _, _) = await open(
        tester,
        pick: photo(bytes: maxPhotoBytes + 1),
      );
      await openSheet(tester);
      await tester.tap(find.text('사진 고르기'));
      await tester.pumpAndSettle();
      expect(find.text('사진은 5MB 이하여야 해요.'), findsOneWidget);
      expect(find.text('다른 사진 고르기'), findsNothing); // nothing was accepted
      expect(repo.submissions, isEmpty);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final (repo, picker, _) = await open(tester, pick: null);
      await openSheet(tester);
      await tester.tap(find.text('사진 고르기'));
      await tester.pumpAndSettle();
      expect(picker.picks, 1);
      expect(find.text('사진 고르기'), findsOneWidget);
      expect(repo.submissions, isEmpty);
    });

    for (final (error, text) in [
      (ContributionError.duplicate, '이미 제출한 사진이에요.'),
      (ContributionError.tooMany, '검토 대기 중인 사진이 너무 많아요. 처리된 뒤에 다시 올려 주세요.'),
      (ContributionError.failed, '올리지 못했어요. 잠시 후 다시 시도해 주세요.'),
    ]) {
      testWidgets(
        'a refused submission explains why ($error) and keeps the sheet',
        (tester) async {
          final repo = FakeContributionRepository()
            ..submitError = ContributionException(error);
          await open(tester, pick: photo(), repo: repo);
          await openSheet(tester);
          await tester.tap(find.text('사진 고르기'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pump();
          await tester.tap(find.text('제출하기'));
          await tester.pumpAndSettle();
          expect(find.text(text), findsOneWidget);
          expect(find.text('제출하기'), findsOneWidget); // can try again
        },
      );
    }
  });

  group('내 리뷰·사진', () {
    Future<(FakeContributionRepository, FakeReviewRepository)> open(
      WidgetTester tester, {
      List<Contribution>? photos,
      List<StudentReview>? reviews,
    }) async {
      final c = FakeContributionRepository(photos);
      final r = FakeReviewRepository(reviews);
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser()),
        profiles: FakeProfileRepository(
          onboardingCompleted: true,
          nickname: '민수',
        ),
        contributions: c,
        reviews: r,
      );
      await pumpApp(tester, h, home: const MyContributionsScreen());
      await tester.pumpAndSettle();
      return (c, r);
    }

    testWidgets('says so when there is nothing yet', (tester) async {
      await open(tester, photos: [], reviews: []);
      expect(find.text('아직 남긴 리뷰나 사진이 없어요.'), findsOneWidget);
    });

    testWidgets(
      'shows where each submission stands, with the moderator\'s reason',
      (tester) async {
        await open(
          tester,
          photos: [
            contribution('p1'),
            contribution(
              'p2',
              status: 'approved',
              kind: ContributionKind.menuPhoto,
            ),
            contribution('p3', status: 'rejected', note: '음식과 관계없는 사진'),
          ],
          reviews: [
            StudentReview(
              id: 'r1',
              userId: 'user-1',
              kakaoPlaceId: 'a',
              rating: 5,
              body: '맛있어요',
              createdAt: DateTime.utc(2026, 11, 9),
            ),
            StudentReview(
              id: 'r2',
              userId: 'user-1',
              kakaoPlaceId: 'b',
              rating: 1,
              body: '숨김',
              createdAt: DateTime.utc(2026, 11, 8),
              moderationStatus: 'hidden',
            ),
          ],
        );
        expect(find.text('검토 중'), findsOneWidget);
        expect(find.text('게시됨'), findsOneWidget);
        expect(find.text('반려됨'), findsOneWidget);
        expect(find.text('사유: 음식과 관계없는 사진'), findsOneWidget);
        expect(find.text('공개 중'), findsOneWidget);
        expect(find.textContaining('관리자가 숨겼어요'), findsOneWidget);
        expect(find.text('메뉴 사진'), findsOneWidget);
      },
    );

    testWidgets(
      'only a pending submission can be withdrawn, after confirming',
      (tester) async {
        final (repo, _) = await open(
          tester,
          photos: [
            contribution('p1'),
            contribution('p2', status: 'approved'),
          ],
          reviews: [],
        );
        expect(find.text('제출 취소'), findsOneWidget); // only the pending one
        await tester.tap(find.text('제출 취소'));
        await tester.pumpAndSettle();
        expect(find.text('제출을 취소할까요? 사진도 삭제돼요.'), findsOneWidget);
        expect(repo.withdrawn, isEmpty);
        await tester.tap(find.text('제출 취소').last);
        await tester.pumpAndSettle();
        expect(repo.withdrawn, ['p1']);
        expect(find.text('제출을 취소했어요.'), findsOneWidget);
      },
    );
  });

  group('small screens and other languages', () {
    for (final lang in ['en', 'zh']) {
      testWidgets(
        'the new screens do not overflow at 320px / 1.6x text in $lang',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final h = await buildHarness(
            storage: {'app_language': lang},
            auth: FakeAuthGateway(user: fakeUser()),
            profiles: FakeProfileRepository(
              onboardingCompleted: true,
              nickname: 'x',
            ),
            contributions: FakeContributionRepository([
              contribution('p1'),
              contribution('p3', status: 'rejected', note: 'reason'),
            ]),
            reviews: FakeReviewRepository([
              StudentReview(
                id: 'r2',
                userId: 'user-1',
                kakaoPlaceId: 'b',
                rating: 1,
                body: 'x',
                createdAt: DateTime.utc(2026, 11, 8),
                moderationStatus: 'hidden',
              ),
            ]),
            photoPicker: FakePhotoPicker(photo()),
          );
          await pumpApp(
            tester,
            h,
            home: const MyContributionsScreen(),
            size: const Size(320, 568),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // the upload sheet and the review editor too
          await pumpApp(
            tester,
            h,
            home: RestaurantDetailScreen(restaurant: fakeRestaurant('a')),
            size: const Size(320, 568),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
