import 'package:flutter/material.dart';

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

/// Centres [child] in a column no wider than [Breakpoints.maxAppWidth] on a
/// calm page-colour backdrop. Below that width it is a no-op.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
