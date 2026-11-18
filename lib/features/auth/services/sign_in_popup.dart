import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/embed/preview_bridge.dart';

/// Whether a page that just loaded is the return of the sign-in popup the website's phone preview opened: the address has
/// the OAuth `code`, and the preview left its marker a moment ago. Pure so it can be tested; [markerFresh] is the
/// result of [consumeLoginPopupMarker].
bool isSignInPopupReturn(Uri address, {required bool markerFresh}) =>
    markerFresh && address.queryParameters.containsKey('code');

/// In the sign-in popup: waits for the session the SDK is creating from the OAuth code, then closes the window. The
/// preview (and the page behind it) pick the session up from the browser storage the popup just wrote. If the sign-in
/// fails the popup simply stays open on the site, so the person can read what happened.
void closeSignInPopupWhenDone(
  SupabaseClient client, {
  Duration wait = const Duration(seconds: 20),
}) {
  if (!kIsWeb ||
      !isSignInPopupReturn(Uri.base, markerFresh: consumeLoginPopupMarker())) {
    return;
  }
  if (client.auth.currentSession != null) {
    closeThisWindow();
    return;
  }
  unawaited(
    client.auth.onAuthStateChange
        .firstWhere((s) => s.session != null)
        .timeout(wait)
        .then<void>((_) => closeThisWindow())
        .catchError((_) {}),
  );
}
