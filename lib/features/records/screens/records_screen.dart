import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/pending_action.dart';
import '../../auth/screens/login_screen.dart';
import '../../navigation/providers/shell_tab_provider.dart';

/// Food records are private to an account, so guests are asked to sign in
/// (and brought back here afterwards). Signed-in users see an honest
/// placeholder: the recording feature is not built yet and nothing is faked.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final signedIn = ref.watch(currentUserProvider) != null;
    return Scaffold(
      body: SafeArea(
        child: signedIn
            ? MascotMessage(
                asset: AppAssets.mascotSleeping,
                title: l10n.recordsEmptyTitle,
                message: l10n.recordsEmptyMessage,
              )
            : MascotMessage(
                asset: AppAssets.mascotStanding,
                title: l10n.authReasonRecords,
                message: l10n.authPromptBody,
                actionLabel: l10n.authPromptLogin,
                onAction: () {
                  ref
                      .read(pendingAuthActionProvider.notifier)
                      .set(const PendingOpenTab(ShellTabs.records));
                  openLogin(context);
                },
              ),
      ),
    );
  }
}
