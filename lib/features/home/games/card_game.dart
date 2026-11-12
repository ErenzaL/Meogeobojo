import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import 'game_candidates.dart';
import 'game_slice_colors.dart';

/// Face-down cards, one per place, already shuffled. Flip one: that place is
/// the result, and the others turn over afterwards to show what they were.
class CardGame extends StatefulWidget {
  const CardGame({
    super.key,
    required this.items,
    required this.onDone,
    this.random,
  });

  final List<GameCandidate> items;
  final ValueChanged<GameCandidate> onDone;
  final Random? random;

  @override
  State<CardGame> createState() => _CardGameState();
}

class _CardGameState extends State<CardGame> {
  late final List<GameCandidate> _cards = [...widget.items]
    ..shuffle(widget.random ?? Random());
  int? _picked;
  bool _revealAll = false;

  Future<void> _pick(int i) async {
    if (_picked != null) return;
    setState(() => _picked = i);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _revealAll = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    widget.onDone(_cards[i]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.homeGameCardsPrompt,
          style: TextStyle(fontSize: 15, color: p.textSecondary),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < _cards.length; i++)
              _FlipCard(
                name: _cards[i].name,
                tag: _cards[i].tag,
                compact: _cards.length > 4,
                index: i,
                flipped: _picked == i || _revealAll,
                dimmed: _revealAll && _picked != i,
                onTap: _picked == null ? () => _pick(i) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({
    required this.name,
    required this.tag,
    required this.index,
    required this.flipped,
    required this.dimmed,
    required this.onTap,
    this.compact = false,
  });

  final String name;
  final String tag;
  final int index;
  final bool flipped;
  final bool dimmed;
  final VoidCallback? onTap;

  /// Five or six cards: smaller, so three fit on a phone row.
  final bool compact;

  double get _w => compact ? 100 : 132;
  double get _h => compact ? 132 : 168;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: onTap != null,
      label: flipped ? name : '${index + 1}',
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: flipped ? 1 : 0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          builder: (_, t, _) {
            final back = t > 0.5;
            final angle = t * pi;
            final (fill, text) = gameSliceColors(p, back ? 1 : 0);
            return Opacity(
              opacity: dimmed ? 0.55 : 1,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(angle),
                child: Container(
                  width: _w,
                  height: _h,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(18),
                    border: back ? Border.all(color: p.rust, width: 2) : null,
                  ),
                  child: back
                      // un-mirror the face so the text reads normally
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(pi),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 3,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          '?',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: text,
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
