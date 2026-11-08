import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/models/auth_failure.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/widgets/auth_fields.dart';
import '../models/nickname.dart';
import '../widgets/nickname_field.dart';
import '../../../core/theme/app_palette.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  Future<void> _editNickname(String? current) async {
    final messenger = ScaffoldMessenger.of(context);
    final updatedMessage = context.l10n.nicknameUpdated;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _NicknameDialog(
        initial: current ?? '',
        onSave: (value) =>
            ref.read(authControllerProvider.notifier).saveNickname(value),
      ),
    );
    if (saved == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(updatedMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snap = ref.watch(authControllerProvider);
    final user = snap.user;
    final provider = user?.appMetadata['provider'] as String?;
    final providerLabel = switch (provider) {
      'kakao' => l10n.accountProviderKakao,
      'email' => l10n.accountProviderEmail,
      _ => null,
    };
    final email = user?.email;

    Widget row(String label, String value, {VoidCallback? onEdit}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.caption(context).copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(value, style: AppText.title.copyWith(fontSize: 15)),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: l10n.accountNicknameEdit,
              onPressed: onEdit,
              icon: Icon(
                Icons.edit_outlined,
                color: context.palette.accentStrong,
              ),
            ),
        ],
      ),
    );

    final nickname = snap.profile?.nickname;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileAccount)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: context.palette.border),
              boxShadow: context.palette.cardShadow,
            ),
            child: Column(
              children: [
                row(
                  l10n.accountNickname,
                  (nickname != null && nickname.isNotEmpty)
                      ? nickname
                      : l10n.profileDefaultNickname,
                  onEdit: snap.profile == null
                      ? null
                      : () => _editNickname(nickname),
                ),
                if (email != null && email.isNotEmpty) ...[
                  Divider(height: 1, color: context.palette.border),
                  row(l10n.accountEmail, email),
                ],
                if (providerLabel != null) ...[
                  Divider(height: 1, color: context.palette.border),
                  row(l10n.accountLoginMethod, providerLabel),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await ref.read(authControllerProvider.notifier).signOut();
              nav.popUntil((r) => r.isFirst);
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: const StadiumBorder(),
              foregroundColor: context.palette.textPrimary,
              side: BorderSide(color: context.palette.border, width: 1.4),
            ),
            child: Text(l10n.profileLogout),
          ),
        ],
      ),
    );
  }
}

/// Owns its controller so it is disposed only after the dialog is fully gone
/// (disposing right after `showDialog` returns would race the exit animation).
/// Saving happens inside the dialog: on failure it stays open with the old
/// nickname untouched and the user can simply press save again.
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial, required this.onSave});

  final String initial;
  final Future<AuthFailure?> Function(String value) onSave;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  NicknameError? _error;
  AuthFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final check = checkNickname(_controller.text);
    if (!check.isValid) {
      setState(() {
        _error = check.error;
        _failure = null;
      });
      return;
    }
    if (check.value == widget.initial) {
      Navigator.pop(context, false); // nothing changed
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _failure = null;
    });
    final f = await widget.onSave(check.value!);
    if (!mounted) return;
    if (f == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _failure = f;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: context.palette.card,
      title: Text(l10n.accountNicknameEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NicknameField(
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              errorText: _error == null
                  ? null
                  : nicknameErrorText(l10n, _error!),
              onChanged: () {
                if (_error != null || _failure != null) {
                  setState(() {
                    _error = null;
                    _failure = null;
                  });
                }
              },
              onSubmitted: _save,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.nicknameRule(kNicknameMinLength, kNicknameMaxLength),
              style: AppText.caption(context),
            ),
            if (_failure != null) ...[
              const SizedBox(height: 10),
              AuthMessage.error(_failure!.message(l10n)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Text(_failure == null ? l10n.commonSave : l10n.commonRetry),
        ),
      ],
    );
  }
}
