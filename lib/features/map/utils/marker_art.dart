import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'marker_image.dart';

/// Map marker art, after the 5th design mock (시안): a small white tag per
/// place (its price, or its kind when the price is unknown), a dark chip with
/// a check for the selected place, and the dark origin pin under its name.
///
/// The map tiles never change with the app theme, so neither do the colors.
/// Every marker is anchored at its bottom centre (all three platforms).

const _ink = AppColors.pinCampus;
const _font = 'Pretendard';
const _shadow = 3.0; // room around the art for its soft shadow

/// How many bitmap pixels one logical pixel takes. Web takes the bitmap as CSS
/// px and iOS as points (`UIImage(data:)` is scale 1), Android as device
/// pixels, so only Android is drawn at the device pixel ratio.
double markerScale(double devicePixelRatio) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? devicePixelRatio
    : 1;

TextPainter _text(String s, double size, Color color) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(
      fontFamily: _font,
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      height: 1.2,
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();

void _softShadow(Canvas canvas, RRect r) => canvas.drawRRect(
  r.shift(const Offset(0, 1)),
  Paint()
    ..color = AppColors.pinShadow
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
);

Future<Uint8List> _bitmap(
  Size size,
  double scale,
  void Function(Canvas c) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  draw(canvas);
  final image = await recorder.endRecording().toImage(
    (size.width * scale).ceil(),
    (size.height * scale).ceil(),
  );
  try {
    // Verified 8-bit RGBA bytes (see markerPngFromImage).
    return await markerPngFromImage(image);
  } finally {
    image.dispose();
  }
}

/// A place: "8,000~" (or "한식") on a white tag; [selected] is the dark chip
/// with a check, a little larger, like the mock's chosen pin.
Future<Uint8List> renderPlaceTag(
  String label, {
  required bool selected,
  required double scale,
}) {
  final h = selected ? 30.0 : 26.0;
  final pad = selected ? 10.0 : 8.0;
  final text = _text(label, selected ? 13 : 12, selected ? Colors.white : _ink);
  final check = selected
      ? (TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.check_rounded.codePoint),
            style: TextStyle(
              fontFamily: Icons.check_rounded.fontFamily,
              package: Icons.check_rounded.fontPackage,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout())
      : null;
  final iconW = check == null ? 0.0 : check.width + 3;
  final w = pad * 2 + iconW + text.width - (selected ? 2 : 0);
  return _bitmap(Size(w + _shadow * 2, h + _shadow * 2), scale, (c) {
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(_shadow, _shadow, w, h),
      const Radius.circular(8),
    );
    _softShadow(c, box);
    c.drawRRect(box, Paint()..color = selected ? _ink : Colors.white);
    if (!selected) {
      c.drawRRect(
        box.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.pinTagBorder,
      );
    }
    var x = _shadow + pad - (selected ? 2 : 0);
    if (check != null) {
      check.paint(c, Offset(x, _shadow + (h - check.height) / 2));
      x += iconW;
    }
    text.paint(c, Offset(x, _shadow + (h - text.height) / 2));
  });
}

/// The walk's starting point: its name on a dark label above a dark pin whose
/// tip is the exact spot.
Future<Uint8List> renderOriginPin(String label, {required double scale}) {
  const labelH = 20.0, gap = 3.0, pinW = 22.0, pinH = 28.0;
  final text = _text(label, 11.5, Colors.white);
  final labelW = text.width + 12;
  final w = math.max(labelW, pinW) + _shadow * 2;
  final h = labelH + gap + pinH + _shadow * 2;
  return _bitmap(Size(w, h), scale, (c) {
    final cx = w / 2;
    final chip = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, _shadow + labelH / 2),
        width: labelW,
        height: labelH,
      ),
      const Radius.circular(6),
    );
    _softShadow(c, chip);
    c.drawRRect(chip, Paint()..color = _ink);
    text.paint(
      c,
      Offset(cx - text.width / 2, _shadow + (labelH - text.height) / 2),
    );

    // Teardrop: a circle whose sides run down to the tip at the bottom.
    final top = _shadow + labelH + gap;
    const r = pinW / 2;
    final centre = Offset(cx, top + r);
    final tip = Offset(cx, top + pinH);
    final pin = Path()
      ..moveTo(tip.dx, tip.dy)
      ..arcTo(
        Rect.fromCircle(center: centre, radius: r),
        math.pi * 0.75,
        math.pi * 1.5,
        false,
      )
      ..close();
    c.drawShadow(pin, Colors.black, 1.5, false);
    c.drawPath(pin, Paint()..color = _ink);
    c.drawCircle(centre, 4, Paint()..color = Colors.white);
  });
}
