import 'dart:typed_data';
import 'dart:ui' as ui;

/// What a PNG says about itself, read straight from its header chunks.
///
/// The Kakao Maps iOS SDK converts every custom marker icon (a `UIImage`) into
/// its own pixel buffer on its render thread. When it meets a pixel format it
/// does not know it throws a C++ exception there, which aborts the whole app
/// (`ImageData::_setPixelSize` → SIGABRT) and cannot be caught from Dart or
/// Swift. So marker bytes are checked in Dart, before they ever reach it.
class PngInfo {
  const PngInfo({
    required this.width,
    required this.height,
    required this.bitDepth,
    required this.colorType,
    required this.interlace,
    required this.hasIccProfile,
    required this.hasPalette,
  });

  final int width;
  final int height;

  /// Bits per channel (8 for an ordinary image, 16 for a wide-gamut one).
  final int bitDepth;

  /// PNG colour type: 0 grey, 2 RGB, 3 palette, 4 grey+alpha, 6 RGBA.
  final int colorType;
  final int interlace;
  final bool hasIccProfile;
  final bool hasPalette;

  @override
  String toString() =>
      'PNG ${width}x$height bitDepth=$bitDepth colorType=$colorType '
      'interlace=$interlace icc=$hasIccProfile palette=$hasPalette';
}

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Reads a PNG's header, or returns null when [bytes] is not a well-formed PNG
/// (too short, wrong signature, no IHDR first).
PngInfo? inspectPng(Uint8List bytes) {
  // signature (8) + IHDR length/type (8) + IHDR data (13)
  if (bytes.length < 33) return null;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }
  final view = ByteData.sublistView(bytes);
  if (view.getUint32(8) != 13 || view.getUint32(12) != 0x49484452 /* IHDR */ ) {
    return null;
  }
  final width = view.getUint32(16);
  final height = view.getUint32(20);
  final bitDepth = bytes[24];
  final colorType = bytes[25];
  final interlace = bytes[28];

  var hasIcc = false;
  var hasPalette = false;
  // Walk the remaining chunks until the image data begins.
  var offset = 8 + 12 + 13;
  while (offset + 8 <= bytes.length) {
    final length = view.getUint32(offset);
    final type = view.getUint32(offset + 4);
    if (type == 0x69434350 /* iCCP */ ) hasIcc = true;
    if (type == 0x504C5445 /* PLTE */ ) hasPalette = true;
    if (type == 0x49444154 /* IDAT */ || type == 0x49454E44 /* IEND */ ) break;
    offset += 12 + length;
  }
  return PngInfo(
    width: width,
    height: height,
    bitDepth: bitDepth,
    colorType: colorType,
    interlace: interlace,
    hasIccProfile: hasIcc,
    hasPalette: hasPalette,
  );
}

/// The largest marker icon edge (px) the app will ever hand the SDK. Pins here
/// are 56–68 px; anything wildly larger is a bug, not a marker.
const int kMaxMarkerEdge = 512;

/// Whether [bytes] is a marker icon the native SDK is known to be able to take:
/// a non-interlaced, 8-bit-per-channel PNG with real, bounded dimensions and no
/// embedded colour profile.
///
/// This is deliberately strict about *depth and profile* because those are what
/// differ between a plain sRGB bitmap and a wide-gamut one; see [PngInfo].
bool isSafeMarkerPng(Uint8List bytes) {
  final info = inspectPng(bytes);
  if (info == null) return false;
  return info.width > 0 &&
      info.height > 0 &&
      info.width <= kMaxMarkerEdge &&
      info.height <= kMaxMarkerEdge &&
      info.bitDepth == 8 &&
      (info.colorType == 6 || info.colorType == 2) &&
      info.interlace == 0 &&
      !info.hasIccProfile;
}

/// Turns a rendered [image] into marker-icon bytes for the native SDK.
///
/// Flutter's own PNG encoder follows the surface the image was drawn on, so on
/// a wide-gamut device (every recent iPhone) the bytes are not guaranteed to be
/// a plain 8-bit sRGB bitmap. The pixels are read back as straight 8-bit RGBA
/// and written as exactly that, then verified. A failure here throws a normal
/// Dart error (which the caller handles: no markers) instead of reaching the
/// SDK, where it would abort the whole process.
Future<Uint8List> markerPngFromImage(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (data == null) {
    throw StateError('The marker image has no pixel data.');
  }
  final png = encodeRgbaPng(
    image.width,
    image.height,
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  if (!isSafeMarkerPng(png)) {
    throw StateError(
      'Refusing a marker image the map SDK cannot take: '
      '${inspectPng(png)}',
    );
  }
  return png;
}

/// Encodes straight (non-premultiplied) 8-bit RGBA pixels, `width * height * 4`
/// bytes, as a plain 8-bit RGBA PNG: colour type 6, no colour profile, no
/// gamma, no interlacing, so every decoder reads it as ordinary sRGB.
///
/// The deflate stream is *stored* (uncompressed): marker bitmaps are a few KB,
/// and this keeps the encoder dependency-free and identical on every platform
/// (no `dart:io`, so it also compiles for the web build).
Uint8List encodeRgbaPng(int width, int height, Uint8List rgba) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('PNG size must be positive: ${width}x$height');
  }
  if (rgba.length != width * height * 4) {
    throw ArgumentError(
      'Expected ${width * height * 4} RGBA bytes for ${width}x$height, '
      'got ${rgba.length}.',
    );
  }

  // Raw scanlines: a filter byte (0 = none) followed by the row's pixels.
  final stride = width * 4;
  final raw = Uint8List(height * (stride + 1));
  for (var y = 0; y < height; y++) {
    final dst = y * (stride + 1);
    raw[dst] = 0;
    raw.setRange(dst + 1, dst + 1 + stride, rgba, y * stride);
  }

  final out = BytesBuilder(copy: false)..add(_pngSignature);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // colour type: RGBA
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace: none
  _writeChunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _writeChunk(out, 'IDAT', _zlibStored(raw));
  _writeChunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _writeChunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final length = ByteData(4)..setUint32(0, data.length);
  out
    ..add(length.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data);
  final crc = _crc32(_crc32Seed, typeBytes);
  final crcFinal = ByteData(4)..setUint32(0, _crc32Finish(_crc32(crc, data)));
  out.add(crcFinal.buffer.asUint8List());
}

/// A zlib stream made of stored (uncompressed) deflate blocks.
Uint8List _zlibStored(Uint8List data) {
  const maxBlock = 0xFFFF;
  final out = BytesBuilder(copy: false)..add(const [0x78, 0x01]);
  var offset = 0;
  do {
    final len = data.length - offset < maxBlock
        ? data.length - offset
        : maxBlock;
    final last = offset + len >= data.length;
    final header = ByteData(5)
      ..setUint8(0, last ? 1 : 0)
      ..setUint16(1, len, Endian.little)
      ..setUint16(3, len ^ 0xFFFF, Endian.little);
    out
      ..add(header.buffer.asUint8List())
      ..add(Uint8List.sublistView(data, offset, offset + len));
    offset += len;
  } while (offset < data.length);
  final adler = ByteData(4)..setUint32(0, _adler32(data));
  out.add(adler.buffer.asUint8List());
  return out.takeBytes();
}

int _adler32(Uint8List data) {
  var a = 1, b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

const _crc32Seed = 0xFFFFFFFF;

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(int crc, Uint8List data) {
  var c = crc;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return c;
}

int _crc32Finish(int crc) => crc ^ 0xFFFFFFFF;
