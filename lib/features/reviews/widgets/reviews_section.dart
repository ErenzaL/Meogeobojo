import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/widgets/auth_prompt.dart';
import '../../restaurants/models/restaurant.dart';
import '../models/student_review.dart';
import '../providers/review_providers.dart';
import 'report_sheet.dart';
import 'review_editor_sheet.dart';

/// Reviews on the restaurant page: average, the visible reviews, the student's
/// own review with its moderation status, and the buttons to write / report.
class ReviewsSection extends ConsumerWidget {
  const ReviewsSection({super.key, required this.restaurant});

  final Restaurant restaurant;

  static const maxShown = 10;

  Future<void> _write(
    BuildContext context,
    WidgetRef ref,
    StudentReview? mine,
  ) async {
    final ok = await requireAuth(context, ref, reason: AuthReason.contribute);
    if (!ok || !context.mounted) return;
    await showReviewEditorSheet(
      context,
      restaurant: restaurant,
      existing: mine,
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref, String id) async {
    final ok = await requireAuth(context, ref, reason: AuthReason.contribute);
    if (!ok || !context.mounted) return;
    await showReportSheet(context, reviewId: id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final me = ref.watch(currentUserProvider)?.id;
    final reviews = ref.watch(restaurantReviewsProvider(restaurant.kakaoId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.reviewsTitle, style: AppText.title),
        const SizedBox(height: 6),
        reviews.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => Row(
            children: [
              Expanded(child: Text(l10n.myContribLoadFailed)),
              TextButton(
                onPressed: () => ref.invalidate(
                  restaurantReviewsProvider(restaurant.kakaoId),
                ),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
          data: (all) {
            final summary = ReviewSummary.of(all);
            StudentReview? mine;
            for (final r in all) {
              if (r.userId == me) mine = r;
            }
            final others = [
              for (final r in all)
                if (r.isVisible && r.userId != me) r,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.count > 0)
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 20, color: p.starAmber),
                      const SizedBox(width: 4),
                      Text(
                        l10n.reviewsSummary(
                          summary.average.toStringAsFixed(1),
                          summary.count,
                        ),
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  Text(l10n.reviewsEmpty, style: AppText.caption(context)),
                const SizedBox(height: 8),
                if (mine != null) _MyReviewCard(review: mine),
                for (final r in others.take(maxShown))
                  _ReviewTile(
                    review: r,
                    onReport: () => _report(context, ref, r.id),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _write(context, ref, mine),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    mine == null ? l10n.reviewWrite : l10n.reviewEditMine,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.year}.${l.month.toString().padLeft(2, '0')}.${l.day.toString().padLeft(2, '0')}';
}

class _Stars extends StatelessWidget {
  const _Stars(this.rating);

  final int rating;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 16,
          color: i <= rating
              ? context.palette.starAmber
              : context.palette.textMuted,
        ),
    ],
  );
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review, required this.onReport});

  final StudentReview review;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Stars(review.rating),
              const SizedBox(width: 8),
              Text(
                '${l10n.reviewAuthor} · ${_date(review.createdAt)}',
                style: AppText.caption(context).copyWith(fontSize: 13),
              ),
              const Spacer(),
              TextButton(
                onPressed: onReport,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(l10n.reportAction),
              ),
            ],
          ),
          if (review.body != null) Text(review.body!, style: AppText.body),
        ],
      ),
    );
  }
}

class _MyReviewCard extends StatelessWidget {
  const _MyReviewCard({required this.review});

  final StudentReview review;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final status = switch (review.moderationStatus) {
      'hidden' => l10n.reviewStatusHidden,
      'removed' => l10n.reviewStatusRemoved,
      _ => null,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.reviewMine,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: p.rustText,
                ),
              ),
              const SizedBox(width: 8),
              _Stars(review.rating),
              const SizedBox(width: 8),
              Text(
                _date(review.createdAt),
                style: AppText.caption(context).copyWith(fontSize: 13),
              ),
            ],
          ),
          if (review.body != null) ...[
            const SizedBox(height: 4),
            Text(review.body!, style: AppText.body),
          ],
          if (status != null) ...[
            const SizedBox(height: 4),
            Text(status, style: TextStyle(color: p.statusWarn, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
