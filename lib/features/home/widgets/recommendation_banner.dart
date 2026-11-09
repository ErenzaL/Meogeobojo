import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../restaurants/screens/restaurant_list_screen.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// Typography-led banner on a single flat color (no decorative shapes). The
/// mascot is intentionally NOT used here: it already appears in the Home hero,
/// and repeating it adds clutter.
class RecommendationBanner extends StatelessWidget {
  const RecommendationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: context.palette.accentSoft,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: context.palette.accent,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    context.l10n.homeBannerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.palette.accentStrong,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.homeBannerTitle,
                style: AppText.heroTitle.copyWith(fontSize: 26),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.homeBannerSubtitle,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecommendationScreen(),
                ),
              ),
              child: Text(context.l10n.homeBannerCta),
            ),
          ],
        ),
      ),
    );
  }
}
