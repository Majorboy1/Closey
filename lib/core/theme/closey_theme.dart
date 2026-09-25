import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'closey_colors.dart';
import 'closey_spacing.dart';
import 'closey_typography.dart';

/// Assembles the two [ThemeData] variants.
///
/// Light is the default: warm paper reads trustworthy and editorial, and it
/// immediately distinguishes Closey from the sea of dark purple "AI" apps.
/// Dark is a first-class peer, not an afterthought — every token in
/// [CloseyColors] has a deliberate dark counterpart.
abstract final class CloseyTheme {
  static ThemeData light() => _build(CloseyColors.light, Brightness.light);
  static ThemeData dark() => _build(CloseyColors.dark, Brightness.dark);

  static ThemeData _build(CloseyColors c, Brightness brightness) {
    final text = CloseyTypography.textTheme(c);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.textOnBrand,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brandText,
      secondary: c.success,
      onSecondary: brightness == Brightness.light
          ? Colors.white
          : CloseyColors.dark.textPrimary,
      secondaryContainer: c.successSoft,
      onSecondaryContainer: c.successText,
      tertiary: c.accent,
      onTertiary: c.accentText,
      tertiaryContainer: c.accentSoft,
      onTertiaryContainer: c.accentText,
      error: c.danger,
      onError: brightness == Brightness.light
          ? Colors.white
          : CloseyColors.dark.textPrimary,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.backgroundSunken,
      surfaceContainerLow: c.background,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      onSurfaceVariant: c.textSecondary,
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: c.shadow,
      scrim: c.scrim,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.surface,
      inversePrimary: c.brandHover,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[c],

      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),

      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: Strokes.hairline,
        space: 0,
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.allLg,
          side: BorderSide(color: c.border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hoverColor: c.brandSoft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.lg,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: c.textTertiary),
        labelStyle: text.titleSmall?.copyWith(color: c.textSecondary),
        // A visible focus ring — the Expo `Input` had no focus state at all,
        // so keyboard users could not tell which field was active.
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.allMd,
          borderSide: BorderSide(color: c.brand, width: Strokes.thin),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.allMd,
          borderSide: BorderSide(color: c.border),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.allMd,
          borderSide: BorderSide(color: c.danger, width: Strokes.thin),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.allMd,
          borderSide: BorderSide(color: c.danger, width: Strokes.thick),
        ),
        errorStyle: text.bodySmall?.copyWith(color: c.danger),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.brand,
        side: BorderSide(color: c.border),
        labelStyle: text.titleSmall!,
        secondaryLabelStyle: text.titleSmall!.copyWith(color: c.textOnBrand),
        showCheckmark: true,
        checkmarkColor: c.textOnBrand,
        shape: const RoundedRectangleBorder(borderRadius: Radii.pill),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.textOnBrand : c.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.brand : c.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.brand : c.borderStrong,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surfaceRaised,
        shape: const RoundedRectangleBorder(borderRadius: Radii.allSheet),
        showDragHandle: false,
      ),

      dividerColor: c.border,

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.textPrimary,
        contentTextStyle: text.bodyLarge?.copyWith(color: c.surface),
        shape: const RoundedRectangleBorder(borderRadius: Radii.allMd),
        insetPadding: const EdgeInsets.all(Gap.lg),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.allXl),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyLarge?.copyWith(color: c.textSecondary),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand,
        linearTrackColor: c.surfaceSunken,
        circularTrackColor: c.surfaceSunken,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brandText,
          textStyle: text.labelLarge,
          minimumSize: const Size(TapTarget.min, TapTarget.min),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        ),
      ),

      iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      primaryIconTheme: IconThemeData(color: c.textOnBrand),
    );
  }
}
