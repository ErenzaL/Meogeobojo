import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../../restaurants/screens/restaurant_link_screen.dart';
import '../../restaurants/utils/restaurant_link.dart';
import '../providers/shell_tab_provider.dart';

/// Browser address bar <-> tabs. The five tabs have URLs (`/#/home`, `/#/map`, `/#/community`, `/#/missions`, `/#/profile`);
/// choosing a tab adds a browser history entry, Back / Forward / a typed URL select the tab again and never leave the app
/// on their own. Web only: phones and tests are untouched unless they switch it on.
const _tabPaths = ['/home', '/map', '/community', '/missions', '/profile'];

String shellPathFor(int tab) => _tabPaths[tab.clamp(0, _tabPaths.length - 1)];

/// Whether URL sync is active (the website). Overridable so tests can exercise it.
final urlSyncEnabledProvider = Provider<bool>((_) => kIsWeb);

/// Reports the address bar. `replace: true` rewrites the current history entry, false adds one.
typedef UrlReporter = Future<void> Function(Uri uri, {required bool replace});

final urlReporterProvider = Provider<UrlReporter>(
  (_) =>
      (uri, {required replace}) =>
          SystemNavigator.routeInformationUpdated(uri: uri, replace: replace),
);

/// Switches the browser to multi-entry history (without it Back would leave the site at once).
final urlHistoryModeProvider = Provider<Future<void> Function()>(
  (_) => SystemNavigator.selectMultiEntryHistory,
);

/// A URL change made by the browser (Back / Forward / typed address) reaches the Navigator as a named push. This route
/// is that push: it closes anything stacked on the shell (an open detail screen), selects the tab and disappears, so the
/// Navigator never gets a duplicate shell or an "unknown route" error.
class UrlTabRoute extends PageRouteBuilder<void> {
  // No route name on purpose: Flutter's root Navigator announces every NAMED route to the browser, which would add a
  // second history entry for what the browser already did.
  UrlTabRoute(int tab)
    : super(
        settings: const RouteSettings(),
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => _UrlTabLanding(tab: tab),
      );
}

Route<dynamic>? generateUrlRoute(RouteSettings settings) {
  // A restaurant's own address (a pasted or shared link, Forward).
  final link = restaurantLinkOf(settings.name);
  if (link != null) return restaurantLinkRoute(link);
  final tab = shellTabForPath(settings.name);
  return tab == null ? null : UrlTabRoute(tab);
}

/// A path that names no tab (a mistyped address) opens Home.
Route<dynamic> unknownUrlRoute(RouteSettings settings) =>
    UrlTabRoute(ShellTabs.home);

class _UrlTabLanding extends ConsumerStatefulWidget {
  const _UrlTabLanding({required this.tab});

  final int tab;

  @override
  ConsumerState<_UrlTabLanding> createState() => _UrlTabLandingState();
}

class _UrlTabLandingState extends ConsumerState<_UrlTabLanding> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(shellTabProvider.notifier).selectFromUrl(widget.tab);
      Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A screen opened over the shell (a restaurant, a settings page ...) adds one history entry for the current tab, so
/// the browser Back button closes that screen instead of leaving the site or jumping to another tab.
class UrlHistoryObserver extends NavigatorObserver {
  UrlHistoryObserver(this._ref);

  final WidgetRef _ref;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is UrlTabRoute || route is! PageRoute) {
      return;
    }
    if (!_ref.read(urlSyncEnabledProvider)) return;
    if (route is RestaurantDetailRoute) {
      // A restaurant has its own address, so a refresh keeps it open.
      if (!route.fromBrowser) {
        _ref.read(urlReporterProvider)(Uri.parse(route.path), replace: false);
      }
      return;
    }
    final tab = _ref.read(shellTabProvider);
    _ref.read(urlReporterProvider)(
      Uri(path: shellPathFor(tab)),
      replace: false,
    );
  }

  /// Leaving a restaurant with the app's own back button: the address bar
  /// must not keep naming it (a refresh would reopen it).
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! RestaurantDetailRoute) return;
    if (!_ref.read(urlSyncEnabledProvider)) return;
    final under = previousRoute;
    _ref.read(urlReporterProvider)(
      under is RestaurantDetailRoute
          ? Uri.parse(under.path)
          : Uri(path: shellPathFor(_ref.read(shellTabProvider))),
      replace: true,
    );
  }
}
