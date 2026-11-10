import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../models/mission_models.dart';
import '../providers/mission_providers.dart';
import '../widgets/mission_visuals.dart';

/// Every badge the user has earned, plus the point total. Opened from MY.
class BadgeCollectionScreen extends ConsumerWidget {
  const BadgeCollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final dash = ref.watch(missionDashboardProvider).value;
    final badges = dash?.badges ?? const <MissionBadge>[];
    return Scaffold(
      backgroundColor: whitePageColor(context),
      appBar: AppBar(title: Text(l10n.missionBadgeCollectionTitle)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: p.fillMuted,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.missionTotalPoints,
                          style: TextStyle(
                            fontSize: 15,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '${dash?.pointsTotal ?? 0}P',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (badges.isEmpty)
                  V5EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: l10n.missionBadgesNone,
                  )
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 20,
                    children: [
                      for (final b in badges)
                        SizedBox(
                          width: 96,
                          child: Column(
                            children: [
                              BadgeArt(
                                asset: AppAssets.mascotByKey(b.mascot),
                                size: 84,
                                unlocked: true,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                b.name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
