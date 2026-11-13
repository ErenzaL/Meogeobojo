import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import 'game_candidates.dart';
import 'game_slice_colors.dart';

/// Rungs of a ladder with [columns] lines and [rows] levels: rungs[row][gap]
/// joins line `gap` and `gap + 1`. Two rungs never touch the same line on one
/// level, so a path is always unambiguous.
List<List<bool>> buildLadder(int columns, int rows, Random random) => [
  for (var r = 0; r < rows; r++)
    () {
      final row = List<bool>.filled(columns - 1, false);
      for (var g = 0; g < columns - 1; g++) {
        if (g > 0 && row[g - 1]) continue;
        row[g] = random.nextBool();
      }
      return row;
    }(),
];

/// The line a walker that starts on [start] ends on.
int ladderEnd(List<List<bool>> rungs, int start) {
  var col = start;
  for (final row in rungs) {
    if (col < row.length && row[col]) {
      col++;
    } else if (col > 0 && row[col - 1]) {
      col--;
    }
  }
  return col;
}

/// A ladder game: pick a line at the top, a marker walks down it, and the
/// place at the bottom of the line it ends on is the result.
class LadderGame extends StatefulWidget {
  const LadderGame({
    super.key,
    required this.items,
    required this.onDone,
    this.random,
  });

  final List<GameCandidate> items;
  final ValueChanged<GameCandidate> onDone;
  final Random? random;

  @override
  State<LadderGame> createState() => _LadderGameState();
}

class _LadderGameState extends State<LadderGame>
    with SingleTickerProviderStateMixin {
  static const _rows = 8;
  late final Random _rnd = widget.random ?? Random();
  late final List<List<bool>> _rungs = buildLadder(
    widget.items.length,
    _rows,
    _rnd,
  );
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  int? _start;
  bool _revealed = false;

  Future<void> _go(int start) async {
    if (_start != null) return;
    setState(() => _start = start);
    await _c.forward();
    if (!mounted) return;
    setState(() => _revealed = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    widget.onDone(widget.items[ladderEnd(_rungs, start)]);
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
    final n = widget.items.length;
    final end = _start == null ? null : ladderEnd(_rungs, _start!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.homeGameLadderPrompt,
          style: TextStyle(fontSize: 15, color: p.textSecondary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Center(
                  child: _Marker(
                    label: '${i + 1}',
                    index: i,
                    chosen: _start == i,
                    onTap: _start == null ? () => _go(i) : null,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 220,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              painter: _LadderPainter(
                rungs: _rungs,
                columns: n,
                start: _start,
                progress: _c.value,
                palette: p,
              ),
            ),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _Slot(
                    text: _revealed ? shortName(widget.items[i].name, 5) : '?',
                    hit: _revealed && end == i,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.label,
    required this.index,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final int index;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (fill, text) = gameSliceColors(p, chosen ? 0 : 1);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.text, required this.hit});

  final String text;
  final bool hit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      decoration: BoxDecoration(
        color: hit ? p.rust : p.fillMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: hit ? p.onRust : p.textPrimary,
        ),
      ),
    );
  }
}

class _LadderPainter extends CustomPainter {
  _LadderPainter({
    required this.rungs,
    required this.columns,
    required this.start,
    required this.progress,
    required this.palette,
  });

  final List<List<bool>> rungs;
  final int columns;
  final int? start;
  final double progress;
  final AppPalette palette;

  double _x(Size s, int col) => (col + 0.5) * s.width / columns;
  double _y(Size s, int row) => (row + 1) * s.height / (rungs.length + 1);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = palette.borderStrong
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var c = 0; c < columns; c++) {
      canvas.drawLine(
        Offset(_x(size, c), 0),
        Offset(_x(size, c), size.height),
        line,
      );
    }
    for (var r = 0; r < rungs.length; r++) {
      for (var g = 0; g < columns - 1; g++) {
        if (rungs[r][g]) {
          canvas.drawLine(
            Offset(_x(size, g), _y(size, r)),
            Offset(_x(size, g + 1), _y(size, r)),
            line,
          );
        }
      }
    }
    final s = start;
    if (s == null) return;
    // the walked path: down, across at each rung, down to the bottom
    final path = Path()..moveTo(_x(size, s), 0);
    var col = s;
    for (var r = 0; r < rungs.length; r++) {
      final row = rungs[r];
      path.lineTo(_x(size, col), _y(size, r));
      if (col < row.length && row[col]) {
        col++;
        path.lineTo(_x(size, col), _y(size, r));
      } else if (col > 0 && row[col - 1]) {
        col--;
        path.lineTo(_x(size, col), _y(size, r));
      }
    }
    path.lineTo(_x(size, col), size.height);
    final metric = path.computeMetrics().first;
    final shown = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      shown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = palette.rust,
    );
    final tangent = metric.getTangentForOffset(metric.length * progress);
    if (tangent != null) {
      canvas.drawCircle(tangent.position, 9, Paint()..color = palette.rust);
      canvas.drawCircle(tangent.position, 4, Paint()..color = palette.onRust);
    }
  }

  @override
  bool shouldRepaint(_LadderPainter old) =>
      old.progress != progress || old.start != start || old.palette != palette;
}
