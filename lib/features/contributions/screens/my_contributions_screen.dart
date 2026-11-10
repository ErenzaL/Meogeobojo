import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../reviews/models/student_review.dart';
import '../../reviews/providers/review_providers.dart';
import '../models/contribution.dart';
import '../providers/contribution_providers.dart';

/// "내 리뷰·사진": everything the student submitted and where it stands
/// (in review / published / not published, with the moderator's reason).
class MyContributionsScreen extends ConsumerWidget {
  const MyContributionsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(myReviewsProvider);
    ref.invalidate(myContributionsProvider);
    await Future.wait([
      ref.read(myReviewsProvider.future),
      ref.read(myContributionsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final reviews = ref.watch(myReviewsProvider);
    final photos = ref.watch(myContributionsProvider);
    final failed = reviews.hasError || photos.hasError;
    final loading = reviews.isLoading || photos.isLoading;
    final rv = reviews.value ?? const <StudentReview>[];
    final ph = photos.value ?? const <Contribution>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myContribTitle)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.screenH),
          children: [
            if (loading && rv.isEmpty && ph.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (failed)
              Row(
                children: [
                  Expanded(child: Text(l10n.myContribLoadFailed)),
                  TextButton(
                    onPressed: () => _refresh(ref),
                    child: Text(l10n.commonRetry),
                  ),
                ],
              )
            else if (rv.isEmpty && ph.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  l10n.myContribEmpty,
                  textAlign: TextAlign.center,
                  style: AppText.caption(context),
                ),
              ),
            if (rv.isNotEmpty) ...[
              Text(l10n.myContribReviews, style: AppText.title),
              const SizedBox(height: 8),
              for (final r in rv) _ReviewRow(review: r),
              const SizedBox(height: 20),
            ],
            if (ph.isNotEmpty) ...[
              Text(l10n.myContribPhotos, style: AppText.title),
              const SizedBox(height: 8),
              for (final c in ph) _PhotoRow(contribution: c),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});

  final StudentReview review;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final (label, color) = switch (review.moderationStatus) {
      'hidden' => (l10n.reviewStatusHidden, p.statusWarn),
      'removed' => (l10n.reviewStatusRemoved, p.statusWarn),
      _ => (l10n.reviewStatusVisible, p.statusOpen),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, size: 18, color: p.starAmber),
                Text(' ${review.rating}'),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _StatusPill(label, color),
                  ),
                ),
              ],
            ),
            if (review.body != null) ...[
              const SizedBox(height: 4),
              Text(review.body!),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoRow extends ConsumerWidget {
  const _PhotoRow({required this.contribution});

  final Contribution contribution;

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.contribWithdrawConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.contribWithdraw),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(contributionRepositoryProvider).withdraw(contribution);
      ref.invalidate(myContributionsProvider);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.contribWithdrawn)));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.photoFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final c = contribution;
    final (label, color) = switch (c.status) {
      'approved' => (l10n.contribStatusApproved, p.statusOpen),
      'rejected' => (l10n.contribStatusRejected, p.statusWarn),
      _ => (l10n.contribStatusPending, p.textSecondary),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_outlined, size: 18, color: p.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    c.kind == ContributionKind.menuPhoto
                        ? l10n.photoKindMenu
                        : l10n.photoKindRestaurant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _StatusPill(label, color),
                  ),
                ),
              ],
            ),
            if (c.caption != null) ...[
              const SizedBox(height: 4),
              Text(c.caption!),
            ],
            if (c.status == 'rejected' && c.reviewNote != null) ...[
              const SizedBox(height: 4),
              Text(
                l10n.contribRejectedReason(c.reviewNote!),
                style: AppText.caption(context).copyWith(fontSize: 13),
              ),
            ],
            if (c.isPending)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _withdraw(context, ref),
                  child: Text(l10n.contribWithdraw),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
