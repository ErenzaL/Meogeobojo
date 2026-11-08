import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/language_controller.dart';
import '../../../core/theme/app_theme.dart';
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
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      children: [
        const SizedBox(height: 24),
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
          style: AppText.caption(context).copyWith(fontSize: 13.5),
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
            foregroundColor: context.palette.textSecondary,
          ),
          child: Text(
            l10n.authBrowseAsGuest,
            textAlign: TextAlign.center,
            style: AppText.link(context).copyWith(fontSize: 14),
          ),
        ),
        const SizedBox(height: 20),
        _SectionLabel(l10n.settingsAppTitle),
        _MenuGroup(
          children: [
            _MenuTile(
              icon: Icons.language_rounded,
              title: l10n.profileLanguage,
              trailing: language.nativeName,
              onTap: () => showLanguageSheet(context),
            ),
            _ThemeTile(mode: themeMode),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        16,
        AppSpacing.screenH,
        24,
      ),
      children: [
        ProfileGreetingCard(
          nickname: (profile?.nickname ?? '').isNotEmpty
              ? profile!.nickname!
              : l10n.profileDefaultNickname,
          email: user.email,
          avatar: Avatar(url: avatarUrlOf(user), size: 56),
          // Nickname editing lives in 계정 설정.
          onEditProfile: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const AccountSettingsScreen(),
            ),
          ),
        ),
        if (hasProfileError) ...[
          const SizedBox(height: 12),
          _ProfileError(
            failure: snapshot.failure ?? AuthFailure.profileLoadFailed,
            onRetry: () =>
                ref.read(authControllerProvider.notifier).retryProfile(),
          ),
        ],
        const SizedBox(height: 12),
        ProfileCampusCard(
          university: university,
          onTap: () => showUniversitySheet(context),
        ),
        const SizedBox(height: 12),
        ProfileStatsCard(
          stats: [
            // Real count of the user's Supabase favorites.
            ProfileStat(
              icon: Icons.favorite_border_rounded,
              label: l10n.profileStatSaved,
              value: favorites.hasValue ? favorites.requireValue.length : null,
              loading: favorites.isLoading,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SavedRestaurantsScreen(),
                ),
              ),
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
        ),
        const SizedBox(height: 20),
        _SectionLabel(l10n.settingsAccountTitle),
        _MenuGroup(
          children: [
            _MenuTile(
              icon: Icons.favorite_border_rounded,
              title: l10n.profileSaved,
              // Real count from the user's favorites; nothing is shown while
              // it loads or if it failed.
              trailing: favorites.hasValue
                  ? l10n.profileSavedCount(favorites.requireValue.length)
                  : null,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SavedRestaurantsScreen(),
                ),
              ),
            ),
            _MenuTile(
              icon: Icons.bookmark_border_rounded,
              title: l10n.profileRecords,
              onTap: () =>
                  ref.read(shellTabProvider.notifier).select(ShellTabs.records),
            ),
            _MenuTile(
              icon: Icons.tune_rounded,
              title: l10n.profilePreferences,
              // Preferences need a loaded profile (and a completed onboarding).
              onTap: hasProfileError || profile == null
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const PreferencesScreen(mode: PreferencesMode.edit),
                      ),
                    ),
            ),
            _MenuTile(
              icon: Icons.manage_accounts_outlined,
              title: l10n.profileAccount,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AccountSettingsScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionLabel(l10n.settingsAppTitle),
        _MenuGroup(
          children: [
            _MenuTile(
              icon: Icons.language_rounded,
              title: l10n.profileLanguage,
              trailing: language.nativeName,
              onTap: () => showLanguageSheet(context),
            ),
            _ThemeTile(mode: themeMode),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const StadiumBorder(),
            foregroundColor: context.palette.textPrimary,
            side: BorderSide(color: context.palette.border, width: 1.4),
          ),
          child: Text(l10n.profileLogout),
        ),
      ],
    );
  }
}

/// Avatar URL supplied by the sign-in provider (Kakao profile image), only if
/// it is https. Nothing is stored or fabricated.
String? avatarUrlOf(User user) {
  final meta = user.userMetadata;
  for (final key in const ['avatar_url', 'picture']) {
    final v = meta?[key];
    if (v is String && v.startsWith('https://')) return v;
  }
  return null;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(text, style: AppText.sectionTitle),
  );
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.palette.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: context.palette.accentStrong,
      ),
    );
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      ),
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

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: context.palette.border),
      boxShadow: context.palette.cardShadow,
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, indent: 56, color: context.palette.border),
          children[i],
        ],
      ],
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled
                    ? context.palette.accentStrong
                    : context.palette.placeholderIcon,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: AppText.title.copyWith(
                    fontSize: 15,
                    color: enabled
                        ? context.palette.textPrimary
                        : context.palette.textSecondary,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(context).copyWith(fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.placeholderIcon,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "화면 테마" row: shows the current choice and opens the Appearance screen.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _MenuTile(
      icon: themeModeIcon(mode),
      title: l10n.themeTitle,
      trailing: themeModeLabel(l10n, mode),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()),
      ),
    );
  }
}
