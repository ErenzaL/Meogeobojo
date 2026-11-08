import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/university_providers.dart';
import 'university_sheet.dart';
import '../../../core/l10n/l10n.dart';
import '../models/university_display.dart';
import '../../../core/theme/app_palette.dart';

/// Rounded pill in the Home header: cap icon + name + chevron.
class UniversitySelector extends ConsumerWidget {
  const UniversitySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedUniversityProvider);
    final l10n = context.l10n;
    final name =
        selected.value?.displayName(Localizations.localeOf(context)) ??
        l10n.universitySelect;
    return Semantics(
      button: true,
      label: l10n.universitySelectCurrent(name),
      child: Material(
        color: context.palette.card,
        shape: StadiumBorder(side: BorderSide(color: context.palette.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showUniversitySheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.school_rounded,
                  size: 20,
                  color: context.palette.accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(fontSize: 15),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: context.palette.textPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
