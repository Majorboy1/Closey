import 'dart:ui';

/// Raw brand ramps.
///
/// Nothing in `features/` should import this file. Widgets read semantic
/// tokens from [CloseyColors] so that light and dark stay in lockstep; the
/// ramps only exist so the semantic layer has something to point at.
///
/// The identity is deliberately warm — paper, ink, clay rose, sage, amber —
/// rather than the cold purple-gradient look every "AI" app ships with.
abstract final class CloseyPalette {
  // ---------------------------------------------------------------- rose ---
  // Primary brand. Fully saturated, deliberately. The previous ramp was clay and
  // dust - chosen to avoid the category's purple gradient, but the result read as
  // washed out next to everything else on a phone. Contrast against white is
  // noted per step, because the brand colour has to work as a *fill* and as
  // *text*, and those are different requirements.
  static const Color rose50 = Color(0xFFFFE9F1);
  static const Color rose100 = Color(0xFFFFCEDE);
  static const Color rose200 = Color(0xFFFFA5C2);
  static const Color rose300 = Color(0xFFFF759F);
  static const Color rose400 = Color(0xFFFB4A7D);
  static const Color rose500 = Color(0xFFF01D63); // brand
  static const Color rose600 = Color(0xFFDE1556); // fill on light, 4.8:1
  static const Color rose700 = Color(0xFFBC0F47); // text on light, 5.9:1
  static const Color rose800 = Color(0xFF940B38);
  static const Color rose900 = Color(0xFF6B0728);

  // ---------------------------------------------------------------- sage ---
  // Success, friendship, "unlimited", positive affirmation. Emerald rather than
  // the previous sage, which sat too close to grey to register as positive.
  static const Color sage50 = Color(0xFFE3FBF4);
  static const Color sage100 = Color(0xFFBFF3E4);
  static const Color sage200 = Color(0xFF86E6CB);
  static const Color sage300 = Color(0xFF45D6B1);
  static const Color sage400 = Color(0xFF16C79A);
  static const Color sage500 = Color(0xFF00B489); // brand
  static const Color sage600 = Color(0xFF009975); // fill on light
  static const Color sage700 = Color(0xFF00815F); // text on light, 4.7:1
  static const Color sage800 = Color(0xFF00644A);

  // --------------------------------------------------------------- amber ---
  // Attention, verification highlights, gentle warnings. Now a real amber
  // rather than a tan.
  static const Color amber50 = Color(0xFFFFF4E0);
  static const Color amber100 = Color(0xFFFFE4B8);
  static const Color amber200 = Color(0xFFFFCE7A);
  static const Color amber300 = Color(0xFFFFB43D);
  static const Color amber400 = Color(0xFFFF9F0A);
  static const Color amber500 = Color(0xFFF08C00); // brand
  static const Color amber600 = Color(0xFFCE7700);
  static const Color amber700 = Color(0xFFA85F00); // text on light, 5.0:1
  static const Color amber800 = Color(0xFF7D4600);

  // ---------------------------------------------------------------- ink ---
  // Neutrals. `ink` doubles as the dark-mode background and the light-mode
  // primary text colour, which is what keeps the two themes feeling related.
  // Cooler than before, to sit under a saturated pink-violet palette.
  static const Color ink = Color(0xFF14121F);
  static const Color ink800 = Color(0xFF221F33); // text on light
  static const Color ink700 = Color(0xFF322E47);
  static const Color ink600 = Color(0xFF45415C);
  static const Color ink500 = Color(0xFF6B6780); // secondary text on light
  static const Color ink400 = Color(0xFF8A86A0);
  static const Color ink300 = Color(0xFFA8A4BC); // tertiary text on light
  static const Color ink200 = Color(0xFFDCD9E6);
  static const Color ink100 = Color(0xFFEFEDF5);

  // -------------------------------------------------------------- paper ---
  // A bright blush tint rather than beige. The old paper read as newsprint,
  // which is precisely what made the whole app feel muted.
  static const Color paper = Color(0xFFFFF4F7); // light background
  static const Color paperDeep = Color(0xFFFFE7EE); // sunken surface on light
  static const Color white = Color(0xFFFFFFFF);

  // --------------------------------------------------------- dark neutrals -
  // Used only by the dark theme. Violet-tinted so dark mode still reads as the
  // same product rather than a generic grey.
  static const Color night = Color(0xFF0E0A16); // dark background
  static const Color nightRaised = Color(0xFF171226); // dark surface
  static const Color nightHigh = Color(0xFF221A38); // dark surface, raised
  static const Color nightBorder = Color(0xFF332A4D);

  static const Color darkTextPrimary = Color(0xFFF6F3FB);
  static const Color darkTextSecondary = Color(0xFFB9B2CE);
  static const Color darkTextTertiary = Color(0xFF857E9C);
}
