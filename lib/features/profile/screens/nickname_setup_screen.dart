import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/models/auth_failure.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/widgets/auth_fields.dart';
import '../../auth/widgets/auth_scaffold.dart';
import '../models/nickname.dart';
import '../widgets/nickname_field.dart';
import '../../../core/theme/app_palette.dart';

/// Short introduction step shown once after the first sign-in (or once for
/// accounts created before app nicknames existed). A name that came from
/// Kakao does not count as chosen.
class NicknameSetupScreen extends ConsumerStatefulWidget {
  const NicknameSetupScreen({super.key});

  @override
  ConsumerState<NicknameSetupScreen> createState() =>
      _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends ConsumerState<NicknameSetupScreen> {
  final _controller = TextEditingController();
  NicknameError? _error;
  AuthFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final check = checkNickname(_controller.text);
    if (!check.isValid) {
      setState(() {
        _error = check.error;
        _failure = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _failure = null;
    });
    // On success the profile is updated and the auth flow host moves on
    // (preference onboarding for new users, the app for everyone else).
    final f = await ref
        .read(authControllerProvider.notifier)
        .saveNickname(check.value!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      child: AuthScaffold(
        showBack: false,
        children: [
          Center(
            child: Image.asset(
              AppAssets.mascotStanding,
              height: 104,
              semanticLabel: l10n.mascotSemantics,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.nicknameSetupTitle,
            textAlign: TextAlign.center,
            style: AppText.heroTitle.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.nicknameSetupSubtitle,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: 28),
          NicknameField(
            controller: _controller,
            enabled: !_busy,
            autofocus: true,
            errorText: _error == null ? null : nicknameErrorText(l10n, _error!),
            onChanged: () {
              if (_error != null || _failure != null) {
                setState(() {
                  _error = null;
                  _failure = null;
                });
              }
            },
            onSubmitted: _submit,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.nicknameRule(kNicknameMinLength, kNicknameMaxLength),
            style: AppText.caption(context),
          ),
          if (_failure != null) ...[
            const SizedBox(height: 12),
            AuthMessage.error(_failure!.message(l10n)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.nicknameNext),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 44),
              foregroundColor: context.palette.textSecondary,
            ),
            child: Text(l10n.onbLogout),
          ),
        ],
      ),
    );
  }
}
