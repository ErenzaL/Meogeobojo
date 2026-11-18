/// Non-web: there is no browser to talk to.
void configurePreviewIframe(
  Object element, {
  required String src,
  required double width,
  required double height,
  required double scale,
  required double radius,
  required void Function() onLoaded,
}) {}

void scalePreviewIframe(Object element, double scale) {}

/// The localStorage entries whose keys contain one of [keyParts] (sign-in session, language, campus).
Map<String, String> readSharedStorage(List<String> keyParts) => const {};

/// Calls [onChange] when ANOTHER page of this site changes localStorage (for instance a sign-in finished in a new tab).
/// Returns the function that stops listening.
void Function() listenStorageChanges(void Function() onChange) => () {};

void reloadPage() {}

/// Opens [url] in a small sign-in window (a popup). False when the browser blocked it.
bool openLoginPopup(String url) => false;

/// Remembers (for a few minutes, in the browser storage shared by the whole site) that a sign-in popup was opened.
void markLoginPopup() {}

/// True once if this page is the return of a sign-in popup opened a moment ago (and forgets it).
bool consumeLoginPopupMarker() => false;

void closeThisWindow() {}
