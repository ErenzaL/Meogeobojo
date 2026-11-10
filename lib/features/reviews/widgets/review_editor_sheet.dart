import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../auth/providers/auth_providers.dart';
import '../../missions/providers/mission_providers.dart';
import '../../restaurants/models/restaurant.dart';
import '../../university/providers/university_providers.dart';
import '../models/student_review.dart';
import '../providers/review_providers.dart';

/// Write, change or delete the signed-in student's review of [restaurant].
/// The caller has already checked that the user is signed in.
Future<void> showReviewEditorSheet(
  BuildContext context, {
  required Restaurant restaurant,
  StudentReview? existing,
}) => showCompactSheet<void>(
  context,
  builder: (_) => _ReviewEditor(restaurant: restaurant, existing: existing),
);

class _ReviewEditor extends ConsumerStatefulWidget {
  const _ReviewEditor({required this.restaurant, this.existing});

  final Restaurant restaurant;
  final StudentReview? existing;

  @override
  ConsumerState<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends ConsumerState<_ReviewEditor> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_rating == 0) {
      setState(() => _error = l10n.reviewRatingRequired);
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    final saved = l10n.reviewSaved;
    try {
      await ref
          .read(reviewRepositoryProvider)
          .save(
            userId: user.id,
            kakaoId: widget.restaurant.kakaoId,
            universityId: ref.read(selectedUniversityProvider).value?.id,
            rating: _rating,
            body: _body.text,
          );
      ref.invalidate(restaurantReviewsProvider(widget.restaurant.kakaoId));
      ref.invalidate(myReviewsProvider);
      // A review can complete a mission: the server recomputes.
      ref.read(missionDashboardProvider.notifier).refresh();
      if (!mounted) return;
      nav.pop();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(saved)));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.reviewSaveFailed;
        });
      }
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.reviewDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.reviewDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    final deleted = l10n.reviewDeleted;
    try {
      await ref.read(reviewRepositoryProvider).delete(widget.existing!.id);
      ref.invalidate(restaurantReviewsProvider(widget.restaurant.kakaoId));
      ref.invalidate(myReviewsProvider);
      if (!mounted) return;
      nav.pop();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(deleted)));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.reviewSaveFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
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
            widget.existing == null ? l10n.reviewWrite : l10n.reviewEditMine,
            style: AppText.sectionTitle.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 2),
          Text(
            widget.restaurant.name,
            style: AppText.caption(context).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.reviewRating,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Semantics(
                  button: true,
                  selected: i <= _rating,
                  label: '$i',
                  child: IconButton(
                    onPressed: _busy ? null : () => setState(() => _rating = i),
                    iconSize: 36,
                    icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: i <= _rating ? p.starAmber : p.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            enabled: !_busy,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(hintText: l10n.reviewEditorHint),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(color: p.error, fontSize: 14)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (widget.existing != null)
                OutlinedButton(
                  onPressed: _busy ? null : _delete,
                  child: Text(l10n.reviewDelete),
                ),
              if (widget.existing != null) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(l10n.reviewSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
