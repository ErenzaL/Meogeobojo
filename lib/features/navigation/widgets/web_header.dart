import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_language.dart';
import '../../../core/l10n/language_controller.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/theme_controller.dart';
import '../../content/widgets/notification_bell.dart';
import '../../search/screens/search_screen.dart';
import '../../../core/widgets/responsive.dart';
import '../providers/shell_tab_provider.dart';

/// Desktop header (V5 `.whead`): brand, tabs with an underline on the active
/// one, search, start over, language, theme and account. Shown instead of the
/// bottom bar when the window is wide.
class WebHeader extends ConsumerWidget {
  const WebHeader({super.key});

  static const height = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final index = ref.watch(shellTabProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tabs = <(int, String)>[
      (ShellTabs.home, l10n.navHome),
      (ShellTabs.map, l10n.navMap),
      (ShellTabs.community, l10n.navCommunity),
      (ShellTabs.missions, l10n.navMissions),
      (ShellTabs.profile, l10n.navProfile),
    ];

    // The header is chrome: it keeps its size when the system text scale is
    // large, and drops labels to icons when the window is narrow.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Container(
        height: height,
        // aligned with the page content below: the same gutter as the pages (24 / 28 / 40)
        padding: EdgeInsets.symmetric(
          horizontal: WebLayout.gutterOf(context, phone: 24),
        ),
        decoration: BoxDecoration(
          color: p.card,
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: LayoutBuilder(
          builder: (context, box) =>
              _row(context, ref, box.maxWidth, tabs, index, dark),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    double width,
    List<(int, String)> tabs,
    int index,
    bool dark,
  ) {
    final l10n = context.l10n;
    final p = context.palette;
    // English / Chinese tab and button labels are wider than Korean, so they
    // collapse the secondary controls to icons sooner.
    final korean = Localizations.localeOf(context).languageCode == 'ko';
    final compact = width < (korean ? 1120 : 1320);
    return Builder(
      builder: (context) => Row(
        children: [
          InkWell(
            onTap: () =>
                ref.read(shellTabProvider.notifier).select(ShellTabs.home),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: p.rust,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '먹어보조', // the brand name is never translated
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          // The tab strip takes the room that is left and scrolls sideways if enlarged text or a long language does
          // not fit, so the header can never overflow.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, label) in tabs)
                      _Tab(
                        label: label,
                        selected: i == index,
                        onTap: () =>
                            ref.read(shellTabProvider.notifier).select(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (compact)
            IconButton(
              tooltip: l10n.homeSearchLabel,
              onPressed: () => _openSearch(context),
              icon: const Icon(Icons.search_rounded),
            )
          else
            // A fixed-width pill (not a Flexible one): the tab strip takes ALL the free space, so the controls on the right
            // end exactly at the right gutter however wide the window is.
            SizedBox(
              width: width >= 1600 ? 420 : 360,
              child: _SearchPill(
                hint: l10n.searchHint,
                onTap: () => _openSearch(context),
              ),
            ),
          const SizedBox(width: 8),
          const SizedBox(width: 12),
          const _LanguageSwitch(),
          const SizedBox(width: 8),
          const NotificationBell(),
          IconButton(
            tooltip: dark ? l10n.themeLight : l10n.themeDark,
            onPressed: () => ref
                .read(themeModeProvider.notifier)
                .select(dark ? ThemeMode.light : ThemeMode.dark),
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          IconButton.filledTonal(
            tooltip: l10n.homeProfileTooltip,
            onPressed: () =>
                ref.read(shellTabProvider.notifier).select(ShellTabs.profile),
            style: IconButton.styleFrom(
              backgroundColor: p.fillMuted,
              foregroundColor: p.textPrimary,
            ),
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: WebHeader.height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? p.textPrimary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? p.textPrimary : p.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.borderStrong),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.search_rounded, size: 20, color: p.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented 한국어 / English / 中文 control (V5 `.seg`).
class _LanguageSwitch extends ConsumerWidget {
  const _LanguageSwitch();

  static const _labels = {
    AppLanguage.ko: '한국어',
    AppLanguage.en: 'English',
    AppLanguage.zhHans: '中文',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final current = ref.watch(appLanguageProvider);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final l in AppLanguage.values)
            Semantics(
              button: true,
              selected: l == current,
              child: InkWell(
                onTap: () => ref.read(languageProvider.notifier).select(l),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  color: l == current ? p.chipSelectedBg : p.card,
                  child: Text(
                    _labels[l]!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: l == current ? p.chipSelectedFg : p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
