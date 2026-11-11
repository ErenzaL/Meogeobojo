import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../content/widgets/notification_bell.dart';
import '../../university/widgets/university_selector.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Flexible(child: UniversitySelector()),
        const Spacer(),
        const NotificationBell(),
      ],
    );
  }
}

/// Section title row with an optional "더보기 >" action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.icon, this.onMore});

  final String title;
  final IconData? icon;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 22, color: context.palette.accent),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.sectionTitle,
          ),
        ),
        if (onMore != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onMore,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(context.l10n.homeMore, style: AppText.link(context)),
            ),
          ),
      ],
    );
  }
}
