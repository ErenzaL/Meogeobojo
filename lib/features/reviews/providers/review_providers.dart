import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../models/collected_review.dart';
import '../models/student_review.dart';
import '../repositories/collected_review_repository.dart';
import '../repositories/review_repository.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => SupabaseReviewRepository(Supabase.instance.client),
);

/// Reviews of one place (visible ones, plus the signed-in user's own).
final restaurantReviewsProvider = FutureProvider.autoDispose
    .family<List<StudentReview>, String>((ref, kakaoId) {
      // A different account sees a different "own" set.
      ref.watch(currentUserProvider);
      return ref.watch(reviewRepositoryProvider).forPlace(kakaoId);
    });

final collectedReviewRepositoryProvider = Provider<CollectedReviewRepository>(
  (ref) => SupabaseCollectedReviewRepository(Supabase.instance.client),
);

/// Count, rated count and rating sum of a place's collected reviews.
final collectedReviewSummaryProvider = FutureProvider.autoDispose
    .family<CollectedReviewSummary, String>(
      (ref, kakaoId) =>
          ref.watch(collectedReviewRepositoryProvider).summary(kakaoId),
    );

/// The newest collected reviews of a place that have text.
final collectedReviewsProvider = FutureProvider.autoDispose
    .family<List<CollectedReview>, String>(
      (ref, kakaoId) =>
          ref.watch(collectedReviewRepositoryProvider).latest(kakaoId),
    );

/// The signed-in user's reviews (any moderation status). Empty for guests.
final myReviewsProvider = FutureProvider.autoDispose<List<StudentReview>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(reviewRepositoryProvider).mine(user.id);
});
