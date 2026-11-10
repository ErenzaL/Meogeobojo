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
    required this.brandWarm,
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
    required this.borderStrong,
    required this.textMuted,
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

  /// The brand's warm yellow-orange (#FFCA80): a complementary accent for web branding (the footer rule). It is NOT the
  /// primary action colour: buttons and links stay rust ([rust] / [accent]).
  final Color brandWarm;

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

  /// Stronger hairline (V5 `--line-2`): outlined buttons, chips, inputs.
  final Color borderStrong;

  /// Muted text (V5 `--muted`), below [textSecondary].
  final Color textMuted;

  static const light = AppPalette(
    background: Color(0xFFF6F5F3),
    card: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFEDE9),
    border: Color(0x171C1A17),
    textPrimary: Color(0xFF1C1A17), // warm dark brown, not pure black
    textSecondary: Color(0xFF57524B),
    accent: Color(0xFFC2410C),
    accentStrong: Color(0xFF9A3412),
    accentSoft: Color(0xFFFBEEE7),
    accentFaint: Color(0xFFFBEEE7),
    accentTile: Color(0xFFFBEEE7),
    peach: Color(0xFFF1EDE7),
    brandWarm: Color(0xFFFFCA80),
    onPeach: Color(0xFF1C1A17),
    bannerStart: Color(0xFFFBEEE7),
    bannerEnd: Color(0xFFFBEEE7),
    placeholder: Color(0xFFEFEDE9),
    placeholderIcon: Color(0xFFA8A097),
    shadow: Color(0x14000000),
    shadowBlur: 16,
    error: Color(0xFFC62828),
    heart: Color(0xFFC62828),
    navSurface: Color(0xFFFFFFFF),
    navBorder: Color(0x171C1A17),
    navIdle: Color(0xFF6F6962),
    navSelectedBg: Color(0x00000000),
    navSelectedFg: Color(0xFFC2410C), // active tab in the brand orange
    navShadow: Color(0x00000000),
    pageWarm: Color(0xFFF6F5F3),
    hairline: Color(0x171C1A17),
    fillMuted: Color(0xFFEFEDE9),
    rust: Color(0xFFC2410C),
    onRust: Color(0xFFFFFFFF),
    rustSoft: Color(0xFFFBEEE7),
    rustText: Color(0xFF9A3412),
    chipSelectedBg: Color(0xFF1C1A17),
    chipSelectedFg: Color(0xFFFFFFFF),
    statusOpen: Color(0xFF15803D),
    statusWarn: Color(0xFFB45309),
    starAmber: Color(0xFFB7791F),
    barMuted: Color(0xFF6F6962),
    artBackdrop: Color(0xFF3B3532),
    borderStrong: Color(0x2B1C1A17),
    textMuted: Color(0xFF6F6962),
  );

  static const dark = AppPalette(
    background: Color(0xFF151413),
    card: Color(0xFF1C1B19),
    surfaceAlt: Color(0xFF272522),
    border: Color(0x17EFEBE4),
    textPrimary: Color(0xFFEFEBE4),
    textSecondary: Color(0xFFB3ADA4),
    accent: Color(0xFFEE7A45),
    accentStrong: Color(0xFFF4A177),
    accentSoft: Color(0x24EE7A45),
    accentFaint: Color(0x24EE7A45),
    accentTile: Color(0x24EE7A45),
    peach: Color(0xFF2A2724),
    brandWarm: Color(0xFFFFCA80),
    onPeach: Color(0xFFEFEBE4),
    bannerStart: Color(0x24EE7A45),
    bannerEnd: Color(0x24EE7A45),
    placeholder: Color(0xFF272522),
    placeholderIcon: Color(0xFF6E675F),
    shadow: Color(0x66000000),
    shadowBlur: 12,
    error: Color(0xFFF07D72),
    heart: Color(0xFFF07D72),
    navSurface: Color(0xFF1C1B19),
    navBorder: Color(0x17EFEBE4),
    navIdle: Color(0xFF938D84),
    navSelectedBg: Color(0x00000000),
    navSelectedFg: Color(0xFFEE7A45), // active tab in the brand orange
    navShadow: Color(0x00000000),
    pageWarm: Color(0xFF151413),
    hairline: Color(0x17EFEBE4),
    fillMuted: Color(0xFF272522),
    rust: Color(0xFFEE7A45),
    onRust: Color(0xFF1C1A17),
    rustSoft: Color(0x24EE7A45),
    rustText: Color(0xFFF4A177),
    chipSelectedBg: Color(0xFFEFEBE4),
    chipSelectedFg: Color(0xFF151413),
    statusOpen: Color(0xFF5FC28A),
    statusWarn: Color(0xFFE8A852),
    starAmber: Color(0xFFE2B04A),
    barMuted: Color(0xFF938D84),
    artBackdrop: Color(0xFF2A2624),
    borderStrong: Color(0x2EEFEBE4),
    textMuted: Color(0xFF938D84),
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
      brandWarm: c(brandWarm, other.brandWarm),
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
      borderStrong: c(borderStrong, other.borderStrong),
      textMuted: c(textMuted, other.textMuted),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The active palette. Always present: both app themes register it.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
