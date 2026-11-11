import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../auth/models/auth_failure.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/widgets/auth_fields.dart';
import '../../language/widgets/language_button.dart';
import '../../recommendation/preference_filter.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../../university/models/university_display.dart';
import '../../university/providers/university_providers.dart';
import '../../university/widgets/university_sheet.dart';
import '../models/user_preferences.dart';
import '../providers/preferences_providers.dart';
import '../widgets/preference_widgets.dart';
import 'preference_labels.dart';
import '../../../core/theme/app_palette.dart';

enum PreferencesMode {
  /// Shown once per account right after the first sign-in.
  firstTime,

  /// Opened from MY → 나의 취향 설정; pre-filled, never resets onboarding.
  edit,
}

class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key, required this.mode, this.random});

  final PreferencesMode mode;

  /// Injectable for tests.
  final Random? random;

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  UserPreferences _draft = const UserPreferences();
  bool _seeded = false;
  bool _saving = false;
  bool _showMissing = false;
  Object? _saveError;

  final _budgetKey = GlobalKey();
  final _distanceKey = GlobalKey();

  bool get _isFirstTime => widget.mode == PreferencesMode.firstTime;

  void _update(UserPreferences next) => setState(() {
    _draft = next;
    _saveError = null;
  });

  Future<void> _save() async {
    if (_saving) return;
    if (!_draft.isComplete) {
      setState(() => _showMissing = true);
      final target = _draft.budget == null ? _budgetKey : _distanceKey;
      final ctx = target.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
        );
      }
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final university = ref.read(selectedUniversityProvider).value;
      final toSave = _draft.copyWith(universityId: () => university?.id);
      final profile = await ref
          .read(preferencesRepositoryProvider)
          .save(toSave);
      if (!mounted) return;
      ref.read(userPreferencesProvider.notifier).setSaved(toSave);
      // First time: this flips the account to "ready", and the auth flow
      // host closes onboarding and shows the result. Edit: close ourselves.
      ref.read(authControllerProvider.notifier).applyProfile(profile);
      if (!_isFirstTime) {
        final messenger = ScaffoldMessenger.of(context);
        final message = context.l10n.prefsSaved;
        Navigator.of(context).pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint('preferences save failed: ${e.runtimeType}');
      if (mounted) setState(() => _saveError = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _random(List<dynamic> eligible) {
    final l10n = context.l10n;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.onbRandomNone)));
      return;
    }
    final pick = eligible[(widget.random ?? Random()).nextInt(eligible.length)];
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RestaurantDetailScreen(restaurant: pick),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (!_isFirstTime && !_seeded) {
      final saved = ref.watch(userPreferencesProvider);
      if (saved.isLoading) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.prefsEditTitle)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      if (saved.hasError) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.prefsEditTitle)),
          body: MascotMessage(
            asset: AppAssets.mascotSleeping,
            title: l10n.prefsLoadFailed,
            actionLabel: l10n.commonRetry,
            onAction: () => ref.invalidate(userPreferencesProvider),
          ),
        );
      }
      _draft = saved.value ?? const UserPreferences();
      _seeded = true;
    }

    final nearby = ref.watch(allNearbyRestaurantsProvider);
    final eligible = nearby.hasValue
        ? applyPreferences(nearby.requireValue, _draft)
        : null;
    final count = eligible?.length;
    final university = ref.watch(selectedUniversityProvider).value;

    final body = Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              4,
              AppSpacing.screenH,
              20,
            ),
            children: [
              _Header(isFirstTime: _isFirstTime),
              const SizedBox(height: 14),
              _CampusTile(
                label: university == null
                    ? l10n.universityFallbackName
                    : university.displayName(Localizations.localeOf(context)),
              ),
              const SizedBox(height: 14),
              _budgetCard(l10n),
              _distanceCard(l10n),
              _companionCard(l10n),
              _foodCard(l10n),
              AuthMessage.info(l10n.onbFilterNote),
            ],
          ),
        ),
        _ActionBar(
          count: count,
          saving: _saving,
          isFirstTime: _isFirstTime,
          error: _saveError,
          canClear: _draft != const UserPreferences(),
          onClear: () => _update(const UserPreferences()),
          onRandom: () => _random(eligible ?? const []),
          onSave: _save,
        ),
      ],
    );

    final scaffold = Scaffold(
      backgroundColor: context.palette.background,
      appBar: _isFirstTime ? null : AppBar(title: Text(l10n.prefsEditTitle)),
      body: SafeArea(bottom: false, child: body),
    );
    // First-time onboarding is a required step; leaving is only possible by
    // signing out (button in the header).
    return _isFirstTime ? PopScope(canPop: false, child: scaffold) : scaffold;
  }

  Widget _budgetCard(AppLocalizations l10n) => KeyedSubtree(
    key: _budgetKey,
    child: PrefCard(
      number: 1,
      title: l10n.onbBudgetTitle,
      badge: l10n.onbBadgeRequired,
      description: l10n.onbBudgetDesc,
      errorText: _showMissing && _draft.budget == null
          ? l10n.onbNeedBudget
          : null,
      child: PrefChipWrap(
        children: [
          for (final o in BudgetOption.values)
            PrefChip(
              label: budgetLabel(l10n, o),
              selected: _draft.budget == o,
              onTap: () => _update(_draft.copyWith(budget: () => o)),
            ),
        ],
      ),
    ),
  );

  Widget _distanceCard(AppLocalizations l10n) {
    Widget row(IconData icon, String semantics, List<DistanceOption> options) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, right: 10),
                child: Icon(
                  icon,
                  size: 22,
                  color: context.palette.textSecondary,
                  semanticLabel: semantics,
                ),
              ),
              Expanded(
                child: PrefChipWrap(
                  children: [
                    for (final o in options)
                      PrefChip(
                        label: distanceLabel(l10n, o),
                        selected: _draft.distance == o,
                        onTap: () =>
                            _update(_draft.copyWith(distance: () => o)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    return KeyedSubtree(
      key: _distanceKey,
      child: PrefCard(
        number: 2,
        title: l10n.onbDistanceTitle,
        badge: l10n.onbBadgeRequired,
        description: l10n.onbDistanceDesc,
        errorText: _showMissing && _draft.distance == null
            ? l10n.onbNeedDistance
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(Icons.directions_walk_rounded, l10n.onbWalkLabel, const [
              DistanceOption.walk5,
              DistanceOption.walk10,
              DistanceOption.walk15,
            ]),
            row(Icons.directions_car_outlined, l10n.onbDriveLabel, const [
              DistanceOption.drive10,
              DistanceOption.drive15,
              DistanceOption.any,
            ]),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 20,
                    color: context.palette.accentStrong,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.onbOriginTitle,
                          style: AppText.title.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.onbOriginHint,
                          style: AppText.caption(context)
                              .copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _companionCard(AppLocalizations l10n) => PrefCard(
    number: 3,
    title: l10n.onbCompanionTitle,
    badge: l10n.onbBadgeOptional,
    description: l10n.onbCompanionDesc,
    child: PrefChipWrap(
      children: [
        for (final c in CompanionType.values)
          PrefChip(
            label: companionLabel(l10n, c),
            icon: companionIcon(c),
            selected: _draft.companions.contains(c),
            // Independent toggles: any combination, or none at all.
            onTap: () {
              final next = {..._draft.companions};
              if (!next.add(c)) next.remove(c);
              _update(_draft.copyWith(companions: next));
            },
          ),
      ],
    ),
  );

  Widget _foodCard(AppLocalizations l10n) => PrefCard(
    number: 4,
    title: l10n.onbFoodTitle,
    badge: l10n.onbBadgeOptional,
    description: l10n.onbFoodDesc,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrefChipWrap(
          children: [
            for (final c in Cuisine.values)
              PrefChip(
                label: cuisineLabel(l10n, c),
                selected: _draft.cuisines.contains(c),
                onTap: () => _update(
                  _draft.copyWith(cuisines: toggleCuisine(_draft.cuisines, c)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        PrefChipWrap(
          children: [
            for (final t in FoodTag.values)
              PrefChip(
                label: tagLabel(l10n, t),
                selected: _draft.tags.contains(t),
                onTap: () {
                  final next = {..._draft.tags};
                  if (!next.add(t)) next.remove(t);
                  _update(_draft.copyWith(tags: next));
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        MergeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.onbUntriedTitle,
                      style: AppText.title.copyWith(fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.onbUntriedDesc,
                      style: AppText.caption(context).copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _draft.prioritizeUntried,
                activeThumbColor: Colors.white,
                activeTrackColor: context.palette.accent,
                onChanged: (v) =>
                    _update(_draft.copyWith(prioritizeUntried: v)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Header extends ConsumerWidget {
  const _Header({required this.isFirstTime});

  final bool isFirstTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isFirstTime)
          Row(
            children: [
              const LanguageButton(),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.textSecondary,
                  minimumSize: const Size(48, 44),
                ),
                child: Text(l10n.onbLogout),
              ),
            ],
          )
        else
          const SizedBox(height: 8),
        if (isFirstTime) ...[
          Text(
            l10n.onbStepLabel,
            style: TextStyle(
              color: context.palette.accentStrong,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          isFirstTime ? l10n.onbTitle : l10n.prefsEditTitle,
          style: AppText.heroTitle.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 4),
        Text(
          isFirstTime ? l10n.onbSubtitle : l10n.prefsEditSubtitle,
          style: AppText.body.copyWith(color: context.palette.textSecondary),
        ),
      ],
    );
  }
}

class _CampusTile extends StatelessWidget {
  const _CampusTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: '${l10n.onbCampusLabel} $label',
      excludeSemantics: true,
      child: Material(
        color: context.palette.accentSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showUniversitySheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.onbCampusLabel,
                        style: AppText.caption(context).copyWith(fontSize: 12),
                      ),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: context.palette.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.count,
    required this.saving,
    required this.isFirstTime,
    required this.error,
    required this.canClear,
    required this.onClear,
    required this.onRandom,
    required this.onSave,
  });

  final int? count;
  final bool saving;
  final bool isFirstTime;
  final Object? error;
  final bool canClear;
  final VoidCallback onClear;
  final VoidCallback onRandom;
  final VoidCallback onSave;

  String _errorText(AppLocalizations l10n) {
    final f = authFailureFrom(error!);
    return switch (f) {
      AuthFailure.permissionDenied => l10n.errPermissionDenied,
      AuthFailure.network => l10n.authErrNetwork,
      AuthFailure.timeout => l10n.authErrTimeout,
      _ => l10n.prefsSaveFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctaLabel = !isFirstTime
        ? l10n.onbSave
        : (count == null ? l10n.onbViewRecs : l10n.onbViewRecsCount(count!));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: context.palette.shadow,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          // Never let the bar crowd out the form, whatever the text scale.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null) ...[
                    AuthMessage.error(_errorText(l10n)),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.palette.accentFaint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    // Wrap (not Row): on a narrow screen or with large text the
                    // "clear" button drops to its own line instead of squeezing
                    // the count text to a few pixels.
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.restaurant_rounded,
                              size: 18,
                              color: context.palette.accentStrong,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    count == null
                                        ? l10n.onbCountUnknown
                                        : l10n.onbCountLabel(count!),
                                    style: AppText.title.copyWith(fontSize: 14),
                                  ),
                                  Text(
                                    l10n.onbCountNote,
                                    style: AppText.caption(context)
                                        .copyWith(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: canClear ? onClear : null,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(l10n.onbClearAll),
                          style: TextButton.styleFrom(
                            foregroundColor: context.palette.textSecondary,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(
                              fontFamily: AppText.fontFamily,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Material(
                        color: AppColors.peach,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          onTap: saving ? null : onRandom,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Always dark: it sits on the peach fill.
                                Icon(
                                  Icons.casino_outlined,
                                  color: context.palette.onPeach,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.onbRandom,
                                  style: AppText.title.copyWith(
                                    fontSize: 15,
                                    color: context.palette.onPeach,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: const [
                                AppColors.primary,
                                AppColors.primaryDeep,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              onTap: saving ? null : onSave,
                              child: Container(
                                height: 56,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                alignment: Alignment.center,
                                child: saving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.6,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              ctaLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (isFirstTime) ...[
                                            const SizedBox(width: 6),
                                            const Icon(
                                              Icons.arrow_forward_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ],
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
