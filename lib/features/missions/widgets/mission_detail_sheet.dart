import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mission_models.dart';
import 'mission_actions.dart';
import 'mission_visuals.dart';

/// Bottom sheet for one mission: what it asks, how far along the user is, the
/// reward, when it resets, and a button into the matching feature.
Future<void> showMissionDetailSheet(
  BuildContext context,
  WidgetRef ref,
  Mission mission,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.palette.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
  ),
  builder: (sheetContext) => _MissionSheet(
    mission: mission,
    onAction: () {
      Navigator.of(sheetContext).pop();
      runMissionAction(context, ref, mission.action);
    },
  ),
);

class _MissionSheet extends StatelessWidget {
  const _MissionSheet({required this.mission, required this.onAction});

  final Mission mission;
  final VoidCallback onAction;

  String _period(BuildContext context) {
    final l10n = context.l10n;
    switch (mission.recurrence) {
      case 'daily':
        return l10n.missionResetsDaily;
      case 'weekly':
        return l10n.missionResetsWeekly;
    }
    final end = mission.endsAt;
    if (end == null) return l10n.missionAlwaysOn;
    return l10n.missionUntil(
      formatSeoulDate(end.subtract(const Duration(seconds: 1))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final m = mission;
    final green = missionDoneColor(context);
    final actionLabel = missionActionLabel(l10n, m.action);
    // An action on a finished or closed mission would not change anything.
    final showAction =
        actionLabel != null && m.state == MissionState.active && !m.completed;

    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: p.textSecondary),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (m.isMaster)
                      BadgeArt(
                        asset: AppAssets.mascotByKey(m.badgeMascot),
                        size: 52,
                        unlocked: m.completed,
                      )
                    else
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: m.completed
                              ? green.withValues(alpha: 0.12)
                              : p.accentSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          m.completed
                              ? Icons.check_rounded
                              : missionIcon(m.icon),
                          size: 26,
                          color: m.completed ? green : p.accentStrong,
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        m.title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: p.border),
                if ((m.description ?? '').isNotEmpty)
                  row(
                    l10n.missionDetailRequirement,
                    Text(
                      m.description!,
                      style: const TextStyle(fontSize: 15, height: 1.45),
                    ),
                  ),
                row(
                  l10n.missionDetailProgress,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: m.fraction,
                                minHeight: 8,
                                color: m.completed ? green : p.accent,
                                backgroundColor: p.fillMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            progressText(m),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (m.completed) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.missionDone,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                row(
                  l10n.missionDetailReward,
                  Text(
                    m.isMaster
                        ? (m.badgeName ?? l10n.missionBadgeReward)
                        : '+${m.rewardPoints}P',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.accentStrong,
                    ),
                  ),
                ),
                row(
                  l10n.missionDetailPeriod,
                  Text(_period(context), style: const TextStyle(fontSize: 15)),
                ),
                if (m.state == MissionState.expired)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.missionExpired,
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                  ),
                const SizedBox(height: 14),
                if (showAction)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
