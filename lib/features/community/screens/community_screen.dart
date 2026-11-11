import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../../core/widgets/web_footer.dart';

/// 밥수다 is not open yet: an honest "coming soon" page with the cheering
/// mascot. No posts are fabricated. (When posting exists it will need an
/// account and go through `requireAuth`.)
///
/// It sits inside [V5Page] like the other tabs, so the website footer and the
/// room under the floating nav bar keep working. In the apps the message is
/// centred in most of the screen; on the website it is a compact block and the
/// footer is pinned to the bottom of the window below it.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final web = ref.watch(webFooterEnabledProvider);
    final minHeight = web
        ? 320.0
        : math.max(360.0, MediaQuery.sizeOf(context).height * 0.7);
    return V5Page(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: MascotMessage(
            asset: AppAssets.mascotCheer,
            title: l10n.communityTitle,
            message: l10n.communityMessage,
          ),
        ),
      ],
    );
  }
}
