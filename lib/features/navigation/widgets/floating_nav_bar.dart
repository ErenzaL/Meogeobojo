import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
  });

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
      height: 62 + (scale - 1) * 16,
      // Sits above the iOS home indicator / Android gesture bar, never on it.
      bottomMargin: math.max(safeBottom - 14, 0) + 12,
      sideMargin: 16,
      contentGap: 12,
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
  _NavItem((l) => l.navHome, Icons.home_outlined, Icons.home_rounded),
  _NavItem((l) => l.navCommunity, Icons.groups_outlined, Icons.groups_rounded),
  _NavItem((l) => l.navMap, Icons.map_outlined, Icons.map_rounded),
  _NavItem(
    (l) => l.navRecords,
    Icons.bookmark_border_rounded,
    Icons.bookmark_rounded,
  ),
  _NavItem(
    (l) => l.navProfile,
    Icons.person_outline_rounded,
    Icons.person_rounded,
  ),
];

/// Floating capsule navigation for the five tabs. Place it in a [Stack] with
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

  static const _radius = BorderRadius.all(Radius.circular(40));

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
          decoration: BoxDecoration(
            borderRadius: _radius,
            boxShadow: [
              BoxShadow(
                color: p.shadow,
                blurRadius: 22,
                spreadRadius: -2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: _radius,
                  border: Border.all(color: p.border),
                ),
                // Labels keep scaling with the user's setting up to 1.3x; the
                // bar height grows to match, then labels shrink to fit.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: FloatingNavMetrics._maxLabelScale,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
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
          borderRadius: BorderRadius.circular(32),
          splashColor: palette.selectedFg.withValues(alpha: 0.12),
          highlightColor: palette.selectedFg.withValues(alpha: 0.06),
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? palette.selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(32),
            ),
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
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
