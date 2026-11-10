import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// Fill / text pair for slice [i] of a wheel or a card back, taken only from
/// the app palette so it follows light and dark mode.
(Color fill, Color text) gameSliceColors(AppPalette p, int i) {
  final pairs = [
    (p.rust, p.onRust),
    (p.accentSoft, p.rustText),
    (p.textPrimary, p.card),
    (p.peach, p.onPeach),
    (p.accent, p.onRust),
    (p.fillMuted, p.textPrimary),
  ];
  return pairs[i % pairs.length];
}

/// A name cut to [max] characters so it fits a slice or a card.
String shortName(String name, [int max = 7]) => name.runes.length <= max
    ? name
    : '${String.fromCharCodes(name.runes.take(max))}…';
