import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../map/screens/map_screen.dart' show kakaoMapInitProvider;
import '../models/origin.dart';

/// What the picker returns: where the user put the pin, its name and the zoom
/// it was placed at (so editing it later starts from the same view).
class PickedPin {
  const PickedPin(this.name, this.latitude, this.longitude, [this.zoomLevel]);

  final String name;
  final double latitude;
  final double longitude;

  /// The plugin's (mobile) zoom scale, higher = closer.
  final int? zoomLevel;
}

/// The map's first view: the whole campus for a new place, the pin itself at
/// its own zoom when editing. The web map takes its initial level on the
/// JavaScript scale (1 = closest), the phones on the plugin's scale.
int pinPickerInitialLevel({int? editingZoom}) {
  if (editingZoom == null) return kIsWeb ? 3 : 15;
  return kIsWeb ? (15 - editingZoom).clamp(1, 14) : editingZoom;
}

/// Full-screen map with a fixed pin in the middle. Moving the map only moves
/// the temporary choice; nothing changes until "이 위치를 출발점으로 설정".
/// Back keeps the previous start point. No location permission is asked:
/// the pin is placed on the campus map, not on the user's position.
class PinPickerScreen extends ConsumerStatefulWidget {
  const PinPickerScreen({
    super.key,
    required this.campusLat,
    required this.campusLng,
    this.editing,
  });

  final double campusLat;
  final double campusLng;

  /// The pin being moved or renamed; null for a new one.
  final Origin? editing;

  @override
  ConsumerState<PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends ConsumerState<PinPickerScreen> {
  KakaoMapController? _controller;
  bool _busy = false;
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The name starts as "직접 지정한 위치"; the user may type their own.
    if (widget.editing == null && _name.text.isEmpty) {
      _name.text = context.l10n.originPinDefault;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final c = _controller;
    if (c == null || _busy) return;
    final name = _name.text.trim().isEmpty
        ? context.l10n.originPinDefault
        : _name.text.trim();
    setState(() => _busy = true);
    try {
      final center = await c.getCenter();
      int? zoom;
      try {
        zoom = await c.getZoomLevel();
      } catch (_) {}
      if (!mounted) return;
      if (center == null) {
        _toast(context.l10n.originPinFailed);
        return;
      }
      Navigator.of(context)
          .pop(PickedPin(name, center.latitude, center.longitude, zoom));
    } catch (_) {
      if (mounted) _toast(context.l10n.originPinFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "학교로 이동": only the map moves (same zoom); nothing is set.
  Future<void> _toCampus() async {
    try {
      await _controller?.moveCamera(
        cameraUpdate: CameraUpdate(
          position: LatLng(
            latitude: widget.campusLat,
            longitude: widget.campusLng,
          ),
          type: 0,
        ),
        animation: const CameraAnimation(
          duration: 400,
          autoElevation: false,
          isConsecutive: false,
        ),
      );
    } catch (e) {
      debugPrint('Pin picker move failed: $e');
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final init = ref.watch(kakaoMapInitProvider);
    final editing = widget.editing;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.originPinPickerTitle)),
      body: init.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(kakaoMapInitProvider),
            child: Text(l10n.commonRetry),
          ),
        ),
        data: (_) => Stack(
          alignment: Alignment.center,
          children: [
            KakaoMap(
              onMapCreated: (c) => _controller = c,
              initialPosition: LatLng(
                latitude: editing?.latitude ?? widget.campusLat,
                longitude: editing?.longitude ?? widget.campusLng,
              ),
              initialLevel: pinPickerInitialLevel(
                editingZoom: editing?.zoomLevel,
              ),
            ),
            // The pin's tip sits on the map center.
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(Icons.place_rounded, size: 44, color: p.rust),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: p.card,
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                child: TextButton.icon(
                  onPressed: _toCampus,
                  icon: const Icon(Icons.school_outlined, size: 18),
                  label: Text(l10n.originPinToCampus),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: Material(
                color: p.card,
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.originPinPickerHint,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _name,
                        maxLength: 20,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.originPinNameTitle,
                          hintText: l10n.originPinDefault,
                          helperText: l10n.originPinNameHint,
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.rust,
                          foregroundColor: p.onRust,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(l10n.originPinConfirm),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
