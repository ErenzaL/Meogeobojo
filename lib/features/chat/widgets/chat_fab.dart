import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_controller.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// The floating mascot's diameter for a screen [width]: 64 on a small phone, 72 on a phone, 80 on a tablet, 88 on a
/// desktop. The steps follow the screen instead of one fixed size, and the mascot always fills most of the circle.
double chatFabSizeFor(double width) {
  if (width < 375) return 64;
  if (width < 600) return 72;
  if (width < 1024) return 80;
  return 88;
}

/// The round mascot that opens the assistant. Only the picture: no permanent label (a tooltip on hover/long-press and a
/// screen-reader label say what it does). The artwork keeps its proportions (contain, never cropped).
class ChatFab extends ConsumerWidget {
  const ChatFab({super.key, required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mascot = ref.watch(chatMascotProvider);
    final p = context.palette;
    final label = context.l10n.chatOpenLabel;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.accentSoft,
            border: Border.all(color: p.card, width: 3),
            boxShadow: [
              BoxShadow(
                color: p.shadow.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('chat-fab'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Padding(
                  padding: EdgeInsets.all(size * 0.1),
                  // A new pose fades in; the picture is never cropped or stretched.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Image.asset(
                      mascot,
                      key: ValueKey(mascot),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
