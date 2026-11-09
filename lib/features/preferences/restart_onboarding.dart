import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../auth/providers/auth_providers.dart';
import '../conditions/providers/conditions_providers.dart';
import '../origin/providers/origin_providers.dart';
import 'providers/preferences_providers.dart';
import 'screens/preferences_screen.dart';

/// "처음 화면으로 돌아가 다시 설정" (Home header and the conditions sheet).
///
/// After a confirmation it puts the conditions and the starting point back to
/// their defaults. A signed-in user then lands on the taste setup with empty
/// answers (the saved ones come back if they leave without saving); a guest
/// has no setup to redo, so they just get the reset.
Future<void> restartOnboarding(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.condRestartTitle),
      content: Text(l10n.condRestartBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.condRestartAction),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final signedIn = ref.read(currentUserProvider) != null;
  await ref.read(originSelectionProvider.notifier).reset();
  if (!signedIn) {
    ref.read(conditionsProvider.notifier).clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.condRestartGuestDone)));
    return;
  }
  if (!context.mounted) return;
  // Clears the in-memory answers only (conditions re-seed from them); the
  // database row is untouched until the user saves again.
  ref.read(userPreferencesProvider.notifier).clearLocal();
  ref.read(conditionsProvider.notifier).clear();
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const PreferencesScreen(mode: PreferencesMode.edit),
    ),
  );
  ref.invalidate(userPreferencesProvider); // back to what is saved
}
