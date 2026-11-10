import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../auth/providers/auth_providers.dart';
import '../../missions/providers/mission_providers.dart';
import '../../restaurants/models/restaurant.dart';
import '../models/contribution.dart';
import '../providers/contribution_providers.dart';

/// Submit a restaurant or menu photo for review. The picture goes to a PRIVATE
/// place (only the student and the moderators can see it) until it is approved.
/// The caller has already checked that the user is signed in.
Future<void> showPhotoContributionSheet(
  BuildContext context, {
  required Restaurant restaurant,
  ContributionKind initialKind = ContributionKind.restaurantPhoto,
}) => showCompactSheet<void>(
  context,
  builder: (_) => _PhotoSheet(restaurant: restaurant, initialKind: initialKind),
);

class _PhotoSheet extends ConsumerStatefulWidget {
  const _PhotoSheet({required this.restaurant, required this.initialKind});

  final Restaurant restaurant;
  final ContributionKind initialKind;

  @override
  ConsumerState<_PhotoSheet> createState() => _PhotoSheetState();
}

class _PhotoSheetState extends ConsumerState<_PhotoSheet> {
  late ContributionKind _kind = widget.initialKind;
  PickedPhoto? _photo;
  final _caption = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final l10n = context.l10n;
    try {
      final photo = await ref.read(photoPickerProvider).pick();
      if (photo == null || !mounted) return;
      if (photo.bytes.length > maxPhotoBytes) {
        setState(() => _error = l10n.photoTooLarge);
        return;
      }
      setState(() {
        _photo = photo;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = l10n.photoFailed);
    }
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final user = ref.read(currentUserProvider);
    final photo = _photo;
    if (user == null || photo == null || !_consent) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    final done = l10n.photoSubmitted;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(contributionRepositoryProvider)
          .submitPhoto(
            userId: user.id,
            kind: _kind,
            kakaoPlaceId: widget.restaurant.kakaoId,
            photo: photo,
            caption: _caption.text,
          );
      ref.invalidate(myContributionsProvider);
      ref.read(missionDashboardProvider.notifier).refresh();
      if (!mounted) return;
      nav.pop();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    } on ContributionException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.error) {
          ContributionError.tooLarge => l10n.photoTooLarge,
          ContributionError.duplicate => l10n.photoDuplicate,
          ContributionError.tooMany => l10n.photoTooMany,
          _ => l10n.photoFailed,
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.photoFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final photo = _photo;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.photoSheetTitle,
            style: AppText.sectionTitle.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 2),
          Text(
            widget.restaurant.name,
            style: AppText.caption(context).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              PillChip(
                label: l10n.photoKindRestaurant,
                selected: _kind == ContributionKind.restaurantPhoto,
                onTap: _busy
                    ? () {}
                    : () => setState(
                        () => _kind = ContributionKind.restaurantPhoto,
                      ),
              ),
              PillChip(
                label: l10n.photoKindMenu,
                selected: _kind == ContributionKind.menuPhoto,
                onTap: _busy
                    ? () {}
                    : () => setState(() => _kind = ContributionKind.menuPhoto),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.memory(
                  photo.bytes,
                  fit: BoxFit.cover,
                  semanticLabel: photo.name,
                  // An undecodable file shows nothing rather than a red error.
                  errorBuilder: (_, _, _) => ColoredBox(color: p.fillMuted),
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(photo == null ? l10n.photoPick : l10n.photoChange),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _caption,
            enabled: !_busy,
            maxLength: 100,
            decoration: InputDecoration(hintText: l10n.photoCaptionHint),
          ),
          CheckboxListTile(
            value: _consent,
            onChanged: _busy
                ? null
                : (v) => setState(() => _consent = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              l10n.photoConsent,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              l10n.photoPrivateNote,
              style: AppText.caption(context).copyWith(fontSize: 12.5),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(color: p.error, fontSize: 14)),
          ],
          const SizedBox(height: 10),
          FilledButton(
            onPressed: (_busy || photo == null || !_consent) ? null : _submit,
            child: Text(_busy ? l10n.photoSubmitting : l10n.photoSubmit),
          ),
        ],
      ),
    );
  }
}
