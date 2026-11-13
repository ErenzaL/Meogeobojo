import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/v5_widgets.dart';
import '../auth/widgets/auth_prompt.dart';
import '../content/models/app_content.dart';
import '../content/providers/app_content_providers.dart';

/// MY → 고객 지원: 공지사항, 문의 및 제안, 이용약관, 개인정보처리방침.
class SupportSection extends ConsumerWidget {
  const SupportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    void push(Widget screen) =>
        Navigator.of(context)
            .push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        V5SectionTitle(l10n.supportTitle),
        V5RowGroup(
          elevated: true,
          rows: [
            V5Row(
              icon: Icons.campaign_outlined,
              title: l10n.footerNoticesTitle,
              onTap: () => push(const NoticesScreen()),
            ),
            V5Row(
              icon: Icons.chat_bubble_outline_rounded,
              title: l10n.footerContactTitle,
              onTap: () => showFeedbackDialog(context, ref),
            ),
            V5Row(
              icon: Icons.description_outlined,
              title: l10n.legalTerms,
              onTap: () => push(const LegalScreen(LegalDoc.terms)),
            ),
            V5Row(
              icon: Icons.privacy_tip_outlined,
              title: l10n.legalPrivacy,
              onTap: () => push(const LegalScreen(LegalDoc.privacy)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 공지사항: the announcements an admin published (앱 콘텐츠 → 공지), newest first.
// ---------------------------------------------------------------------------

class NoticesScreen extends ConsumerWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final tag = Localizations.localeOf(context).toString();
    final notices = [
      for (final c in ref.watch(campusContentProvider))
        if (c.kind == AppContentKind.announcement) c,
    ]..sort((a, b) => (b.time ?? DateTime(0)).compareTo(a.time ?? DateTime(0)));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.footerNoticesTitle)),
      body: notices.isEmpty
          ? Center(
              child: Text(
                l10n.footerNoticesEmpty,
                style: TextStyle(color: p.textSecondary),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notices.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = notices[i];
                final link = n.linkUrl == null ? null : Uri.parse(n.linkUrl!);
                return ExpansionTile(
                  title: Text(
                    n.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: n.time == null
                      ? null
                      : Text(DateFormat.yMd(tag).format(n.time!.toLocal())),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (n.body != null) SelectableText(n.body!),
                    if (link != null)
                      TextButton.icon(
                        onPressed: () => launchUrl(
                          link,
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(l10n.noticeOpenLink),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 문의 및 제안: a `reports` row of type 'feedback' (migration 20261121000100);
// the admin 리뷰·신고 page lists and resolves it. Signed-in users only.
// ---------------------------------------------------------------------------

enum FeedbackCategory { question, suggestion, bug }

typedef FeedbackSender = Future<void> Function(
  FeedbackCategory category,
  String title,
  String body,
);

final feedbackSenderProvider = Provider<FeedbackSender>(
  (_) =>
      (category, title, body) => Supabase.instance.client
          .from('reports')
          .insert({
            'target_type': 'feedback',
            'target_id': category.name,
            'reason': title,
            'description': body,
          })
          .timeout(const Duration(seconds: 15)),
);

/// Asks a guest to sign in first; then the form. True when it was sent.
Future<bool> showFeedbackDialog(BuildContext context, WidgetRef ref) async {
  if (!await requireAuth(context, ref, reason: AuthReason.feedback)) {
    return false;
  }
  if (!context.mounted) return false;
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => const _FeedbackDialog(),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.feedbackSent)));
  }
  return sent == true;
}

class _FeedbackDialog extends ConsumerStatefulWidget {
  const _FeedbackDialog();

  @override
  ConsumerState<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<_FeedbackDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  var _category = FeedbackCategory.question;
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final title = _title.text.trim(), body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(
        () => _error = title.isEmpty
            ? l10n.feedbackNeedTitle
            : l10n.feedbackNeedBody,
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(feedbackSenderProvider)(_category, title, body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('feedback not sent: ${e.runtimeType}');
      if (mounted) {
        setState(() {
          _sending = false;
          _error = l10n.feedbackFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String label(FeedbackCategory c) => switch (c) {
      FeedbackCategory.question => l10n.feedbackCatQuestion,
      FeedbackCategory.suggestion => l10n.feedbackCatSuggestion,
      FeedbackCategory.bug => l10n.feedbackCatBug,
    };
    return AlertDialog(
      title: Text(l10n.footerContactTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                maxLength: 200,
                decoration: InputDecoration(labelText: l10n.feedbackTitleLabel),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<FeedbackCategory>(
                initialValue: _category,
                decoration: InputDecoration(labelText: l10n.feedbackCategory),
                items: [
                  for (final c in FeedbackCategory.values)
                    DropdownMenuItem(value: c, child: Text(label(c))),
                ],
                onChanged: _sending
                    ? null
                    : (c) => setState(() => _category = c ?? _category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                maxLength: 2000,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: l10n.feedbackBodyLabel,
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: context.palette.rustText),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: Text(l10n.feedbackSubmit),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 이용약관 · 개인정보처리방침: bundled text (assets/legal/), shown in the app.
// ---------------------------------------------------------------------------

enum LegalDoc { terms, privacy }

class LegalScreen extends StatelessWidget {
  const LegalScreen(this.doc, {super.key});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          doc == LegalDoc.terms ? l10n.legalTerms : l10n.legalPrivacy,
        ),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('assets/legal/${doc.name}_ko.md'),
        builder: (context, snap) => snap.hasData
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: SelectableText(
                      snap.data!,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
