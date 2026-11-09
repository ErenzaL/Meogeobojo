import 'package:flutter/material.dart';

/// Brand constants that look the same in every theme. Anything that changes
/// with Light / Dark (backgrounds, cards, borders, text, accents) lives in
/// `AppPalette` and is read with `context.palette`.
abstract final class AppColors {
  /// Brand orange used for FILLED controls (buttons, selected circles) in both
  /// themes, so the identity is identical in Light and Dark.
  static const primary = Color(0xFFC2410C);

  /// Deeper end of the orange CTA gradient.
  static const primaryDeep = Color(0xFF9A3412);

  /// Brand peach, used for decorative shapes and accents.
  static const peach = Color(0xFFF1EDE7);

  /// Campus pin on the map (the map tiles are fixed, so pins never change
  /// with the app theme).
  static const pinCampus = Color(0xFF2D201A);

  /// Text/icons placed on filled orange.
  static const textOnPrimary = Color(0xFFFFFFFF);
}
