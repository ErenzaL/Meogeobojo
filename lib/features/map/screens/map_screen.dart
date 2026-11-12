import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/config/env.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../home/providers/home_providers.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../origin/models/origin.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../search/screens/search_screen.dart';
import '../../university/widgets/university_sheet.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../../core/widgets/responsive.dart';
import '../utils/kakao_relayout.dart';
import '../utils/marker_art.dart';
import '../utils/map_camera.dart';
import '../widgets/map_filter_bar.dart';
import '../widgets/map_places_sheet.dart';
import '../../recommendation/home_ranking.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/utils/directions.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../../university/providers/university_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../university/models/university_display.dart';
import '../../../core/theme/app_palette.dart';

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

const _campusMarkerId = 'campus';

/// The pins: Home's confirmed matches (same categories, conditions and data),
/// so the map never shows a place Home would not.
final mapPlacesProvider = Provider<AsyncValue<List<Restaurant>>>(
  (ref) => ref
      .watch(homeMatchesProvider)
      .whenData((l) => [for (final r in l) r.restaurant]),
);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  KakaoMapController? _controller;
  bool _stylesReady = false;

  /// Marker styles already handed to the map: "pin" (every unselected place),
  /// "s:{id}" (the selected place, under its name) and "o:정문" (the origin).
  final _styles = <String>{};

  /// A tap on the map itself clears the selection, unless a pin reported the
  /// tap meanwhile (the SDK has no "empty map tapped" event, so a tap that no
  /// pin claims within this delay is taken as one). Phones only: on the web
  /// the map's own pointer events never reach Flutter (the card has ×).
  Timer? _deselectTimer;
  Offset? _downAt;

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
    _deselectTimer?.cancel();
    _clickSub?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(KakaoMapController c) async {
    _controller = c;
    if (Env.mapDiagnosticBasic) {
      // Diagnostic build (--dart-define=MAP_DIAGNOSTIC_BASIC=true): the bare map only. No padding call, marker layer,
      // styles or markers ([_stylesReady] stays false, so [_syncMarkers] does nothing).
      debugPrint('Map diagnostic: basic map, no markers or overlays.');
      return;
    }
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
      _stylesReady = true;
      _clickSub = c.onLabelClickedStream.listen(_onMarkerTapped);
      await _syncMarkers();
    } catch (e) {
      debugPrint('Map marker setup failed: $e');
    }
    _applyFocusRequest();
  }

  /// Another screen asked to show a place (detail page → 지도). Before the map exists only the card is selected; the
  /// pan happens once the controller is ready. The request also cancels the one-time fit so it does not move away.
  void _applyFocusRequest() {
    final r = ref.read(mapFocusProvider);
    if (r == null || !mounted) return;
    if (_controller == null) {
      _select(r);
      return;
    }
    ref.read(mapFocusProvider.notifier).clear();
    _fitPending = false;
    unawaited(_focus(r));
  }

  void _onMarkerTapped(LabelClickEvent e) {
    _deselectTimer?.cancel();
    final items = ref.read(mapPlacesProvider).value ?? const [];
    final match = items.where((r) => r.kakaoId == e.labelId);
    if (match.isEmpty || !mounted) return;
    _select(match.first);
    unawaited(_revealAboveCard(match.first));
  }

  void _onMapPointerUp(PointerUpEvent e) {
    final down = _downAt;
    _downAt = null;
    if (down == null || _selected == null) return;
    if ((e.position - down).distance > 8) return; // a drag, not a tap
    _deselectTimer?.cancel();
    _deselectTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _select(null);
    });
  }

  /// The card covers the bottom of the map: when the chosen pin is under it,
  /// the map moves so the pin sits in the open part. Same zoom.
  Future<void> _revealAboveCard(Restaurant r) async {
    final c = _controller;
    final box = _mapBox;
    if (c == null || box == null) return;
    // Screen points come in the same units the marker bitmaps are drawn in.
    final unit = markerScale(MediaQuery.devicePixelRatioOf(context));
    try {
      final at = await c.toScreenPoint(
        position: LatLng(latitude: r.latitude, longitude: r.longitude),
      );
      if (at == null || !mounted) return;
      final y = at.dy / unit;
      final open = box.height - _kCardReserve - _bottomInset;
      if (y > 24 && y < open - 16) return; // already in view
      final shift = y - open * 0.45;
      final centre = await c.fromScreenPoint(
        point: Offset(box.width / 2, box.height / 2 + shift) * unit,
      );
      if (centre == null || !mounted) return;
      await c.moveCamera(
        cameraUpdate: CameraUpdate(position: centre, type: 0),
        animation: const CameraAnimation(
          duration: 300,
          autoElevation: false,
          isConsecutive: false,
        ),
      );
    } catch (e) {
      debugPrint('Map reveal failed: $e');
    }
  }

  /// The map's own size (logical px), for [_revealAboveCard].
  Size? _mapBox;

  /// Selects [r] (or nothing) and swaps the two affected pins: the old one back
  /// to a plain pin, the new one to the larger pin under its name. Only those
  /// two markers change, so the rest of the map does not flicker.
  void _select(Restaurant? r) {
    final old = _selected;
    setState(() => _selected = r);
    if (old?.kakaoId == r?.kakaoId) return;
    final look = _tagLook();
    unawaited(() async {
      final c = _controller;
      if (c == null || !_stylesReady) return;
      final shown = {
        for (final x
            in ref.read(mapPlacesProvider).value ?? const <Restaurant>[])
          x.kakaoId: x,
      };
      try {
        for (final x in [?old, ?r]) {
          final place = shown[x.kakaoId];
          if (place == null) continue;
          final option = await _placeMarker(c, place, look);
          await c.removeMarker(id: place.kakaoId);
          await c.addMarker(markerOption: option);
        }
      } catch (e) {
        debugPrint('Map marker restyle failed: $e');
      }
    }());
  }

  /// What the pins need from the context, read once before any await: the
  /// wording and the bitmap scale.
  ({AppLocalizations l10n, double scale}) _tagLook() => (
    l10n: context.l10n,
    scale: markerScale(MediaQuery.devicePixelRatioOf(context)),
  );

  /// Hands the map a style for [id] the first time it is needed.
  Future<void> _ensureStyle(
    KakaoMapController c,
    String id,
    Future<Uint8List> Function() draw,
  ) async {
    if (_styles.contains(id)) return;
    await c.registerMarkerStyles(
      styles: [
        MarkerStyle(
          styleId: id,
          perLevels: [
            MarkerPerLevelStyle.fromBytes(bytes: await draw(), level: 0),
          ],
        ),
      ],
    );
    _styles.add(id);
  }

  Future<MarkerOption> _placeMarker(
    KakaoMapController c,
    Restaurant r,
    ({AppLocalizations l10n, double scale}) look,
  ) async {
    final selected = _selected?.kakaoId == r.kakaoId;
    final style = selected ? 's:${r.kakaoId}:${r.name}' : 'pin';
    await _ensureStyle(
      c,
      style,
      () => renderPlacePin(
        selected: selected,
        scale: look.scale,
        name: r.name,
        kind: r.categoryTag,
      ),
    );
    return MarkerOption(
      id: r.kakaoId,
      latLng: LatLng(latitude: r.latitude, longitude: r.longitude),
      styleId: style,
      rank: selected ? 3 : 1,
      // Web shows it as the hover title; native would draw it on the map a second time.
      text: kIsWeb ? r.name : null,
    );
  }

  /// Bumped by every [_syncMarkers]; an older one still drawing styles when a
  /// newer one starts must not touch the map.
  int _syncGen = 0;

  Future<void> _syncMarkers() async {
    final c = _controller;
    final origin = ref.read(originProvider);
    if (c == null || !_stylesReady || origin == null || !mounted) return;
    final gen = ++_syncGen;
    bool stale() => !mounted || gen != _syncGen;
    final items = ref.read(mapPlacesProvider).value ?? const [];
    final originLabel = origin.label(context.l10n);
    final look = _tagLook();
    try {
      final originStyle = 'o:$originLabel';
      await _ensureStyle(
        c,
        originStyle,
        () => renderOriginPin(originLabel, scale: look.scale),
      );
      final places = [for (final r in items) await _placeMarker(c, r, look)];
      if (stale()) return;
      await c.clearMarkers();
      if (stale()) return;
      await c.addMarkers(
        markerOptions: [
          // The pin marks where the walk starts (the chosen origin).
          MarkerOption(
            id: _campusMarkerId,
            latLng: LatLng(
              latitude: origin.latitude,
              longitude: origin.longitude,
            ),
            styleId: originStyle,
            text: kIsWeb ? originLabel : null,
            rank: 2,
          ),
          ...places,
        ],
      );
      if (stale()) return;
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
    _select(r);
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

  /// Moves the map only: the selected place stays selected.
  Future<void> _moveTo(double lat, double lng) async {
    final c = _controller;
    if (c == null) return;
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
    ref.listen(mapPlacesProvider, (_, _) => _syncMarkers());
    ref.listen(mapFocusProvider, (_, next) {
      if (next != null) _applyFocusRequest();
    });

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
    // the same side gutter as the header and the other pages (16 on phones)
    final gutter = WebLayout.gutterOf(context);
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
              padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
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
              padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 10),
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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [OriginReselectBanner(), MapFilterBar()],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  // Whenever the map's own box changes size (window resized, panel shown, filter rows wrapping) the
                  // web map is told to re-measure itself (same centre and zoom).
                  Expanded(
                    child: NotificationListener<SizeChangedLayoutNotification>(
                      onNotification: (_) {
                        _scheduleRelayout();
                        return false;
                      },
                      child: SizeChangedLayoutNotifier(
                        child: _mapStack(context, wide),
                      ),
                    ),
                  ),
                  if (wide)
                    SizedBox(
                      // the map keeps the majority of the width; the list is a side panel (400 / 440 / 480 px)
                      width: MediaQuery.sizeOf(context).width >= 1920
                          ? 480
                          : MediaQuery.sizeOf(context).width >= 1440
                          ? 440
                          : 400,
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

  /// The map with its floating cards. On a wide screen the places list is a
  /// panel beside it instead of a sheet over it. The chosen place's card sits
  /// at the bottom (above the navigation bar); on a phone it replaces the
  /// list sheet while a place is chosen.
  Widget _mapStack(BuildContext context, bool wide) {
    final l10n = context.l10n;
    final p = context.palette;
    final init = ref.watch(kakaoMapInitProvider);
    final univ = ref.watch(selectedUniversityProvider).value;
    final origin = ref.watch(originProvider);
    // The card always shows the place the pin and label show: looked up in the
    // current results, so a place a filter removed loses its card too.
    final matches = ref.watch(homeMatchesProvider);
    final chosenId = _selected?.kakaoId;
    final chosen = chosenId == null
        ? null
        : matches.value
              ?.where((x) => x.restaurant.kakaoId == chosenId)
              .firstOrNull;
    if (chosenId != null && matches.hasValue && chosen == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected?.kakaoId == chosenId) _select(null);
      });
    }
    return LayoutBuilder(
      builder: (context, box) {
        _mapBox = box.biggest;
        return Stack(
          children: [
            Positioned.fill(
              child: init.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _MapError(
                  onRetry: () => ref.invalidate(kakaoMapInitProvider),
                ),
                data: (_) => univ == null
                    ? const Center(child: CircularProgressIndicator())
                    : Listener(
                        onPointerDown: (e) => _downAt = e.position,
                        onPointerUp: _onMapPointerUp,
                        child: KakaoMap(
                          onMapCreated: _onMapCreated,
                          initialPosition: LatLng(
                            latitude: origin?.latitude ?? univ.latitude,
                            longitude: origin?.longitude ?? univ.longitude,
                          ),
                          initialLevel: kIsWeb ? kWebCampusInitialLevel : 14,
                        ),
                      ),
              ),
            ),
            if (origin != null)
              Positioned(
                right: 16,
                top: 12,
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
            if (!wide && chosen == null) const MapPlacesSheet(),
            if (chosen != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12 + MediaQuery.paddingOf(context).bottom,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: MapPlaceCard(
                      item: chosen,
                      onClose: () => _select(null),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Room the chosen place's card takes at the bottom of the map (logical px).
const _kCardReserve = 210.0;

/// The chosen place: name and kind, its menu and price, how far it is from
/// the start point, and the two things to do next. Narrow phones keep both
/// buttons whole (they stack under 300 px).
class MapPlaceCard extends ConsumerWidget {
  const MapPlaceCard({super.key, required this.item, required this.onClose});

  final RankedRestaurant item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = item.restaurant;
    final origin = ref.watch(originProvider);
    final menus =
        ref.watch(restaurantMenusProvider(r.kakaoId)).value ?? const [];
    final menu =
        menus.where((m) => m.representative && m.available).firstOrNull ??
        menus.where((m) => m.recommended && m.available).firstOrNull ??
        menus.where((m) => m.available).firstOrNull;
    final price = menu?.priceKrw ?? item.insight.minPriceKrw;
    final menuLine = [
      ?menu?.name,
      if (price != null)
        menu?.priceKrw != null
            ? l10n.restaurantPriceWon(price)
            : l10n.homePriceFrom(price),
    ].join(' · ');

    void directions() {
      final o = origin;
      if (o == null) return;
      ref.read(activeRecommendationProvider.notifier).markWent(r);
      openDirections(
        context,
        to: r,
        fromName: o.label(l10n),
        fromLat: o.latitude,
        fromLng: o.longitude,
      );
    }

    final details = OutlinedButton.icon(
      onPressed: () => openRestaurantDetail(context, r),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: p.borderStrong),
      ),
      icon: const Icon(Icons.info_outline_rounded, size: 19),
      label: Text(l10n.mapCardDetails),
    );
    final route = FilledButton.icon(
      onPressed: origin == null ? null : directions,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: const Icon(Icons.directions_outlined, size: 19),
      label: Text(l10n.homeDirections),
    );

    return Material(
      key: ValueKey('map-card-${r.kakaoId}'),
      color: p.card,
      elevation: 6,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title,
                      ),
                      if (r.categoryTag.isNotEmpty)
                        Text(r.categoryTag, style: AppText.caption(context)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n.commonClose,
                ),
              ],
            ),
            if (menuLine.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                menuLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                [
                  if (origin != null) l10n.originFromLabel(origin.label(l10n)),
                  l10n.homeWalkAbout(item.walkMinutes),
                  l10n.restaurantDistanceStraight(formatDistance(item.meters)),
                ].join(' · '),
                style: TextStyle(fontSize: 13.5, color: p.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: LayoutBuilder(
                builder: (context, box) => box.maxWidth < 300
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [route, const SizedBox(height: 8), details],
                      )
                    : Row(
                        children: [
                          Expanded(child: details),
                          const SizedBox(width: 10),
                          Expanded(child: route),
                        ],
                      ),
              ),
            ),
          ],
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
