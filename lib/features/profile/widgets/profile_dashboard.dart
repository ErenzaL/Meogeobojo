import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../university/models/university.dart';
import '../../university/models/university_display.dart';

/// Hairline-bordered card surface shared by the MY dashboard cards, matching
/// the existing menu groups (card colour, subtle border, card radius).
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child, this.borderColor, this.onTap});

  final Widget child;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = BorderRadius.circular(AppRadius.card);
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: borderColor ?? p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

/// "안녕하세요, {닉네임}님" with the saved nickname. Mostly white: only the
/// outline is a soft orange.
class ProfileGreetingCard extends StatelessWidget {
  const ProfileGreetingCard({
    super.key,
    required this.nickname,
    required this.email,
    required this.avatar,
    required this.onEditProfile,
  });

  final String nickname;
  final String? email;
  final Widget avatar;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final hasEmail = email != null && email!.isNotEmpty;
    return _DashboardCard(
      borderColor: p.accent.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.profileGreeting(nickname),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.profileGreetingSub,
                        style: AppText.caption(context).copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            Row(
              children: [
                // Only shown when the account really has an email (Kakao
                // users may not share one).
                if (hasEmail)
                  Expanded(
                    flex: 2,
                    child: Text(
                      email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(context).copyWith(fontSize: 12.5),
                    ),
                  )
                else
                  const Spacer(),
                Flexible(
                  child: TextButton(
                    onPressed: onEditProfile,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: p.accentStrong,
                    ),
                    child: Text(
                      l10n.profileEditProfile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
    final p = context.palette;
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.school_outlined, color: p.accentStrong),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title.copyWith(fontSize: 15.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(context)
                            .copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.placeholderIcon),
              ],
            ),
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fixed height so labels line up whether the value is a big
              // number or the smaller "준비 중" text.
              SizedBox(
                height: 28,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      stat.icon,
                      size: 16,
                      color: available ? p.accentStrong : p.placeholderIcon,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          text,
                          style: available
                              ? AppText.title.copyWith(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                )
                              : AppText.caption(context).copyWith(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stat.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption(context).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
