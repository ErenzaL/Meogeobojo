import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collected_review.dart';

/// Read-only access to the collected Naver / Kakao Map / delivery-app reviews (migration 20261128000100).
abstract interface class CollectedReviewRepository {
  Future<CollectedReviewSummary> summary(String kakaoId);

  /// The newest reviews of a place that have text.
  Future<List<CollectedReview>> latest(String kakaoId);
}

class SupabaseCollectedReviewRepository implements CollectedReviewRepository {
  SupabaseCollectedReviewRepository(this._db);

  final SupabaseClient _db;

  // ponytail: the newest 100 only; page with .range() if older ones are ever wanted.
  static const latestLimit = 100;

  @override
  Future<CollectedReviewSummary> summary(String kakaoId) async {
    final rows = await _db
        .from('collected_review_stats')
        .select('platform,review_count,rated_count,rating_sum')
        .eq('kakao_place_id', kakaoId)
        .timeout(const Duration(seconds: 12));
    return CollectedReviewSummary.fromStats(rows);
  }

  @override
  Future<List<CollectedReview>> latest(String kakaoId) async {
    final rows = await _db
        .from('collected_reviews')
        .select('platform,rating,body,reviewed_on')
        .eq('kakao_place_id', kakaoId)
        .not('body', 'is', null)
        .order('reviewed_on', ascending: false, nullsFirst: false)
        .limit(latestLimit)
        .timeout(const Duration(seconds: 12));
    return [for (final r in rows) ?CollectedReview.fromJson(r)];
  }
}
