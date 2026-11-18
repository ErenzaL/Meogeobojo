import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject get _window => globalContext;

/// Turns the created `<iframe>` into a phone-sized page: it is [width] x [height] CSS pixels (so the app inside sees a
/// genuine phone viewport and lays itself out as on a phone) and is only SCALED visually to fit the window.
void configurePreviewIframe(
  Object element, {
  required String src,
  required double width,
  required double height,
  required double scale,
  required double radius,
  required void Function() onLoaded,
}) {
  final el = element as JSObject;
  final style = el['style'] as JSObject;
  style['border'] = '0'.toJS;
  style['width'] = '${width}px'.toJS;
  style['height'] = '${height}px'.toJS;
  style['transformOrigin'] = '0 0'.toJS;
  style['transform'] = 'scale($scale)'.toJS;
  style['background'] = '#ffffff'.toJS;
  style['borderRadius'] = '${radius}px'.toJS;
  style['overflow'] = 'hidden'.toJS;
  el.callMethod(
    'addEventListener'.toJS,
    'load'.toJS,
    ((JSAny _) => onLoaded()).toJS,
  );
  el['title'] = '먹어보조'.toJS;
  el['src'] = src.toJS;
}

void scalePreviewIframe(Object element, double scale) {
  final style = (element as JSObject)['style'] as JSObject;
  style['transform'] = 'scale($scale)'.toJS;
}

Map<String, String> readSharedStorage(List<String> keyParts) {
  final out = <String, String>{};
  try {
    final storage = _window['localStorage'] as JSObject;
    final n = (storage['length'] as JSNumber).toDartInt;
    for (var i = 0; i < n; i++) {
      final key = (storage.callMethod('key'.toJS, i.toJS) as JSString?)?.toDart;
      if (key == null || !keyParts.any(key.contains)) continue;
      final v =
          (storage.callMethod('getItem'.toJS, key.toJS) as JSString?)?.toDart;
      if (v != null) out[key] = v;
    }
  } catch (_) {
    // storage blocked: nothing to compare
  }
  return out;
}

void Function() listenStorageChanges(void Function() onChange) {
  final listener = ((JSAny _) => onChange()).toJS;
  _window.callMethod('addEventListener'.toJS, 'storage'.toJS, listener);
  return () =>
      _window.callMethod('removeEventListener'.toJS, 'storage'.toJS, listener);
}

void reloadPage() {
  (_window['location'] as JSObject).callMethod('reload'.toJS);
}

const _popupMarker = 'meogeobojo.login_popup';

bool openLoginPopup(String url) {
  try {
    double num(String k) => ((_window[k] as JSNumber?)?.toDartDouble) ?? 0;
    const w = 480.0, h = 760.0;
    final left = (num('screenX') + (num('outerWidth') - w) / 2).round();
    final top = (num('screenY') + (num('outerHeight') - h) / 2).round();
    final win = _window.callMethod(
      'open'.toJS,
      url.toJS,
      'meogeobojo_login'.toJS,
      'popup=yes,width=${w.round()},height=${h.round()},left=$left,top=$top'
          .toJS,
    );
    return win != null;
  } catch (_) {
    return false;
  }
}

void markLoginPopup() {
  try {
    (_window['localStorage'] as JSObject).callMethod(
      'setItem'.toJS,
      _popupMarker.toJS,
      DateTime.now().millisecondsSinceEpoch.toString().toJS,
    );
  } catch (_) {}
}

bool consumeLoginPopupMarker() {
  try {
    final storage = _window['localStorage'] as JSObject;
    final raw = (storage.callMethod(
      'getItem'.toJS,
      _popupMarker.toJS,
    ) as JSString?)?.toDart;
    if (raw == null) return false;
    storage.callMethod('removeItem'.toJS, _popupMarker.toJS);
    final at = int.tryParse(raw);
    return at != null &&
        DateTime.now().millisecondsSinceEpoch - at < 5 * 60 * 1000;
  } catch (_) {
    return false;
  }
}

void closeThisWindow() {
  _window.callMethod('close'.toJS);
}
