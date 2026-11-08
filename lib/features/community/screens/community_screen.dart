import 'package:flutter/material.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/mascot_message.dart';

/// Honest placeholder: no posts are fabricated. (Posting will need an
/// account and go through `requireAuth` when it exists.)
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: MascotMessage(
          asset: AppAssets.mascotCheer,
          title: l10n.communityTitle,
          message: l10n.communityMessage,
        ),
      ),
    );
  }
}
