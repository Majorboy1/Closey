import 'package:flutter/widgets.dart';

/// A strict 4pt spacing scale. Nothing in the app should use a raw number.
///
/// The Expo version mixed `spacing.md` tokens with hardcoded 14/16/18/20/22/24
/// padding values in the same file, which is why screens never quite lined up.
abstract final class Gap {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double giant = 56;

  /// Standard horizontal page padding. One value, everywhere.
  static const double page = 20;

  /// Bottom padding so content clears the tab bar / home indicator.
  static const double scrollBottomInset = 96;

  static const EdgeInsets pageInsets = EdgeInsets.symmetric(horizontal: page);
  static const EdgeInsets sheetInsets = EdgeInsets.fromLTRB(xxl, sm, xxl, xxl);
  static const EdgeInsets cardInsets = EdgeInsets.all(lg);

  /// Vertical rhythm between major blocks of a screen.
  static const SizedBox block = SizedBox(height: xxl);
  static const SizedBox gap4 = SizedBox(height: xs);
  static const SizedBox gap8 = SizedBox(height: sm);
  static const SizedBox gap12 = SizedBox(height: md);
  static const SizedBox gap16 = SizedBox(height: lg);
  static const SizedBox gap20 = SizedBox(height: xl);
  static const SizedBox gap24 = SizedBox(height: xxl);
}

/// Corner radii.
///
/// Generous and round. A tight, near-square radius was the right call for the
/// print-like direction and the wrong one for this product: rounded shapes read
/// as friendly, and a dating app is asking people to be vulnerable. Cards 22,
/// sheets 32, pills fully round.
abstract final class Radii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 30;
  static const double sheet = 32;
  static const double full = 999;

  static const BorderRadius allSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius allSheet = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));

  /// Chat bubbles: rounded everywhere but the "tail" corner.
  static const BorderRadius bubbleMine = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
    bottomLeft: Radius.circular(lg),
    bottomRight: Radius.circular(xs),
  );
  static const BorderRadius bubbleTheirs = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
    bottomLeft: Radius.circular(xs),
    bottomRight: Radius.circular(lg),
  );
}

/// Hairline widths.
abstract final class Strokes {
  static const double hairline = 1;
  static const double thin = 1.5;
  static const double thick = 2;
  static const double ring = 3;
}

/// Minimum interactive size. 48dp is the Material and WCAG target; the Expo app
/// shipped several 32–38dp tap areas (composer `add` button, tab bar icons,
/// settings chevrons) which are genuinely hard to hit.
abstract final class TapTarget {
  static const double min = 48;
  static const double comfortable = 52;
}
