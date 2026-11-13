import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../support/support.dart';

/// 이용약관 · 개인정보처리방침: the documents bundled with the app
/// ([LegalScreen]), or the URLs in TERMS_URL / PRIVACY_URL when those are set.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  Future<void> _open(BuildContext context, Uri? url, LegalDoc doc) async {
    if (url == null) {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc)));
      return;
    }
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.legalOpenFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget link(String text, Uri? url, LegalDoc doc) => TextButton(
      onPressed: () => _open(context, url, doc),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        foregroundColor: context.palette.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(
        text,
        style: AppText.link(context)
            .copyWith(decoration: TextDecoration.underline),
      ),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link(l10n.legalTerms, Env.termsUrl, LegalDoc.terms),
        Text('·', style: TextStyle(color: context.palette.textSecondary)),
        link(l10n.legalPrivacy, Env.privacyUrl, LegalDoc.privacy),
      ],
    );
  }
}
