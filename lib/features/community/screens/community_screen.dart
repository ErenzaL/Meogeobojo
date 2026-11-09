import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../university/models/university_display.dart';
import '../../university/providers/university_providers.dart';

/// 밥수다 (V5): filters, a composer card and the campus feed. Posting is not
/// built yet and no posts exist, so the feed is an honest empty state and the
/// composer actions say that writing is coming (nothing is faked).
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  int _filter = 0;

  void _soon() => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(context.l10n.communityComposeSoon)));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final locale = Localizations.localeOf(context);
    final university = ref.watch(selectedUniversityProvider).value;
    final campus =
        university?.displayName(locale) ?? l10n.universityFallbackName;
    final filters = [
      l10n.communityFilterAll,
      l10n.communityFilterReviews,
      l10n.communityFilterMeets,
      l10n.communityFilterQuestions,
    ];

    return V5Page(
      children: [
        V5Header(
          title: l10n.navCommunity,
          subtitle: l10n.communitySubtitle(campus),
          trailing: TextButton.icon(
            onPressed: _soon,
            icon: const Icon(Icons.history_rounded, size: 20),
            label: Text(l10n.communityMyActivity),
            style: TextButton.styleFrom(foregroundColor: p.textPrimary),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < filters.length; i++)
              PillChip(
                label: filters[i],
                selected: i == _filter,
                onTap: () => setState(() => _filter = i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.fillMuted,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.communityComposerTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _soon,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(l10n.communityWriteReview),
                      style: TextButton.styleFrom(
                        foregroundColor: p.textPrimary,
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _soon,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        l10n.communityStartMeet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _soon,
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: Text(l10n.communityAsk),
                style: TextButton.styleFrom(
                  foregroundColor: p.textPrimary,
                  minimumSize: const Size(0, 44),
                ),
              ),
            ],
          ),
        ),
        V5SectionTitle(l10n.communityFeedTitle),
        V5EmptyState(
          icon: Icons.forum_outlined,
          title: l10n.communityEmptyTitle,
          message: l10n.communityEmptyBody,
        ),
      ],
    );
  }
}
