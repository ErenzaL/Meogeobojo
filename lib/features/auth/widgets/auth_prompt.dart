import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_providers.dart';
import '../providers/pending_action.dart';
import '../screens/login_screen.dart';
import '../../../core/theme/app_palette.dart';

/// Why a feature needs an account; picks the explanation shown to guests.
enum AuthReason { favorite, records, community, profile, contribute, feedback }

extension on AuthReason {
  String title(AppLocalizations l10n) => switch (this) {
    AuthReason.favorite => l10n.authReasonFavorite,
    AuthReason.records => l10n.authReasonRecords,
    AuthReason.community => l10n.authReasonCommunity,
    AuthReason.profile => l10n.authReasonProfile,
    AuthReason.contribute => l10n.authReasonContribute,
    AuthReason.feedback => l10n.authReasonFeedback,
  };
}

/// Gate for account-only actions.
///
/// Returns true when the user is signed in and the caller may proceed.
/// Otherwise explains why an account is needed and returns false; if the user
/// agrees, the login screens open and [resume] is carried out automatically
/// after sign-in (and onboarding, for new accounts).
Future<bool> requireAuth(
  BuildContext context,
  WidgetRef ref, {
  required AuthReason reason,
  PendingAuthAction? resume,
}) async {
  if (ref.read(currentUserProvider) != null) return true;
  final proceed = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    backgroundColor: context.palette.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (_) => _AuthPromptSheet(reason: reason),
  );
  if (proceed == true && context.mounted) {
    ref.read(pendingAuthActionProvider.notifier).set(resume);
    await openLogin(context);
  }
  return false;
}

class _AuthPromptSheet extends StatelessWidget {
  const _AuthPromptSheet({required this.reason});

  final AuthReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            AppAssets.mascotStanding,
            height: 96,
            semanticLabel: l10n.mascotSemantics,
          ),
          const SizedBox(height: 12),
          Text(
            reason.title(l10n),
            textAlign: TextAlign.center,
            style: AppText.title.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.authPromptBody,
            textAlign: TextAlign.center,
            style: AppText.caption(context).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.authPromptLogin),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 44),
              foregroundColor: context.palette.textSecondary,
            ),
            child: Text(l10n.commonLater),
          ),
        ],
      ),
    );
  }
}
