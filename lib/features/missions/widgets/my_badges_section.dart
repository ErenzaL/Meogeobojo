import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../providers/mission_providers.dart';
import '../screens/badge_collection_screen.dart';
import 'mission_visuals.dart';

/// "내 뱃지" on MY: the badges earned from missions and a way into the full
/// collection. Nothing is shown as earned unless the server says so.
class MyBadgesSection extends ConsumerWidget {
  const MyBadgesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final badges =
        ref.watch(missionDashboardProvider).value?.badges ?? const [];
    void openAll() => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BadgeCollectionScreen()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V5SectionTitle(
          l10n.missionMyBadges,
          actionLabel: l10n.missionBadgesAll,
          onAction: openAll,
          actionColor: p.accentStrong,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: softCardShadow(p),
          ),
          child: Material(
            color: p.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: p.border),
            ),
            child: InkWell(
              onTap: openAll,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: badges.isEmpty
                    ? Row(
                        children: [
                          Icon(Icons.emoji_events_outlined, color: p.textMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.missionBadgesNone,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final b in badges) ...[
                              Tooltip(
                                message: b.name,
                                child: BadgeArt(
                                  asset: AppAssets.mascotByKey(b.mascot),
                                  size: 56,
                                  unlocked: true,
                                  semanticLabel: b.name,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
