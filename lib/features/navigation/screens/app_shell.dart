import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../community/screens/community_screen.dart';
import '../../home/screens/home_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../records/screens/records_screen.dart';
import '../providers/shell_tab_provider.dart';
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
    _community,
    _map,
    _records,
    _profile,
  ];

  static Widget _home(BuildContext _) => const HomeScreen();
  static Widget _community(BuildContext _) => const CommunityScreen();
  static Widget _map(BuildContext _) => const MapScreen();
  static Widget _records(BuildContext _) => const RecordsScreen();
  static Widget _profile(BuildContext _) => const ProfileScreen();

  final _visited = <int>{ShellTabs.home};

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    _visited.add(index);

    final mq = MediaQuery.of(context);
    final metrics = FloatingNavMetrics.of(mq);
    final keyboardOpen = mq.viewInsets.bottom > 0;

    return Scaffold(
      // The tab screens extend behind the floating bar; the keyboard must not
      // resize or push the shell (the bar simply steps aside below).
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Tab screens see the bar's footprint as bottom padding, so
          // SafeArea / scroll padding keep content clear of it, while a
          // screen that wants to (Home, the map) can draw underneath.
          Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(bottom: metrics.reservedBottom),
              ),
              child: IndexedStack(
                index: index,
                children: [
                  for (var i = 0; i < _builders.length; i++)
                    _visited.contains(i)
                        ? _builders[i](context)
                        : const SizedBox.shrink(),
                ],
              ),
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
