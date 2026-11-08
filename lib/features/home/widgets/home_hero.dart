import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../university/providers/university_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/rich_text.dart';
import '../../university/models/university_display.dart';
import '../../../core/theme/app_palette.dart';

class HomeHero extends ConsumerWidget {
  const HomeHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final univ = ref.watch(selectedUniversityProvider).value;
    final name =
        univ?.displayName(Localizations.localeOf(context)) ??
        l10n.universityFallbackName;
    return LayoutBuilder(
      builder: (context, c) {
        final mascotW = (c.maxWidth * 0.40).clamp(110.0, 170.0);
        final titleSize = (c.maxWidth * 0.082).clamp(24.0, 32.0);
        final titleStyle = AppText.heroTitle.copyWith(fontSize: titleSize);
        return SizedBox(
          height: mascotW * 0.95,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Decorative circles (shapes, not baked into any image).
              Positioned(
                right: -mascotW * 0.08,
                top: -mascotW * 0.02,
                child: _Circle(
                  size: mascotW * 0.92,
                  color: context.palette.accentSoft,
                ),
              ),
              Positioned(
                right: mascotW * 0.62,
                bottom: mascotW * 0.02,
                child: _Circle(
                  size: mascotW * 0.22,
                  color: AppColors.peach.withValues(alpha: 0.55),
                ),
              ),
              Positioned(
                right: mascotW * 0.02,
                top: 0,
                bottom: 0,
                width: mascotW,
                child: Image.asset(
                  AppAssets.mascotHero,
                  fit: BoxFit.contain,
                  semanticLabel: l10n.mascotSemantics,
                ),
              ),
              Positioned.fill(
                right: mascotW * 0.9,
                // One FittedBox for the whole block: shrinks as a unit if the
                // width or the user's text scale leaves too little room.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: highlightPlaceholder(
                            l10n.homeHeroAround,
                            name,
                            TextStyle(color: context.palette.accent),
                          ),
                        ),
                        style: AppText.title.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(l10n.homeHeroTitle, style: titleStyle),
                      const SizedBox(height: 8),
                      Text(
                        l10n.homeHeroSubtitle,
                        style: AppText.caption(context)
                            .copyWith(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
