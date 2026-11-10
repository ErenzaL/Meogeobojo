import 'package:flutter/foundation.dart';

/// A student review (`student_reviews`). The public sees only `visible` ones;
/// the author also sees their own hidden / removed review, with its status.
@immutable
class StudentReview {
  const StudentReview({
    required this.id,
    required this.userId,
    required this.kakaoPlaceId,
    required this.rating,
    required this.createdAt,
    this.body,
    this.moderationStatus = 'visible',
  });

  final String id;
  final String userId;
  final String kakaoPlaceId;
  final int rating;
  final String? body;
  final DateTime createdAt;

  /// visible | hidden | removed
  final String moderationStatus;

  bool get isVisible => moderationStatus == 'visible';

  static StudentReview? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final user = j['user_id'] as String?;
    final place = j['kakao_place_id'] as String?;
    final rating = (j['rating'] as num?)?.toInt();
    final created = DateTime.tryParse('${j['created_at']}');
    if (id == null ||
        user == null ||
        place == null ||
        rating == null ||
        rating < 1 ||
        rating > 5 ||
        created == null) {
      return null;
    }
    final body = (j['body'] as String?)?.trim();
    return StudentReview(
      id: id,
      userId: user,
      kakaoPlaceId: place,
      rating: rating,
      body: (body == null || body.isEmpty) ? null : body,
      createdAt: created,
      moderationStatus: (j['moderation_status'] as String?) ?? 'visible',
    );
  }
}

/// Average and count over the VISIBLE reviews only (what other students see).
@immutable
class ReviewSummary {
  const ReviewSummary(this.count, this.average);

  final int count;
  final double average;

  static ReviewSummary of(Iterable<StudentReview> reviews) {
    final visible = reviews.where((r) => r.isVisible).toList();
    if (visible.isEmpty) return const ReviewSummary(0, 0);
    final sum = visible.fold<int>(0, (a, r) => a + r.rating);
    return ReviewSummary(visible.length, sum / visible.length);
  }
}
