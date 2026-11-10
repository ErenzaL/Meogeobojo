import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/pending_action.dart';
import '../../auth/screens/login_screen.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../models/mission_models.dart';
import '../providers/mission_providers.dart';
import '../widgets/campaign_banner.dart';
import '../widgets/mission_card.dart';
import '../widgets/mission_dashboard_card.dart';
import '../widgets/mission_detail_sheet.dart';

/// 미션 tab: the month's banner and progress, then the missions in four tabs
/// (this month / daily / weekly / challenges). Every number comes from the
/// server; nothing here is computed from guesses or sample data.
class MissionScreen extends ConsumerStatefulWidget {
  const MissionScreen({super.key});

  @override
  ConsumerState<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends ConsumerState<MissionScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Coming back to this tab: ask the server to recompute (actions taken
    // elsewhere may have moved a mission).
    ref.listen(shellTabProvider, (prev, next) {
      if (next == ShellTabs.missions && prev != next) {
        ref.read(missionDashboardProvider.notifier).refresh();
      }
    });
    final signedIn = ref.watch(currentUserProvider) != null;
    final dash = ref.watch(missionDashboardProvider);

    return V5Page(
      backgroundColor: whitePageColor(context),
      // Pull down to re-read the missions an admin may have just changed.
      onRefresh: signedIn
          ? () => ref.read(missionDashboardProvider.notifier).refresh()
          : null,
      children: [
        V5Header(title: l10n.missionPageTitle),
        const SizedBox(height: 14),
        if (!signedIn)
          const _GuestView()
        else
          dash.when(
            loading: () => const _Skeleton(),
            error: (_, _) => _LoadFailed(
              onRetry: () => ref.invalidate(missionDashboardProvider),
            ),
            data: (d) => d == null
                ? const _GuestView()
                : _Content(
                    dashboard: d,
                    tab: _tab,
                    onTab: (i) => setState(() => _tab = i),
                  ),
          ),
      ],
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.dashboard,
    required this.tab,
    required this.onTab,
  });

  final MissionDashboard dashboard;
  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final d = dashboard;
    final campaign = d.campaign;
    final labels = [
      campaign?.title ?? l10n.missionTabMonthlyFallback,
      l10n.missionTabDaily,
      l10n.missionTabWeekly,
      l10n.missionTabChallenge,
    ];
    final kinds = [
      MissionKind.monthly,
      MissionKind.daily,
      MissionKind.weekly,
      MissionKind.achievement,
    ];
    final shown = d.byKind(kinds[tab]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (campaign != null) ...[
          CampaignBanner(campaign: campaign),
          const SizedBox(height: 14),
          MissionDashboardCard(dashboard: d),
          const SizedBox(height: 18),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                PillChip(
                  label: labels[i],
                  selected: i == tab,
                  onTap: () => onTab(i),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          V5EmptyState(
            icon: Icons.emoji_events_outlined,
            title: l10n.missionEmptyTitle,
            message: l10n.missionEmptyBody,
          )
        else
          for (final m in shown) ...[
            MissionCard(
              mission: m,
              onTap: () => showMissionDetailSheet(context, ref, m),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _GuestView extends ConsumerWidget {
  const _GuestView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      children: [
        const SizedBox(height: 8),
        Image.asset(
          AppAssets.mascotCheer,
          height: 120,
          cacheWidth: 360,
          semanticLabel: l10n.mascotSemantics,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.missionGuestTitle,
          textAlign: TextAlign.center,
          style: AppText.sectionTitle,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.missionGuestBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () {
            // After signing in (and onboarding, for a new account) come back here.
            ref
                .read(pendingAuthActionProvider.notifier)
                .set(const PendingOpenTab(ShellTabs.missions));
            openLogin(context);
          },
          child: Text(l10n.profileLoginButton),
        ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return V5EmptyState(
      icon: Icons.cloud_off_rounded,
      title: l10n.missionLoadFailed,
      message: l10n.tryAgainLater,
      actions: [
        FilledButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SkeletonBox(height: 150, radius: AppRadius.card),
      SizedBox(height: 14),
      SkeletonBox(height: 170, radius: AppRadius.card),
      SizedBox(height: 18),
      SkeletonBox(height: 44, radius: 12),
      SizedBox(height: 14),
      SkeletonBox(height: 96, radius: AppRadius.card),
      SizedBox(height: 12),
      SkeletonBox(height: 96, radius: AppRadius.card),
    ],
  );
}
