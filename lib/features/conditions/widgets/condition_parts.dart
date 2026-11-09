import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';

/// Sub-section title with its content underneath.
class CondSection extends StatelessWidget {
  const CondSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

/// Bold group header ("꼭 지킬 조건") with an optional grey hint beside it.
class CondGroupHeader extends StatelessWidget {
  const CondGroupHeader({super.key, required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(context).copyWith(fontSize: 14),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Title + helper text on the left, switch on the right.
class CondSwitchRow extends StatelessWidget {
  const CondSwitchRow({
    super.key,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: AppText.caption(context).copyWith(fontSize: 13.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: p.card,
            activeTrackColor: p.chipSelectedBg,
            inactiveThumbColor: p.card,
            inactiveTrackColor: p.fillMuted,
            trackOutlineColor: WidgetStatePropertyAll(p.hairline),
          ),
        ],
      ),
    );
  }
}

/// Card showing the current origin with a "바꾸기 ›" affordance.
class CondOriginCard extends StatelessWidget {
  const CondOriginCard({
    super.key,
    required this.label,
    required this.action,
    required this.onTap,
  });

  final String label;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: p.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
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
                  child: Icon(
                    Icons.place_outlined,
                    size: 22,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                Text(
                  '$action ›',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
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
