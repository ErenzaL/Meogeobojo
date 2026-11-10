import 'package:flutter/material.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mission_models.dart';

/// Seasonal banner: title, subtitle, period and a mascot pose. Everything
/// comes from the campaign, so a new month only needs new data (title, theme
/// colour, mascot key) - no code.
class CampaignBanner extends StatelessWidget {
  const CampaignBanner({super.key, required this.campaign});

  final MissionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = campaign.themeColor ?? p.accent;
    final subtitle = campaign.subtitle;
    return Semantics(
      container: true,
      label: '${campaign.title}, ${campaign.periodLabel}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card + 4),
          border: Border.all(color: c.withValues(alpha: 0.28)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.withValues(alpha: 0.16), c.withValues(alpha: 0.05)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: p.card.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      campaign.periodLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Image.asset(
              AppAssets.mascotByKey(campaign.bannerMascot),
              width: 104,
              height: 104,
              fit: BoxFit.contain,
              cacheWidth: 312,
              excludeFromSemantics: true,
            ),
          ],
        ),
      ),
    );
  }
}
