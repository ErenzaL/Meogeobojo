import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/content/models/app_content.dart';
import 'package:meogeobojo/features/restaurants/utils/restaurant_link.dart';
import 'package:meogeobojo/features/support/support.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  testWidgets('문의 및 제안: title, category and message reach the admin; '
      'empty fields are refused', (tester) async {
    final sent = <(FeedbackCategory, String, String)>[];
    final h = await buildHarness(
      auth: FakeAuthGateway(user: fakeUser()),
      extraOverrides: [
        feedbackSenderProvider.overrideWithValue(
          (c, t, b) async => sent.add((c, t, b)),
        ),
      ],
    );
    await pumpApp(
      tester,
      h,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () => showFeedbackDialog(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제출'));
    await tester.pump();
    expect(find.text('제목을 입력해 주세요.'), findsOneWidget);
    expect(sent, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, '제목'), '지도 핀');
    await tester.tap(find.text('문의'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제안').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '내용'), '핀을 키워 주세요');
    await tester.tap(find.text('제출'));
    await tester.pumpAndSettle();
    expect(sent, [(FeedbackCategory.suggestion, '지도 핀', '핀을 키워 주세요')]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('보냈어요. 운영자가 확인할게요.'), findsOneWidget);
  });

  testWidgets('공지사항 lists the announcements newest first and opens one', (
    tester,
  ) async {
    final h = await buildHarness(
      content: FakeAppContentRepository([
        AppContent(
          id: 'old',
          kind: AppContentKind.announcement,
          title: '1차 업데이트',
          time: DateTime.utc(2026, 11, 1),
        ),
        AppContent(
          id: 'new',
          kind: AppContentKind.announcement,
          title: '2차 업데이트',
          body: '지도 핀이 커졌어요',
          time: DateTime.utc(2026, 11, 12),
        ),
        const AppContent(id: 'b', kind: AppContentKind.banner, title: '배너'),
      ]),
    );
    await pumpApp(tester, h, home: const NoticesScreen());
    await tester.pumpAndSettle();
    expect(find.text('배너'), findsNothing);
    final newer = tester.getTopLeft(find.text('2차 업데이트')).dy;
    final older = tester.getTopLeft(find.text('1차 업데이트')).dy;
    expect(newer, lessThan(older));
    await tester.tap(find.text('2차 업데이트'));
    await tester.pumpAndSettle();
    expect(find.text('지도 핀이 커졌어요'), findsOneWidget);
  });

  test('네이버맵 link searches the place by name near its city', () {
    final r = fakeRestaurant('1', name: '국수집');
    final url = naverMapUrl(r);
    expect(url.host, 'map.naver.com');
    expect(Uri.decodeComponent(url.path), startsWith('/p/search/'));
    expect(Uri.decodeComponent(url.path), endsWith(r.name));
  });
}
