import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_surface.dart';
import '../../data/models/quota.dart';
import '../../state/app_providers.dart';
import '../../state/services.dart';

/// Paywall and credits.
///
/// Ported from the Expo `PaywallOptions` + `QuotaPill`, with the same two-path
/// model the DECISIONS log argues for: a one-off **top-up** and a
/// **subscription**, side by side. A subscription-only paywall loses the heavy
/// occasional user, and the "+5 for $1.99" escape hatch is what stops somebody
/// who has hit the daily cap from simply closing the app.
///
/// The state-driven CTA is preserved because it was a genuinely good idea: at
/// zero credits the secondary button in the coach card becomes "Buy more" with a
/// plus icon and the sage colour, so the *change of state* is what signals the
/// action, not a new piece of copy the user has to notice.
///
/// What is new:
/// * **The reason is stated.** The screen explains which limit you hit and what
///   it costs, instead of showing one generic pitch for both cases.
/// * **Real error handling.** The old screen showed an Alert explaining that the
///   Stripe functions were not deployed; this one routes to a clear message and
///   keeps the button retryable.
/// * **Prices are read from config** so they can change without a release.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.reason});

  /// `quota` (ran out of AI credits), `dm` (monthly DM limit), or null.
  final String? reason;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _busyTopUp = false;
  bool _busyPremium = false;
  String? _error;
  Map<String, String> _prices = const {
    'topup': r'$1.99',
    'premium': r'$7.99/mo',
  };

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    final prices = await ref.read(billingRepositoryProvider).loadPricing();
    if (mounted) setState(() => _prices = prices);
  }

  Future<void> _checkout(SubscriptionPlan plan) async {
    setState(() {
      _busyTopUp = plan == SubscriptionPlan.topUp5;
      _busyPremium = plan == SubscriptionPlan.premium;
      _error = null;
    });

    try {
      final url = await ref
          .read(billingRepositoryProvider)
          .createCheckoutSession(plan);
      final uri = Uri.parse(url);
      if (!await canLaunchUrl(uri)) {
        throw Exception('Could not open the checkout page.');
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on CloseyFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not start checkout. $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyTopUp = false;
          _busyPremium = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quota = ref.watch(quotaProvider).value ?? SuggestionQuota.unknown;
    final dm = ref.watch(dmUsageProvider).value ?? DmUsage.unknown;
    final isPremium = ref.watch(subscriptionProvider).value?.isPremium ?? false;

    final (headline, subhead) = switch (widget.reason) {
      'quota' => (
        'You are out of suggestions for today',
        'Your daily pool resets at midnight. Top up to keep going now, or go '
            'Premium for 20 a day.',
      ),
      'dm' => (
        'You have used your 5 free conversations',
        'Adding someone as a friend is free and unlimited. Premium removes the '
            'limit entirely.',
      ),
      _ => (
        'Keep the conversation going',
        'The coach reads your thread and keeps it moving. Both of you see the '
            'shared suggestions; private nudges stay private.',
      ),
    };

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: 'Credits and Premium'),
      child: Padding(
        padding: Gap.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------------------------------------------------- live usage
            CloseyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your limits today',
                          style: context.text.titleSmall,
                        ),
                      ),
                      if (isPremium)
                        const CloseyBadge(
                          label: 'PREMIUM',
                          tone: CloseyBadgeTone.warning,
                          icon: Icons.workspace_premium_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.lg),
                  _UsageBar(
                    label: 'AI suggestions',
                    used: quota.usedToday,
                    limit: quota.dailyLimit,
                    unlimited: quota.isUnlimited,
                  ),
                  const SizedBox(height: Gap.md),
                  _UsageBar(
                    label: 'New conversations this month',
                    used: dm.startedThisMonth,
                    limit: dm.monthlyLimit ?? dm.startedThisMonth,
                    unlimited: dm.isUnlimited,
                  ),
                ],
              ),
            ),

            const SizedBox(height: Gap.xxl),
            Text(headline, style: context.text.displaySmall),
            const SizedBox(height: Gap.md),
            Text(
              subhead,
              style: context.text.bodyLarge?.copyWith(
                color: colors.textSecondary,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: Gap.xl),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.lg),
                decoration: BoxDecoration(
                  color: colors.dangerSoft,
                  borderRadius: Radii.allMd,
                  border: Border.all(color: colors.brandBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: colors.danger,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Text(
                        _error!,
                        style: context.text.bodySmall?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: Gap.xxl),

            // -------------------------------------------------------- top-up
            _PlanCard(
              title: '+5 suggestions',
              price: _prices['topup'] ?? Pricing.topUpLabel,
              blurb: 'One-off. Valid for today only.',
              perks: const [
                'Use them immediately',
                'No subscription, no renewal',
                'Stacks on top of your daily allowance',
              ],
              actionLabel: 'Buy top-up',
              busy: _busyTopUp,
              onAction: () => _checkout(SubscriptionPlan.topUp5),
            ),

            const SizedBox(height: Gap.lg),

            // ------------------------------------------------------- premium
            _PlanCard(
              title: 'Premium',
              price: _prices['premium'] ?? '${Pricing.premiumLabel}/mo',
              blurb: '20 suggestions a day, a stronger model, unlimited DMs.',
              highlighted: true,
              perks: const [
                '20 AI suggestions every day',
                'A smarter model â€” better, more specific suggestions',
                'Unlimited direct conversations',
                'Cancel any time',
              ],
              actionLabel: isPremium ? 'You are on Premium' : 'Go Premium',
              busy: _busyPremium,
              onAction: isPremium
                  ? null
                  : () => _checkout(SubscriptionPlan.premium),
            ),

            const SizedBox(height: Gap.xxl),

            // --------------------------------------------------- the promise
            CloseyCard(
              tinted: colors.coachSurface,
              borderColor: colors.coachBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.visibility_off_outlined,
                        size: 16,
                        color: colors.accentText,
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        'What paying does not change',
                        style: context.text.titleSmall?.copyWith(
                          color: colors.accentText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    'Everyone gets the same coach for free, and private nudges '
                    'stay private on every plan. Premium buys more suggestions '
                    'and a better model â€” it never buys a better chance with a '
                    'specific person, and it never lets anyone see your nudges.',
                    style: context.text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Gap.xl),
            Center(
              child: Text(
                'Payments are handled by Stripe. Cancel any time in Settings.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: colors.textTertiary,
                ),
              ),
            ),

            const SizedBox(height: Gap.giant),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.blurb,
    required this.perks,
    required this.actionLabel,
    required this.busy,
    required this.onAction,
    this.highlighted = false,
  });

  final String title;
  final String price;
  final String blurb;
  final List<String> perks;
  final String actionLabel;
  final bool busy;
  final VoidCallback? onAction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CloseyCard(
      tinted: highlighted ? colors.brandSoft : null,
      borderColor: highlighted ? colors.brand : null,
      borderWidth: highlighted ? Strokes.thin : Strokes.hairline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      blurb,
                      style: context.text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              Text(
                price,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: highlighted ? colors.brandText : colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          ...perks.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 14, color: colors.success),
                  const SizedBox(width: Gap.sm),
                  Expanded(child: Text(p, style: context.text.bodySmall)),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
          CloseyButton(
            label: actionLabel,
            fullWidth: true,
            size: CloseyButtonSize.md,
            loading: busy,
            variant: highlighted
                ? CloseyButtonVariant.primary
                : CloseyButtonVariant.secondary,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// Usage bar. Mirrors the quota readout in Settings so the numbers always agree.
class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.used,
    required this.limit,
    required this.unlimited,
  });

  final String label;
  final int used;
  final int limit;
  final bool unlimited;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fraction = unlimited || limit <= 0
        ? 1.0
        : (used / limit).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: context.text.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Text(
              unlimited ? 'Unlimited' : '$used of $limit used',
              style: context.text.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: unlimited
                    ? colors.successText
                    : (used >= limit ? colors.danger : colors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: Radii.pill,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: colors.surfaceSunken,
              valueColor: AlwaysStoppedAnimation(
                unlimited
                    ? colors.success
                    : (used >= limit ? colors.danger : colors.brand),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
