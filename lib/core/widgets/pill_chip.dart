import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Selectable chip: near-black fill with a leading check when selected, white
/// with a hairline border otherwise. Radius 12.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Leading icon shown only while unselected (the check replaces it).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.chipSelectedFg : p.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.chipSelectedBg : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? p.chipSelectedBg : p.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected || icon != null) ...[
                  Icon(
                    selected ? Icons.check_rounded : icon,
                    size: 17,
                    color: selected ? fg : p.textSecondary,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: fg,
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

/// Wrapping group of chips with the app's standard spacing.
class ChipWrap extends StatelessWidget {
  const ChipWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);
}
