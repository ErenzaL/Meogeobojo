import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/pending_action.dart';
import '../../auth/screens/login_screen.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../../home/widgets/home_card_parts.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../profile/screens/saved_restaurants_screen.dart';
import '../../recommendation/providers/ranking_providers.dart';

/// 기록 (V5): a private food diary page. The recording feature itself is not
/// built yet, so the figures are shown as "—" (never invented) and the add
/// actions say so; guests are asked to sign in first because records belong to
/// an account. "가고 싶은 곳" is the user's real saved restaurants.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  void _add(BuildContext context, WidgetRef ref) {
    if (ref.read(currentUserProvider) == null) {
      ref
          .read(pendingAuthActionProvider.notifier)
          .set(const PendingOpenTab(ShellTabs.records));
      openLogin(context);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.recordsEmptyMessage)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final signedIn = ref.watch(currentUserProvider) != null;
    final favorites = ref.watch(favoritesProvider);
    final saved = signedIn && favorites.hasValue
        ? '${favorites.requireValue.length}'
        : '—';
    final month = ref.watch(seoulNowProvider).month;

    return V5Page(
      children: [
        V5Header(
          title: l10n.recordsPageTitle,
          subtitle: l10n.recordsSubtitle,
          trailing: FilledButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(l10n.recordsAdd),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
        ),
        const SizedBox(height: 16),
        _ReportCard(month: month),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillChip(
              label: l10n.recordsTabEaten('—'),
              selected: true,
              onTap: () {},
            ),
            PillChip(
              label: l10n.recordsTabWant(saved),
              selected: false,
              onTap: () {
                if (signedIn) {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SavedRestaurantsScreen(),
                    ),
                  );
                } else {
                  ref
                      .read(pendingAuthActionProvider.notifier)
                      .set(const PendingOpenTab(ShellTabs.records));
                  openLogin(context);
                }
              },
            ),
          ],
        ),
        V5EmptyState(
          icon: Icons.menu_book_outlined,
          title: l10n.recordsNoRecordsTitle,
          message: l10n.recordsNoRecordsBody,
          actions: [
            FilledButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(l10n.recordsFirst),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.month});

  final int month;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: p.textMuted),
          ),
        ],
      ),
    );
    return HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  l10n.recordsReportTitle(month),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: p.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  l10n.recordsReportBasis,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.rustText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: p.fillMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  stat('—', l10n.recordsStatMeals),
                  VerticalDivider(width: 1, color: p.borderStrong),
                  stat('—', l10n.recordsStatSpend),
                  VerticalDivider(width: 1, color: p.borderStrong),
                  stat('—', l10n.recordsStatAvg),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.recordsReportHint,
            style: TextStyle(fontSize: 15, color: p.rustText),
          ),
        ],
      ),
    );
  }
}
