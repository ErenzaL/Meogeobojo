import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../providers/review_providers.dart';
import '../repositories/review_repository.dart';

/// Report a review to the moderators (one open report per user and review).
Future<void> showReportSheet(
  BuildContext context, {
  required String reviewId,
}) => showCompactSheet<void>(
  context,
  builder: (_) => _ReportSheet(reviewId: reviewId),
);

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.reviewId});

  final String reviewId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  bool _busy = false;
  String? _error;

  Future<void> _send(String reason) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(reviewRepositoryProvider)
          .report(reviewId: widget.reviewId, reason: reason);
      if (!mounted) return;
      nav.pop();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              outcome == ReportOutcome.sent
                  ? l10n.reportSent
                  : l10n.reportAlready,
            ),
          ),
        );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.reportFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reasons = [
      l10n.reportReasonAbuse,
      l10n.reportReasonSpam,
      l10n.reportReasonFalse,
      l10n.reportReasonOther,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.reportTitle,
            style: AppText.sectionTitle.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in reasons)
                PillChip(
                  label: r,
                  selected: _reason == r,
                  onTap: _busy ? () {} : () => setState(() => _reason = r),
                ),
            ],
          ),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_busy || _reason == null)
                ? null
                : () => _send(_reason!),
            child: Text(l10n.reportSend),
          ),
        ],
      ),
    );
  }
}
