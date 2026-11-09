import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../map/screens/map_screen.dart' show kakaoMapInitProvider;

/// What the picker returns: where the user put the pin, and its name.
class PickedPin {
  const PickedPin(this.name, this.latitude, this.longitude);

  final String name;
  final double latitude;
  final double longitude;
}

/// Full-screen map with a fixed pin in the middle: move the map, then confirm.
/// The map SDK is initialized lazily, exactly as on the map tab.
class PinPickerScreen extends ConsumerStatefulWidget {
  const PinPickerScreen({
    super.key,
    required this.startLat,
    required this.startLng,
    required this.nextPinNumber,
  });

  final double startLat;
  final double startLng;
  final int nextPinNumber;

  @override
  ConsumerState<PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends ConsumerState<PinPickerScreen> {
  KakaoMapController? _controller;
  bool _busy = false;

  Future<void> _confirm() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final center = await c.getCenter();
      if (!mounted) return;
      if (center == null) {
        _toast(context.l10n.originPinFailed);
        return;
      }
      final name = await _askName();
      if (name == null || !mounted) return;
      Navigator.of(context)
          .pop(PickedPin(name, center.latitude, center.longitude));
    } catch (_) {
      if (mounted) _toast(context.l10n.originPinFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<String?> _askName() {
    final l10n = context.l10n;
    final text = TextEditingController(
      text: l10n.originPinDefaultName(widget.nextPinNumber),
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.originPinNameTitle),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(hintText: l10n.originPinNameHint),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final v = text.text.trim();
              if (v.isNotEmpty) Navigator.of(ctx).pop(v);
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    ).whenComplete(text.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final init = ref.watch(kakaoMapInitProvider);
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
                latitude: widget.startLat,
                longitude: widget.startLng,
              ),
              initialLevel: 16,
            ),
            // The pin's tip sits on the map center.
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(Icons.place_rounded, size: 44, color: p.rust),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: p.card,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        l10n.originPinPickerHint,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
          ],
        ),
      ),
    );
  }
}
