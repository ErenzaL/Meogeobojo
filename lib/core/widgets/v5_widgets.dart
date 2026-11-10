import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bottom_pinned.dart';
import 'responsive.dart';
import 'web_footer.dart';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// Page header used by the four tab screens (V5 `.brand` row): accent dot,
/// title, optional subtitle and a trailing action.
class V5Header extends StatelessWidget {
  const V5Header({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Replaces the accent dot (e.g. a back button on a pushed page).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            leading ??
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: p.rust,
                    shape: BoxShape.circle,
                  ),
                ),
            SizedBox(width: leading == null ? 10 : 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: p.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// Scrollable tab page: safe area, a readable column (max 720) on wide
/// screens, 16px gutters on phones.
class V5Page extends StatelessWidget {
  const V5Page({
    super.key,
    required this.children,
    this.scrollKey,
    this.backgroundColor,
    this.onRefresh,
    this.maxWidth = 720,
  });

  final List<Widget> children;
  final Key? scrollKey;

  /// Width of the content column. Phones are never wider than this anyway; desktop pages pass a larger value.
  final double maxWidth;

  /// When set, pulling the page down calls it (pull-to-refresh).
  final Future<void> Function()? onRefresh;

  /// Overrides the page colour (MY is pure white); defaults to the palette.
  final Color? backgroundColor;

  Widget _refreshable(Widget list) => onRefresh == null
      ? list
      : RefreshIndicator(onRefresh: onRefresh!, child: list);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? context.palette.background,
      body: SafeArea(
        bottom: false,
        child: _refreshable(
          // The web footer sits at the bottom of the viewport on a short page (BottomPinned measures the content and the
          // footer for real) and follows the content on a long one. Off the web the footer is empty: nothing changes.
          LayoutBuilder(
            builder: (context, box) => CustomScrollView(
              key: scrollKey,
              physics: onRefresh == null
                  ? null
                  : const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(top: 12),
                  sliver: SliverToBoxAdapter(
                    child: BottomPinned(
                      minHeight: box.maxHeight - 12,
                      content: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          // The website uses the whole window (the page's own columns decide their widths); phones and
                          // the native apps keep the bounded reading column.
                          constraints: BoxConstraints(
                            maxWidth: WebLayout.fullWidthOf(context)
                                ? double.infinity
                                : maxWidth,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              WebLayout.gutterOf(context),
                              0,
                              WebLayout.gutterOf(context),
                              24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: children,
                            ),
                          ),
                        ),
                      ),
                      footer: Column(
                        children: [
                          const WebFooterSlot(),
                          // The system inset (on a phone: the floating nav bar) stays below the page so the footer can be
                          // scrolled clear of it; on a desktop with the footer the footer ends flush with the window.
                          Consumer(
                            builder: (context, ref, _) {
                              final flush =
                                  ref.watch(webFooterEnabledProvider) &&
                                  MediaQuery.sizeOf(context).width >=
                                      Breakpoints.desktop;
                              return flush
                                  ? const SizedBox.shrink()
                                  : SizedBox(
                                      height: MediaQuery.paddingOf(context)
                                          .bottom,
                                    );
                            },
                          ),
                        ],
                      ),
                    ),
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

/// White card with a hairline border and rows separated by hairlines.
class V5RowGroup extends StatelessWidget {
  const V5RowGroup({super.key, required this.rows, this.elevated = false});

  final List<Widget> rows;

  /// Adds the soft card shadow (for cards sitting on a white page).
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: p.border),
        boxShadow: elevated ? softCardShadow(p) : null,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Icon tile + title + subtitle + chevron (V5 list row). A null [onTap]
/// renders it disabled (no chevron).
class V5Row extends StatelessWidget {
  const V5Row({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: p.fillMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: p.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: enabled ? p.textPrimary : p.textMuted,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: p.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  trailing!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
              ),
            ],
            if (enabled) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: p.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section title (V5 18px / 600) with an optional trailing text action.
class V5SectionTitle extends StatelessWidget {
  const V5SectionTitle(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.actionColor,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Colour of the trailing action (defaults to the primary text colour).
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppText.sectionTitle)),
          if (actionLabel != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  '$actionLabel →',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: actionColor ?? p.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pure white page in Light (cards float on it with soft shadows); Dark keeps
/// its normal page colour. Used by Home and MY.
Color whitePageColor(BuildContext context) {
  final p = context.palette;
  return Theme.of(context).brightness == Brightness.light
      ? p.card
      : p.background;
}

/// Soft, wide shadow for cards on a white page.
List<BoxShadow> softCardShadow(AppPalette p) => [
  BoxShadow(
    color: p.shadow.withValues(alpha: p.shadow.a * 0.5),
    blurRadius: 24,
    offset: const Offset(0, 6),
  ),
];

/// Centered empty state: line icon, title, message and optional actions.
class V5EmptyState extends StatelessWidget {
  const V5EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 44, color: p.textMuted),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: p.textSecondary,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small filled / outlined action button (V5 `.btn.sm`, 36px).
class V5SmallButton extends StatelessWidget {
  const V5SmallButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    );
    const size = Size(0, 36);
    const pad = EdgeInsets.symmetric(horizontal: 14);
    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: size,
              padding: pad,
              shape: shape,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              padding: pad,
              shape: shape,
              side: BorderSide(color: p.borderStrong),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: child,
          );
  }
}
