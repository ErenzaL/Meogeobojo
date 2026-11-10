import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_palette.dart';
import '../models/app_content.dart';
import '../providers/app_content_providers.dart';

/// Notices and banners an admin published, under the Home header. Nothing is
/// shown (and no space is taken) when there are none.
class HomeNotices extends ConsumerWidget {
  const HomeNotices({super.key});

  static const maxShown = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(homeNoticesProvider).take(maxShown).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          for (final c in items) ...[
            _NoticeCard(item: c),
            if (c != items.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.item});

  final AppContent item;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(item.linkUrl ?? '');
    if (uri == null || uri.scheme != 'https') return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tappable = item.linkUrl != null;
    final image = item.kind == AppContentKind.banner ? item.imageUrl : null;
    return Semantics(
      button: tappable,
      label: item.title,
      child: Material(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tappable ? () => _open(context) : null,
          child: Row(
            children: [
              if (image != null)
                SizedBox(
                  width: 96,
                  height: 72,
                  child: Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(color: p.fillMuted),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.rustText,
                        ),
                      ),
                      if (item.body != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.body!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (tappable)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(Icons.chevron_right_rounded, color: p.rustText),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
