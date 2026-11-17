import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import 'providers/ranking_providers.dart';

/// "AI 리뷰 요약": the AI-written summary of a place's collected reviews, with its repeated points and how many reviews
/// it was made from. Nothing at all when the place has no summary.
class AiReviewSummary extends ConsumerWidget {
  const AiReviewSummary({super.key, required this.kakaoId, this.topGap = 0});

  final String kakaoId;

  /// Space above the box, only when it is shown.
  final double topGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(reviewInsightsProvider).value?[kakaoId];
    final summary = insight?.summary;
    if (insight == null || summary == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final p = context.palette;
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.accentFaint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: p.rustText),
              const SizedBox(width: 6),
              Text(
                l10n.aiReviewTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: p.rustText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(summary, style: AppText.body.copyWith(fontSize: 14.5)),
          if (insight.highlights.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final h in insight.highlights)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(h, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.aiReviewSource(insight.reviewCount),
            style: AppText.caption(context).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: box,
    );
  }
}
