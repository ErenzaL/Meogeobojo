import 'package:flutter/foundation.dart';

/// A review (`student_reviews`): written by a student in the app, or imported by an administrator from a CSV
/// (Kakao, Naver, delivery apps). Both live in the same table, so every screen reads one list.
/// The public sees only `visible` ones; the author also sees their own hidden / removed review, with its status.
@immutable
class StudentReview {
  const StudentReview({
    required this.id,
    required this.userId,
    required this.kakaoPlaceId,
    required this.createdAt,
    this.rating,
    this.body,
    this.moderationStatus = 'visible',
    this.source = appSource,
    this.platform,
  });

  /// `source` of a review a student wrote in the app (the others are imported).
  static const appSource = 'app';

  final String id;

  /// The author. Null for an imported review: nobody's account is behind it.
  final String? userId;
  final String kakaoPlaceId;

  /// Whole stars 1..5. Null for an imported review that has text only (many Naver reviews).
  final int? rating;
  final String? body;
  final DateTime createdAt;

  /// visible | hidden | removed
  final String moderationStatus;

  /// `app`, or where an imported review came from (`kakao`, `naver`, `lemong`, ...).
  final String source;

  /// For an imported review, the delivery app it was written on (`BAEMIN`, `CPEATS`, `YOGIYO`, `NAVER`).
  final String? platform;

  bool get isVisible => moderationStatus == 'visible';
  bool get isImported => source != appSource;

  /// Whether [uid] wrote this review. A guest (null) wrote nothing, and an imported review has no author, so the two
  /// never match each other.
  bool isMadeBy(String? uid) => uid != null && userId == uid;

  static StudentReview? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final user = j['user_id'] as String?;
    final place = j['kakao_place_id'] as String?;
    final rating = (j['rating'] as num?)?.toInt();
    final created = DateTime.tryParse('${j['created_at']}');
    final source = (j['source'] as String?) ?? appSource;
    final body = (j['body'] as String?)?.trim();
    final text = (body == null || body.isEmpty) ? null : body;
    final imported = source != appSource;
    if (id == null ||
        place == null ||
        created == null ||
        // a rating that is there must be a real one
        (rating != null && (rating < 1 || rating > 5)) ||
        // a student's review has an author and a rating; an imported one needs a rating or some text
        (!imported && (user == null || rating == null)) ||
        (imported && rating == null && text == null)) {
      return null;
    }
    final platform = (j['platform'] as String?)?.trim();
    return StudentReview(
      id: id,
      userId: user,
      kakaoPlaceId: place,
      rating: rating,
      body: text,
      createdAt: created,
      moderationStatus: (j['moderation_status'] as String?) ?? 'visible',
      source: source,
      platform: (platform == null || platform.isEmpty) ? null : platform,
    );
  }
}

/// Count and average over the VISIBLE reviews only (what other students see). [count] is every visible review, with or
/// without stars; [average] is taken over the ones that have a rating ([ratedCount]).
@immutable
class ReviewSummary {
  const ReviewSummary(this.count, this.average, {int? ratedCount})
    : ratedCount = ratedCount ?? count;

  final int count;
  final double average;
  final int ratedCount;

  static ReviewSummary of(Iterable<StudentReview> reviews) {
    final visible = reviews.where((r) => r.isVisible).toList();
    if (visible.isEmpty) return const ReviewSummary(0, 0);
    final rated = [
      for (final r in visible)
        if (r.rating != null) r.rating!,
    ];
    final sum = rated.fold<int>(0, (a, r) => a + r);
    return ReviewSummary(
      visible.length,
      rated.isEmpty ? 0 : sum / rated.length,
      ratedCount: rated.length,
    );
  }
}
