import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';

String themeModeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
  ThemeMode.light => l10n.themeLight,
  ThemeMode.dark => l10n.themeDark,
  ThemeMode.system => l10n.themeSystem,
};

IconData themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.light => Icons.light_mode_rounded,
  ThemeMode.dark => Icons.dark_mode_rounded,
  ThemeMode.system => Icons.phone_iphone_rounded,
};

/// MY → 앱 설정 → 화면 테마. Light / Dark / System, applied immediately and
/// stored locally, so it works for guests and without a network.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  // Light, Dark, then System Default last.
  static const _order = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.themeTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          for (final mode in _order)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ThemeOption(
                mode: mode,
                label: themeModeLabel(l10n, mode),
                selected: mode == current,
                onTap: () => ref.read(themeModeProvider.notifier).select(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? p.accentSoft : p.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected ? p.accent : p.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  themeModeIcon(mode),
                  color: selected ? p.accentStrong : p.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.title.copyWith(
                      fontSize: 15.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? p.accent : p.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
