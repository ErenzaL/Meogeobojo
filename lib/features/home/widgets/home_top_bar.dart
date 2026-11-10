import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/theme_controller.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../university/models/university_display.dart';
import '../../university/providers/university_providers.dart';
import '../../university/widgets/university_sheet.dart';

/// Home header (phones): the selected university (opens the university
/// sheet) on the left; notifications, theme and profile on the right.
class HomeTopBar extends ConsumerWidget {
  const HomeTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        const Expanded(child: _UniversityButton()),
        // No unread-count badge: notifications are not implemented yet, and a
        // fake count would be misleading.
        _BarIcon(
          icon: Icons.notifications_none_rounded,
          tooltip: l10n.homeNotificationsLabel,
          onTap: () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(l10n.homeNotificationsSoon))),
        ),
        _BarIcon(
          icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          tooltip: dark ? l10n.themeLight : l10n.themeDark,
          onTap: () => ref
              .read(themeModeProvider.notifier)
              .select(dark ? ThemeMode.light : ThemeMode.dark),
        ),
        _BarIcon(
          icon: Icons.person_outline_rounded,
          tooltip: l10n.homeProfileTooltip,
          onTap: () =>
              ref.read(shellTabProvider.notifier).select(ShellTabs.profile),
        ),
      ],
    );
  }
}

/// "📍 순천향대학교 ⌄": plain text button, no pill.
class _UniversityButton extends ConsumerWidget {
  const _UniversityButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final selected = ref.watch(selectedUniversityProvider);
    final name =
        selected.value?.displayName(Localizations.localeOf(context)) ??
        l10n.universitySelect;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: l10n.universitySelectCurrent(name),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showUniversitySheet(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place_outlined, size: 22, color: p.textSecondary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 24,
                    color: p.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(icon, size: 24),
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
  );
}
