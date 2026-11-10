import 'package:flutter/material.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../models/mission_models.dart';
import 'mission_visuals.dart';

/// One mission: icon, title, description, reward, progress bar and status.
class MissionCard extends StatelessWidget {
  const MissionCard({super.key, required this.mission, required this.onTap});

  final Mission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final m = mission;
    final done = m.completed;
    final green = missionDoneColor(context);
    final dim = m.state == MissionState.expired;

    final Widget leading = m.isMaster
        ? BadgeArt(
            asset: AppAssets.mascotByKey(m.badgeMascot),
            size: 48,
            unlocked: done,
          )
        : Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: done ? green.withValues(alpha: 0.12) : p.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              done ? Icons.check_rounded : missionIcon(m.icon),
              size: 24,
              color: done ? green : p.accentStrong,
            ),
          );

    final Widget status;
    if (done) {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: green),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              l10n.missionDone,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: green,
              ),
            ),
          ),
        ],
      );
    } else if (m.state == MissionState.expired) {
      status = Text(
        l10n.missionExpired,
        style: TextStyle(fontSize: 13, color: p.textMuted),
      );
    } else if (m.state == MissionState.upcoming) {
      status = Text(
        l10n.missionUpcoming,
        style: TextStyle(fontSize: 13, color: p.textMuted),
      );
    } else if (m.isMaster) {
      status = Text(
        l10n.missionBadgeReward,
        textAlign: TextAlign.end,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: p.accentStrong,
        ),
      );
    } else {
      status = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: p.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '+${m.rewardPoints}P',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: p.accentStrong,
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label:
          '${m.title}, ${progressText(m)}${done ? ', ${l10n.missionDone}' : ''}',
      excludeSemantics: true,
      child: Opacity(
        opacity: dim ? 0.6 : 1,
        child: DecoratedBox(
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
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((m.description ?? '').isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              m.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _Bar(
                                  value: m.fraction,
                                  color: done ? green : p.accent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                progressText(m),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Long labels ("Limited badge") wrap instead of pushing the row.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 88),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: status,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => LinearProgressIndicator(
        value: v,
        minHeight: 7,
        color: color,
        backgroundColor: context.palette.fillMuted,
      ),
    ),
  );
}
