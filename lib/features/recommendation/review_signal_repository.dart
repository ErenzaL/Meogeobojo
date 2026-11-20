import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'recommendation_score.dart';

/// The visible student reviews the review signal R is computed from: (place id, stars, when).
abstract interface class ReviewSignalSource {
  Future<List<({String placeId, ReviewSample sample})>> visibleReviews();
}

/// Reads one page of ratings: rows [from] .. [from] + page - 1, in the stable order. Overridable in tests.
typedef ReviewPageReader = Future<List<Map<String, dynamic>>> Function(int from);

class SupabaseReviewSignalSource implements ReviewSignalSource {
  SupabaseReviewSignalSource(this._db, {this.pageReader});

  final SupabaseClient Function() _db;
  final ReviewPageReader? pageReader;

  /// Rows per request, and how many requests are sent at once. Imported reviews make this table large (thousands of
  /// ratings), and one request returns at most [pageSize] rows, so the ratings are read page by page, a few at a time.
  static const pageSize = 1000;
  static const _parallel = 4;
  static const _maxRows = 30000;

  /// A failure (offline, table missing) means "no review signal": the ranking then uses preference and distance only.
  @override
  Future<List<({String placeId, ReviewSample sample})>> visibleReviews() async {
    try {
      final rows = <Map<String, dynamic>>[];
      for (var wave = 0; rows.length < _maxRows; wave++) {
        final pages = await Future.wait([
          for (var i = 0; i < _parallel; i++)
            (pageReader ?? _read)((wave * _parallel + i) * pageSize),
        ]);
        for (final p in pages) {
          rows.addAll(p);
        }
        if (pages.any((p) => p.length < pageSize)) break;
      }
      final out = <({String placeId, ReviewSample sample})>[];
      for (final r in rows) {
        final id = r['kakao_place_id'] as String?;
        final rating = (r['rating'] as num?)?.toInt();
        final at = DateTime.tryParse('${r['created_at']}');
        // reviews without stars (text-only imports) carry no rating signal
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

  Future<List<Map<String, dynamic>>> _read(int from) async {
    final rows = await _db()
        .from('student_reviews')
        .select('kakao_place_id,rating,created_at')
        .eq('moderation_status', 'visible')
        .not('rating', 'is', null)
        // a stable order, so no row is skipped or read twice between pages
        .order('created_at', ascending: false)
        .order('id')
        .range(from, from + pageSize - 1)
        .timeout(const Duration(seconds: 15));
    return [for (final r in rows) Map<String, dynamic>.from(r)];
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
