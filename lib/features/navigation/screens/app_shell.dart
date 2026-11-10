import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../community/screens/community_screen.dart';
import '../../home/screens/home_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../missions/screens/mission_screen.dart';
import '../../missions/widgets/mission_celebration_host.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/sync/content_sync.dart';
import '../../university/providers/university_account_sync.dart';
import '../providers/shell_tab_provider.dart';
import '../widgets/web_header.dart';
import '../widgets/floating_nav_bar.dart';

/// Persistent five-tab shell. Tabs live in an [IndexedStack] so each keeps
/// its state (Home scroll position, map camera). Tabs other than Home are
/// built on first visit, which also keeps the Kakao map out of startup.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _builders = <WidgetBuilder>[
    _home,
    _map,
    _community,
    _missions,
    _profile,
  ];

  static Widget _home(BuildContext _) => const HomeScreen();
  static Widget _community(BuildContext _) => const CommunityScreen();
  static Widget _map(BuildContext _) => const MapScreen();
  static Widget _missions(BuildContext _) => const MissionScreen();
  static Widget _profile(BuildContext _) => const ProfileScreen();

  final _visited = <int>{ShellTabs.home};
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the app (or the browser tab) re-reads what admins
    // published: photos, menus, hidden places. No rebuild or restart needed.
    _lifecycle = AppLifecycleListener(
      onResume: () => refreshAllContent(_container),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _syncTimer?.cancel();
    super.dispose();
  }

  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  Timer? _syncTimer;
  final _pendingTables = <String>{};

  /// A burst of admin edits (a save touches several rows) becomes one refresh.
  void _onContentChanged(String table) {
    _pendingTables.add(table);
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      for (final t in _pendingTables) {
        invalidateForTable(_container, t);
      }
      _pendingTables.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Published changes arrive live (Realtime) and refresh the screens that
    // show them. Silent when Realtime is unavailable.
    // The campus follows the account (server-side mission eligibility).
    ref.watch(universityAccountSyncProvider);
    ref.listen(contentChangesProvider, (_, next) {
      final table = next.value;
      if (table != null) _onContentChanged(table);
    });
    return MissionCelebrationHost(child: _shell(context));
  }

  Widget _shell(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    _visited.add(index);

    final mq = MediaQuery.of(context);
    final metrics = FloatingNavMetrics.of(mq);
    final keyboardOpen = mq.viewInsets.bottom > 0;

    final tabs = IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < _builders.length; i++)
          _visited.contains(i)
              ? _builders[i](context)
              : const SizedBox.shrink(),
      ],
    );

    // Wide windows (desktop browsers): header on top, no bottom bar.
    if (mq.size.width >= Breakpoints.desktop) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            const WebHeader(),
            Expanded(
              child: MediaQuery(
                data: mq.copyWith(padding: mq.padding.copyWith(bottom: 24)),
                child: tabs,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      // The tab screens extend behind the bar; the keyboard must not resize or
      // push the shell (the bar simply steps aside below).
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Tab screens see the bar's footprint as bottom padding, so
          // SafeArea / scroll padding keep content clear of it.
          Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(bottom: metrics.reservedBottom),
              ),
              child: tabs,
            ),
          ),
          Positioned(
            left: metrics.sideMargin,
            right: metrics.sideMargin,
            bottom: metrics.bottomMargin,
            child: IgnorePointer(
              ignoring: keyboardOpen,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                offset: keyboardOpen ? const Offset(0, 1.6) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: keyboardOpen ? 0 : 1,
                  child: FloatingNavBar(
                    index: index,
                    metrics: metrics,
                    onTap: (i) => ref.read(shellTabProvider.notifier).select(i),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
