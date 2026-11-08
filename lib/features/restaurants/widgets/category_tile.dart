import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';

/// Rounded icon container with a label underneath. Used for the Home category
/// shortcuts and inside the "all categories" sheet, so both look identical.
///
/// Light: white surface, hairline border, orange icon, peach when selected or
/// pressed. Dark: charcoal surface, orange icon, warm brown when selected.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.highlighted = false,
    this.maxBox = 58,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The current category (peach fill + orange border).
  final bool selected;

  /// A shortcut to a different feature (e.g. 학식): a warm tile fill.
  final bool highlighted;

  /// Upper bound of the icon box; it shrinks to fit narrow columns.
  final double maxBox;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fill = selected
        ? p.accentSoft
        : (highlighted ? p.accentTile : p.card);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        splashColor: p.accentSoft,
        highlightColor: p.accentSoft.withValues(alpha: 0.6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: LayoutBuilder(
            builder: (context, c) {
              final box = (c.maxWidth - 6).clamp(40.0, maxBox);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: box,
                    height: box,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected || highlighted ? p.accent : p.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Icon(icon, size: box * 0.5, color: p.accent),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppText.title.copyWith(
                        fontSize: 12.5,
                        fontWeight: selected || highlighted
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected || highlighted
                            ? p.accentStrong
                            : p.textPrimary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
