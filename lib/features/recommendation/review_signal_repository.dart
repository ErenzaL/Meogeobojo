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
