import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../models/university.dart';
import '../providers/university_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../models/university_display.dart';
import '../../../core/theme/app_palette.dart';

Future<void> showUniversitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.palette.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (_) => const _UniversitySheet(),
  );
}

class _UniversitySheet extends ConsumerStatefulWidget {
  const _UniversitySheet();

  @override
  ConsumerState<_UniversitySheet> createState() => _UniversitySheetState();
}

class _UniversitySheetState extends ConsumerState<_UniversitySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(universityListProvider);
    final selected = ref.watch(selectedUniversityProvider).value;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                18,
                AppSpacing.screenH,
                12,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.universitySelect,
                  style: AppText.sectionTitle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH,
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.l10n.universitySearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: context.palette.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide(color: context.palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide(color: context.palette.border),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: list.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => MascotMessage(
                  asset: AppAssets.mascotMapConfused,
                  title: context.l10n.universityLoadFailed,
                  actionLabel: context.l10n.commonRetry,
                  onAction: () => ref.invalidate(universityListProvider),
                ),
                data: (all) {
                  final items = all
                      .where(
                        (u) =>
                            u.nameKo.contains(_query) ||
                            (u.nameEn ?? '').toLowerCase().contains(
                              _query.toLowerCase(),
                            ),
                      )
                      .toList();
                  if (items.isEmpty) {
                    return MascotMessage(
                      asset: AppAssets.mascotSearching,
                      title: context.l10n.universityNoMatch,
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      4,
                      AppSpacing.screenH,
                      24,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _UniversityTile(
                      university: items[i],
                      selected: items[i] == selected,
                      onTap: () async {
                        await ref
                            .read(selectedUniversityProvider.notifier)
                            .select(items[i]);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UniversityTile extends StatelessWidget {
  const _UniversityTile({
    required this.university,
    required this.selected,
    required this.onTap,
  });

  final University university;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected ? context.palette.accentSoft : context.palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.school_rounded,
                  color: selected
                      ? context.palette.accent
                      : context.palette.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        university.displayName(Localizations.localeOf(context)),
                        style: AppText.title,
                      ),
                      if (university.city != null)
                        Text(
                          cityLabel(context.l10n, university.city!),
                          style: AppText.caption(context),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: context.palette.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
