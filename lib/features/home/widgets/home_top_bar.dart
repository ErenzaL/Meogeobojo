import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/theme_controller.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../preferences/restart_onboarding.dart';
import '../../search/screens/search_screen.dart';

/// Wordmark on the left; search, start over, dark mode and profile on the
/// right.
class HomeTopBar extends ConsumerWidget {
  const HomeTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: p.rust, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '먹어보조', // the brand name is never translated
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        _BarIcon(
          icon: Icons.search_rounded,
          tooltip: l10n.homeSearchLabel,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
        ),
        _BarIcon(
          icon: Icons.refresh_rounded,
          tooltip: l10n.homeRestartTooltip,
          onTap: () => restartOnboarding(context, ref),
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
