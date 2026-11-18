import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/chat_controller.dart';

/// A speech bubble above the mascot that says "this is an AI chat", without a permanent label:
///  * once after the app opens: a sparkle and a short invitation, which fades by itself;
///  * each time the mascot changes pose after the chat was minimized: three typing dots for a moment.
/// Both are finite (nothing animates forever), a tap on either opens the chat, and with "reduce motion" they are not
/// shown at all.
class ChatHintBubble extends ConsumerStatefulWidget {
  const ChatHintBubble({
    super.key,
    required this.fabSize,
    required this.maxWidth,
    required this.onTap,
    this.introDelay = const Duration(milliseconds: 1400),
  });

  final double fabSize;
  final double maxWidth;
  final VoidCallback onTap;
  final Duration introDelay;

  @override
  ConsumerState<ChatHintBubble> createState() => _ChatHintBubbleState();
}

enum _Hint { intro, dots }

class _ChatHintBubbleState extends ConsumerState<ChatHintBubble>
    with SingleTickerProviderStateMixin {
  static const _introMs = 8000, _dotsMs = 2600;

  late final AnimationController _c = AnimationController(vsync: this);
  _Hint _hint = _Hint.intro;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) return;
    // The invitation waits a moment so it does not fight the first screen for attention.
    _play(_Hint.intro, delay: widget.introDelay);
  }

  void _play(_Hint hint, {Duration delay = Duration.zero}) {
    final total = hint == _Hint.intro ? _introMs : _dotsMs;
    final lead = delay.inMilliseconds;
    setState(() => _hint = hint);
    _c.duration = Duration(milliseconds: lead + total);
    // value 0..lead is the wait; the bubble's own life is the rest
    _lead = lead / (lead + total);
    _c.forward(from: 0);
  }

  double _lead = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0 hidden .. 1 fully shown, for the bubble's life (grow in, hold, fade out).
  double _shown(double v) {
    if (v <= _lead) return 0;
    final t = (v - _lead) / (1 - _lead);
    const inEnd = 0.06, outStart = 0.9;
    if (t < inEnd) {
      return Curves.easeOutBack.transform(t / inEnd).clamp(0.0, 1.0);
    }
    if (t > outStart) {
      return 1 - Curves.easeIn.transform((t - outStart) / (1 - outStart));
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    // A new pose (the chat was minimized or closed): show the typing dots.
    ref.listen(chatMascotProvider, (prev, next) {
      if (prev != null &&
          prev != next &&
          !MediaQuery.of(context).disableAnimations) {
        _play(_Hint.dots);
      }
    });
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final s = _shown(_c.value);
        if (s <= 0.001) return const SizedBox.shrink();
        final bubble = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.border),
              boxShadow: [
                BoxShadow(
                  color: p.shadow.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: _hint == _Hint.intro
                  ? _Invitation(text: context.l10n.chatHint)
                  : _Dots(phase: _c.value),
            ),
          ),
        );
        return ExcludeSemantics(
          child: Opacity(
            opacity: s.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.85 + 0.15 * s,
              alignment: Alignment.bottomRight,
              // Material only supplies the text style: the bubble sits over the shell, outside any Scaffold.
              child: Material(
                type: MaterialType.transparency,
                child: GestureDetector(
                  key: const ValueKey('chat-hint'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      bubble,
                      // the tail points at the middle of the mascot
                      Padding(
                        padding: EdgeInsets.only(
                          right: math.max(8, widget.fabSize / 2 - 8),
                        ),
                        child: CustomPaint(
                          size: const Size(16, 8),
                          painter: _Tail(fill: p.card, line: p.border),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Invitation extends StatelessWidget {
  const _Invitation({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_rounded, size: 16, color: p.accent),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.title.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Three dots that rise in turn, in the brand's orange tones.
class _Dots extends StatelessWidget {
  const _Dots({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = [p.accentSoft, p.accent, p.accentStrong];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 7),
            child: Transform.translate(
              offset: Offset(
                0,
                -3.5 *
                    math.max(0, math.sin((phase * 5 - i * 0.18) * 2 * math.pi)),
              ),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tail extends CustomPainter {
  _Tail({required this.fill, required this.line});

  final Color fill, line;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // cover the bubble's own border where the tail joins it
    canvas.drawLine(
      const Offset(1, -0.5),
      Offset(size.width - 1, -0.5),
      Paint()
        ..color = fill
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_Tail old) => old.fill != fill || old.line != line;
}
