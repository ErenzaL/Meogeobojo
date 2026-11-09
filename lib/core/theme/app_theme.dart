import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_palette.dart';

abstract final class AppSpacing {
  static const double screenH = 20;
  static const double gap = 12;
  static const double sectionGap = 28;
}

abstract final class AppRadius {
  static const double card = 20;
  static const double pill = 999;
  static const double sheet = 28;
}

/// Text styles. Colourless ones inherit the theme's text colour; [caption] and
/// [link] are secondary text, so their colour comes from the palette.
abstract final class AppText {
  static const heroTitle = TextStyle(
    fontSize: 30,
    height: 1.25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );
  static const sectionTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );
  static const title = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontSize: 14, height: 1.4);

  /// Times and prices (19:01, ₩5,100): monospaced, tabular digits so they
  /// line up and do not jitter when a minute ticks over.
  static TextStyle numeric({double size = 16, FontWeight? weight}) {
    final mono =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return TextStyle(
      fontFamily: mono ? 'Menlo' : 'monospace',
      fontSize: size,
      fontWeight: weight ?? FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle caption(BuildContext context) => TextStyle(
    fontSize: 12,
    height: 1.3,
    color: context.palette.textSecondary,
  );

  static TextStyle link(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: context.palette.textSecondary,
  );
}

ThemeData buildLightTheme() => _build(Brightness.light, AppPalette.light);
ThemeData buildDarkTheme() => _build(Brightness.dark, AppPalette.dark);

/// Kept for callers that just want "the" theme: Light.
ThemeData buildAppTheme() => buildLightTheme();

ThemeData _build(Brightness brightness, AppPalette p) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
      ).copyWith(
        primary: p.accent,
        onPrimary: AppColors.textOnPrimary,
        primaryContainer: p.accentSoft,
        onPrimaryContainer: p.accentStrong,
        secondary: p.peach,
        onSecondary: p.onPeach,
        secondaryContainer: p.accentSoft,
        onSecondaryContainer: p.accentStrong,
        surface: p.background,
        onSurface: p.textPrimary,
        onSurfaceVariant: p.textSecondary,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: p.background,
        surfaceContainerLow: p.card,
        surfaceContainer: p.card,
        surfaceContainerHigh: p.surfaceAlt,
        surfaceContainerHighest: p.surfaceAlt,
        outline: p.border,
        outlineVariant: p.border,
        error: p.error,
      );
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final text = base.textTheme.apply(
    bodyColor: p.textPrimary,
    displayColor: p.textPrimary,
  );
  RoundedRectangleBorder round(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    cardColor: p.card,
    dividerColor: p.border,
    splashFactory: InkRipple.splashFactory,
    extensions: [p],
    iconTheme: IconThemeData(color: p.textPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: p.textPrimary,
      iconTheme: IconThemeData(color: p.textPrimary),
      titleTextStyle: AppText.title.copyWith(color: p.textPrimary),
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: round(AppRadius.card),
    ),
    dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: round(24),
      titleTextStyle: AppText.title.copyWith(
        fontSize: 18,
        color: p.textPrimary,
      ),
      contentTextStyle: AppText.body.copyWith(color: p.textPrimary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: round(16),
      textStyle: AppText.body.copyWith(fontSize: 15, color: p.textPrimary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // The brand orange fill, identical in both themes.
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: p.surfaceAlt,
        disabledForegroundColor: p.textSecondary,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accentStrong),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        side: BorderSide(color: p.border),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceAlt,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.border,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.28),
      selectionHandleColor: p.accent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.dark
          ? p.surfaceAlt
          : p.textPrimary,
      contentTextStyle: TextStyle(
        color: brightness == Brightness.dark ? p.textPrimary : Colors.white,
        fontSize: 14,
      ),
      actionTextColor: brightness == Brightness.dark
          ? p.accentStrong
          : AppColors.peach,
      shape: round(14),
    ),
  );
}
