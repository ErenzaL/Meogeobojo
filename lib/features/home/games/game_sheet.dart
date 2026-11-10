import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../recommendation/home_ranking.dart';
import '../providers/home_providers.dart';
import 'card_game.dart';
import 'ladder_game.dart';
import 'roulette_game.dart';

enum PickGame { roulette, ladder, cards }

/// Most places a single game puts in play (a wheel / ladder needs few).
int gameSize(PickGame g, int available) => min(available, switch (g) {
  PickGame.roulette => 6,
  PickGame.ladder => 4,
  PickGame.cards => 4,
});

/// [size] places sampled at random from the best of [ranked], so a replay
/// does not always show the same few.
List<RankedRestaurant> gameCandidates(
  List<RankedRestaurant> ranked,
  int size,
  Random random,
) {
  final pool = ranked.take(12).toList()..shuffle(random);
  return pool.take(size).toList();
}

/// Bottom sheet with three ways to let chance choose among the places that
/// match the current conditions: roulette, ladder and card flip.
Future<void> showGameSheet(
  BuildContext context, {
  required HomeRecs recs,
  Random? random,
}) => showCompactSheet<void>(
  context,
  builder: (_) => _GameSheet(recs: recs, random: random),
);

class _GameSheet extends ConsumerStatefulWidget {
  const _GameSheet({required this.recs, this.random});

  final HomeRecs recs;
  final Random? random;

  @override
  ConsumerState<_GameSheet> createState() => _GameSheetState();
}

class _GameSheetState extends ConsumerState<_GameSheet> {
  late final Random _rnd = widget.random ?? Random();
  PickGame? _game;
  RankedRestaurant? _winner;
  List<RankedRestaurant> _items = const [];
  int _round = 0;

  void _start(PickGame g) {
    setState(() {
      _game = g;
      _winner = null;
      _round++;
      _items = gameCandidates(
        widget.recs.ranked,
        gameSize(g, widget.recs.ranked.length),
        _rnd,
      );
    });
  }

  void _menu() => setState(() {
    _game = null;
    _winner = null;
  });

  void _confirm() {
    final w = _winner;
    if (w == null) return;
    ref.read(heroPickProvider.notifier).choose(w.restaurant.kakaoId);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = context.l10n.homeGameChosen(w.restaurant.name);
    Navigator.of(context).pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final game = _game;
    final winner = _winner;

    final Widget body;
    if (winner != null) {
      body = _Result(
        winner: winner,
        onAgain: () => _start(game!),
        onConfirm: _confirm,
      );
    } else if (game == null) {
      body = _Menu(onPick: _start);
    } else {
      void done(RankedRestaurant r) => setState(() => _winner = r);
      body = KeyedSubtree(
        key: ValueKey('$game-$_round'),
        child: switch (game) {
          PickGame.roulette => RouletteGame(
            items: _items,
            onDone: done,
            random: _rnd,
          ),
          PickGame.ladder => LadderGame(
            items: _items,
            onDone: done,
            random: _rnd,
          ),
          PickGame.cards => CardGame(items: _items, onDone: done, random: _rnd),
        },
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (game != null && winner == null)
                IconButton(
                  tooltip: l10n.homeGameBack,
                  onPressed: _menu,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              Expanded(
                child: Text(
                  winner != null ? l10n.homeGameResult : l10n.homeGameTitle,
                  style: AppText.sectionTitle.copyWith(fontSize: 22),
                ),
              ),
            ],
          ),
          if (game == null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.homeGameSub,
              style: AppText.body.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: body,
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.onPick});

  final ValueChanged<PickGame> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final games = [
      (
        PickGame.roulette,
        Icons.pie_chart_rounded,
        l10n.homeGameRoulette,
        l10n.homeGameRouletteHint,
      ),
      (
        PickGame.ladder,
        Icons.stairs_rounded,
        l10n.homeGameLadder,
        l10n.homeGameLadderHint,
      ),
      (
        PickGame.cards,
        Icons.style_rounded,
        l10n.homeGameCards,
        l10n.homeGameCardsHint,
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (g, icon, title, hint) in games) ...[
          _GameTile(
            icon: icon,
            title: title,
            hint: hint,
            onTap: () => onPick(g),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.borderStrong),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: p.rustText, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(fontSize: 14, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.winner,
    required this.onAgain,
    required this.onConfirm,
  });

  final RankedRestaurant winner;
  final VoidCallback onAgain;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.accentSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text(
                winner.restaurant.name,
                textAlign: TextAlign.center,
                style: AppText.sectionTitle.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 6),
              Text(
                '${winner.restaurant.categoryTag} · ${l10n.homeWalkAbout(winner.walkMinutes)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: p.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onAgain,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: shape,
                  side: BorderSide(color: p.hairline),
                ),
                child: Text(l10n.homeGameAgain),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: p.rust,
                  foregroundColor: p.onRust,
                  minimumSize: const Size.fromHeight(52),
                  shape: shape,
                ),
                child: Text(l10n.homeGameConfirm),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
