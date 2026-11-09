import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/config/env.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../origin/providers/origin_providers.dart';
import '../../search/screens/search_screen.dart';
import '../../university/widgets/university_sheet.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../widgets/map_filter_bar.dart';
import '../widgets/map_places_sheet.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../../university/providers/university_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../university/models/university_display.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_colors.dart';

/// Initializes the Kakao Maps SDK with the *native* app key, lazily: only
/// when the map tab is first opened, so an SDK problem can never affect
/// startup or the Home screen. Invalidate to retry.
final kakaoMapInitProvider = FutureProvider<void>((ref) async {
  // Web needs the JavaScript key (and no native key); mobile the opposite.
  await KakaoMapsFlutter.init(
    kIsWeb ? null : Env.kakaoNativeAppKey,
    webAPIKey: Env.kakaoJavascriptKey.isEmpty ? null : Env.kakaoJavascriptKey,
  );
});

const _restaurantStyle = 'restaurant_pin';
const _campusStyle = 'campus_pin';
const _campusMarkerId = 'campus';

Future<Uint8List> _renderPin(Color fill, {int size = 56}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final c = Offset(size / 2, size / 2);
  canvas.drawCircle(c, size / 2 - 1, Paint()..color = Colors.white);
  canvas.drawCircle(c, size / 2 - 7, Paint()..color = fill);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  KakaoMapController? _controller;
  bool _stylesReady = false;
  Restaurant? _selected;
  StreamSubscription<LabelClickEvent>? _clickSub;

  /// Floating-nav footprint (logical px) and what the map was last told.
  double _bottomInset = 0;
  double? _appliedInset;

  /// Lifts the Kakao logo / controls above the floating navigation bar. The
  /// map itself still draws behind it and stays fully interactive. iOS takes
  /// points, Android pixels.
  Future<void> _applyBottomPadding() async {
    final c = _controller;
    if (c == null || _appliedInset == _bottomInset) return;
    _appliedInset = _bottomInset;
    final scale = defaultTargetPlatform == TargetPlatform.android
        ? MediaQuery.devicePixelRatioOf(context)
        : 1.0;
    try {
      await c.setPadding(
        left: 0,
        top: 0,
        right: 0,
        bottom: (_bottomInset * scale).round(),
      );
    } catch (e) {
      debugPrint('Map padding failed: $e');
    }
  }

  @override
  void dispose() {
    _clickSub?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(KakaoMapController c) async {
    _controller = c;
    unawaited(_applyBottomPadding());
    try {
      // The plugin does not create the default label layer itself.
      await c.addMarkerLayer(
        layerId: KakaoMapController.defaultLabelLayerId,
        zOrder: 10,
        clickable: true,
      );
      await c.registerMarkerStyles(
        styles: [
          MarkerStyle(
            styleId: _restaurantStyle,
            perLevels: [
              MarkerPerLevelStyle.fromBytes(
                bytes: await _renderPin(AppColors.primary),
                level: 0,
              ),
            ],
          ),
          MarkerStyle(
            styleId: _campusStyle,
            perLevels: [
              MarkerPerLevelStyle.fromBytes(
                bytes: await _renderPin(AppColors.pinCampus, size: 68),
                level: 0,
              ),
            ],
          ),
        ],
      );
      _stylesReady = true;
      _clickSub = c.onLabelClickedStream.listen(_onMarkerTapped);
      await _syncMarkers();
    } catch (e) {
      debugPrint('Map marker setup failed: $e');
    }
  }

  void _onMarkerTapped(LabelClickEvent e) {
    final items = ref.read(filteredRestaurantsProvider).value ?? const [];
    final match = items.where((r) => r.kakaoId == e.labelId);
    if (match.isNotEmpty && mounted) setState(() => _selected = match.first);
  }

  Future<void> _syncMarkers() async {
    final c = _controller;
    final origin = ref.read(originProvider);
    if (c == null || !_stylesReady || origin == null || !mounted) return;
    final items = ref.read(filteredRestaurantsProvider).value ?? const [];
    final originLabel = origin.label(context.l10n);
    try {
      await c.clearMarkers();
      await c.addMarkers(
        markerOptions: [
          // The pin marks where the walk starts (the chosen origin).
          MarkerOption(
            id: _campusMarkerId,
            latLng: LatLng(
              latitude: origin.latitude,
              longitude: origin.longitude,
            ),
            styleId: _campusStyle,
            text: originLabel,
            rank: 2,
          ),
          for (final r in items)
            MarkerOption(
              id: r.kakaoId,
              latLng: LatLng(latitude: r.latitude, longitude: r.longitude),
              styleId: _restaurantStyle,
              rank: 1,
            ),
        ],
      );
    } catch (e) {
      debugPrint('Map marker update failed: $e');
    }
  }

  Future<void> _moveTo(double lat, double lng) async {
    final c = _controller;
    if (c == null) return;
    setState(() => _selected = null);
    try {
      await c.moveCamera(
        cameraUpdate: CameraUpdate.fromLatLng(
          LatLng(latitude: lat, longitude: lng),
        ),
        animation: const CameraAnimation(
          duration: 600,
          autoElevation: true,
          isConsecutive: false,
        ),
      );
    } catch (e) {
      debugPrint('Map camera move failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the map synchronised with the selected origin.
    ref.listen(originProvider, (prev, next) {
      if (next != null && next != prev) {
        _moveTo(next.latitude, next.longitude);
        _syncMarkers();
      }
    });
    // Markers follow the shared conditions, not the raw nearby list.
    ref.listen(filteredRestaurantsProvider, (_, _) => _syncMarkers());

    _bottomInset = MediaQuery.paddingOf(context).bottom;
    if (_controller != null && _appliedInset != _bottomInset) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_applyBottomPadding()),
      );
    }

    final l10n = context.l10n;
    final p = context.palette;
    final init = ref.watch(kakaoMapInitProvider);
    final univ = ref.watch(selectedUniversityProvider).value;
    final origin = ref.watch(originProvider);
    final campus =
        univ?.displayName(Localizations.localeOf(context)) ??
        l10n.universityFallbackName;

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: V5Header(
                title: l10n.mapPageTitle,
                trailing: IconButton(
                  tooltip: l10n.homeSearchLabel,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SearchScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: InkWell(
                onTap: () => showUniversitySheet(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          campus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: MapFilterBar(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: init.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => _MapError(
                        onRetry: () => ref.invalidate(kakaoMapInitProvider),
                      ),
                      data: (_) => univ == null
                          ? const Center(child: CircularProgressIndicator())
                          : KakaoMap(
                              onMapCreated: _onMapCreated,
                              initialPosition: LatLng(
                                latitude: origin?.latitude ?? univ.latitude,
                                longitude: origin?.longitude ?? univ.longitude,
                              ),
                              initialLevel: 14,
                            ),
                    ),
                  ),
                  if (_selected != null)
                    Positioned(
                      left: AppSpacing.screenH,
                      right: AppSpacing.screenH,
                      top: 12,
                      child: _SelectedCard(
                        restaurant: _selected!,
                        onClose: () => setState(() => _selected = null),
                      ),
                    ),
                  if (origin != null)
                    Positioned(
                      right: 16,
                      top: _selected != null ? 92 : 12,
                      child: Material(
                        color: p.card,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: l10n.mapRecenter,
                          onPressed: () =>
                              _moveTo(origin.latitude, origin.longitude),
                          icon: const Icon(Icons.my_location_rounded),
                        ),
                      ),
                    ),
                  const MapPlacesSheet(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.restaurant, required this.onClose});

  final Restaurant restaurant;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return Material(
      color: context.palette.card,
      elevation: 6,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => openRestaurantDetail(context, r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title,
                    ),
                    Text(
                      context.l10n.restaurantTagDistance(
                        r.categoryTag,
                        formatDistance(r.distanceMeters),
                      ),
                      style: AppText.caption(context),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                tooltip: context.l10n.commonClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapError extends StatelessWidget {
  const _MapError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: MascotMessage(
        asset: AppAssets.mascotMapConfused,
        title: context.l10n.mapErrorTitle,
        message: context.l10n.mapErrorMessage,
        actionLabel: context.l10n.commonRetry,
        onAction: onRetry,
      ),
    );
  }
}
