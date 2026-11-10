import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_review.dart';

enum ReportOutcome { sent, alreadyReported }

abstract interface class ReviewRepository {
  /// Visible reviews of a place, plus the signed-in user's own (any status):
  /// row-level security returns exactly that.
  Future<List<StudentReview>> forPlace(String kakaoId);

  /// Creates or updates the signed-in user's review of the place (one each).
  Future<void> save({
    required String userId,
    required String kakaoId,
    required String? universityId,
    required int rating,
    required String? body,
  });

  Future<void> delete(String reviewId);

  /// All of the signed-in user's reviews, with their moderation status.
  Future<List<StudentReview>> mine(String userId);

  Future<ReportOutcome> report({
    required String reviewId,
    required String reason,
    String? description,
  });
}

class SupabaseReviewRepository implements ReviewRepository {
  SupabaseReviewRepository(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id,user_id,kakao_place_id,rating,body,created_at,moderation_status';

  @override
  Future<List<StudentReview>> forPlace(String kakaoId) async {
    final rows = await _db
        .from('student_reviews')
        .select(_columns)
        .eq('kakao_place_id', kakaoId)
        .order('created_at', ascending: false)
        .limit(100)
        .timeout(const Duration(seconds: 12));
    return [for (final r in rows) ?StudentReview.fromJson(r)];
  }

  @override
  Future<void> save({
    required String userId,
    required String kakaoId,
    required String? universityId,
    required int rating,
    required String? body,
  }) async {
    final clean = body?.trim();
    final text = (clean == null || clean.isEmpty) ? null : clean;
    // select() so a row hidden by RLS (0 rows) is an error, not a silent no-op.
    final updated = await _db
        .from('student_reviews')
        .update({'rating': rating, 'body': text})
        .eq('user_id', userId)
        .eq('kakao_place_id', kakaoId)
        .select('id')
        .timeout(const Duration(seconds: 15));
    if (updated.isNotEmpty) return;
    await _db
        .from('student_reviews')
        .insert({
          'kakao_place_id': kakaoId,
          'university_id': universityId,
          'rating': rating,
          'body': text,
        })
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> delete(String reviewId) async {
    final rows = await _db
        .from('student_reviews')
        .delete()
        .eq('id', reviewId)
        .select('id')
        .timeout(const Duration(seconds: 15));
    if (rows.isEmpty) {
      throw const PostgrestException(message: 'review not deleted');
    }
  }

  @override
  Future<List<StudentReview>> mine(String userId) async {
    final rows = await _db
        .from('student_reviews')
        .select(_columns)
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 12));
    return [for (final r in rows) ?StudentReview.fromJson(r)];
  }

  @override
  Future<ReportOutcome> report({
    required String reviewId,
    required String reason,
    String? description,
  }) async {
    try {
      await _db
          .from('reports')
          .insert({
            'target_type': 'review',
            'target_id': reviewId,
            'reason': reason,
            'description': description,
          })
          .timeout(const Duration(seconds: 15));
      return ReportOutcome.sent;
    } on PostgrestException catch (e) {
      // The unique index allows one open report per user and review.
      if (e.code == '23505') return ReportOutcome.alreadyReported;
      rethrow;
    }
  }
}
