import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/config/env.dart';
import 'package:meogeobojo/features/map/utils/marker_image.dart';

/// A solid-colour RGBA bitmap with a transparent first pixel.
Uint8List _rgba(int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = 255;
    out[i * 4 + 1] = 138;
    out[i * 4 + 2] = 61;
    out[i * 4 + 3] = i == 0 ? 0 : 255;
  }
  return out;
}

/// Overwrites bytes of [png] (e.g. IHDR fields) on a copy.
Uint8List _patched(Uint8List png, Map<int, int> bytes) {
  final copy = Uint8List.fromList(png);
  bytes.forEach((i, v) => copy[i] = v);
  return copy;
}

/// The same PNG with an `iCCP` chunk (a colour profile) after IHDR.
Uint8List _withIccChunk(Uint8List png) {
  final payload = Uint8List.fromList([...'p'.codeUnits, 0, 0, 1, 2, 3]);
  final chunk = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
    ..add('iCCP'.codeUnits)
    ..add(payload)
    ..add(Uint8List(4)); // CRC is irrelevant to the header scan
  final head = png.sublist(0, 33); // signature + IHDR chunk
  return Uint8List.fromList([
    ...head,
    ...chunk.takeBytes(),
    ...png.sublist(33),
  ]);
}

int _referenceCrc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

void main() {
  group('encodeRgbaPng', () {
    test('writes a plain 8-bit non-interlaced RGBA PNG without a profile', () {
      final png = encodeRgbaPng(56, 56, _rgba(56, 56));
      final info = inspectPng(png)!;
      expect(info.width, 56);
      expect(info.height, 56);
      expect(info.bitDepth, 8);
      expect(info.colorType, 6);
      expect(info.interlace, 0);
      expect(info.hasIccProfile, isFalse);
      expect(info.hasPalette, isFalse);
      expect(isSafeMarkerPng(png), isTrue);
    });

    test(
      'every chunk CRC and the zlib stream are valid (checked independently)',
      () {
        for (final (w, h) in [(1, 1), (56, 56), (68, 68), (300, 300)]) {
          final png = encodeRgbaPng(w, h, _rgba(w, h));
          final view = ByteData.sublistView(png);
          var offset = 8;
          final idat = BytesBuilder();
          final types = <String>[];
          while (offset < png.length) {
            final length = view.getUint32(offset);
            final type = String.fromCharCodes(
              png.sublist(offset + 4, offset + 8),
            );
            final body = png.sublist(offset + 8, offset + 8 + length);
            final stored = view.getUint32(offset + 8 + length);
            expect(
              stored,
              _referenceCrc32([...type.codeUnits, ...body]),
              reason: '$type CRC for ${w}x$h',
            );
            if (type == 'IDAT') idat.add(body);
            types.add(type);
            offset += 12 + length;
          }
          expect(offset, png.length);
          expect(types, ['IHDR', 'IDAT', 'IEND']);
          // dart:io's zlib verifies the Adler-32 and the block structure; the
          // inflated data must be the scanlines, each led by filter byte 0.
          final raw = ZLibDecoder().convert(idat.takeBytes());
          expect(raw.length, h * (w * 4 + 1), reason: 'scanline bytes ${w}x$h');
          expect(raw[0], 0, reason: 'filter byte of the first row');
          expect(raw.sublist(1, 5), [255, 138, 61, 0], reason: 'first pixel');
          if (w > 1) {
            expect(raw.sublist(5, 9), [255, 138, 61, 255], reason: 'pixel 2');
          }
        }
      },
    );

    test('rejects a pixel buffer of the wrong size or an empty image', () {
      expect(() => encodeRgbaPng(4, 4, Uint8List(10)), throwsArgumentError);
      expect(() => encodeRgbaPng(0, 4, Uint8List(0)), throwsArgumentError);
      expect(() => encodeRgbaPng(4, 0, Uint8List(0)), throwsArgumentError);
    });

    testWidgets('Flutter\'s own PNG decoder reads it back pixel for pixel', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const w = 17, h = 9;
        final source = _rgba(w, h);
        final codec = await ui.instantiateImageCodec(
          encodeRgbaPng(w, h, source),
        );
        final image = (await codec.getNextFrame()).image;
        expect(image.width, w);
        expect(image.height, h);
        final back = (await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!.buffer.asUint8List();
        // Fully transparent pixels may lose their RGB; compare the rest.
        for (var i = 1; i < w * h; i++) {
          expect(
            back.sublist(i * 4, i * 4 + 4),
            source.sublist(i * 4, i * 4 + 4),
            reason: 'pixel $i',
          );
        }
        expect(back[3], 0, reason: 'transparent stays transparent');
      });
    });
  });

  group('isSafeMarkerPng', () {
    final good = encodeRgbaPng(56, 56, _rgba(56, 56));

    test('accepts the sizes the map actually uses', () {
      expect(isSafeMarkerPng(encodeRgbaPng(56, 56, _rgba(56, 56))), isTrue);
      expect(isSafeMarkerPng(encodeRgbaPng(68, 68, _rgba(68, 68))), isTrue);
    });

    test('rejects what is not a PNG', () {
      expect(isSafeMarkerPng(Uint8List(0)), isFalse);
      expect(isSafeMarkerPng(Uint8List(32)), isFalse);
      expect(isSafeMarkerPng(Uint8List.fromList('GIF89a'.codeUnits)), isFalse);
      expect(
        isSafeMarkerPng(good.sublist(0, 20)),
        isFalse,
        reason: 'truncated',
      );
      expect(
        isSafeMarkerPng(_patched(good, {1: 0x51})),
        isFalse,
        reason: 'bad signature',
      );
      expect(
        isSafeMarkerPng(_patched(good, {12: 0x58})),
        isFalse,
        reason: 'IHDR missing',
      );
    });

    test('rejects zero-sized and oversized images', () {
      // width is the 4 bytes at 16..19, height at 20..23
      expect(isSafeMarkerPng(_patched(good, {19: 0})), isFalse);
      expect(isSafeMarkerPng(_patched(good, {23: 0})), isFalse);
      expect(
        isSafeMarkerPng(_patched(good, {18: 0x02, 19: 0x01})), // 513
        isFalse,
      );
      expect(
        isSafeMarkerPng(_patched(good, {18: 0x02, 19: 0x00})), // 512
        isTrue,
      );
    });

    test('rejects pixel layouts other than plain 8-bit RGB(A)', () {
      expect(
        isSafeMarkerPng(_patched(good, {24: 16})),
        isFalse,
        reason: '16 bits per channel (wide gamut)',
      );
      expect(isSafeMarkerPng(_patched(good, {24: 1})), isFalse);
      expect(
        isSafeMarkerPng(_patched(good, {25: 3})),
        isFalse,
        reason: 'palette',
      );
      expect(
        isSafeMarkerPng(_patched(good, {25: 4})),
        isFalse,
        reason: 'grey + alpha',
      );
      expect(isSafeMarkerPng(_patched(good, {25: 0})), isFalse, reason: 'grey');
      expect(
        isSafeMarkerPng(_patched(good, {28: 1})),
        isFalse,
        reason: 'interlaced',
      );
      expect(
        isSafeMarkerPng(_withIccChunk(good)),
        isFalse,
        reason: 'embedded colour profile',
      );
    });
  });

  group('markerPngFromImage', () {
    testWidgets('renders a pin as a verified 8-bit RGBA PNG', (tester) async {
      await tester.runAsync(() async {
        for (final size in [56, 68]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          final c = Offset(size / 2, size / 2);
          canvas.drawCircle(
            c,
            size / 2 - 1,
            Paint()..color = const Color(0xFFFFFFFF),
          );
          canvas.drawCircle(
            c,
            size / 2 - 7,
            Paint()..color = const Color(0xFFFF8A3D),
          );
          final image = await recorder.endRecording().toImage(size, size);
          final png = await markerPngFromImage(image);
          image.dispose();
          final info = inspectPng(png)!;
          expect(info.width, size);
          expect(info.height, size);
          expect(info.bitDepth, 8);
          expect(info.colorType, 6);
          expect(isSafeMarkerPng(png), isTrue);
          // The pin's centre keeps its fill colour, its corner stays clear.
          final codec = await ui.instantiateImageCodec(png);
          final back = (await (await codec.getNextFrame()).image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!.buffer.asUint8List();
          final mid = ((size ~/ 2) * size + size ~/ 2) * 4;
          expect(back.sublist(mid, mid + 4), [255, 138, 61, 255]);
          expect(back[3], 0);
        }
      });
    });

    testWidgets('the smallest possible image still passes the guard', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder);
        final image = await recorder.endRecording().toImage(1, 1);
        // Zero-sized images cannot be created by the engine; the zero-size
        // guard is exercised on the PNG bytes in `isSafeMarkerPng` above.
        expect(isSafeMarkerPng(await markerPngFromImage(image)), isTrue);
        image.dispose();
      });
    });
  });

  test('the diagnostic basic-map switch is off unless defined', () {
    expect(Env.mapDiagnosticBasic, isFalse);
  });
}
