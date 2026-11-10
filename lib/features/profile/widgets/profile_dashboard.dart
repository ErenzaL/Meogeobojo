import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../university/models/university.dart';
import '../../university/models/university_display.dart';
import '../models/profile_avatar.dart';
import 'profile_avatar_view.dart';

/// Card surface shared by the MY dashboard cards: card colour, hairline border,
/// card radius and a soft shadow (the page behind is white).
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = BorderRadius.circular(AppRadius.card);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: softCardShadow(p)),
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

/// Top of MY: a large round mascot avatar, the nickname with a pencil, the
/// email and a "꾸미기" button. Tapping the avatar or the button opens the
/// avatar picker; the pencil edits the nickname.
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.nickname,
    required this.email,
    required this.avatar,
    required this.onChangeAvatar,
    required this.onEditNickname,
  });

  final String nickname;
  final String? email;
  final ProfileAvatar avatar;

  /// Null while the profile is not loaded (nowhere to save a picture yet).
  final VoidCallback? onChangeAvatar;

  /// Null while the profile is not loaded (nothing to edit yet).
  final VoidCallback? onEditNickname;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final hasEmail = email != null && email!.isNotEmpty;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Soft peach shapes behind the avatar (decoration only).
        Positioned.fill(
          child: ExcludeSemantics(
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    top: -34,
                    left: -46,
                    child: _Blob(size: 150, color: p.accentSoft),
                  ),
                  Positioned(
                    top: 8,
                    right: -30,
                    child: _Blob(size: 96, color: p.accentSoft),
                  ),
                  Positioned(
                    top: 120,
                    left: 18,
                    child: _Blob(size: 26, color: p.accentSoft),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: l10n.profileAvatarChange,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onChangeAvatar,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: p.card,
                      shape: BoxShape.circle,
                      boxShadow: softCardShadow(p),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ProfileAvatarView(avatar: avatar, size: 112),
                        // A hint that the picture can be tapped to change it.
                        if (onChangeAvatar != null)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: p.rust,
                                shape: BoxShape.circle,
                                border: Border.all(color: p.card, width: 2.5),
                              ),
                              child: Icon(
                                Icons.photo_camera_rounded,
                                size: 16,
                                color: p.onRust,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (onEditNickname != null)
                    IconButton(
                      tooltip: l10n.accountNicknameEdit,
                      onPressed: onEditNickname,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: p.textSecondary,
                      ),
                    ),
                ],
              ),
              // Only shown when the account really has an email (Kakao users
              // may not share one).
              if (hasEmail) ...[
                const SizedBox(height: 2),
                Text(
                  email!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The selected university (the same state Home and the map use). Tapping it
/// opens the existing university selector.
class ProfileCampusCard extends StatelessWidget {
  const ProfileCampusCard({
    super.key,
    required this.university,
    required this.onTap,
  });

  /// Null only while the selection is still loading.
  final University? university;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final u = university;
    final locale = Localizations.localeOf(context);
    final name = u == null
        ? l10n.universityFallbackName
        : u.displayName(locale);
    final city = u?.city;
    final subtitle = city == null
        ? l10n.profileCampusHintNoCity
        : l10n.profileCampusHint(cityLabel(l10n, city));
    return Semantics(
      button: true,
      label: l10n.universitySelectCurrent(name),
      excludeSemantics: true,
      child: _DashboardCard(
        onTap: onTap,
        child: V5Row(
          icon: Icons.school_outlined,
          title: name,
          subtitle: subtitle,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// One statistic. A null [value] means the number is not available (the
/// feature behind it does not exist yet, or a real count is still loading);
/// it is shown as text, never as an invented number.
class ProfileStat {
  const ProfileStat({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final int? value;
  final VoidCallback? onTap;

  /// A real count that has not arrived yet ("–"), as opposed to a feature
  /// that does not exist yet ("준비 중").
  final bool loading;
}

class ProfileStatsCard extends StatelessWidget {
  const ProfileStatsCard({super.key, required this.stats});

  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _DashboardCard(
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                VerticalDivider(width: 1, thickness: 1, color: p.border),
              Expanded(child: _StatCell(stat: stats[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat});

  final ProfileStat stat;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final available = stat.value != null;
    final text = available
        ? '${stat.value}'
        : (stat.loading ? '–' : l10n.profileStatUnavailable);
    return Semantics(
      button: stat.onTap != null,
      label: '${stat.label} $text',
      excludeSemantics: true,
      child: InkWell(
        onTap: stat.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fixed height so labels line up whether the value is a big
              // number or the smaller "준비 중" text.
              SizedBox(
                height: 36,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      style: available
                          ? const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            )
                          : TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.textMuted,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stat.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: p.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
