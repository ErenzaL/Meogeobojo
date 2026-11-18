import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when this page is the mobile-app preview: the website opened the SAME app inside a phone-sized frame with
/// `?embed=phone`. The app then renders its true mobile layout (the frame is 390 px wide, so every responsive rule that
/// applies on a phone applies) and leaves the address bar, the browser history and the desktop-only chrome alone.
/// Only the website can be embedded; the phone apps never are.
bool get isEmbeddedPhone =>
    kIsWeb && Uri.base.queryParameters['embed'] == 'phone';

/// [isEmbeddedPhone] as a provider (overridable in tests).
final embeddedPreviewProvider = Provider<bool>((_) => isEmbeddedPhone);
