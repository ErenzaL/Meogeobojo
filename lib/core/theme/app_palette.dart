import 'package:flutter/material.dart';

/// Every theme-dependent colour in the app, as one [ThemeExtension].
///
/// Widgets read these through `context.palette` (or the [ColorScheme] for
/// standard Material widgets); nothing outside this file may hard-code a
/// background, card, border or text colour, so Light, Dark and System all
/// flow from a single place.
///
/// Light is a clean white canvas with warm orange/peach personality; Dark is
/// charcoal with warm accents. Dark is not an inversion: accents are
/// re-tuned for contrast and orange is kept restrained.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.card,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.accentFaint,
    required this.accentTile,
    required this.peach,
    required this.onPeach,
    required this.bannerStart,
    required this.bannerEnd,
    required this.placeholder,
    required this.placeholderIcon,
    required this.shadow,
    required this.shadowBlur,
    required this.error,
    required this.heart,
    required this.navSurface,
    required this.navBorder,
    required this.navIdle,
    required this.navSelectedBg,
    required this.navSelectedFg,
    required this.navShadow,
    required this.pageWarm,
    required this.hairline,
    required this.fillMuted,
    required this.rust,
    required this.onRust,
    required this.rustSoft,
    required this.rustText,
    required this.chipSelectedBg,
    required this.chipSelectedFg,
    required this.statusOpen,
    required this.statusWarn,
    required this.starAmber,
    required this.barMuted,
    required this.artBackdrop,
  });

  /// Page / scaffold background.
  final Color background;

  /// Cards and other raised content surfaces.
  final Color card;

  /// Secondary / elevated surfaces (inputs, chips, sheets).
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  /// Brand orange for icons, outlines and highlights.
  final Color accent;

  /// Orange for TEXT and small glyphs that must reach AA contrast on the page
  /// and on [accentSoft] (a deeper orange in Light, a lighter one in Dark).
  final Color accentStrong;

  /// Selected-control background (selected chips, tabs, tiles).
  final Color accentSoft;

  /// Very soft orange tint for highlighted blocks (cards in onboarding, tags).
  final Color accentFaint;

  /// Fill of highlighted shortcut tiles (e.g. 학식 on Home): peach in Light,
  /// a muted warm brown in Dark.
  final Color accentTile;
  final Color peach;

  /// Text/icons drawn ON [peach] fills; always dark so it reads in both modes.
  final Color onPeach;
  final Color bannerStart;
  final Color bannerEnd;
  final Color placeholder;
  final Color placeholderIcon;
  final Color shadow;
  final double shadowBlur;
  final Color error;
  final Color heart;
  final Color navSurface;
  final Color navBorder;
  final Color navIdle;
  final Color navSelectedBg;
  final Color navSelectedFg;
  final Color navShadow;

  // ---- Home / sheets role tokens (calm warm-neutral look) ----

  /// Warm off-white page behind the Home tab and the sheets' scroll area.
  final Color pageWarm;

  /// 1px hairline on cards, chips and dividers (warmer than [border]).
  final Color hairline;

  /// Neutral fill for secondary buttons, tiles and icon wells.
  final Color fillMuted;

  /// Deep rust: filled CTAs, logo dot, primary action buttons.
  final Color rust;
  final Color onRust;

  /// Light rust tint for a selected row.
  final Color rustSoft;

  /// Rust used for text / links (AA on the page and card).
  final Color rustText;

  /// Selected chip: near-black fill in Light, inverted in Dark.
  final Color chipSelectedBg;
  final Color chipSelectedFg;

  /// "Order available" green, "closing / closed" orange, rating star amber.
  final Color statusOpen;
  final Color statusWarn;
  final Color starAmber;

  /// Secondary bar in comparison charts.
  final Color barMuted;

  /// Backdrop behind category illustrations when there is no photo.
  final Color artBackdrop;

  static const light = AppPalette(
    background: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F7F7),
    border: Color(0xFFEAEAEA),
    textPrimary: Color(0xFF2D201A), // warm dark brown, not pure black
    textSecondary: Color(0xFF6F6F6F),
    accent: Color(0xFFF36B21),
    accentStrong: Color(0xFFB8420A),
    accentSoft: Color(0xFFFFE7C9),
    accentFaint: Color(0xFFFFF3E6),
    accentTile: Color(0xFFFFEFDB),
    peach: Color(0xFFFFCA80),
    onPeach: Color(0xFF2D201A),
    bannerStart: Color(0xFFFFF3E4),
    bannerEnd: Color(0xFFFFE7C9),
    placeholder: Color(0xFFF4F4F4),
    placeholderIcon: Color(0xFFC9C9C9),
    shadow: Color(0x14000000),
    shadowBlur: 16,
    error: Color(0xFFC93C3C),
    heart: Color(0xFFE5484D),
    navSurface: Color(0xEDFFFFFF),
    navBorder: Color(0xFFEAEAEA),
    navIdle: Color(0xFF2D201A),
    navSelectedBg: Color(0xFFFFE7C9),
    navSelectedFg: Color(0xFFB8420A),
    navShadow: Color(0x1A000000),
    pageWarm: Color(0xFFF5F4F1),
    hairline: Color(0xFFE8E5E0),
    fillMuted: Color(0xFFEEECE7),
    rust: Color(0xFFB34A22),
    onRust: Color(0xFFFFFFFF),
    rustSoft: Color(0xFFFBEBE2),
    rustText: Color(0xFFB34A22),
    chipSelectedBg: Color(0xFF1C1B19),
    chipSelectedFg: Color(0xFFFFFFFF),
    statusOpen: Color(0xFF3A7D44),
    statusWarn: Color(0xFFB8561E),
    starAmber: Color(0xFFB8862F),
    barMuted: Color(0xFF6B655D),
    artBackdrop: Color(0xFF3B3532),
  );

  static const dark = AppPalette(
    background: Color(0xFF121212),
    card: Color(0xFF202020),
    surfaceAlt: Color(0xFF292929),
    border: Color(0xFF383838),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFB0B0B0),
    accent: Color(0xFFFF873F),
    accentStrong: Color(0xFFFFA066),
    accentSoft: Color(0xFF483021),
    accentFaint: Color(0xFF332316),
    accentTile: Color(0xFF5A3A22),
    peach: Color(0xFFFFCA80),
    onPeach: Color(0xFF2D201A),
    bannerStart: Color(0xFF332316),
    bannerEnd: Color(0xFF3E2918),
    placeholder: Color(0xFF2A2A2A),
    placeholderIcon: Color(0xFF6A5A4C),
    shadow: Color(0x33000000),
    shadowBlur: 12,
    error: Color(0xFFFF7A7A),
    heart: Color(0xFFFF6B70),
    navSurface: Color(0xEB292929),
    navBorder: Color(0xFF383838),
    navIdle: Color(0xFFB8B8B8),
    navSelectedBg: Color(0xFF483021),
    navSelectedFg: Color(0xFFFFA066),
    navShadow: Color(0x66000000),
    pageWarm: Color(0xFF141312),
    hairline: Color(0xFF38342F),
    fillMuted: Color(0xFF2B2926),
    rust: Color(0xFFC25A2E),
    onRust: Color(0xFFFFFFFF),
    rustSoft: Color(0xFF3A2519),
    rustText: Color(0xFFFF9C74),
    chipSelectedBg: Color(0xFFF2EFEA),
    chipSelectedFg: Color(0xFF1C1B19),
    statusOpen: Color(0xFF6FBF7B),
    statusWarn: Color(0xFFF09A62),
    starAmber: Color(0xFFD9A94E),
    barMuted: Color(0xFF9A948A),
    artBackdrop: Color(0xFF2A2624),
  );

  /// Cards are separated from the page by their hairline border only. A
  /// drop shadow was tried and rejected: two neighbouring card shadows
  /// overlap in the 12px gap between cards and tint the page (it measured
  /// #F9F5F2, i.e. cream, on the white page), so the space between sections
  /// is no longer pure #FFFFFF / #121212. [shadow] is kept for the few
  /// floating surfaces that really do sit above content.
  List<BoxShadow> get cardShadow => const [];

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: c(background, other.background),
      card: c(card, other.card),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      border: c(border, other.border),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      accent: c(accent, other.accent),
      accentStrong: c(accentStrong, other.accentStrong),
      accentSoft: c(accentSoft, other.accentSoft),
      accentFaint: c(accentFaint, other.accentFaint),
      accentTile: c(accentTile, other.accentTile),
      peach: c(peach, other.peach),
      onPeach: c(onPeach, other.onPeach),
      bannerStart: c(bannerStart, other.bannerStart),
      bannerEnd: c(bannerEnd, other.bannerEnd),
      placeholder: c(placeholder, other.placeholder),
      placeholderIcon: c(placeholderIcon, other.placeholderIcon),
      shadow: c(shadow, other.shadow),
      shadowBlur: shadowBlur + (other.shadowBlur - shadowBlur) * t,
      error: c(error, other.error),
      heart: c(heart, other.heart),
      navSurface: c(navSurface, other.navSurface),
      navBorder: c(navBorder, other.navBorder),
      navIdle: c(navIdle, other.navIdle),
      navSelectedBg: c(navSelectedBg, other.navSelectedBg),
      navSelectedFg: c(navSelectedFg, other.navSelectedFg),
      navShadow: c(navShadow, other.navShadow),
      pageWarm: c(pageWarm, other.pageWarm),
      hairline: c(hairline, other.hairline),
      fillMuted: c(fillMuted, other.fillMuted),
      rust: c(rust, other.rust),
      onRust: c(onRust, other.onRust),
      rustSoft: c(rustSoft, other.rustSoft),
      rustText: c(rustText, other.rustText),
      chipSelectedBg: c(chipSelectedBg, other.chipSelectedBg),
      chipSelectedFg: c(chipSelectedFg, other.chipSelectedFg),
      statusOpen: c(statusOpen, other.statusOpen),
      statusWarn: c(statusWarn, other.statusWarn),
      starAmber: c(starAmber, other.starAmber),
      barMuted: c(barMuted, other.barMuted),
      artBackdrop: c(artBackdrop, other.artBackdrop),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The active palette. Always present: both app themes register it.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
