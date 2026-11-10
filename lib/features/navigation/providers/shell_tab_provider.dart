import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab indexes of the persistent shell.
abstract final class ShellTabs {
  static const home = 0;
  static const map = 1;
  static const community = 2;
  static const missions = 3;
  static const profile = 4;
}

/// Selected bottom-nav tab. A provider (not widget state) so that auth flows
/// can send the user back to the tab they left.
final shellTabProvider = NotifierProvider<ShellTabController, int>(
  ShellTabController.new,
);

/// The browser URL path of each tab (`/#/map` opens the map directly).
const _tabPaths = <String, int>{
  '': ShellTabs.home,
  'home': ShellTabs.home,
  'map': ShellTabs.map,
  'community': ShellTabs.community,
  'missions': ShellTabs.missions,
  'profile': ShellTabs.profile,
};

/// The tab a URL path names, or null when it names none (then Home opens, never an error page).
int? shellTabForPath(String? route) {
  if (route == null) return null;
  final path = Uri.tryParse(route)?.path ?? '';
  final name = path.replaceAll(RegExp(r'^/+|/+$'), '').split('/').first;
  return _tabPaths[name.toLowerCase()];
}

class ShellTabController extends Notifier<int> {
  /// Opens on the tab the URL asks for (direct links), Home otherwise. Tests and phones start at '/'.
  @override
  int build() =>
      shellTabForPath(
        WidgetsBinding.instance.platformDispatcher.defaultRouteName,
      ) ??
      ShellTabs.home;

  void select(int index) => state = index;
}
