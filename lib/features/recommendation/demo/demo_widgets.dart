import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import 'demo_providers.dart';

/// The demo-mode switch (only where the build has one: demo builds and debug runs).
class DemoModeSwitchTile extends ConsumerWidget {
  const DemoModeSwitchTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoAvailableProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    return SwitchListTile(
      key: const ValueKey('demo-mode-switch'),
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.demoSwitchTitle),
      subtitle: Text(l10n.demoSwitchSubtitle),
      value: ref.watch(demoModeProvider),
      onChanged: (v) => ref.read(demoModeProvider.notifier).set(v),
    );
  }
}
