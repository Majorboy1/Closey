/// Global, compile-time configuration and product constants.
///
/// Everything that used to be scattered as magic numbers across the Expo app
/// lives here so it can be unit-tested and kept in sync with the Cloud
/// Functions in `functions/`.
library;

abstract final class AppConfig {
  static const String appName = 'Closey';
  static const String tagline = 'Never run out of things to say.';

  /// Shown in Settings and the About sheet.
  static const String version = '1.0.0';

  /// Public URL used by "Share profile".
  static const String shareBaseUrl = 'https://closey.app';

  /// Whether to build against live Firebase. When `false` (or when Firebase
  /// fails to initialise because `firebase_options.dart` is still the
  /// generated placeholder) every repository falls back to `data/mock`.
  ///
  /// This exists so `flutter run` works on a fresh clone with zero setup.
  static const bool preferLiveBackend = bool.fromEnvironment(
    'CLOSEY_LIVE',
    defaultValue: true,
  );

  /// Set to `true` by [FirebaseBootstrap] when live Firebase is unavailable.
  static bool useMockBackend = false;
}

/// Freemium rules. Mirrors `functions/src/config.ts` — change both together.
abstract final class QuotaConfig {
  /// Free tier: NEW direct-message conversations started per calendar month.
  /// Messages inside an existing thread are always unlimited.
  static const int freeDmConversationsPerMonth = 5;

  /// Free tier: AI coach generations per day, from ONE app-wide pool.
  static const int freeAiSuggestionsPerDay = 5;

  /// Premium: AI coach generations per day.
  static const int premiumAiSuggestionsPerDay = 20;

  /// A one-off top-up grants this many extra generations, valid for the day.
  static const int topUpGrant = 5;

  /// Minimum gap between two *unprompted* coach cards in the same chat.
  /// Guardrail from the spec: the coach should feel helpful, never nagging.
  static const Duration coachQuietPeriod = Duration(minutes: 20);

  /// How long a thread can sit silent before the coach may re-open it.
  static const Duration stallThreshold = Duration(hours: 6);
}

/// Prices in minor units (cents). Mirrors the Stripe price configuration.
abstract final class Pricing {
  static const int topUpCents = 199;
  static const int premiumMonthlyCents = 799;

  static String get topUpLabel => r'$1.99';
  static String get premiumLabel => r'$7.99';
}

/// Verification tiers. Order matters — `index` is used for comparison.
enum VerificationTier {
  basic,
  verified,
  premium;

  /// The AI coach requires at least this tier.
  static const VerificationTier aiMinimum = VerificationTier.verified;

  bool get canUseCoach => index >= aiMinimum.index;
  bool get isPremium => this == VerificationTier.premium;

  String get label => switch (this) {
    VerificationTier.basic => 'Basic',
    VerificationTier.verified => 'Verified',
    VerificationTier.premium => 'Premium',
  };
}

/// Fields the user can filter discovery by.
abstract final class DiscoveryDefaults {
  static const int minAge = 18;
  static const int maxAge = 99;
  static const int defaultMinAge = 18;
  static const int defaultMaxAge = 35;
  static const int defaultRadiusKm = 50;
  static const int maxRadiusKm = 200;
}
