import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/recommendation/providers/ranking_providers.dart';
import 'package:meogeobojo/features/recommendation/review_signal_repository.dart';

import '../home/new_home_test.dart' show inHero, openHome;

class _Insights implements ReviewInsightSource {
  _Insights(this.byId);

  final Map<String, ReviewInsight> byId;

  @override
  Future<Map<String, ReviewInsight>> visibleInsights() async => byId;
}

const _summary = '국물이 진하고 양이 푸짐하다는 평이 많아요.';

void main() {
  test('student reviews keep priority over the stored R', () {
    final merged = mergeReviewSignals(
      {'a': 0.3},
      {
        'a': const ReviewInsight(reviewCount: 5, signal: -0.5),
        'b': const ReviewInsight(reviewCount: 9, signal: 0.1),
      },
    );
    expect(merged, {'a': 0.3, 'b': 0.1});
  });

  testWidgets('the top pick shows its AI review summary', (tester) async {
    await openHome(
      tester,
      overrides: [
        reviewInsightSourceProvider.overrideWithValue(
          _Insights({
            '가까운집': const ReviewInsight(
              reviewCount: 12,
              signal: 0,
              summary: _summary,
              highlights: ['양이 푸짐해요', '혼밥하기 좋아요'],
            ),
          }),
        ),
      ],
    );
    expect(inHero(find.text('가까운집')), findsWidgets);
    expect(inHero(find.text('AI 리뷰 요약')), findsOneWidget);
    expect(inHero(find.text(_summary)), findsOneWidget);
    expect(inHero(find.text('혼밥하기 좋아요')), findsOneWidget);
    expect(inHero(find.text('리뷰 12건을 AI가 요약했어요')), findsOneWidget);
  });

  testWidgets('no summary, no box', (tester) async {
    await openHome(
      tester,
      overrides: [
        reviewInsightSourceProvider.overrideWithValue(
          _Insights({'가까운집': const ReviewInsight(reviewCount: 3, signal: 0)}),
        ),
      ],
    );
    expect(find.text('AI 리뷰 요약'), findsNothing);
  });

  testWidgets('a stored review signal moves a place up the ranking (V3)', (
    tester,
  ) async {
    // Without reviews the nearest place leads; a strong R lifts the one ~110 m farther above it.
    await openHome(
      tester,
      overrides: [
        reviewInsightSourceProvider.overrideWithValue(
          _Insights({'중간집': const ReviewInsight(reviewCount: 40, signal: 1)}),
        ),
      ],
    );
    expect(inHero(find.text('중간집')), findsWidgets);
  });
}
