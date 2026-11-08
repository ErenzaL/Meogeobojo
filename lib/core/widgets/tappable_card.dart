import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_palette.dart';

/// Rounded card with a hairline border and an ink ripple. It adds no drop
/// shadow in either theme (see [AppPalette.cardShadow]), so the page between
/// cards stays the pure page colour.
class TappableCard extends StatelessWidget {
  const TappableCard({
    super.key,
    required this.child,
    this.onTap,
    this.radius = AppRadius.card,
    this.shadow = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? context.palette.cardShadow : null,
      ),
      child: Material(
        color: context.palette.card,
        // A hairline keeps white cards distinct on the white page.
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: context.palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}
