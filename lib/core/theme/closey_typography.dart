import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'closey_colors.dart';
import 'closey_palette.dart';

/// Type system.
///
/// Two families, deliberately paired:
/// * **Fraunces** — a soft, optical-sized serif for brand moments, screen
///   titles and profile names. It gives Closey the warm, editorial, "someone
///   actually designed this" feel that a default sans cannot.
/// * **Plus Jakarta Sans** — a friendly geometric grotesque for all UI and
///   body copy. High x-height, excellent at 13–16px, and it pairs with
///   Fraunces without competing.
///
/// Both are requested through `google_fonts`, which caches them on device
/// after first load. Before shipping to stores, run
/// `dart run google_fonts:google_fonts` (or drop the TTFs into
/// `assets/fonts/`) so text renders on first frame offline.
abstract final class CloseyTypography {
  static TextTheme textTheme(CloseyColors c) {
    // One family. The serif display face was the single biggest reason the app
    // read as a magazine rather than as a dating app, and it was doing no work
    // the sans could not do at a heavier weight.
    final display = GoogleFonts.plusJakartaSansTextTheme();
    final body = GoogleFonts.plusJakartaSansTextTheme();

    TextStyle d(
      double size,
      FontWeight weight, {
      double? height,
      double? letterSpacing,
    }) => (display.displaySmall ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: c.textPrimary,
    );

    TextStyle b(
      double size,
      FontWeight weight, {
      double? height,
      double? letterSpacing,
    }) => (body.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: c.textPrimary,
    );

    return TextTheme(
      // Fraunces — brand + screen titles.
      displayLarge: d(40, FontWeight.w700, height: 1.06, letterSpacing: -1.0),
      displayMedium: d(32, FontWeight.w700, height: 1.1, letterSpacing: -0.7),
      displaySmall: d(26, FontWeight.w700, height: 1.15, letterSpacing: -0.4),

      headlineLarge: d(24, FontWeight.w600, height: 1.2, letterSpacing: -0.3),
      headlineMedium: d(21, FontWeight.w600, height: 1.25, letterSpacing: -0.2),
      headlineSmall: d(18, FontWeight.w600, height: 1.3),

      // Plus Jakarta Sans — everything functional.
      titleLarge: b(19, FontWeight.w700, height: 1.3, letterSpacing: -0.2),
      titleMedium: b(16, FontWeight.w700, height: 1.35),
      titleSmall: b(14.5, FontWeight.w600, height: 1.35),

      bodyLarge: b(15.5, FontWeight.w500, height: 1.5),
      bodyMedium: b(14, FontWeight.w500, height: 1.5),
      bodySmall: b(12.5, FontWeight.w500, height: 1.45),

      labelLarge: b(14, FontWeight.w700, height: 1.2, letterSpacing: 0.1),
      labelMedium: b(12, FontWeight.w700, height: 1.2, letterSpacing: 0.3),
      labelSmall: b(11, FontWeight.w700, height: 1.2, letterSpacing: 0.4),
    );
  }

  /// Extra styles that do not map onto Material's slots.
  static const TextStyle wordmark = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.0,
  );

  /// Small uppercase section label — one shared definition replaces the
  /// copy-pasted `13px/800 uppercase letterSpacing 0.6` literals found in
  /// every second screen of the Expo app.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    height: 1.2,
  );

  /// Tabular numerals for counters, quota pills and prices.
  static const TextStyle numeric = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w700,
  );

  static TextStyle coachCopy(CloseyColors c) => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 17.5,
    fontWeight: FontWeight.w600,
    height: 1.42,
    letterSpacing: -0.1,
    color: c.textPrimary,
  );

  static TextStyle chatBubble(CloseyColors c) => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 15.5,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: c.textPrimary,
  );

  /// The coach's marginal voice.
  ///
  /// Smaller and lighter than [coachCopy] so it reads as annotation rather than
  /// as another message in the thread. It used to be an italic serif, which
  /// made the point by borrowing a print convention; weight and colour carry it
  /// now that the serif is gone.
  static TextStyle marginNote(CloseyColors c) => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    height: 1.45,
    letterSpacing: -0.05,
    color: c.accentText,
  );

  /// A person's own words, quoted back at display size.
  ///
  /// A prompt answer is the closest thing Closey has to a voice sample, so it is
  /// set as a pull quote rather than as another line of body copy — the one
  /// detail on a profile that tells you what they are actually like to talk to.
  static TextStyle pullQuote(CloseyColors c) => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 21,
    fontWeight: FontWeight.w800,
    height: 1.28,
    letterSpacing: -0.5,
    color: c.textPrimary,
  );
}

/// Brand-tinted eyebrow, used by section headers.
extension CloseyEyebrowContext on BuildContext {
  TextStyle eyebrow([Color? color]) =>
      CloseyTypography.eyebrow.copyWith(color: color ?? colors.textTertiary);
}

/// Amber is reserved for the coach; this keeps the ratio obvious in code.
const Color kCoachTint = CloseyPalette.amber500;
