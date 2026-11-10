import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_providers.dart';
import '../models/profile_avatar.dart';
import 'profile_avatar_view.dart';

/// "프로필 이미지 선택": a grid of the mascots. Nothing is saved until
/// "선택 완료"; the choice is written to the account (`profiles.avatar_path`),
/// so it survives logging out and follows the user to other devices.
Future<void> showProfileAvatarSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => const _AvatarSheet(),
    );

class _AvatarSheet extends ConsumerStatefulWidget {
  const _AvatarSheet();

  @override
  ConsumerState<_AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends ConsumerState<_AvatarSheet> {
  late final ProfileAvatar _current = ProfileAvatar.resolve(
    ref.read(authControllerProvider).profile?.avatarPath,
  );
  late ProfileAvatar _picked = _current;
  bool _busy = false;
  bool _failed = false;

  Future<void> _confirm() async {
    if (_busy) return;
    if (_picked == _current) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .saveAvatar(_picked.key);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.profileAvatarSheetTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.profileAvatarSheetSubtitle,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  children: [
                    for (final (i, a) in ProfileAvatar.values.indexed)
                      _AvatarChoice(
                        avatar: a,
                        label: l10n.profileAvatarOption(i + 1),
                        selected: a == _picked,
                        onTap: _busy ? null : () => setState(() => _picked = a),
                      ),
                  ],
                ),
                if (_failed) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.profileAvatarSaveFailed,
                    style: TextStyle(fontSize: 13.5, color: p.error),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _confirm,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(l10n.profileAvatarConfirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.avatar,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ProfileAvatar avatar;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, c) {
            final size = c.biggest.shortestSide;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? p.accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: ProfileAvatarView(avatar: avatar, size: size - 12),
                ),
                if (selected)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.card, width: 2),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: p.onRust,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
