import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../models/student_review.dart';
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

/// The signed-in user's reviews (any moderation status). Empty for guests.
final myReviewsProvider = FutureProvider.autoDispose<List<StudentReview>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(reviewRepositoryProvider).mine(user.id);
});
