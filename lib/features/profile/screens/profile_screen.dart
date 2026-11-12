import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/language_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../auth/models/auth_failure.dart';
import '../../auth/models/auth_snapshot.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/screens/login_screen.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../../language/widgets/language_sheet.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../preferences/screens/preferences_screen.dart';
import '../../university/providers/university_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
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
        // The sign-in prompt and the settings rows keep a card-like width (not stretched across a wide window).
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  style: TextStyle(
                    fontSize: 15,
                    color: context.palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => openLogin(context),
                  child: Text(l10n.profileLoginButton),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => ref
                      .read(shellTabProvider.notifier)
                      .select(ShellTabs.home),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: context.palette.accentStrong,
                  ),
                  child: Text(
                    l10n.authBrowseAsGuest,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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
            ),
          ),
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
          // 기록 lives inside MY (the bottom tab is 미션).
          onTap: () => push(const RecordsScreen()),
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
          // The start point Home, the map and search measure from. It can
          // also be changed right there; this is where it is kept.
          V5Row(
            icon: Icons.place_outlined,
            title: l10n.profileDefaultOrigin,
            trailing: ref.watch(originProvider)?.label(l10n),
            onTap: () => showOriginSheet(context),
          ),
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
            // The account column keeps a card width (so settings rows are not stretched); the activity area takes
            // the rest, in two columns on a large window.
            SizedBox(
              width: MediaQuery.sizeOf(context).width >= 1440 ? 420 : 380,
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
            const SizedBox(width: 32),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final first = <Widget>[statsW];
                  final second = <Widget>[...activity, const MyBadgesSection()];
                  if (box.maxWidth < 900) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [...first, ...second],
                    );
                  }
                  return Row(
                    key: const ValueKey('my-two-columns'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: first,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: second,
                        ),
                      ),
                    ],
                  );
                },
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
