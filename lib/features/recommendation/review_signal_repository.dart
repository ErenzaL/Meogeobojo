import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'recommendation_score.dart';

/// The visible student reviews the review signal R is computed from: (place id, stars, when).
abstract interface class ReviewSignalSource {
  Future<List<({String placeId, ReviewSample sample})>> visibleReviews();
}

class SupabaseReviewSignalSource implements ReviewSignalSource {
  SupabaseReviewSignalSource(this._db);

  final SupabaseClient Function() _db;

  /// A failure (offline, table missing) means "no review signal": the ranking then uses preference and distance only.
  @override
  Future<List<({String placeId, ReviewSample sample})>> visibleReviews() async {
    try {
      final rows = await _db()
          .from('student_reviews')
          .select('kakao_place_id,rating,created_at')
          .eq('moderation_status', 'visible')
          .order('created_at', ascending: false)
          .limit(5000)
          .timeout(const Duration(seconds: 10));
      final out = <({String placeId, ReviewSample sample})>[];
      for (final r in rows) {
        final id = r['kakao_place_id'] as String?;
        final rating = (r['rating'] as num?)?.toInt();
        final at = DateTime.tryParse('${r['created_at']}');
        if (id == null ||
            rating == null ||
            rating < 1 ||
            rating > 5 ||
            at == null) {
          continue;
        }
        out.add((placeId: id, sample: ReviewSample(rating: rating, at: at)));
      }
      return out;
    } catch (e) {
      debugPrint('review signal unavailable: ${e.runtimeType}');
      return const [];
    }
  }
}

/// R per place id, from [reviews]. The overall average is taken over every review given. Places without reviews are
/// left out (their R is 0).
Map<String, double> reviewSignalsFrom(
  List<({String placeId, ReviewSample sample})> reviews,
  DateTime now,
) {
  if (reviews.isEmpty) return const {};
  final overall =
      reviews.fold<double>(0, (s, r) => s + r.sample.rating) / reviews.length;
  final byPlace = <String, List<ReviewSample>>{};
  for (final r in reviews) {
    (byPlace[r.placeId] ??= []).add(r.sample);
  }
  return {
    for (final e in byPlace.entries)
      e.key: reviewSignal(reviews: e.value, now: now, overallRating: overall),
  };
}

/// One place's stored review insight (`restaurant_review_insights`): R and the AI review summary, generated offline
/// by scripts/review_insights from the collected reviews.
class ReviewInsight {
  const ReviewInsight({
    required this.reviewCount,
    required this.signal,
    this.summary,
    this.highlights = const [],
  });

  final int reviewCount;

  /// R, -1..1.
  final double signal;

  /// The AI-written summary (Korean). Null when the place has a signal but no summary.
  final String? summary;
  final List<String> highlights;
}

/// The visible review insights per Kakao place id.
abstract interface class ReviewInsightSource {
  Future<Map<String, ReviewInsight>> visibleInsights();
}

class SupabaseReviewInsightSource implements ReviewInsightSource {
  SupabaseReviewInsightSource(this._db);

  final SupabaseClient Function() _db;

  /// A failure (offline, table not migrated yet) means "no insights": nothing is shown and R falls back to 0.
  @override
  Future<Map<String, ReviewInsight>> visibleInsights() async {
    try {
      final rows = await _db()
          .from('restaurant_review_insights')
          .select(
            'kakao_place_id,review_count,review_signal,summary_ko,highlights',
          )
          .timeout(const Duration(seconds: 10));
      return {
        for (final r in rows)
          if (r['kakao_place_id'] is String)
            r['kakao_place_id'] as String: ReviewInsight(
              reviewCount: (r['review_count'] as num?)?.toInt() ?? 0,
              signal: ((r['review_signal'] as num?)?.toDouble() ?? 0).clamp(
                -1.0,
                1.0,
              ),
              summary: (r['summary_ko'] as String?)?.trim().isEmpty ?? true
                  ? null
                  : (r['summary_ko'] as String).trim(),
              highlights: [
                for (final h in (r['highlights'] as List?) ?? const [])
                  if (h is String && h.trim().isNotEmpty) h.trim(),
              ],
            ),
      };
    } catch (e) {
      debugPrint('review insights unavailable: ${e.runtimeType}');
      return const {};
    }
  }
}

/// R per place: the app's own student reviews when a place has any, otherwise the stored insight's R.
Map<String, double> mergeReviewSignals(
  Map<String, double> fromStudentReviews,
  Map<String, ReviewInsight> insights,
) => {
  for (final e in insights.entries) e.key: e.value.signal,
  ...fromStudentReviews,
};
