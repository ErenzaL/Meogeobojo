import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'marker_image.dart';

/// Map marker art: an orange location pin per place, the selected place a
/// larger deep-orange pin with a white ring under a label (its name first,
/// its kind below), and the dark origin pin under its name.
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

/// The widest a label may be (logical px) when [reserved] more goes beside it
/// in a bitmap drawn at [scale]: past [kMaxMarkerEdge] pixels the map SDK
/// refuses the marker, so longer text ends in "…" instead.
double _room(double scale, double reserved) =>
    (kMaxMarkerEdge - 1) / scale - reserved;

TextPainter _text(String s, double size, Color color, double maxWidth) =>
    TextPainter(
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
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

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

/// Logical size of the transparent box around a place pin: the touch target
/// (a design goal of 44x44), larger than the pin that is drawn in it.
const kPinTouchSize = 44.0;

/// A teardrop [w] wide and [h] tall whose tip is at [tip].
Path _teardrop(Offset tip, double w, double h) {
  final r = w / 2;
  final centre = Offset(tip.dx, tip.dy - h + r);
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..arcTo(
      Rect.fromCircle(center: centre, radius: r),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
    )
    ..close();
}

/// A place. Unselected: a small orange pin inside a [kPinTouchSize] square
/// whose bottom centre is the pin's tip. [selected]: a larger pin with a
/// white ring and a dark edge, under a white label with [name] first and
/// [kind] after it.
Future<Uint8List> renderPlacePin({
  required bool selected,
  required double scale,
  String name = '',
  String kind = '',
}) {
  if (!selected) {
    const box = kPinTouchSize, pinW = 20.0, pinH = 26.0;
    return _bitmap(const Size(box, box), scale, (c) {
      final pin = _teardrop(const Offset(box / 2, box - 1), pinW, pinH);
      c.drawShadow(pin, Colors.black, 1.5, false);
      c.drawPath(pin, Paint()..color = AppColors.primary);
      c.drawPath(
        pin,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
      c.drawCircle(
        Offset(box / 2, box - 1 - pinH + pinW / 2),
        3.5,
        Paint()..color = Colors.white,
      );
    });
  }
  const pinW = 30.0, pinH = 38.0, gap = 4.0, padX = 10.0, padY = 6.0;
  final room = _room(scale, _shadow * 2 + padX * 2);
  final title = TextPainter(
    text: TextSpan(
      text: name,
      style: const TextStyle(
        fontFamily: _font,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _ink,
        height: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: room);
  final sub = _text(kind, 11, _ink.withValues(alpha: 0.62), room);
  final labelW =
      math.max(title.width, kind.isEmpty ? 0.0 : sub.width) + padX * 2;
  final labelH = title.height + (kind.isEmpty ? 0 : sub.height) + padY * 2;
  final w = math.max(labelW, pinW + 8) + _shadow * 2;
  final h = labelH + gap + pinH + _shadow * 2;
  return _bitmap(Size(w, h), scale, (c) {
    final cx = w / 2;
    final chip = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, _shadow + labelH / 2),
        width: labelW,
        height: labelH,
      ),
      const Radius.circular(8),
    );
    _softShadow(c, chip);
    c.drawRRect(chip, Paint()..color = Colors.white);
    c.drawRRect(
      chip.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.pinTagBorder,
    );
    title.paint(c, Offset(cx - title.width / 2, _shadow + padY));
    if (kind.isNotEmpty) {
      sub.paint(c, Offset(cx - sub.width / 2, _shadow + padY + title.height));
    }
    final pin = _teardrop(Offset(cx, h - _shadow), pinW, pinH);
    c.drawShadow(pin, Colors.black, 2, false);
    c.drawPath(pin, Paint()..color = AppColors.primaryDeep);
    c.drawPath(
      pin,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white,
    );
    c.drawPath(
      pin,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink,
    );
    c.drawCircle(
      Offset(cx, h - _shadow - pinH + pinW / 2),
      5,
      Paint()..color = Colors.white,
    );
  });
}

/// The walk's starting point: its name on a dark label above a dark pin whose
/// tip is the exact spot.
Future<Uint8List> renderOriginPin(String label, {required double scale}) {
  const labelH = 20.0, gap = 3.0, pinW = 22.0, pinH = 28.0;
  final text = _text(label, 11.5, Colors.white, _room(scale, _shadow * 2 + 12));
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
    final pin = _teardrop(Offset(cx, top + pinH), pinW, pinH);
    c.drawShadow(pin, Colors.black, 1.5, false);
    c.drawPath(pin, Paint()..color = _ink);
    c.drawCircle(Offset(cx, top + pinW / 2), 4, Paint()..color = Colors.white);
  });
}
