import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/widgets/legal_links.dart';
import '../../features/content/models/app_content.dart';
import '../../features/content/providers/app_content_providers.dart';
import '../../features/university/providers/university_providers.dart';
import '../config/env.dart';
import '../l10n/l10n.dart';
import '../theme/app_palette.dart';
import 'responsive.dart';

/// The footer exists on the public website only. A provider (not a bare kIsWeb check) so tests can switch it on;
/// the native Android / iOS apps never show it.
final webFooterEnabledProvider = Provider<bool>((_) => kIsWeb);

/// Sits at the end of a page's scroll content (the shared page shell places it once, pages do not repeat it).
class WebFooterSlot extends ConsumerWidget {
  const WebFooterSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(webFooterEnabledProvider)
      ? const WebFooter()
      : const SizedBox.shrink();
}

/// Four information columns, then the brand line with copyright and the service / legal / feedback links.
/// Everything shown is real: the published announcements, the universities in the database, and contact or legal
/// links only when they are configured (otherwise it says they are not set up yet).
class WebFooter extends ConsumerWidget {
  const WebFooter({super.key});

  /// Content width where the layout is not full width (never on the website).
  static const fallbackContentWidth = 1200.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final notices = [
      for (final c in ref.watch(campusContentProvider))
        if (c.kind == AppContentKind.announcement) c,
    ].take(3).toList();
    final universities = ref.watch(universityListProvider).value?.length;

    final about = _Column(
      title: l10n.footerAboutTitle,
      icon: Icons.restaurant_menu_rounded,
      children: [Text(l10n.footerAboutBody, style: _body(context))],
    );
    final announcements = _Column(
      title: l10n.footerNoticesTitle,
      icon: Icons.campaign_outlined,
      children: [
        if (notices.isEmpty)
          Text(l10n.footerNoticesEmpty, style: _body(context))
        else
          for (final n in notices) _NoticeLink(item: n),
      ],
    );
    final contact = _Column(
      title: l10n.footerContactTitle,
      icon: Icons.chat_bubble_outline_rounded,
      children: [
        Text(l10n.footerContactBody, style: _body(context)),
        const SizedBox(height: 10),
        const FeedbackLink(),
      ],
    );
    final service = _Column(
      title: l10n.footerServiceTitle,
      icon: Icons.school_outlined,
      children: [
        if (universities != null && universities > 0) ...[
          Text(
            l10n.footerUniversities(universities),
            style: _body(context)
                .copyWith(color: p.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
        ],
        Text(l10n.footerServiceNote, style: _body(context)),
      ],
    );

    return Container(
      key: const ValueKey('web-footer'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 32),
      decoration: BoxDecoration(
        color: p.fillMuted,
        // the brand's warm yellow-orange as a complementary accent; primary actions elsewhere stay rust
        border: Border(top: BorderSide(color: p.brandWarm, width: 4)),
      ),
      child: Center(
        child: ConstrainedBox(
          // Edge to edge on the website (the content is inset by the page gutter); a bounded column only where the
          // layout is not full width.
          constraints: BoxConstraints(
            maxWidth: WebLayout.fullWidthOf(context)
                ? double.infinity
                : fallbackContentWidth,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: WebLayout.gutterOf(context, phone: 24),
              vertical: 32,
            ),
            // The column layout depends only on the screen width (not on a LayoutBuilder), so the footer can sit in a
            // SliverFillRemaining, which measures its child's intrinsic size.
            child: Builder(
              builder: (context) {
                final full = WebLayout.fullWidthOf(context);
                final screen = MediaQuery.sizeOf(context).width;
                final width =
                    (full ? screen : screen.clamp(0.0, fallbackContentWidth)) -
                    2 * WebLayout.gutterOf(context, phone: 24);
                final box = (maxWidth: width);
                final columns = [about, announcements, contact, service];
                final Widget top;
                if (box.maxWidth >= Breakpoints.desktop - 48) {
                  top = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < columns.length; i++) ...[
                        if (i > 0) const SizedBox(width: 32),
                        Expanded(child: columns[i]),
                      ],
                    ],
                  );
                } else if (box.maxWidth >= Breakpoints.tablet - 48) {
                  top = Wrap(
                    spacing: 32,
                    runSpacing: 28,
                    children: [
                      for (final c in columns)
                        SizedBox(width: (box.maxWidth - 32) / 2, child: c),
                    ],
                  );
                } else {
                  top = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < columns.length; i++) ...[
                        if (i > 0) const SizedBox(height: 24),
                        columns[i],
                      ],
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    top,
                    const SizedBox(height: 28),
                    Divider(height: 1, color: p.border),
                    const SizedBox(height: 18),
                    const _BrandLine(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static TextStyle _body(BuildContext context) => TextStyle(
    fontSize: 14,
    height: 1.55,
    color: context.palette.textSecondary,
  );
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // a long title may wrap; the icons of all columns stay on one line
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: p.rustText),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _NoticeLink extends StatelessWidget {
  const _NoticeLink({required this.item});

  final AppContent item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final url = Uri.tryParse(item.linkUrl ?? '');
    final openable = url != null && url.scheme == 'https';
    final text = Text(
      item.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: openable ? p.textPrimary : p.textSecondary,
        decoration: openable ? TextDecoration.underline : null,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: openable
          ? InkWell(
              onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
              child: text,
            )
          : text,
    );
  }
}

/// A working way to send feedback: the configured form (FEEDBACK_URL) or mail address (SUPPORT_EMAIL). Nothing
/// configured means no button and an honest note, never an invented address.
class FeedbackLink extends StatelessWidget {
  const FeedbackLink({super.key});

  /// What the link opens, or null when no channel is configured.
  static Uri? get target {
    final url = Env.feedbackUrl;
    if (url != null) return url;
    final mail = Env.supportEmail;
    return mail == null ? null : Uri(scheme: 'mailto', path: mail);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final uri = target;
    if (uri == null) {
      return Text(
        l10n.footerContactNotReady,
        key: const ValueKey('footer-contact-not-ready'),
        style: TextStyle(fontSize: 14, color: p.textMuted),
      );
    }
    return OutlinedButton.icon(
      key: const ValueKey('footer-feedback'),
      onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      icon: const Icon(Icons.mail_outline_rounded, size: 18),
      label: Text(l10n.footerFeedback),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
    );
  }
}

class _BrandLine extends StatelessWidget {
  const _BrandLine();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final year = DateTime.now().year;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      spacing: 24,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: p.rust,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '먹어보조', // the brand name is never translated
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Text(
              '© $year 먹어보조 (Meogeobojo)', // the brand name is never translated
              style: TextStyle(fontSize: 13, color: p.textMuted),
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('footer-about'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(l10n.footerAboutTitle),
                  content: Text(l10n.footerAboutBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonClose),
                    ),
                  ],
                ),
              ),
              child: Text(l10n.footerAboutLink),
            ),
            const LegalLinks(),
            if (FeedbackLink.target != null)
              TextButton(
                onPressed: () => launchUrl(
                  FeedbackLink.target!,
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(l10n.footerFeedback),
              ),
          ],
        ),
      ],
    );
  }
}
