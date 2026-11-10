import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../models/mission_models.dart';

/// Icon for a mission's `icon` key (a closed list; unknown keys get a star).
IconData missionIcon(String key) => switch (key) {
  'sparkle' => Icons.auto_awesome_rounded,
  'favorite' => Icons.favorite_border_rounded,
  'review' => Icons.rate_review_outlined,
  'photo' => Icons.photo_camera_outlined,
  'category' => Icons.explore_outlined,
  'value' => Icons.savings_outlined,
  'fix' => Icons.edit_note_rounded,
  'trophy' => Icons.emoji_events_outlined,
  _ => Icons.star_border_rounded,
};

/// Success green used for checkmarks (the palette's "open now" green).
Color missionDoneColor(BuildContext context) => context.palette.statusOpen;

const _grey = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// A mascot shown as an achievement: in colour when earned, grey and faded
/// while still locked. Uses the existing artwork only.
class BadgeArt extends StatelessWidget {
  const BadgeArt({
    super.key,
    required this.asset,
    required this.size,
    required this.unlocked,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final bool unlocked;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final image = Image.asset(
      asset,
      fit: BoxFit.contain,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unlocked ? p.accentSoft : p.fillMuted,
        border: Border.all(color: unlocked ? p.accent : p.border, width: 1.5),
      ),
      child: unlocked
          ? image
          : ColorFiltered(
              colorFilter: _grey,
              child: Opacity(opacity: 0.45, child: image),
            ),
    );
  }
}

/// Shown next to a mission's progress: "2/5", capped at the target.
String progressText(Mission m) =>
    '${m.progress.clamp(0, m.target)}/${m.target}';
