import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/language_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../preferences/models/user_preferences.dart';
import '../../preferences/restart_onboarding.dart';
import '../../preferences/screens/preference_labels.dart';
import '../../auth/models/auth_failure.dart';
import '../../auth/models/auth_snapshot.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/screens/login_screen.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../../language/widgets/language_sheet.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../preferences/screens/preferences_screen.dart';
import '../../university/providers/university_providers.dart';
import '../../university/widgets/university_sheet.dart';
import '../models/profile_avatar.dart';
import '../widgets/profile_avatar_sheet.dart';
import '../../records/screens/records_screen.dart';
import '../../missions/widgets/my_badges_section.dart';
import '../widgets/profile_dashboard.dart';
import 'account_settings_screen.dart';
import 'saved_restaurants_screen.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/theme_controller.dart';
import '../../settings/screens/appearance_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(authControllerProvider);
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: whitePageColor(context),
      body: SafeArea(
        child: user == null
            ? const _GuestView()
            : _SignedInView(snapshot: snap, user: user),
      ),
    );
  }
}

class _GuestView extends ConsumerWidget {
  const _GuestView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);
    return V5Page(
      backgroundColor: whitePageColor(context),
      children: [
        V5Header(title: l10n.myTitle),
        const SizedBox(height: 8),
        Center(
          child: Image.asset(
            AppAssets.mascotStanding,
            height: 120,
            semanticLabel: l10n.mascotSemantics,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.profileGuestTitle,
          textAlign: TextAlign.center,
          style: AppText.sectionTitle,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.profileGuestSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: context.palette.textSecondary),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => openLogin(context),
          child: Text(l10n.profileLoginButton),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () =>
              ref.read(shellTabProvider.notifier).select(ShellTabs.home),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: context.palette.accentStrong,
          ),
          child: Text(
            l10n.authBrowseAsGuest,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        V5SectionTitle(l10n.settingsAppTitle),
        V5RowGroup(
          elevated: true,
          rows: [
            V5Row(
              icon: Icons.language_rounded,
              title: l10n.profileLanguage,
              trailing: language.nativeName,
              onTap: () => showLanguageSheet(context),
            ),
            _themeRow(context, themeMode),
          ],
        ),
      ],
    );
  }
}

class _SignedInView extends ConsumerWidget {
  const _SignedInView({required this.snapshot, required this.user});

  final AuthSnapshot snapshot;
  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);
    final favorites = ref.watch(favoritesProvider);
    final university = ref.watch(selectedUniversityProvider).value;
    final profile = snapshot.profile;
    final hasProfileError = snapshot.status == AuthStatus.error;
    void push(Widget screen) =>
        Navigator.of(context)
            .push<void>(MaterialPageRoute<void>(builder: (_) => screen));

    final heroW = ProfileHero(
      nickname: (profile?.nickname ?? '').isNotEmpty
          ? profile!.nickname!
          : l10n.profileDefaultNickname,
      email: user.email,
      avatar: ProfileAvatar.resolve(profile?.avatarPath),
      // Choosing a picture needs a loaded profile row to save into.
      onChangeAvatar: profile == null
          ? null
          : () => showProfileAvatarSheet(context),
      onEditNickname: profile == null
          ? null
          : () => showNicknameEditor(context, ref, profile.nickname),
    );
    final campusW = ProfileCampusCard(
      university: university,
      onTap: () => showUniversitySheet(context),
    );
    final statsW = ProfileStatsCard(
      stats: [
        // Real count of the user's Supabase favorites.
        ProfileStat(
          icon: Icons.favorite_border_rounded,
          label: l10n.profileStatSaved,
          value: favorites.hasValue ? favorites.requireValue.length : null,
          loading: favorites.isLoading,
          onTap: () => push(const SavedRestaurantsScreen()),
        ),
        // Neither food records nor plans can be created in the app yet,
        // so there is no real number to show.
        ProfileStat(
          icon: Icons.bookmark_border_rounded,
          label: l10n.profileStatRecords,
          value: null,
        ),
        ProfileStat(
          icon: Icons.event_outlined,
          label: l10n.profileStatPlans,
          value: null,
        ),
      ],
    );
    final activity = <Widget>[
      V5SectionTitle(l10n.myActivityTitle),
      V5RowGroup(
        elevated: true,
        rows: [
          V5Row(
            icon: Icons.menu_book_outlined,
            title: l10n.profileRecords,
            // The original Records page, now a page of its own (the bottom
            // tab became 미션). Back returns here.
            onTap: () => push(const RecordsScreen()),
          ),
          V5Row(
            icon: Icons.favorite_border_rounded,
            title: l10n.profileSaved,
            // Real count from the user's favorites; nothing is shown while
            // it loads or if it failed.
            subtitle: favorites.hasValue
                ? l10n.profileSavedCount(favorites.requireValue.length)
                : null,
            onTap: () => push(const SavedRestaurantsScreen()),
          ),
          V5Row(
            icon: Icons.tune_rounded,
            title: l10n.profilePreferences,
            // Preferences need a loaded profile (and a completed onboarding).
            onTap: hasProfileError || profile == null
                ? null
                : () =>
                      push(const PreferencesScreen(mode: PreferencesMode.edit)),
          ),
          V5Row(
            icon: Icons.manage_accounts_outlined,
            title: l10n.profileAccount,
            onTap: () => push(const AccountSettingsScreen()),
          ),
        ],
      ),
    ];
    final settings = <Widget>[
      V5SectionTitle(l10n.settingsAppTitle),
      V5RowGroup(
        elevated: true,
        rows: [
          V5Row(
            icon: Icons.language_rounded,
            title: l10n.profileLanguage,
            trailing: language.nativeName,
            onTap: () => showLanguageSheet(context),
          ),
          _themeRow(context, themeMode),
        ],
      ),
    ];
    final logoutW = OutlinedButton(
      onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.palette.accentStrong,
        side: BorderSide(color: context.palette.accent, width: 1.5),
      ),
      child: Text(l10n.profileLogout),
    );
    final header = V5Header(
      title: l10n.myTitle,
      trailing: IconButton(
        tooltip: l10n.profileAccount,
        onPressed: () => push(const AccountSettingsScreen()),
        icon: const Icon(Icons.settings_outlined),
      ),
    );
    final errorW = hasProfileError
        ? <Widget>[
            const SizedBox(height: 12),
            _ProfileError(
              failure: snapshot.failure ?? AuthFailure.profileLoadFailed,
              onRetry: () =>
                  ref.read(authControllerProvider.notifier).retryProfile(),
            ),
          ]
        : const <Widget>[];

    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
    if (!wide) {
      return V5Page(
        backgroundColor: whitePageColor(context),
        children: [
          header,
          heroW,
          ...errorW,
          const SizedBox(height: 12),
          campusW,
          const SizedBox(height: 12),
          statsW,
          const _MyConditions(),
          ...activity,
          const MyBadgesSection(),
          ...settings,
          const SizedBox(height: 20),
          logoutW,
        ],
      );
    }
    // Desktop: the account on the left (who, which campus, app settings, sign out); what the user has done and
    // chosen (counts, conditions, activity, badges) on the right. Same widgets and the same real data.
    return V5Page(
      maxWidth: 1120,
      backgroundColor: whitePageColor(context),
      children: [
        header,
        Row(
          key: const ValueKey('my-desktop'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heroW,
                  ...errorW,
                  const SizedBox(height: 12),
                  campusW,
                  ...settings,
                  const SizedBox(height: 20),
                  logoutW,
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  statsW,
                  const _MyConditions(),
                  ...activity,
                  const MyBadgesSection(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "화면 테마" row: shows the current choice and opens the Appearance screen.
Widget _themeRow(BuildContext context, ThemeMode mode) {
  final l10n = context.l10n;
  return V5Row(
    icon: themeModeIcon(mode),
    title: l10n.themeTitle,
    trailing: themeModeLabel(l10n, mode),
    onTap: () => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()),
    ),
  );
}

/// "내 조건": what is applied to Home / map / search right now, with a way to
/// start over, and the walking origin (opens the 출발 위치 sheet).
class _MyConditions extends ConsumerWidget {
  const _MyConditions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = ref.watch(conditionsProvider);
    final origin = ref.watch(originProvider);
    final pins = ref.watch(savedPinsProvider).length;
    final chips = <String>[
      if (c.budget != BudgetOption.any) budgetLabel(l10n, c.budget),
      if (c.distance != DistanceOption.any) distanceLabel(l10n, c.distance),
      for (final u in c.cuisines) cuisineLabel(l10n, u),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V5SectionTitle(
          l10n.myConditionsTitle,
          actionLabel: l10n.myRestart,
          onAction: () => restartOnboarding(context, ref),
          actionColor: context.palette.accentStrong,
        ),
        if (chips.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 2),
            child: Text(
              l10n.myConditionsEmpty,
              style: TextStyle(
                fontSize: 15,
                color: context.palette.textSecondary,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in chips)
                  PillChip(label: label, selected: true, onTap: () {}),
              ],
            ),
          ),
        if (origin != null)
          V5RowGroup(
            elevated: true,
            rows: [
              V5Row(
                icon: Icons.place_outlined,
                title: l10n.homeOriginChip(origin.label(l10n)),
                subtitle: l10n.myOriginHint(pins),
                onTap: () => showOriginSheet(context),
              ),
            ],
          ),
      ],
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.failure, required this.onRetry});

  final AuthFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: context.palette.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failure.message(l10n),
              style: TextStyle(color: context.palette.error, fontSize: 13.5),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}
