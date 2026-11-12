import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../recommendation/home_ranking.dart';
import '../providers/home_providers.dart';
import 'card_game.dart';
import 'game_candidates.dart';
import 'ladder_game.dart';
import 'roulette_game.dart';

enum PickGame { roulette, ladder, cards }

/// Bottom sheet that lets chance choose: first the candidates (recommended
/// places, or names typed in), then a roulette, a ladder or a card flip. The
/// three games play with the same list, all of it.
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
  GameCandidate? _winner;
  int _round = 0;

  @override
  void initState() {
    super.initState();
    // The recommended places follow the current matches.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(gameSetupProvider.notifier).syncPlaces(widget.recs.ranked);
      }
    });
  }

  List<GameCandidate> get _items =>
      ref.read(gameSetupProvider).candidates(widget.recs.ranked);

  void _start(PickGame g) => setState(() {
    _game = g;
    _winner = null;
    _round++;
  });

  void _menu() => setState(() {
    _game = null;
    _winner = null;
  });

  void _confirm() {
    final place = _winner?.place;
    if (place == null) return;
    ref.read(heroPickProvider.notifier).choose(place.restaurant.kakaoId);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = context.l10n.homeGameChosen(place.restaurant.name);
    Navigator.of(context).pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    // Changing the candidates clears the previous result.
    ref.listen(gameSetupProvider, (prev, next) {
      if (prev != next && _winner != null) setState(() => _winner = null);
    });
    ref.watch(gameSetupProvider);
    final game = _game;
    final winner = _winner;

    final Widget body;
    if (winner != null) {
      body = _Result(
        winner: winner,
        onAgain: () => _start(game!),
        onConfirm: winner.place == null ? null : _confirm,
        onEdit: _menu,
      );
    } else if (game == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CandidateEditor(matches: widget.recs.ranked),
          const SizedBox(height: 18),
          _Menu(onPick: _start, enabled: _items.length >= kGameMin),
        ],
      );
    } else {
      void done(GameCandidate c) => setState(() => _winner = c);
      final items = _items;
      body = KeyedSubtree(
        key: ValueKey('$game-$_round'),
        child: switch (game) {
          PickGame.roulette => RouletteGame(
            items: items,
            onDone: done,
            random: _rnd,
          ),
          PickGame.ladder => LadderGame(
            items: items,
            onDone: done,
            random: _rnd,
          ),
          PickGame.cards => CardGame(items: items, onDone: done, random: _rnd),
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

/// The two ways to fill the list, and the list itself: recommended places to
/// add or take out, or names to add, rename and delete. The count is the
/// list's length; there is no separate number to set.
class _CandidateEditor extends ConsumerStatefulWidget {
  const _CandidateEditor({required this.matches});

  final List<RankedRestaurant> matches;

  @override
  ConsumerState<_CandidateEditor> createState() => _CandidateEditorState();
}

class _CandidateEditorState extends ConsumerState<_CandidateEditor> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _problemText(NameProblem p, String name) => switch (p) {
    NameProblem.empty => context.l10n.gameErrEmpty,
    NameProblem.duplicate => context.l10n.gameErrDuplicate(name.trim()),
    NameProblem.full => context.l10n.gameErrFull(kGameMax),
  };

  void _add() {
    final raw = _input.text;
    final problem = ref.read(gameSetupProvider.notifier).addName(raw);
    setState(
      () => _error = problem == null ? null : _problemText(problem, raw),
    );
    if (problem == null) _input.clear();
  }

  Future<void> _rename(int i, String current) async {
    final l10n = context.l10n;
    final text = TextEditingController(text: current);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void save() {
            final problem = ref
                .read(gameSetupProvider.notifier)
                .rename(i, text.text);
            if (problem == null) {
              Navigator.of(ctx).pop();
            } else {
              setLocal(() => error = _problemText(problem, text.text));
            }
          }

          return AlertDialog(
            title: Text(l10n.gameEditName),
            content: TextField(
              controller: text,
              autofocus: true,
              maxLength: 20,
              onSubmitted: (_) => save(),
              decoration: InputDecoration(errorText: error),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(onPressed: save, child: Text(l10n.commonSave)),
            ],
          );
        },
      ),
    );
    text.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final setup = ref.watch(gameSetupProvider);
    final notifier = ref.read(gameSetupProvider.notifier);
    final matches = widget.matches;
    final count = setup.mode == GameMode.places
        ? setup.candidates(matches).length
        : setup.names.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillChip(
              icon: Icons.restaurant_rounded,
              label: l10n.gameModePlaces,
              selected: setup.mode == GameMode.places,
              onTap: () => notifier.setMode(GameMode.places),
            ),
            PillChip(
              icon: Icons.edit_note_rounded,
              label: l10n.gameModeCustom,
              selected: setup.mode == GameMode.custom,
              onTap: () => notifier.setMode(GameMode.custom),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          l10n.gameCandidatesCount(count, kGameMin, kGameMax),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (setup.mode == GameMode.places) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in setup.candidates(matches))
                InputChip(
                  label: Text(c.name),
                  onDeleted: () =>
                      notifier.togglePlace(c.place!.restaurant.kakaoId),
                  deleteButtonTooltipMessage: l10n.gameRemove,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.gameAddPlacesTitle, style: AppText.caption(context)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in matches.take(12))
                if (!setup.placeIds.contains(m.restaurant.kakaoId))
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: Text(m.restaurant.name),
                    onPressed: count >= kGameMax
                        ? null
                        : () => notifier.togglePlace(m.restaurant.kakaoId),
                  ),
            ],
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 20,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: l10n.gameNameHint,
                    errorText: _error,
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: count >= kGameMax ? null : _add,
                child: Text(l10n.gameAdd),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < setup.names.length; i++)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: p.fillMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      setup.names[i],
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.gameEditName,
                    onPressed: () => _rename(i, setup.names[i]),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: l10n.gameRemove,
                    onPressed: () => notifier.removeName(i),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
        ],
        if (count < kGameMin) ...[
          const SizedBox(height: 10),
          Text(
            l10n.gameNeedTwo(kGameMin),
            style: TextStyle(fontSize: 13.5, color: p.statusWarn),
          ),
        ],
      ],
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.onPick, required this.enabled});

  final ValueChanged<PickGame> onPick;

  /// False until the list holds [kGameMin] candidates.
  final bool enabled;

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
            onTap: enabled ? () => onPick(g) : null,
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
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
      ),
    );
  }
}

/// The result, its whole name. A recommended place adds its kind and walk
/// and can become the pick; a typed name has nothing else to show.
class _Result extends StatelessWidget {
  const _Result({
    required this.winner,
    required this.onAgain,
    required this.onConfirm,
    required this.onEdit,
  });

  final GameCandidate winner;
  final VoidCallback onAgain;

  /// Null for a typed name (it is not a place).
  final VoidCallback? onConfirm;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final place = winner.place;
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
                winner.name,
                textAlign: TextAlign.center,
                softWrap: true,
                style: AppText.sectionTitle.copyWith(fontSize: 26),
              ),
              if (place != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${place.restaurant.categoryTag} · ${l10n.homeWalkAbout(place.walkMinutes)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: p.textSecondary),
                ),
              ],
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
              child: onConfirm == null
                  ? OutlinedButton(
                      onPressed: onEdit,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: shape,
                        side: BorderSide(color: p.hairline),
                      ),
                      child: Text(l10n.gameEditCandidates),
                    )
                  : FilledButton(
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
