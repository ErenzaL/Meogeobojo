import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Dark mode for the Kakao *web* maps: Kakao has no dark map style, so `web/index.html` darkens the map tiles with a
/// CSS filter while `<html>` has the `map-dark` class. Our pins are `data:` images and keep their colours.
void setKakaoMapDark(bool dark) {
  try {
    final html =
        (globalContext['document'] as JSObject)['documentElement'] as JSObject;
    (html['classList'] as JSObject).callMethod(
      'toggle'.toJS,
      'map-dark'.toJS,
      dark.toJS,
    );
  } catch (_) {
    // Only the map's colours are at stake.
  }
}
