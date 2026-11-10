import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';

void main() {
  test('a direct link names its tab; anything else opens Home, never an error', () {
    expect(shellTabForPath('/map'), ShellTabs.map);
    expect(shellTabForPath('/community'), ShellTabs.community);
    expect(shellTabForPath('/missions'), ShellTabs.missions);
    expect(shellTabForPath('/profile'), ShellTabs.profile);
    expect(shellTabForPath('/home'), ShellTabs.home);
    expect(shellTabForPath('/'), ShellTabs.home);
    expect(shellTabForPath('/MAP/'), ShellTabs.map);
    expect(shellTabForPath('/map?university=1'), ShellTabs.map);
    expect(shellTabForPath('/nonsense'), isNull); // the controller falls back to Home
    expect(shellTabForPath(null), isNull);
  });
}
