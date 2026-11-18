import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/responsive.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../navigation/widgets/floating_nav_bar.dart';
import '../providers/chat_controller.dart';
import 'chat_fab.dart';
import 'chat_hint.dart';
import 'chat_panel.dart';

/// Where the assistant sits, for a window of [size]: the mascot button's diameter and position, and the panel's frame.
/// Pure so every screen size can be checked in tests.
class ChatPlacement {
  const ChatPlacement({
    required this.fabSize,
    required this.fabRight,
    required this.fabBottom,
    required this.floatingPanel,
    required this.panelWidth,
    required this.panelHeight,
    required this.panelRight,
    required this.panelBottom,
    required this.panelTop,
  });

  final double fabSize;
  final double fabRight;
  final double fabBottom;

  /// A card floating at the corner (tablet, desktop) instead of a sheet over the whole phone screen.
  final bool floatingPanel;
  final double panelWidth;
  final double panelHeight;
  final double panelRight;
  final double panelBottom;
  final double panelTop;

  /// [navReserved] is what the bottom bar takes (0 on a desktop, which has a header instead).
  factory ChatPlacement.of(
    Size size, {
    required double safeTop,
    required double safeBottom,
    required double navReserved,
    double keyboard = 0,
  }) {
    final w = size.width;
    final desktop = w >= Breakpoints.desktop;
    final floating = w >= Breakpoints.tablet;
    final fab = chatFabSizeFor(w);
    final right = desktop ? 24.0 : (floating ? 20.0 : 16.0);
    // On a phone / tablet the button clears the bottom bar; on a desktop it sits near the corner.
    final bottom = desktop ? 24.0 + safeBottom : navReserved + 12;
    if (!floating) {
      return ChatPlacement(
        fabSize: fab,
        fabRight: right,
        fabBottom: bottom,
        floatingPanel: false,
        panelWidth: w,
        panelHeight: size.height - safeTop - 8 - keyboard,
        panelRight: 0,
        panelBottom: keyboard,
        panelTop: safeTop + 8,
      );
    }
    final panelBottom = keyboard > 0 ? keyboard + 12 : bottom;
    final width = (w - right * 2).clamp(0.0, desktop ? 400.0 : 380.0);
    final top = safeTop + (desktop ? 72.0 : 16.0);
    final height = (size.height - top - panelBottom).clamp(320.0, 640.0);
    return ChatPlacement(
      fabSize: fab,
      fabRight: right,
      fabBottom: bottom,
      floatingPanel: true,
      panelWidth: width,
      panelHeight: height,
      panelRight: right,
      panelBottom: panelBottom,
      panelTop: top,
    );
  }
}

/// The assistant over the app shell: a round mascot button that opens the chat, which minimizes back to the mascot.
/// The conversation lives in [chatControllerProvider] and the panel stays mounted once opened, so minimizing keeps the
/// messages, the draft, the scroll position and the open menus.
class ChatOverlay extends ConsumerStatefulWidget {
  const ChatOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends ConsumerState<ChatOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 190),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    // The state may already be open (the shell rebuilt).
    if (ref.read(chatPanelProvider).open) _anim.value = 1;
  }

  bool _warmed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the mascot poses once, so a new one appears without a flash.
    if (_warmed) return;
    _warmed = true;
    for (final a in AppAssets.chatMascots) {
      precacheImage(AssetImage(a), context).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatPanelProvider.select((s) => s.open), (_, open) {
      if (open) {
        _anim.forward();
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
        _anim.reverse();
      }
    });
    final panel = ref.watch(chatPanelProvider);
    final tab = ref.watch(shellTabProvider);
    final mq = MediaQuery.of(context);
    final metrics = FloatingNavMetrics.of(mq);
    final desktop = mq.size.width >= Breakpoints.desktop;
    final place = ChatPlacement.of(
      mq.size,
      safeTop: mq.padding.top,
      safeBottom: mq.viewPadding.bottom,
      navReserved: desktop ? 0 : metrics.reservedBottom,
      keyboard: mq.viewInsets.bottom,
    );
    // The map tab has its own sheet and place card where the button would sit: on phones and tablets the mascot
    // steps aside there (it is one tap away on every other tab).
    final hideFab = tab == ShellTabs.map && !desktop;

    return PopScope(
      // On Android the back button minimizes an open chat before it leaves the screen.
      canPop: !panel.open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(chatPanelProvider.notifier).minimize();
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (panel.everOpened) _panel(context, place, panel.open),
          if (!hideFab) _fab(place, panel.open, mq.size.width),
        ],
      ),
    );
  }

  Widget _fab(ChatPlacement place, bool open, double screenWidth) => Positioned(
    right: place.fabRight,
    bottom: place.fabBottom,
    child: AnimatedBuilder(
      animation: _t,
      builder: (_, child) {
        final v = 1 - _t.value;
        return IgnorePointer(
          ignoring: open || v < 0.5,
          child: Opacity(
            opacity: v,
            child: Transform.scale(
              scale: 0.6 + 0.4 * v,
              alignment: Alignment.bottomRight,
              child: child,
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ChatHintBubble(
            fabSize: place.fabSize,
            maxWidth: math.min(250, screenWidth - place.fabRight - 16),
            onTap: ref.read(chatPanelProvider.notifier).open,
          ),
          const SizedBox(height: 2),
          ChatFab(
            size: place.fabSize,
            onTap: ref.read(chatPanelProvider.notifier).open,
          ),
        ],
      ),
    ),
  );

  Widget _panel(BuildContext context, ChatPlacement place, bool open) {
    final p = context.palette;
    final notifier = ref.read(chatPanelProvider.notifier);
    final radius = place.floatingPanel
        ? BorderRadius.circular(22)
        : const BorderRadius.vertical(top: Radius.circular(22));
    final content = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): notifier.minimize,
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: p.card,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            // The keyboard replaces the bottom inset; with it closed the input stays above the home indicator.
            bottom: MediaQuery.of(context).viewInsets.bottom == 0,
            child: ChatPanel(
              onMinimize: notifier.minimize,
              onClose: notifier.closeAndClear,
            ),
          ),
        ),
      ),
    );

    final animated = AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Offstage(
        offstage: _anim.isDismissed,
        child: IgnorePointer(
          ignoring: !open,
          child: TickerMode(
            enabled: !_anim.isDismissed,
            child: FadeTransition(
              opacity: _t,
              child: place.floatingPanel
                  ? ScaleTransition(
                      scale: Tween(begin: 0.86, end: 1.0).animate(_t),
                      alignment: Alignment.bottomRight,
                      child: child,
                    )
                  : SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(_t),
                      child: child,
                    ),
            ),
          ),
        ),
      ),
      child: content,
    );

    return place.floatingPanel
        ? Positioned(
            right: place.panelRight,
            bottom: place.panelBottom,
            width: place.panelWidth,
            height: place.panelHeight,
            child: animated,
          )
        : Positioned(
            left: 0,
            right: 0,
            top: place.panelTop,
            bottom: place.panelBottom,
            child: animated,
          );
  }
}
