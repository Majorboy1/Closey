import 'package:flutter/widgets.dart';

/// Motion tokens.
///
/// The Expo app had 1400ms, 4000ms, 800ms, 220ms, 350ms and 900ms literals
/// scattered across seven components with no shared vocabulary. Here there are
/// four durations and three curves, and every animation in the app picks one.
abstract final class Motion {
  /// Micro-feedback: press states, checkbox ticks, chip selection.
  static const Duration instant = Duration(milliseconds: 120);

  /// The default for almost everything: expanding cards, colour changes,
  /// sheet contents, tab indicators.
  static const Duration quick = Duration(milliseconds: 220);

  /// Entrances: page transitions, coach cards arriving, list items appearing.
  static const Duration moderate = Duration(milliseconds: 380);

  /// Celebrations and hero moments only — the match animation, onboarding
  /// completion. Used sparingly so it stays special.
  static const Duration slow = Duration(milliseconds: 620);

  /// The rhythmic loop used by the "coach is thinking" shimmer.
  static const Duration loop = Duration(milliseconds: 1400);

  /// Total budget for the match celebration sequence.
  static const Duration celebration = Duration(milliseconds: 2400);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;

  /// Slight overshoot — reserved for the match heart and success checkmarks.
  static const Curve overshoot = Curves.easeOutBack;

  /// Exits are faster and linear-ish so dismissals feel responsive.
  static const Curve exit = Curves.easeInCubic;

  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 220,
    damping: 22,
  );

  /// A springy "pop" for the match card.
  static const SpringDescription bouncySpring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 14,
  );

  static const Duration stagger = Duration(milliseconds: 55);
}

/// Respect the platform's reduce-motion setting.
///
/// The Expo build animated floating hearts, a pulsing logo and a bouncing
/// match heart unconditionally. Here every animation is gated on this, which
/// is both an accessibility requirement and a battery win.
extension CloseyMotionContext on BuildContext {
  bool get reduceMotion {
    final view = View.maybeOf(this);
    if (view == null) return false;
    return MediaQuery.maybeDisableAnimationsOf(this) ?? false;
  }

  /// Returns `Duration.zero` when the user has asked for reduced motion, so
  /// call sites stay readable: `duration: context.motion(Motion.quick)`.
  Duration motion(Duration duration) => reduceMotion ? Duration.zero : duration;

  Curve motionCurve(Curve curve) => reduceMotion ? Curves.linear : curve;
}
