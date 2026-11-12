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
import '../../content/providers/app_content_providers.dart';
import '../../university/providers/university_account_sync.dart';
import '../../university/providers/university_providers.dart';
import '../providers/shell_tab_provider.dart';
import '../../restaurants/screens/restaurant_link_screen.dart';
import '../../restaurants/utils/restaurant_link.dart';
import '../utils/url_sync.dart';
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
    // published: announcements, photos, menus, hidden places. No rebuild or
    // restart needed. While the app is in the background nothing polls.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        refreshAllContent(_container);
        _container.read(contentSyncEngineProvider)?.retryFailed();
        _startPolling();
      },
      onInactive: _stopPolling,
      onHide: _stopPolling,
      onPause: _stopPolling,
    );
    _startPolling();
    _startUrlSync();
  }

  /// Website: history becomes multi-entry and the first entry names the tab the page opened on, so the very first Back
  /// returns to a known state instead of an anonymous one.
  void _startUrlSync() {
    if (!ref.read(urlSyncEnabledProvider)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(urlHistoryModeProvider)();
      if (!mounted) return;
      await ref.read(urlReporterProvider)(
        Uri(path: shellPathFor(ref.read(shellTabProvider))),
        replace: true,
      );
      // Opened on a restaurant's address (a shared link, a refresh on the
      // details): show that place over Home, which Back then returns to.
      final link = restaurantLinkOf(initialShellRoute());
      if (link != null && mounted) {
        await Navigator.of(context)
            .push(restaurantLinkRoute(link, fromBrowser: false));
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _syncTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Safety net under Realtime: a Realtime event can be missed (a dropped
  /// connection, an update that row-level security hides), so the cheap live
  /// content is re-read once a minute while the app is in the foreground.
  void _startPolling() {
    _pollTimer?.cancel();
    final every = ref.read(contentPollIntervalProvider);
    _pollTimer = Timer.periodic(every, (_) {
      if (mounted) refreshLiveContent(_container);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  Timer? _syncTimer;
  Timer? _pollTimer;
  final _pendingTables = <String>{};

  /// A burst of admin edits (a save touches several rows) becomes one refresh.
  void _onContentChanged(ContentChange change) {
    _pendingTables.add(change.source);
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final tables = {..._pendingTables};
      _pendingTables.clear();
      if (tables.contains(ContentChange.resyncSource)) {
        refreshAllContent(
          _container,
        ); // reconnected: events may have been missed
      } else {
        for (final t in tables) {
          invalidateForTable(_container, t);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Published changes arrive live (Realtime) and refresh the screens that
    // show them. Silent when Realtime is unavailable.
    // The campus follows the account (server-side mission eligibility).
    ref.watch(universityAccountSyncProvider);
    ref.listen(contentChangesProvider, (_, next) {
      final change = next.value;
      if (change != null) _onContentChanged(change);
    });
    // A different campus, or coming back to Home: re-read the announcements
    // (the list is global, the campus only filters it, but this also clears
    // anything that went stale while another tab was open).
    ref.listen(selectedUniversityProvider, (prev, next) {
      if (prev?.value?.id != next.value?.id) ref.invalidate(appContentProvider);
    });
    ref.listen(shellTabProvider, (prev, next) {
      if (next == ShellTabs.home && prev != ShellTabs.home) {
        ref.invalidate(appContentProvider);
      }
      // Website: a tab the user chose becomes the address (and a browser history entry). A tab the BROWSER asked for
      // (Back / Forward / typed URL) is already the address.
      if (ref.read(urlSyncEnabledProvider) &&
          !ref.read(shellTabProvider.notifier).takeFromUrl()) {
        ref.read(urlReporterProvider)(
          Uri(path: shellPathFor(next)),
          replace: false,
        );
      }
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
