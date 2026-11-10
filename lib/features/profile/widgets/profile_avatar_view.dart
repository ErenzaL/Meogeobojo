import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../models/profile_avatar.dart';

/// A mascot shown as a round profile picture on a soft peach disc.
class ProfileAvatarView extends StatelessWidget {
  const ProfileAvatarView({
    super.key,
    required this.avatar,
    required this.size,
    this.semanticLabel,
  });

  final ProfileAvatar avatar;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(size * 0.08),
          child: Image.asset(
            avatar.asset,
            fit: BoxFit.contain,
            semanticLabel: semanticLabel,
            excludeFromSemantics: semanticLabel == null,
            gaplessPlayback: true,
            // Mascot art is large; decode near the size it is drawn at.
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
          ),
        ),
      ),
    );
  }
}
