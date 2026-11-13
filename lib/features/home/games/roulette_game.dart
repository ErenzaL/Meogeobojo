import 'dart:math';

import '../../../core/theme/app_theme.dart';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import 'game_candidates.dart';
import 'game_slice_colors.dart';

/// A wheel with one slice per place. The winner is drawn first, then the wheel
/// spins down to it, so what stops under the pointer is the real result.
class RouletteGame extends StatefulWidget {
  const RouletteGame({
    super.key,
    required this.items,
    required this.onDone,
    this.random,
  });

  final List<GameCandidate> items;
  final ValueChanged<GameCandidate> onDone;
  final Random? random;

  @override
  State<RouletteGame> createState() => _RouletteGameState();
}

class _RouletteGameState extends State<RouletteGame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );
  late final Random _rnd = widget.random ?? Random();
  double _from = 0;
  double _to = 0;
  bool _spinning = false;

  double get _angle =>
      _from + (_to - _from) * Curves.easeOutCubic.transform(_c.value);

  Future<void> _spin() async {
    final n = widget.items.length;
    final winner = _rnd.nextInt(n);
    final slice = 2 * pi / n;
    // Land somewhere inside the winner's slice, not always dead centre.
    final jitter = (_rnd.nextDouble() - 0.5) * slice * 0.7;
    final turns = 5 + _rnd.nextInt(2);
    final base = _angle % (2 * pi);
    setState(() {
      _spinning = true;
      _from = base;
      _to = 2 * pi * turns - (winner + 0.5) * slice + jitter;
    });
    _c.reset();
    await _c.forward();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _spinning = false);
    widget.onDone(widget.items[winner]);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final size = min(box.maxWidth, 300.0);
            return SizedBox(
              width: size,
              height: size + 18,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 18,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, _) => Transform.rotate(
                        angle: _angle,
                        child: CustomPaint(
                          size: Size.square(size),
                          painter: _WheelPainter(
                            names: [for (final i in widget.items) i.name],
                            palette: p,
                            textStyle: TextStyle(
                              fontFamily: AppText.fontFamily,
                              fontSize: size < 260 ? 12 : 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // pointer
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 48,
                    color: p.textPrimary,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _spinning ? null : _spin,
          style: FilledButton.styleFrom(
            backgroundColor: p.rust,
            foregroundColor: p.onRust,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(_spinning ? l10n.homeGameSpinning : l10n.homeGameSpin),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.names,
    required this.palette,
    required this.textStyle,
  });

  final List<String> names;
  final AppPalette palette;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final n = names.length;
    final slice = 2 * pi / n;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < n; i++) {
      final start = -pi / 2 + i * slice;
      final (fill, text) = gameSliceColors(palette, i);
      canvas.drawArc(rect, start, slice, true, Paint()..color = fill);
      canvas.drawArc(
        rect,
        start,
        slice,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = palette.card,
      );
      // label along the slice's centre line, reading outwards
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(start + slice / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: shortName(names[i], 6),
          style: textStyle.copyWith(color: text),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: radius * 0.66);
      tp.paint(canvas, Offset(radius * 0.28, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(center, 16, Paint()..color = palette.card);
    canvas.drawCircle(
      center,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = palette.hairline,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.names != names || old.palette != palette;
}
