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
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../meal_records.dart';

/// 기록 (V5): a private food diary page. Meals come from "먹었어요" (식당 정보
/// or the Home card after 길찾기); figures with no data behind them (spend)
/// stay "—", never invented. Guests are asked to sign in first because records
/// belong to an account. "가고 싶은 곳" is the user's real saved restaurants.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  void _add(BuildContext context, WidgetRef ref) {
    if (ref.read(currentUserProvider) == null) {
      ref
          .read(pendingAuthActionProvider.notifier)
          .set(const PendingOpenTab(ShellTabs.profile));
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
    final now = ref.watch(seoulNowProvider);
    final month = now.month;
    final meals = ref.watch(mealRecordsProvider);
    final thisMonth = meals
        .where((m) => m.eatenAt.year == now.year && m.eatenAt.month == month)
        .length;
    // Opens the place again when it is still in the nearby list.
    final nearby = {
      for (final r in ref.watch(allNearbyRestaurantsProvider).value ?? const [])
        r.kakaoId: r,
    };

    return V5Page(
      children: [
        V5Header(
          // Records is opened from MY → 내 활동 → 나의 기록; back returns there.
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
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
        _ReportCard(month: month, meals: signedIn ? '$thisMonth' : '—'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillChip(
              label: l10n.recordsTabEaten(signedIn ? '${meals.length}' : '—'),
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
                      .set(const PendingOpenTab(ShellTabs.profile));
                  openLogin(context);
                }
              },
            ),
          ],
        ),
        if (meals.isNotEmpty) ...[
          const SizedBox(height: 14),
          V5RowGroup(
            rows: [
              for (final m in meals)
                V5Row(
                  icon: Icons.restaurant_rounded,
                  title: m.name,
                  subtitle: [
                    if (m.category.isNotEmpty) m.category,
                    MaterialLocalizations.of(context)
                        .formatMediumDate(m.eatenAt),
                  ].join(' · '),
                  onTap: nearby[m.kakaoId] == null
                      ? null
                      : () => openRestaurantDetail(context, nearby[m.kakaoId]!),
                ),
            ],
          ),
        ] else
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
  const _ReportCard({required this.month, required this.meals});

  final int month;

  /// This month's meals, or "—" for a guest.
  final String meals;

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
                  stat(meals, l10n.recordsStatMeals),
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
