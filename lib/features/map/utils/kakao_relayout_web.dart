import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void relayoutKakaoMaps() {
  try {
    if (globalContext.has('__meogeobojoRelayout')) {
      globalContext.callMethod('__meogeobojoRelayout'.toJS);
    }
  } catch (_) {
    // A failed re-measure only leaves the map as it was.
  }
}
