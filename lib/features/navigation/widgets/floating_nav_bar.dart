import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// Geometry of the floating bar, computed once from the window so the bar and
/// the content that must stay clear of it always agree.
class FloatingNavMetrics {
  const FloatingNavMetrics({
    required this.height,
    required this.bottomMargin,
    required this.sideMargin,
    required this.contentGap,
    this.safeBottom = 0,
  });

  /// Device bottom inset the flat bar extends under (home indicator).
  final double safeBottom;

  /// Bar height (grows slightly with the text scale; labels stop growing at
  /// [_maxLabelScale] so the bar stays compact).
  final double height;

  /// Space between the bar and the bottom edge of the screen.
  final double bottomMargin;
  final double sideMargin;

  /// Extra breathing room kept between scrolled content and the bar.
  final double contentGap;

  /// Everything a screen must leave free at the bottom (bar + margins). The
  /// shell publishes this as `MediaQuery.padding.bottom` for the tab screens.
  double get reservedBottom => bottomMargin + height + contentGap;

  static const _maxLabelScale = 1.3;

  static double clampedLabelScale(MediaQueryData mq) =>
      math.min(math.max(mq.textScaler.scale(10) / 10, 1.0), _maxLabelScale);

  factory FloatingNavMetrics.of(MediaQueryData mq) {
    // viewPadding (not padding) so the keyboard opening never changes it.
    final safeBottom = mq.viewPadding.bottom;
    final scale = clampedLabelScale(mq);
    return FloatingNavMetrics(
      // V5: a flat 64px bar plus the device's bottom inset (icons stay above
      // the home indicator / gesture bar, the bar itself runs to the edge).
      height: 64 + (scale - 1) * 16 + safeBottom,
      bottomMargin: 0,
      sideMargin: 0,
      contentGap: 0,
      safeBottom: safeBottom,
    );
  }
}

class _NavPalette {
  const _NavPalette({
    required this.surface,
    required this.border,
    required this.idle,
    required this.selectedBg,
    required this.selectedFg,
    required this.shadow,
  });

  final Color surface;
  final Color border;
  final Color idle;
  final Color selectedBg;
  final Color selectedFg;
  final Color shadow;

  /// Light and Dark colours both come from the theme's [AppPalette]; this
  /// class only gives the bar its own short names for them.
  static _NavPalette of(BuildContext context) {
    final p = context.palette;
    return _NavPalette(
      surface: p.navSurface,
      border: p.navBorder,
      idle: p.navIdle,
      selectedBg: p.navSelectedBg,
      selectedFg: p.navSelectedFg,
      shadow: p.navShadow,
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon);
  final String Function(AppLocalizations) label;
  final IconData icon;
  final IconData activeIcon;
}

final _items = [
  // V5 order and icons: 홈 · 지도 · 밥수다 · 기록 · MY (filled when active).
  _NavItem((l) => l.navHome, Icons.home_outlined, Icons.home_rounded),
  _NavItem((l) => l.navMap, Icons.map_outlined, Icons.map_rounded),
  _NavItem((l) => l.navCommunity, Icons.forum_outlined, Icons.forum_rounded),
  _NavItem(
    (l) => l.navRecords,
    Icons.menu_book_outlined,
    Icons.menu_book_rounded,
  ),
  _NavItem(
    (l) => l.navProfile,
    Icons.person_outline_rounded,
    Icons.person_rounded,
  ),
];

/// Flat bottom navigation for the five tabs (V5 `.navbar`). Place it in a [Stack] with
/// [Positioned] using [FloatingNavMetrics]; the shell does that.
///
/// The blur is confined to the capsule, and the surface stays ~93% opaque, so
/// it is legible over anything (including the native map) even where the
/// platform cannot blur what is behind it.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.metrics,
  });

  final int index;
  final ValueChanged<int> onTap;
  final FloatingNavMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final p = _NavPalette.of(context);
    final l10n = context.l10n;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : _kAnimation;

    return Semantics(
      container: true,
      role: SemanticsRole.tabBar,
      explicitChildNodes: true,
      child: SizedBox(
        height: metrics.height,
        child: DecoratedBox(
          // Flat, full width, hairline on top (V5 `.navbar`).
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.border)),
          ),
          // Labels keep scaling with the user's setting up to 1.3x; the bar
          // height grows to match, then labels shrink to fit.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: FloatingNavMetrics._maxLabelScale,
            child: Padding(
              padding: EdgeInsets.only(bottom: metrics.safeBottom),
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _NavButton(
                        label: _items[i].label(l10n),
                        icon: _items[i].icon,
                        activeIcon: _items[i].activeIcon,
                        selected: i == index,
                        palette: p,
                        duration: duration,
                        onTap: () => onTap(i),
                      ),
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

/// Soft cross-fade / colour transition; no scaling or bouncing.
const _kAnimation = Duration(milliseconds: 220);

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.palette,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final _NavPalette palette;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.selectedFg : palette.idle;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      role: SemanticsRole.tab,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          splashColor: palette.selectedFg.withValues(alpha: 0.12),
          highlightColor: palette.selectedFg.withValues(alpha: 0.06),
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            // V5: the active tab is a filled icon with a bold label, no pill.
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  child: Icon(
                    selected ? activeIcon : icon,
                    key: ValueKey(selected),
                    size: 24,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                    child: Text(label, maxLines: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
