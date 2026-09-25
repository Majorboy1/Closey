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
  // Primary brand. The ramp exists because the brand colour is legible as a
  // *fill* but not as *text* on a light background — a distinction the old
  // single-value palette could not express.
  static const Color rose50 = Color(0xFFFDF2F4);
  static const Color rose100 = Color(0xFFFBE0E5);
  static const Color rose200 = Color(0xFFF6C2CC);
  static const Color rose300 = Color(0xFFEE9DAE);
  static const Color rose400 = Color(0xFFDE7288);
  static const Color rose500 = Color(0xFFC4576B); // brand
  static const Color rose600 = Color(0xFFB94A5E); // fill on light
  static const Color rose700 = Color(0xFFA23A4E); // text on light, 6.5:1
  static const Color rose800 = Color(0xFF832E3E);
  static const Color rose900 = Color(0xFF5C202B);

  // ---------------------------------------------------------------- sage ---
  // Success, friendship, "unlimited", positive affirmation.
  static const Color sage50 = Color(0xFFF1F6F1);
  static const Color sage100 = Color(0xFFDCE9DD);
  static const Color sage200 = Color(0xFFBDD3BF);
  static const Color sage300 = Color(0xFFA9C4AC);
  static const Color sage400 = Color(0xFF83A487);
  static const Color sage500 = Color(0xFF5F8062); // brand
  static const Color sage600 = Color(0xFF4E6B51); // fill on light, 5.9:1
  static const Color sage700 = Color(0xFF3D5540);
  static const Color sage800 = Color(0xFF2C3E2E);

  // --------------------------------------------------------------- amber ---
  // Attention, streaks, verification highlights, gentle warnings.
  static const Color amber50 = Color(0xFFFDF8EE);
  static const Color amber100 = Color(0xFFF9EDD3);
  static const Color amber200 = Color(0xFFF3D9A8);
  static const Color amber300 = Color(0xFFE8B463);
  static const Color amber400 = Color(0xFFDFA64E);
  static const Color amber500 = Color(0xFFD89A3E); // brand
  static const Color amber600 = Color(0xFFB97B22);
  static const Color amber700 = Color(0xFF8A5D14); // text on light, 5.6:1
  static const Color amber800 = Color(0xFF67430E);

  // ---------------------------------------------------------------- ink ---
  // Neutrals. `ink` doubles as the dark-mode background and the light-mode
  // primary text colour, which is what keeps the two themes feeling related.
  static const Color ink = Color(0xFF201F2E);
  static const Color ink800 = Color(0xFF2B2A35); // text on light
  static const Color ink700 = Color(0xFF3A3850);
  static const Color ink600 = Color(0xFF4A4960);
  static const Color ink500 = Color(0xFF716F82); // secondary text on light
  static const Color ink400 = Color(0xFF8C8AA0);
  static const Color ink300 = Color(0xFFA9A3B3); // tertiary text on light
  static const Color ink200 = Color(0xFFD8D2DC);
  static const Color ink100 = Color(0xFFE9E1D4); // hairline on light

  // -------------------------------------------------------------- paper ---
  static const Color paper = Color(0xFFFAF6F1); // light background
  static const Color paperDeep = Color(0xFFF1E9DF); // sunken surface on light
  static const Color white = Color(0xFFFFFFFF);

  // --------------------------------------------------------- dark neutrals -
  // Used only by the dark theme. Slightly warm-tinted so dark mode still
  // reads as the same product rather than a generic grey.
  static const Color night = Color(0xFF17161F); // dark background
  static const Color nightRaised = Color(0xFF201F2E); // dark surface
  static const Color nightHigh = Color(0xFF2A2839); // dark surface, raised
  static const Color nightBorder = Color(0xFF35334A);

  static const Color darkTextPrimary = Color(0xFFF6F1EA);
  static const Color darkTextSecondary = Color(0xFFB3AEC2);
  static const Color darkTextTertiary = Color(0xFF837E94);
}
