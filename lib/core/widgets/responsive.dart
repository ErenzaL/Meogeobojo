import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palette.dart';

/// Width classes. Phones (below [tablet]) are untouched; wider screens get
/// the same app centred in a bounded column instead of stretched edge to edge.
abstract final class Breakpoints {
  static const double tablet = 600;

  /// Desktop browsers: header instead of the bottom bar (V5 `S.wide`).
  static const double desktop = 960;

  /// Width of the centred app column on tablets / desktops.
  static const double maxAppWidth = 1280;

  /// Home switches to two columns at this content width.
  static const double homeTwoColumn = 860;
}

/// True on the website: the app uses the WHOLE browser width (header, page background, content and footer), with a
/// gutter that grows with the window. Native apps keep the bounded column. Overridable so tests can exercise both.
final webFullWidthProvider = Provider<bool>((_) => kIsWeb);

/// What the full-width website layout tells the pages: whether it is on, and the horizontal gutter for the window.
/// Without an [AppFrame] above (a test mounting one screen) the layout is the classic bounded one.
class WebLayout extends InheritedWidget {
  const WebLayout({super.key, required this.fullWidth, required super.child});

  final bool fullWidth;

  @override
  bool updateShouldNotify(WebLayout old) => old.fullWidth != fullWidth;

  /// Whether pages should use the whole window width (website, tablet width and up). Phones are never full-width
  /// desktop: they keep their own layout.
  static bool fullWidthOf(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<WebLayout>()?.fullWidth ??
          false) &&
      MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

  /// Side padding of page content: 24 on a tablet, 28 on a desktop, 40 on a large desktop (1440 and up). [phone] is what
  /// the page used before (phones and the native apps keep it).
  static double gutterOf(BuildContext context, {double phone = 16}) {
    if (!fullWidthOf(context)) return phone;
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1440) return 40;
    if (w >= 1024) return 28;
    return 24;
  }
}

/// Native tablets / desktops: [child] centred in a column no wider than [Breakpoints.maxAppWidth] on a calm
/// page-colour backdrop. The website ([fullWidth]) uses the whole window instead. Below that width it is a no-op.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child, this.fullWidth = false});

  final Widget child;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (fullWidth) return WebLayout(fullWidth: true, child: child);
    final mq = MediaQuery.of(context);
    if (mq.size.width <= Breakpoints.maxAppWidth) return child;
    return ColoredBox(
      color: context.palette.pageWarm,
      child: Center(
        child: ClipRect(
          child: SizedBox(
            width: Breakpoints.maxAppWidth,
            // Descendants read the column's width, not the window's.
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(Breakpoints.maxAppWidth, mq.size.height),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
