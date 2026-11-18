// The few browser calls the phone preview needs (an iframe's size / scale / load, localStorage, the storage event, a
// page reload). Real on the web, harmless no-ops elsewhere, so nothing else in the app imports a web library.
export 'preview_bridge_stub.dart'
    if (dart.library.js_interop) 'preview_bridge_web.dart';
