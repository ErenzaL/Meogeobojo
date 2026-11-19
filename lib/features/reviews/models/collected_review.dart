import 'package:flutter/foundation.dart';

import 'student_review.dart';

/// A Naver / Kakao Map / delivery-app review of a place (`collected_reviews`), imported offline and shown read-only.
@immutable
class CollectedReview {
  const CollectedReview({
    required this.platform,
    this.rating,
    this.body,
    this.reviewedOn,
  });

  /// naver | kakao | baemin | coupangeats | yogiyo
  final String platform;

  /// 0.5–5 in half steps; many Naver reviews have none.
  final double? rating;
  final String? body;
  final DateTime? reviewedOn;

  static CollectedReview? fromJson(Map<String, dynamic> j) {
    final platform = j['platform'] as String?;
    if (platform == null) return null;
    final body = (j['body'] as String?)?.trim();
    return CollectedReview(
      platform: platform,
      rating: (j['rating'] as num?)?.toDouble(),
      body: (body == null || body.isEmpty) ? null : body,
      reviewedOn: DateTime.tryParse('${j['reviewed_on']}'),
    );
  }
}

/// Every collected review of a place, from its per-platform rows of `collected_review_stats`.
@immutable
class CollectedReviewSummary {
  const CollectedReviewSummary({
    required this.byPlatform,
    required this.ratedCount,
    required this.ratingSum,
  });

  static const empty = CollectedReviewSummary(
    byPlatform: {},
    ratedCount: 0,
    ratingSum: 0,
  );

  /// Review count per platform, the largest first.
  final Map<String, int> byPlatform;
  final int ratedCount;
  final double ratingSum;

  int get count => byPlatform.values.fold(0, (a, n) => a + n);

  /// Over the reviews that have a rating; null when none has.
  double? get average => ratedCount == 0 ? null : ratingSum / ratedCount;

  static CollectedReviewSummary fromStats(Iterable<Map<String, dynamic>> rows) {
    final counts = <String, int>{};
    var rated = 0;
    var sum = 0.0;
    for (final r in rows) {
      final platform = r['platform'] as String?;
      final n = (r['review_count'] as num?)?.toInt() ?? 0;
      if (platform == null || n <= 0) continue;
      counts[platform] = (counts[platform] ?? 0) + n;
      rated += (r['rated_count'] as num?)?.toInt() ?? 0;
      sum += (r['rating_sum'] as num?)?.toDouble() ?? 0;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return CollectedReviewSummary(
      byPlatform: Map.fromEntries(sorted),
      ratedCount: rated,
      ratingSum: sum,
    );
  }
}

/// The restaurant page's rating line: every review (the students' visible ones and the collected ones) and the
/// average over those with a rating (null when none has).
({int count, double? average}) reviewTotals(
  ReviewSummary students,
  CollectedReviewSummary collected,
) {
  final rated = students.count + collected.ratedCount;
  return (
    count: students.count + collected.count,
    average: rated == 0
        ? null
        : (students.average * students.count + collected.ratingSum) / rated,
  );
}
