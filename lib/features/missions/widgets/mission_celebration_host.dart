import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../models/mission_models.dart';
import '../providers/mission_providers.dart';

/// Wraps the app shell and shows a short, quiet celebration whenever the
/// server reports a mission completed ("미션 완료! +15P 획득"), on any tab.
/// Each completion is shown once: the queue is cleared as it is taken.
class MissionCelebrationHost extends ConsumerStatefulWidget {
  const MissionCelebrationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MissionCelebrationHost> createState() =>
      _MissionCelebrationHostState();
}

class _MissionCelebrationHostState
    extends ConsumerState<MissionCelebrationHost> {
  final _queue = <CompletedMission>[];
  CompletedMission? _current;
  bool _visible = false;
  Timer? _timer;

  static const _shown = Duration(milliseconds: 2600);
  static const _fade = Duration(milliseconds: 260);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _take(List<CompletedMission> done) {
    if (done.isEmpty) return;
    ref.read(missionCelebrationProvider.notifier).clear();
    _queue.addAll(done);
    if (_current == null) _next();
  }

  void _next() {
    if (!mounted) return;
    if (_queue.isEmpty) {
      setState(() {
        _current = null;
        _visible = false;
      });
      return;
    }
    setState(() {
      _current = _queue.removeAt(0);
      _visible = true;
    });
    _timer?.cancel();
    _timer = Timer(_shown, () {
      if (!mounted) return;
      setState(() => _visible = false);
      _timer = Timer(_fade + const Duration(milliseconds: 80), _next);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(missionCelebrationProvider, (_, next) => _take(next));
    final c = _current;
    return Stack(
      children: [
        widget.child,
        if (c != null)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 8,
            child: IgnorePointer(
              child: Center(
                child: AnimatedSlide(
                  duration: _fade,
                  curve: Curves.easeOutCubic,
                  offset: _visible ? Offset.zero : const Offset(0, -0.6),
                  child: AnimatedOpacity(
                    duration: _fade,
                    opacity: _visible ? 1 : 0,
                    child: _Toast(done: c),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.done});

  final CompletedMission done;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${l10n.missionCelebrationTitle} ${done.title}',
      child: Material(
        color: p.chipSelectedBg,
        elevation: 6,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Image.asset(
                    AppAssets.mascotSparkle,
                    width: 44,
                    height: 44,
                    cacheWidth: 132,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.missionCelebrationTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: p.chipSelectedFg,
                        ),
                      ),
                      Text(
                        done.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: p.chipSelectedFg.withValues(alpha: 0.85),
                        ),
                      ),
                      Text(
                        done.points > 0
                            ? l10n.missionCelebrationPoints(done.points)
                            : (done.badgeKey != null
                                  ? l10n.missionCelebrationBadge
                                  : ''),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: p.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
