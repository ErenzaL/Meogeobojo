import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/embed/preview_bridge.dart';
import '../../core/l10n/app_language.dart';
import '../../core/l10n/language_controller.dart';
import '../university/providers/university_providers.dart';
import 'phone_preview.dart';

/// The parts of the browser's storage the preview and the website share: the sign-in session, the language and the campus.
const kSyncedStorageParts = [
  'auth-token',
  languagePrefsKey,
  selectedUniversityPrefsKey,
];

/// What changed while the preview was open.
class PreviewChanges {
  const PreviewChanges({
    this.session = false,
    this.language = false,
    this.university = false,
  });

  final bool session;
  final bool language;
  final bool university;

  bool get any => session || language || university;

  static PreviewChanges between(
    Map<String, String> before,
    Map<String, String> after,
  ) {
    bool changed(String part) {
      final keys = {
        ...before.keys,
        ...after.keys,
      }.where((k) => k.contains(part));
      return keys.any((k) => before[k] != after[k]);
    }

    return PreviewChanges(
      session: changed('auth-token'),
      language: changed(languagePrefsKey),
      university: changed(selectedUniversityPrefsKey),
    );
  }
}

/// Opens the preview over the website. When it is closed, anything the user changed inside it (signing in or out, the
/// language, the campus) is applied to the website too, so both always agree.
Future<void> showPhonePreview(BuildContext context, WidgetRef ref) async {
  final before = readSharedStorage(kSyncedStorageParts);
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    barrierDismissible: false, // the dialog handles taps on the dim area itself
    useSafeArea: false,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: SizedBox.expand(
        child: PhonePreviewDialog(url: previewUrl(Uri.base)),
      ),
    ),
  );
  await applyPreviewChanges(
    ref,
    PreviewChanges.between(before, readSharedStorage(kSyncedStorageParts)),
  );
}

Future<void> applyPreviewChanges(WidgetRef ref, PreviewChanges c) async {
  if (!c.any) return;
  // A different account: the whole page starts over on that session (the simplest way to be sure nothing stale stays).
  if (c.session) {
    reloadPage();
    return;
  }
  final sp = ref.read(sharedPreferencesProvider);
  await sp.reload(); // the preview wrote to the same browser storage
  if (c.language) {
    final lang = AppLanguage.fromCode(sp.getString(languagePrefsKey));
    if (lang != null && lang != ref.read(appLanguageProvider)) {
      await ref.read(languageProvider.notifier).select(lang);
    }
  }
  if (c.university) ref.invalidate(selectedUniversityProvider);
}
