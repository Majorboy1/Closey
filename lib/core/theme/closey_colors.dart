import 'package:flutter/material.dart';

import 'closey_palette.dart';

/// Semantic colour tokens, exposed as a [ThemeExtension] so widgets never
/// branch on brightness and never hardcode a hex value.
///
/// This is the single biggest structural fix over the Expo app, which
/// accumulated ~40 ad-hoc greys (`#999999`, `#666666`, `rgba(255,255,255,.05)`
/// …) scattered inline across 22 screen files while the documented palette sat
/// unused in `theme.ts`.
@immutable
class CloseyColors extends ThemeExtension<CloseyColors> {
  const CloseyColors({
    required this.brightness,
    required this.background,
    required this.backgroundSunken,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnBrand,
    required this.brand,
    required this.brandHover,
    required this.brandText,
    required this.brandSoft,
    required this.brandBorder,
    required this.accent,
    required this.accentText,
    required this.accentSoft,
    required this.success,
    required this.successText,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.coachSurface,
    required this.coachBorder,
    required this.coachGlow,
    required this.privateSurface,
    required this.chatMine,
    required this.chatMineText,
    required this.chatTheirs,
    required this.chatTheirsText,
    required this.chatTheirsBorder,
    required this.scrim,
    required this.skeleton,
    required this.shadow,
  });

  final Brightness brightness;

  /// Page background.
  final Color background;

  /// A subtle band behind the page (e.g. behind a photo header).
  final Color backgroundSunken;

  /// Default card/panel fill.
  final Color surface;

  /// Card that sits above another card (sheets, popovers).
  final Color surfaceRaised;

  /// Inset well — code blocks, photo placeholders, inactive tracks.
  final Color surfaceSunken;

  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Text/icon colour placed on top of [brand].
  final Color textOnBrand;

  /// Brand fill. White text on it clears 5:1 in light mode.
  final Color brand;
  final Color brandHover;

  /// Brand used as *text* on [background]. Always contrast-safe.
  final Color brandText;

  /// Tinted brand container for pills and inline notices.
  final Color brandSoft;
  final Color brandBorder;

  final Color accent;
  final Color accentText;
  final Color accentSoft;

  final Color success;
  final Color successText;
  final Color successSoft;

  final Color danger;
  final Color dangerSoft;

  /// The AI coach's own surface — intentionally warmer than a normal card so
  /// suggestions never get mistaken for a chat bubble.
  final Color coachSurface;
  final Color coachBorder;
  final Color coachGlow;

  /// Surface for private ("just for you") nudges.
  final Color privateSurface;

  final Color chatMine;
  final Color chatMineText;
  final Color chatTheirs;
  final Color chatTheirsText;
  final Color chatTheirsBorder;

  final Color scrim;
  final Color skeleton;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  // ------------------------------------------------------------------ light

  static const CloseyColors light = CloseyColors(
    brightness: Brightness.light,
    background: CloseyPalette.paper,
    backgroundSunken: CloseyPalette.paperDeep,
    surface: CloseyPalette.white,
    surfaceRaised: CloseyPalette.white,
    surfaceSunken: CloseyPalette.paperDeep,
    border: CloseyPalette.ink100,
    borderStrong: CloseyPalette.ink200,
    textPrimary: CloseyPalette.ink800,
    textSecondary: CloseyPalette.ink500,
    textTertiary: CloseyPalette.ink400,
    textOnBrand: CloseyPalette.white,
    brand: CloseyPalette.rose600,
    brandHover: CloseyPalette.rose700,
    brandText: CloseyPalette.rose700,
    brandSoft: CloseyPalette.rose50,
    brandBorder: CloseyPalette.rose100,
    accent: CloseyPalette.amber500,
    accentText: CloseyPalette.amber700,
    accentSoft: CloseyPalette.amber50,
    success: CloseyPalette.sage600,
    successText: CloseyPalette.sage700,
    successSoft: CloseyPalette.sage50,
    danger: CloseyPalette.rose700,
    dangerSoft: CloseyPalette.rose50,
    coachSurface: CloseyPalette.amber50,
    coachBorder: CloseyPalette.amber200,
    coachGlow: CloseyPalette.amber100,
    privateSurface: CloseyPalette.rose50,
    chatMine: CloseyPalette.rose600,
    chatMineText: CloseyPalette.white,
    chatTheirs: CloseyPalette.white,
    chatTheirsText: CloseyPalette.ink800,
    chatTheirsBorder: CloseyPalette.ink100,
    scrim: Color(0x8C201F2E),
    skeleton: CloseyPalette.ink100,
    shadow: Color(0x14201F2E),
  );

  // ------------------------------------------------------------------- dark

  static const CloseyColors dark = CloseyColors(
    brightness: Brightness.dark,
    background: CloseyPalette.night,
    backgroundSunken: Color(0xFF121118),
    surface: CloseyPalette.nightRaised,
    surfaceRaised: CloseyPalette.nightHigh,
    surfaceSunken: Color(0xFF100F16),
    border: CloseyPalette.nightBorder,
    borderStrong: Color(0xFF44415C),
    textPrimary: CloseyPalette.darkTextPrimary,
    textSecondary: CloseyPalette.darkTextSecondary,
    textTertiary: CloseyPalette.darkTextTertiary,
    // Material 3 flips this on dark: a *lighter* brand fill with dark ink on
    // top is what actually clears AA. Keeping the light-mode fill here would
    // have shipped a 4.29:1 button label.
    textOnBrand: CloseyPalette.ink,
    brand: CloseyPalette.rose400,
    brandHover: CloseyPalette.rose300,
    brandText: CloseyPalette.rose300,
    brandSoft: Color(0xFF33202A),
    brandBorder: Color(0xFF54323F),
    accent: CloseyPalette.amber400,
    accentText: CloseyPalette.amber300,
    accentSoft: Color(0xFF322616),
    success: CloseyPalette.sage300,
    successText: CloseyPalette.sage300,
    successSoft: Color(0xFF1F2A20),
    danger: CloseyPalette.rose300,
    dangerSoft: Color(0xFF33202A),
    coachSurface: Color(0xFF2B2416),
    coachBorder: Color(0xFF57432A),
    coachGlow: Color(0xFF3C3220),
    privateSurface: Color(0xFF31202A),
    chatMine: CloseyPalette.rose400,
    chatMineText: CloseyPalette.ink,
    chatTheirs: CloseyPalette.nightHigh,
    chatTheirsText: CloseyPalette.darkTextPrimary,
    chatTheirsBorder: CloseyPalette.nightBorder,
    scrim: Color(0xCC0B0A12),
    skeleton: Color(0xFF2A2839),
    shadow: Color(0x66000000),
  );

  @override
  CloseyColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? backgroundSunken,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnBrand,
    Color? brand,
    Color? brandHover,
    Color? brandText,
    Color? brandSoft,
    Color? brandBorder,
    Color? accent,
    Color? accentText,
    Color? accentSoft,
    Color? success,
    Color? successText,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? coachSurface,
    Color? coachBorder,
    Color? coachGlow,
    Color? privateSurface,
    Color? chatMine,
    Color? chatMineText,
    Color? chatTheirs,
    Color? chatTheirsText,
    Color? chatTheirsBorder,
    Color? scrim,
    Color? skeleton,
    Color? shadow,
  }) {
    return CloseyColors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      backgroundSunken: backgroundSunken ?? this.backgroundSunken,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textOnBrand: textOnBrand ?? this.textOnBrand,
      brand: brand ?? this.brand,
      brandHover: brandHover ?? this.brandHover,
      brandText: brandText ?? this.brandText,
      brandSoft: brandSoft ?? this.brandSoft,
      brandBorder: brandBorder ?? this.brandBorder,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      successText: successText ?? this.successText,
      successSoft: successSoft ?? this.successSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      coachSurface: coachSurface ?? this.coachSurface,
      coachBorder: coachBorder ?? this.coachBorder,
      coachGlow: coachGlow ?? this.coachGlow,
      privateSurface: privateSurface ?? this.privateSurface,
      chatMine: chatMine ?? this.chatMine,
      chatMineText: chatMineText ?? this.chatMineText,
      chatTheirs: chatTheirs ?? this.chatTheirs,
      chatTheirsText: chatTheirsText ?? this.chatTheirsText,
      chatTheirsBorder: chatTheirsBorder ?? this.chatTheirsBorder,
      scrim: scrim ?? this.scrim,
      skeleton: skeleton ?? this.skeleton,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  CloseyColors lerp(covariant CloseyColors? other, double t) {
    if (other == null) return this;
    return CloseyColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      backgroundSunken: Color.lerp(backgroundSunken, other.backgroundSunken, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textOnBrand: Color.lerp(textOnBrand, other.textOnBrand, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandHover: Color.lerp(brandHover, other.brandHover, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      brandBorder: Color.lerp(brandBorder, other.brandBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      coachSurface: Color.lerp(coachSurface, other.coachSurface, t)!,
      coachBorder: Color.lerp(coachBorder, other.coachBorder, t)!,
      coachGlow: Color.lerp(coachGlow, other.coachGlow, t)!,
      privateSurface: Color.lerp(privateSurface, other.privateSurface, t)!,
      chatMine: Color.lerp(chatMine, other.chatMine, t)!,
      chatMineText: Color.lerp(chatMineText, other.chatMineText, t)!,
      chatTheirs: Color.lerp(chatTheirs, other.chatTheirs, t)!,
      chatTheirsText: Color.lerp(chatTheirsText, other.chatTheirsText, t)!,
      chatTheirsBorder: Color.lerp(
        chatTheirsBorder,
        other.chatTheirsBorder,
        t,
      )!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      skeleton: Color.lerp(skeleton, other.skeleton, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// The canonical way to reach design tokens from a widget:
/// `context.colors`, `context.type`, `context.motion(d)`, `context.reduceMotion`.
///
/// The Expo app had no equivalent — screens called
/// `Theme.of(context).textTheme.titleMedium` at best, and more often just
/// hardcoded a hex value and a font size inline.
extension CloseyThemeContext on BuildContext {
  CloseyColors get colors =>
      Theme.of(this).extension<CloseyColors>() ?? CloseyColors.light;

  TextTheme get type => Theme.of(this).textTheme;

  /// Alias kept because most call sites read better as `context.text`.
  TextTheme get text => Theme.of(this).textTheme;

  ColorScheme get scheme => Theme.of(this).colorScheme;

  bool get isDark => colors.isDark;
}
