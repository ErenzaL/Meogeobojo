import 'package:flutter/material.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/mascot_message.dart';

/// Placeholder for the cafeteria-vs-outside price comparison page: the route
/// exists so the Home button works, the content comes later.
class OutsideCompareScreen extends StatelessWidget {
  const OutsideCompareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeMealCompare)),
      body: MascotMessage(
        asset: AppAssets.mascotSleeping,
        title: l10n.homeMealCompare,
        message: l10n.homeCompareSoon,
      ),
    );
  }
}
