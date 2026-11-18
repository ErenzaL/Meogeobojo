import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/embed/preview_bridge.dart';

/// What the app wears INSIDE the website's phone preview, to look and behave like the iPhone simulator (iPhone 17 Pro):
///  * the status-bar and home-indicator areas are reserved (as MediaQuery padding: 62 above, 34 below, the real iPhone
///    values), so SafeArea, the bottom bar and scrolling content keep clear of them exactly as on the phone;
///  * a status bar is drawn there (the time, signal, Wi-Fi and battery) with the dynamic island and the home indicator, in
///    dark or light ink to match the app's theme. They are decoration only and never catch the mouse;
///  * when ANOTHER page of the site changes the sign-in (a Kakao login finished in its popup) this page reloads and picks
///    the session up.
/// With [enabled] false (the website itself and the phone apps) it adds nothing at all.
class EmbeddedPhoneChrome extends StatefulWidget {
  const EmbeddedPhoneChrome({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  /// iPhone 17 Pro: the safe areas and the dynamic island.
  static const topInset = 62.0;
  static const bottomInset = 34.0;
  static const islandWidth = 125.0;
  static const islandHeight = 36.0;
  static const islandTop = 14.0;

  @override
  State<EmbeddedPhoneChrome> createState() => _EmbeddedPhoneChromeState();
}

class _EmbeddedPhoneChromeState extends State<EmbeddedPhoneChrome> {
  static const _sessionKey = 'auth-token';
  late Map<String, String> _session;
  void Function()? _stop;
  Timer? _clock;
  DateTime _now = DateTime.now();

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
    // the status bar shows the real time, like the simulator's
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  static bool _differs(Map<String, String> a, Map<String, String> b) =>
      a.length != b.length || a.entries.any((e) => b[e.key] != e.value);

  @override
  void dispose() {
    _stop?.call();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final mq = MediaQuery.of(context);
    final top = math.max(mq.padding.top, EmbeddedPhoneChrome.topInset);
    final bottom = math.max(mq.padding.bottom, EmbeddedPhoneChrome.bottomInset);
    // dark ink on a light app, white ink on a dark one (as iOS does)
    final ink = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
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
                  top: 0,
                  left: 0,
                  right: 0,
                  height:
                      EmbeddedPhoneChrome.islandTop +
                      EmbeddedPhoneChrome.islandHeight / 2 +
                      12,
                  child: _StatusBar(now: _now, ink: ink),
                ),
                Positioned(
                  top: EmbeddedPhoneChrome.islandTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      key: const ValueKey('phone-island'),
                      width: EmbeddedPhoneChrome.islandWidth,
                      height: EmbeddedPhoneChrome.islandHeight,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(
                          EmbeddedPhoneChrome.islandHeight / 2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      key: const ValueKey('phone-home-bar'),
                      width: 134,
                      height: 5,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(3),
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

/// The iOS status bar: the time on the left of the island, signal / Wi-Fi / battery on the right.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.now, required this.ink});

  final DateTime now;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final h12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final time = '$h12:${now.minute.toString().padLeft(2, '0')}';
    const centreY =
        EmbeddedPhoneChrome.islandTop + EmbeddedPhoneChrome.islandHeight / 2;
    return Stack(
      children: [
        Positioned(
          left: 0,
          width: 402 / 2 - EmbeddedPhoneChrome.islandWidth / 2,
          top: centreY - 12,
          height: 24,
          child: Center(
            child: Text(
              time,
              key: const ValueKey('phone-time'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: ink,
                height: 1.2,
                // the chrome sits above the Navigator, outside any Material: without this the default style underlines it
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          width: 402 / 2 - EmbeddedPhoneChrome.islandWidth / 2,
          top: centreY - 12,
          height: 24,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // no cellular in the simulator: four small dots
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                const SizedBox(width: 3),
                Icon(Icons.wifi_rounded, size: 18, color: ink),
                const SizedBox(width: 5),
                _Battery(ink: ink),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.ink});

  final Color ink;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 25,
        height: 12.5,
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          border: Border.all(color: ink.withValues(alpha: 0.4), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Container(
        width: 1.5,
        height: 4.5,
        margin: const EdgeInsets.only(left: 1),
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.4),
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(1),
          ),
        ),
      ),
    ],
  );
}
