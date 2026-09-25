import '../../core/config/app_config.dart';
import 'enums.dart';

/// The user's live AI coach allowance.
///
/// Firestore layout: `users/{uid}/private/account` → `suggestionQuota`.
/// Stored in a `private` subcollection so security rules can make it
/// **server-write-only**: the client can read how many credits it has left but
/// can never grant itself more. The Expo version enforced this in Postgres;
/// this is the Firestore equivalent and it is just as tamper-proof.
class SuggestionQuota {
  const SuggestionQuota({
    required this.usedToday,
    required this.dailyLimit,
    this.tier = VerificationTier.basic,
    this.smarterAi = false,
    this.isUnlimited = false,
  });

  final int usedToday;
  final int dailyLimit;
  final VerificationTier tier;

  /// Premium routes to a stronger model. The Expo DECISIONS log is explicit
  /// that Premium buys *smarter* suggestions, not merely more of them.
  final bool smarterAi;
  final bool isUnlimited;

  int get remaining =>
      isUnlimited ? 9999 : (dailyLimit - usedToday).clamp(0, dailyLimit);

  bool get isEmpty => !isUnlimited && remaining <= 0;

  double get fraction {
    if (isUnlimited || dailyLimit <= 0) return 1;
    return (usedToday / dailyLimit).clamp(0, 1);
  }

  /// Tier gate: the coach needs at least Verified.
  bool get tierAllowsCoach => tier.canUseCoach;

  static const SuggestionQuota unknown = SuggestionQuota(
    usedToday: 0,
    dailyLimit: QuotaConfig.freeAiSuggestionsPerDay,
  );

  /// Demo-mode default: pretend the user is Premium so the coach is fully
  /// explorable without a billing backend.
  static const SuggestionQuota demo = SuggestionQuota(
    usedToday: 0,
    dailyLimit: QuotaConfig.premiumAiSuggestionsPerDay,
    tier: VerificationTier.premium,
    smarterAi: true,
  );

  factory SuggestionQuota.fromMap(Map<String, dynamic> d) {
    final tier =
        VerificationTier.values.where((e) => e.name == d['tier']).firstOrNull ??
        VerificationTier.basic;
    return SuggestionQuota(
      usedToday: (d['usedToday'] as num?)?.toInt() ?? 0,
      dailyLimit:
          (d['dailyLimit'] as num?)?.toInt() ??
          QuotaConfig.freeAiSuggestionsPerDay,
      tier: tier,
      smarterAi: (d['smarterAi'] as bool?) ?? false,
      isUnlimited: (d['isUnlimited'] as bool?) ?? false,
    );
  }

  SuggestionQuota copyWith({
    int? usedToday,
    int? dailyLimit,
    VerificationTier? tier,
    bool? smarterAi,
    bool? isUnlimited,
  }) => SuggestionQuota(
    usedToday: usedToday ?? this.usedToday,
    dailyLimit: dailyLimit ?? this.dailyLimit,
    tier: tier ?? this.tier,
    smarterAi: smarterAi ?? this.smarterAi,
    isUnlimited: isUnlimited ?? this.isUnlimited,
  );
}

/// How many *new* direct conversations the user has started this month.
///
/// Free tier gets [QuotaConfig.freeDmConversationsPerMonth]; friends are
/// unlimited. Messages inside an existing thread never count.
class DmUsage {
  const DmUsage({required this.startedThisMonth, required this.monthlyLimit});

  final int startedThisMonth;

  /// `null` means unlimited (Premium).
  final int? monthlyLimit;

  bool get isUnlimited => monthlyLimit == null;

  int get remaining => isUnlimited
      ? 9999
      : (monthlyLimit! - startedThisMonth).clamp(0, monthlyLimit!);

  bool get isEmpty => !isUnlimited && remaining <= 0;

  static const DmUsage unknown = DmUsage(
    startedThisMonth: 0,
    monthlyLimit: QuotaConfig.freeDmConversationsPerMonth,
  );

  static const DmUsage demo = DmUsage(startedThisMonth: 1, monthlyLimit: null);

  factory DmUsage.fromMap(Map<String, dynamic> d) => DmUsage(
    startedThisMonth: (d['count'] as num?)?.toInt() ?? 0,
    monthlyLimit: d.containsKey('limit') ? (d['limit'] as num?)?.toInt() : null,
  );
}

/// The user's subscription record.
class Subscription {
  const Subscription({
    this.planKey = SubscriptionPlan.free,
    this.status = SubscriptionStatus.none,
    this.currentPeriodEnd,
    this.stripeCustomerId,
  });

  final SubscriptionPlan planKey;
  final SubscriptionStatus status;
  final DateTime? currentPeriodEnd;
  final String? stripeCustomerId;

  bool get isPremium =>
      planKey == SubscriptionPlan.premium &&
      status == SubscriptionStatus.active;

  static const Subscription free = Subscription();

  factory Subscription.fromMap(Map<String, dynamic> d) => Subscription(
    planKey:
        SubscriptionPlan.values
            .where((e) => e.key == d['planKey'])
            .firstOrNull ??
        SubscriptionPlan.free,
    status:
        SubscriptionStatus.values
            .where((e) => e.name == d['status'])
            .firstOrNull ??
        SubscriptionStatus.none,
    currentPeriodEnd: dateField(d, 'currentPeriodEnd'),
    stripeCustomerId: d['stripeCustomerId'] as String?,
  );
}

enum SubscriptionPlan {
  free('free', 'Free', 0, QuotaConfig.freeAiSuggestionsPerDay),
  topUp5('topup_5', '+5 suggestions', Pricing.topUpCents, null),
  premium(
    'premium',
    'Premium',
    Pricing.premiumMonthlyCents,
    QuotaConfig.premiumAiSuggestionsPerDay,
  );

  const SubscriptionPlan(
    this.key,
    this.label,
    this.priceCents,
    this.dailyLimit,
  );

  final String key;
  final String label;
  final int priceCents;
  final int? dailyLimit;

  String get priceLabel => this == SubscriptionPlan.premium
      ? '${Pricing.premiumLabel}/mo'
      : Pricing.topUpLabel;

  static SubscriptionPlan? fromKey(String? key) =>
      values.where((e) => e.key == key).firstOrNull;
}

enum SubscriptionStatus { none, active, canceled, pastDue }
