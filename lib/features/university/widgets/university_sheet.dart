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

  /// A "준비 중" school was tapped: say why nothing changed, in the sheet.
  bool _onlySch = false;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(universityListProvider);
    final selected = ref.watch(selectedUniversityProvider).value;
    final supported = ref.watch(supportedUniversityProvider);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.universitySelect,
                      style: AppText.sectionTitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.footerAvailableAt,
                      style: AppText.caption(context),
                    ),
                  ],
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
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: !_onlySch
                  ? const SizedBox(width: double.infinity)
                  : Semantics(
                      liveRegion: true,
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          4,
                          AppSpacing.screenH,
                          4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: context.palette.rustSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          context.l10n.universityOnlySch,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
            ),
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
                      available: supported(items[i]),
                      onTap: () async {
                        // Still "준비 중": the sheet and the campus stay.
                        if (!supported(items[i])) {
                          setState(() => _onlySch = true);
                          return;
                        }
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
    required this.available,
    required this.onTap,
  });

  final University university;
  final bool selected;

  /// False for a school still "준비 중": a muted tile that says so in words
  /// (not by colour alone), with readable text.
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? p.accentSoft
            : available
            ? p.card
            : p.fillMuted,
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
                  color: selected ? p.accent : p.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        university.displayName(Localizations.localeOf(context)),
                        style: available
                            ? AppText.title
                            : AppText.title.copyWith(color: p.textSecondary),
                      ),
                      if (university.city != null)
                        Text(
                          cityLabel(context.l10n, university.city!),
                          style: AppText.caption(context),
                        ),
                    ],
                  ),
                ),
                if (!available)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.border),
                    ),
                    child: Text(
                      context.l10n.universityComingSoon,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.textSecondary,
                      ),
                    ),
                  ),
                if (selected) Icon(Icons.check_circle_rounded, color: p.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// After a saved campus that is still "준비 중" was switched to 순천향대학교:
/// says so once, until closed.
class UniversitySwitchBanner extends ConsumerWidget {
  const UniversitySwitchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final from = ref.watch(universitySwitchNoticeProvider);
    if (from == null) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: p.accentSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.school_outlined, color: p.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.universitySwitched(
                  from.displayName(Localizations.localeOf(context)),
                ),
                style: const TextStyle(fontSize: 14.5),
              ),
            ),
            IconButton(
              tooltip: context.l10n.commonClose,
              onPressed: ref
                  .read(universitySwitchNoticeProvider.notifier)
                  .dismiss,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
