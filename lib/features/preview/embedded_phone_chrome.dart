import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/embed/preview_bridge.dart';

/// What the app wears INSIDE the website's phone preview, to behave like a real phone:
///  * the status-bar and home-indicator areas are reserved (as MediaQuery padding), so SafeArea, the bottom bar and the
///    scrolling content keep clear of them exactly as on a phone;
///  * a small island and a home bar are drawn there (decoration only, never touched by the mouse);
///  * when ANOTHER page of the site changes the sign-in (a Kakao login finished in its new tab) this page reloads and
///    picks the session up.
/// With [enabled] false (the website itself and the phone apps) it adds nothing at all.
class EmbeddedPhoneChrome extends StatefulWidget {
  const EmbeddedPhoneChrome({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  static const topInset = 44.0;
  static const bottomInset = 20.0;

  @override
  State<EmbeddedPhoneChrome> createState() => _EmbeddedPhoneChromeState();
}

class _EmbeddedPhoneChromeState extends State<EmbeddedPhoneChrome> {
  static const _sessionKey = 'auth-token';
  late Map<String, String> _session;
  void Function()? _stop;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _session = readSharedStorage(const [_sessionKey]);
    _stop = listenStorageChanges(() {
      final now = readSharedStorage(const [_sessionKey]);
      if (_differs(_session, now)) {
        _session = now;
        reloadPage();
      }
    });
  }

  static bool _differs(Map<String, String> a, Map<String, String> b) =>
      a.length != b.length || a.entries.any((e) => b[e.key] != e.value);

  @override
  void dispose() {
    _stop?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final mq = MediaQuery.of(context);
    final top = math.max(mq.padding.top, EmbeddedPhoneChrome.topInset);
    final bottom = math.max(mq.padding.bottom, EmbeddedPhoneChrome.bottomInset);
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(top: top, bottom: bottom),
        viewPadding: mq.viewPadding.copyWith(top: top, bottom: bottom),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          IgnorePointer(
            child: Stack(
              children: [
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      key: const ValueKey('phone-island'),
                      width: 96,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      key: const ValueKey('phone-home-bar'),
                      width: 120,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
