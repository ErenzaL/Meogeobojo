import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../recommendation/home_ranking.dart';
import '../models/origin.dart';

/// Rounded white card holding rows separated by hairlines.
class OriginGroupCard extends StatelessWidget {
  const OriginGroupCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.hairline),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class OriginRow extends StatelessWidget {
  const OriginRow({
    super.key,
    required this.origin,
    required this.selected,
    required this.nearest,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final Origin origin;
  final bool selected;
  final RankedRestaurant? nearest;
  final VoidCallback onTap;

  /// Pins only: move or rename it on the map.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  IconData get _icon => switch (origin.kind) {
    OriginKind.gate => Icons.door_front_door_outlined,
    OriginKind.dorm => Icons.bed_outlined,
    OriginKind.building => Icons.apartment_rounded,
    OriginKind.pin => Icons.place_outlined,
    OriginKind.campusCenter => Icons.my_location_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final n = nearest;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.rustSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? p.card : p.fillMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon, size: 22, color: p.textSecondary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Two lines, never cut: "향설생활관 1관" must keep "1관".
                      Text(
                        origin.label(l10n),
                        maxLines: 2,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        n == null
                            ? l10n.originNearestNone
                            : l10n.originNearest(
                                n.restaurant.name,
                                n.walkMinutes,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(context)
                            .copyWith(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: l10n.originPinEdit,
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit_location_alt_outlined,
                      size: 20,
                      color: p.textSecondary,
                    ),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: l10n.originPinDelete,
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: p.textSecondary,
                    ),
                  ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_rounded, size: 22),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
