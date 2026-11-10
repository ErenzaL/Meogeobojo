import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// The rounded chip used by Home and the map header.
class HomeChip extends StatelessWidget {
  const HomeChip({
    super.key,
    required this.onTap,
    required this.background,
    required this.children,
    this.dense = false,
  });

  /// Tighter padding (the map header, where three chips share a phone row).
  final bool dense;
  final VoidCallback onTap;
  final Color background;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.palette.borderStrong),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 11 : 14,
          vertical: dense ? 11 : 12,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}
