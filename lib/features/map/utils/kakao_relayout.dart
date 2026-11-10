// Tells the Kakao *web* map that its container changed size (browser window resized, the desktop list panel appeared,
// the map tab became visible again). The plugin has no relayout call, so `web/index.html` tracks the map instances and
// exposes `__meogeobojoRelayout`, which re-measures each map and puts it back on the same centre and zoom (so the
// selected university and any manual pan / zoom survive). Elsewhere this does nothing.
export 'kakao_relayout_stub.dart'
    if (dart.library.js_interop) 'kakao_relayout_web.dart';
