# Mobile app preview (website)

The phone icon next to the language switch in the desktop header opens the **real** mobile app inside a phone-sized frame,
so visitors can use it without installing anything.

## How it works

* The preview is an `<iframe>` of the SAME website, opened with `?embed=phone`, and it is exactly 390 x 844 CSS pixels
  (only scaled visually to fit the window). The app inside therefore sees a genuine phone viewport and uses its normal
  mobile layout: bottom bar, mobile header, the same screens, providers, Supabase calls and the AI chat. There are no
  mockup screens and no separate data.
* Same origin, so the Supabase session, the language and the campus (browser storage) are shared automatically.
* In embedded mode (`lib/core/embed/embed_mode.dart`) the app: does not touch the address bar or history, does not use the
  full-width website layout, does not count as an extra "app open", hides the preview button, reserves the status-bar and
  home-indicator areas as a phone does (`EmbeddedPhoneChrome`), and runs the Kakao login in a small popup window (Kakao refuses
  to be shown in a frame). It is the website's own login: same redirect and PKCE exchange. The popup closes itself once signed
  in (`sign_in_popup.dart`), and the preview picks the session up from the shared storage and reloads itself. Email
  sign-in needs no redirect and runs inside the phone. If the browser blocks the popup, a normal new tab is used.
* The map is the website's own map: the preview is the same page, so it uses the same Kakao key and registered domain.
* When the preview closes, a change made inside it is applied to the page: a different sign-in reloads the page; a
  different language or campus is applied without a reload (`preview_sync.dart`).
* The phone apps and the normal website are unchanged: none of this runs unless the page was opened with `?embed=phone`.

## Files

`lib/features/preview/` (dialog, frame, sync, in-frame chrome), `lib/core/embed/` (embed flag and the few browser calls,
with a no-op stub off the web), the button in `lib/features/navigation/widgets/web_header.dart`,
`test/features/preview/`.

## Keep in mind

* Do not send `X-Frame-Options: DENY` or a `frame-ancestors` policy on the web site; use `SAMEORIGIN` / `'self'`.
* The Kakao map in the preview needs the same Kakao JS key and registered domain as the site (it is the same page).
* Two copies of the app run while the preview is open (the page and the frame), so the first open takes a few seconds.
