import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../restaurants/screens/restaurant_list_screen.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// Typography-led banner. The mascot is intentionally NOT used here: it
/// already appears in the Home hero, and repeating it adds clutter.
class RecommendationBanner extends StatelessWidget {
  const RecommendationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.palette.accentFaint, context.palette.accentSoft],
        ),
      ),
      child: Stack(
        children: [
          // Subtle decorative shapes (pure Flutter, no imagery).
          Positioned(
            right: -44,
            top: -44,
            child: _ring(170, AppColors.peach.withValues(alpha: 0.28)),
          ),
          Positioned(
            right: -10,
            top: -10,
            child: _disc(96, AppColors.peach.withValues(alpha: 0.30)),
          ),
          Positioned(
            right: 36,
            bottom: -28,
            child: _disc(64, AppColors.peach.withValues(alpha: 0.22)),
          ),
          Positioned(
            left: -30,
            bottom: -40,
            child: _disc(100, AppColors.peach.withValues(alpha: 0.18)),
          ),
          Padding(
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
        ],
      ),
    );
  }

  Widget _disc(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _ring(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
    ),
  );
}
