import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab indexes of the persistent shell.
abstract final class ShellTabs {
  static const home = 0;
  static const community = 1;
  static const map = 2;
  static const records = 3;
  static const profile = 4;
}

/// Selected bottom-nav tab. A provider (not widget state) so that auth flows
/// can send the user back to the tab they left.
final shellTabProvider = NotifierProvider<ShellTabController, int>(
  ShellTabController.new,
);

class ShellTabController extends Notifier<int> {
  @override
  int build() => ShellTabs.home;

  void select(int index) => state = index;
}
