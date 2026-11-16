import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import 'demo_providers.dart';

/// Shown on Home while demo mode is on, so simulated data is never mistaken for verified information.
class DemoModeBanner extends ConsumerWidget {
  const DemoModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoModeProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final p = context.palette;
    return Container(
      key: const ValueKey('demo-mode-banner'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.accentFaint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.statusWarn),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: p.statusWarn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.demoBannerTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.demoBannerBody,
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
