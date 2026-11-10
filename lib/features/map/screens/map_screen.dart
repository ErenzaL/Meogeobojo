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
import '../../navigation/providers/shell_tab_provider.dart';
import '../../origin/models/origin.dart';
import '../../origin/providers/origin_providers.dart';
import '../../search/screens/search_screen.dart';
import '../../university/widgets/university_sheet.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../../core/widgets/responsive.dart';
import '../utils/kakao_relayout.dart';
import '../utils/map_camera.dart';
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

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  KakaoMapController? _controller;
  bool _stylesReady = false;

  /// Web: fit the first results (with the campus) into view once per campus, never again, so later filter changes
  /// and the user's own panning/zooming are left alone.
  bool _fitPending = kIsWeb;
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
    if (c == null || kIsWeb || _appliedInset == _bottomInset) return;
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

  Timer? _relayoutTimer;
  bool? _wasWide;

  /// The map's container changed size (window resized, the list panel came or went, the tab came back): re-measure the
  /// web map once things settle. It keeps the same centre and zoom, so nothing the user set is lost.
  void _scheduleRelayout() {
    if (!kIsWeb) return;
    _relayoutTimer?.cancel();
    _relayoutTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) relayoutKakaoMaps();
    });
  }

  @override
  void didChangeMetrics() => _scheduleRelayout();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _relayoutTimer?.cancel();
    _clickSub?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(KakaoMapController c) async {
    _controller = c;
    unawaited(_applyBottomPadding());
    try {
      // The plugin does not create the default label layer itself (native only: on the web the layer call is
      // unsupported and used to abort the whole marker setup, leaving the web map without markers).
      if (!kIsWeb) {
        await c.addMarkerLayer(
          layerId: KakaoMapController.defaultLabelLayerId,
          zOrder: 10,
          clickable: true,
        );
      }
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
      await _fitResultsOnce(origin, items);
    } catch (e) {
      debugPrint('Map marker update failed: $e');
    }
  }

  /// Web only, once per campus: show the campus and the restaurants around it. With no results nothing happens
  /// (the map stays on the campus, never on a whole country).
  Future<void> _fitResultsOnce(Origin origin, List<Restaurant> items) async {
    final c = _controller;
    if (c == null || !_fitPending || !mounted) return;
    final box = boundsToFit(GeoPoint(origin.latitude, origin.longitude), [
      for (final r in items) GeoPoint(r.latitude, r.longitude),
    ]);
    if (box == null) return;
    _fitPending = false;
    try {
      await c.moveCamera(
        cameraUpdate: CameraUpdate.fromBounds(
          LatLngBounds(
            southwest: LatLng(latitude: box.south, longitude: box.west),
            northeast: LatLng(latitude: box.north, longitude: box.east),
          ),
          padding: 60,
        ),
      );
    } catch (e) {
      debugPrint('Map fit failed: $e');
    }
  }

  /// A list row was chosen: select its pin's card and pan to it, keeping the current zoom.
  Future<void> _focus(Restaurant r) async {
    setState(() => _selected = r);
    final c = _controller;
    if (c == null) return;
    try {
      await c.moveCamera(
        cameraUpdate: CameraUpdate(
          position: LatLng(latitude: r.latitude, longitude: r.longitude),
          type: 0,
        ),
        animation: const CameraAnimation(
          duration: 400,
          autoElevation: false,
          isConsecutive: false,
        ),
      );
    } catch (e) {
      debugPrint('Map focus failed: $e');
    }
  }

  Future<void> _moveTo(double lat, double lng) async {
    final c = _controller;
    if (c == null) return;
    setState(() => _selected = null);
    try {
      await c.moveCamera(
        cameraUpdate: kIsWeb
            // The plugin's fromLatLng zooms to street level (17); on the web a campus view is the right size.
            ? CameraUpdate(
                position: LatLng(latitude: lat, longitude: lng),
                type: 0,
                zoomLevel: kWebCampusMoveLevel,
              )
            : CameraUpdate.fromLatLng(LatLng(latitude: lat, longitude: lng)),
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
        _fitPending = kIsWeb;
        _moveTo(next.latitude, next.longitude);
        _syncMarkers();
      }
    });
    // Coming back to the map tab: it was laid out while hidden, so it may have a stale size.
    ref.listen(shellTabProvider, (prev, next) {
      if (next == ShellTabs.map && prev != next) _scheduleRelayout();
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
    final univ = ref.watch(selectedUniversityProvider).value;
    final campus =
        univ?.displayName(Localizations.localeOf(context)) ??
        l10n.universityFallbackName;

    // Same breakpoint as the shell's desktop header: a list panel beside the map instead of a bottom sheet.
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
    if (_wasWide != null && _wasWide != wide) _scheduleRelayout();
    _wasWide = wide;

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
              child: Row(
                children: [
                  Expanded(child: _mapStack(context, wide)),
                  if (wide)
                    SizedBox(
                      width: 400,
                      child: MapPlacesPanel(
                        onFocus: _focus,
                        focusedId: _selected?.kakaoId,
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

  /// The map with its floating cards. On a wide screen the places list is a panel beside it instead of a sheet over it.
  Widget _mapStack(BuildContext context, bool wide) {
    final l10n = context.l10n;
    final p = context.palette;
    final init = ref.watch(kakaoMapInitProvider);
    final univ = ref.watch(selectedUniversityProvider).value;
    final origin = ref.watch(originProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: init.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                _MapError(onRetry: () => ref.invalidate(kakaoMapInitProvider)),
            data: (_) => univ == null
                ? const Center(child: CircularProgressIndicator())
                : KakaoMap(
                    onMapCreated: _onMapCreated,
                    initialPosition: LatLng(
                      latitude: origin?.latitude ?? univ.latitude,
                      longitude: origin?.longitude ?? univ.longitude,
                    ),
                    initialLevel: kIsWeb ? kWebCampusInitialLevel : 14,
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
                onPressed: () => _moveTo(origin.latitude, origin.longitude),
                icon: const Icon(Icons.my_location_rounded),
              ),
            ),
          ),
        if (!wide) const MapPlacesSheet(),
      ],
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
    // The map area shares the screen with the header and the list sheet, so on
    // a small phone it can be short: shrink the picture and let it scroll.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: MascotMessage(
            asset: AppAssets.mascotMapConfused,
            imageHeight: box.maxHeight < 360 ? 56 : 120,
            title: context.l10n.mapErrorTitle,
            message: context.l10n.mapErrorMessage,
            actionLabel: context.l10n.commonRetry,
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}
