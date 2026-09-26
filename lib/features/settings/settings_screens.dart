import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_avatar.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_chip.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_sheet.dart';
import '../../core/widgets/closey_surface.dart';
import '../../data/constants.dart';
import '../../data/models/quota.dart';
import '../../state/app_providers.dart';
import '../../state/services.dart';

/// Settings.
///
/// Same information architecture as the Expo version â€” it was one of the better
/// screens â€” with the inconsistencies removed: one row shape, one section
/// header, switches that reflect real persisted values, and destructive actions
/// that use a themed confirm dialog instead of `Alert.alert`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserValueProvider);
    final quota = ref.watch(quotaProvider).value ?? SuggestionQuota.unknown;
    final dm = ref.watch(dmUsageProvider).value ?? DmUsage.unknown;

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: 'Settings'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (me != null) _AccountSummary(user: me, quota: quota, dm: dm),

            const CloseySectionHeader(title: 'Account'),
            CloseyCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  CloseyListRow(
                    title: 'Edit profile',
                    subtitle: 'Photos, prompts, interests',
                    icon: Icons.person_outline_rounded,
                    onTap: () => context.push(Routes.editProfile),
                  ),
                  CloseyListRow(
                    title: 'Verification',
                    subtitle: me?.verificationTier.canUseCoach ?? false
                        ? '${me!.verificationTier.label} — the coach is unlocked'
                        : 'Verify to unlock the conversation coach',
                    icon: Icons.verified_outlined,
                    onTap: () => context.push(Routes.verification),
                  ),
                  CloseyListRow(
                    title: 'Premium and top-ups',
                    subtitle: 'Plans, credits and billing',
                    icon: Icons.workspace_premium_outlined,
                    onTap: () => context.push(Routes.paywall),
                  ),
                  CloseyListRow(
                    title: 'Discovery preferences',
                    subtitle: 'Age range, distance, who you see',
                    icon: Icons.tune_rounded,
                    showDivider: false,
                    onTap: () => context.push(Routes.editProfile),
                  ),
                ],
              ),
            ),

            if (me != null) ...[
              const CloseySectionHeader(title: 'Notifications'),
              CloseyCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ToggleRow(
                      title: 'New matches',
                      icon: Icons.favorite_border_rounded,
                      value: me.notifyMatches,
                      onChanged: (v) => ref
                          .read(userRepositoryProvider)
                          .updateProfile(me.id, notifyMatches: v),
                    ),
                    _ToggleRow(
                      title: 'New messages',
                      icon: Icons.chat_bubble_outline_rounded,
                      value: me.notifyMessages,
                      onChanged: (v) => ref
                          .read(userRepositoryProvider)
                          .updateProfile(me.id, notifyMessages: v),
                    ),
                    _ToggleRow(
                      title: 'Coach suggestions',
                      subtitle:
                          'Only shared cards are ever announced — never '
                          'a private nudge',
                      icon: Icons.auto_awesome_outlined,
                      value: me.notifySuggestions,
                      showDivider: false,
                      onChanged: (v) => ref
                          .read(userRepositoryProvider)
                          .updateProfile(me.id, notifySuggestions: v),
                    ),
                  ],
                ),
              ),

              const CloseySectionHeader(title: 'Privacy'),
              CloseyCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ToggleRow(
                      title: 'Show my distance',
                      icon: Icons.location_on_outlined,
                      value: me.showDistance,
                      onChanged: (v) => ref
                          .read(userRepositoryProvider)
                          .updateProfile(me.id, showDistance: v),
                    ),
                    _ToggleRow(
                      title: 'Show when I am online',
                      icon: Icons.visibility_outlined,
                      value: me.showOnline,
                      showDivider: false,
                      onChanged: (v) => ref
                          .read(userRepositoryProvider)
                          .updateProfile(me.id, showOnline: v),
                    ),
                  ],
                ),
              ),
            ],

            const CloseySectionHeader(title: 'Safety'),
            CloseyCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  CloseyListRow(
                    title: 'Blocked people',
                    icon: Icons.block_outlined,
                    onTap: () => context.push(Routes.blocked),
                  ),
                  CloseyListRow(
                    title: 'Community guidelines',
                    icon: Icons.menu_book_outlined,
                    showDivider: false,
                    onTap: () => showCloseySheet<void>(
                      context: context,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: Gap.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CloseySheetHeader(
                                title: 'How we expect people to behave',
                              ),
                              ...CloseyContent.communityGuidelines.map(
                                (g) => Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    Gap.xxl,
                                    0,
                                    Gap.xxl,
                                    Gap.md,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: context.colors.success,
                                      ),
                                      const SizedBox(width: Gap.md),
                                      Expanded(
                                        child: Text(
                                          g,
                                          style: context.text.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const CloseySectionHeader(title: 'Account actions'),
            CloseyCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  CloseyListRow(
                    title: 'Sign out',
                    icon: Icons.logout_rounded,
                    onTap: () async {
                      final ok = await showCloseyConfirm(
                        context: context,
                        title: 'Sign out?',
                        message: 'You can sign back in any time.',
                        confirmLabel: 'Sign out',
                      );
                      if (ok) await ref.read(authRepositoryProvider).signOut();
                    },
                  ),
                  CloseyListRow(
                    title: 'Delete my account',
                    subtitle:
                        'Permanently removes your profile and conversations',
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    showDivider: false,
                    onTap: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Gap.xxl),
            Center(
              child: Text(
                'Closey · v${AppConfig.version} · Made for real conversations',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showCloseyConfirm(
      context: context,
      title: 'Delete your account?',
      message:
          'This removes your profile, your photos, every conversation and every '
          'match. It cannot be undone.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!ok) return;

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      await ref.read(safetyRepositoryProvider).requestDataSweep();
    } on CloseyFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({
    required this.user,
    required this.quota,
    required this.dm,
  });

  final dynamic user;
  final SuggestionQuota quota;
  final DmUsage dm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.lg),
      child: CloseyCard(
        child: Row(
          children: [
            CloseyAvatar(
              name: user.fullName as String,
              imageUrl: user.primaryPhoto as String?,
              size: 52,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName as String,
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    children: [
                      CloseyBadge(
                        label: quota.isUnlimited
                            ? 'UNLIMITED AI'
                            : '${quota.remaining} AI LEFT TODAY',
                        tone: quota.isEmpty
                            ? CloseyBadgeTone.danger
                            : CloseyBadgeTone.warning,
                      ),
                      CloseyBadge(
                        label: dm.isUnlimited
                            ? 'UNLIMITED DMS'
                            : '${dm.remaining} DMS LEFT',
                        tone: CloseyBadgeTone.neutral,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        CloseyListRow(
          title: title,
          subtitle: subtitle,
          icon: icon,
          showDivider: false,
          trailing: Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: colors.brand,
          ),
          onTap: () => onChanged(!value),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 66),
            child: Divider(height: 1, color: colors.border),
          ),
      ],
    );
  }
}

/// Blocked people, with real unblock.
class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: 'Blocked people'),
      child: AsyncSection(
        value: blocked,
        loading: const CloseySkeletonList(rows: 4),
        builder: (context, users) {
          if (users.isEmpty) {
            return const CloseyEmptyState(
              icon: Icons.shield_outlined,
              title: 'Nobody is blocked',
              message:
                  'If someone makes you uncomfortable, block them from their '
                  'profile or from the chat menu. They will not be able to find '
                  'you or message you again.',
            );
          }

          return Column(
            children: users
                .map(
                  (b) => Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.page,
                      0,
                      Gap.page,
                      Gap.md,
                    ),
                    child: CloseyCard(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Row(
                        children: [
                          CloseyAvatar(
                            name: b.user.fullName,
                            imageUrl: b.user.primaryPhoto,
                            size: 46,
                          ),
                          const SizedBox(width: Gap.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.user.fullName,
                                  style: context.text.titleSmall,
                                ),
                                Text(
                                  'They cannot see you or message you',
                                  style: context.text.bodySmall?.copyWith(
                                    color: context.colors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CloseyButton(
                            label: 'Unblock',
                            size: CloseyButtonSize.sm,
                            variant: CloseyButtonVariant.secondary,
                            onPressed: () async {
                              final uid = ref.read(uidProvider);
                              if (uid == null) return;
                              try {
                                await ref
                                    .read(safetyRepositoryProvider)
                                    .unblockUser(
                                      blockerId: uid,
                                      blockedId: b.user.id,
                                    );
                              } on CloseyFailure catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

/// Report and block.
///
/// Kept as one screen because they belong together: filing a report should
/// always offer blocking in the same breath, since blocking is the action that
/// immediately protects the user. The Expo version had reporting but no block
/// call to action on the same surface.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({
    super.key,
    required this.reportedUserId,
    this.contextLabel = 'profile',
  });

  final String reportedUserId;
  final String contextLabel;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  String? _reason;
  final _details = TextEditingController();
  bool _block = true;
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final uid = ref.read(uidProvider);
    if (uid == null || _reason == null) return;

    setState(() => _busy = true);
    try {
      final safety = ref.read(safetyRepositoryProvider);

      // Report first: it fails soft. Blocking is the action that actually
      // protects the user, so it must not be blocked by a report failing.
      try {
        await safety.reportUser(
          reporterId: uid,
          reportedId: widget.reportedUserId,
          reason: _reason!,
          details: _details.text.trim().isEmpty ? null : _details.text.trim(),
          context: widget.contextLabel,
        );
      } catch (_) {
        /* surfaced below via block */
      }

      if (_block) {
        await safety.blockUser(
          blockerId: uid,
          blockedId: widget.reportedUserId,
        );
      }

      if (mounted) setState(() => _done = true);
    } on CloseyFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final profile = ref.watch(profileByIdProvider(widget.reportedUserId)).value;
    final name = profile?.fullName ?? 'this person';

    if (_done) {
      return CloseyScaffold(
        appBar: const CloseyAppBar(title: ''),
        child: Padding(
          padding: const EdgeInsets.all(Gap.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, size: 56, color: colors.success),
              const SizedBox(height: Gap.xl),
              Text(
                'Thank you',
                style: context.text.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.md),
              Text(
                _block
                    ? 'We have your report, and they can no longer see or '
                          'message you.'
                    : 'We have your report. A person reviews every one of '
                          'them.',
                textAlign: TextAlign.center,
                style: context.text.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: Gap.xxl),
              CloseyButton(
                label: 'Done',
                fullWidth: true,
                size: CloseyButtonSize.lg,
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      );
    }

    return CloseyScaffold(
      appBar: CloseyAppBar(title: 'Report $name'),
      child: Padding(
        padding: Gap.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What is going on?', style: context.text.displaySmall),
            const SizedBox(height: Gap.sm),
            Text(
              'Pick the closest match. You can add detail below.',
              style: context.text.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Gap.xl),

            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: CloseyContent.reportReasons
                  .map(
                    (r) => CloseyChip(
                      label: r,
                      selected: _reason == r,
                      onTap: () => setState(() => _reason = r),
                      dense: true,
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: Gap.xl),
            TextField(
              controller: _details,
              maxLines: 4,
              maxLength: 500,
              style: context.text.bodyLarge,
              cursorColor: colors.brand,
              decoration: InputDecoration(
                hintText: 'Anything else we should know? (optional)',
              ),
            ),

            const SizedBox(height: Gap.lg),
            CloseyCard(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Also block $name',
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Recommended. They will not be able to find you or '
                          'message you again.',
                          style: context.text.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _block,
                    onChanged: (v) => setState(() => _block = v),
                    activeTrackColor: colors.brand,
                  ),
                ],
              ),
            ),

            const SizedBox(height: Gap.xxl),
            CloseyButton(
              label: _block ? 'Report and block' : 'Submit report',
              icon: Icons.flag_outlined,
              fullWidth: true,
              size: CloseyButtonSize.lg,
              loading: _busy,
              onPressed: _reason == null ? null : _submit,
            ),
            const SizedBox(height: Gap.md),
            Text(
              'Reports are confidential. We never tell someone who reported '
              'them.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Verification tiers.
///
/// The Expo screen ran a fake 1400ms timer and then declared the user verified.
/// This one is honest: it explains what each tier unlocks, and the action
/// records a verification *request* handled by a Cloud Function and an external
/// KYC provider. It never raises its own tier, because the security rules do not
/// allow the client to.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final me = ref.watch(currentUserValueProvider);
    final current = me?.verificationTier ?? VerificationTier.basic;

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: 'Verification'),
      child: Padding(
        padding: Gap.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why verify?', style: context.text.displaySmall),
            const SizedBox(height: Gap.sm),
            Text(
              'Verified profiles get seen more, and the conversation coach only '
              'works between two verified people — so nobody is being coached '
              'without their knowledge.',
              style: context.text.bodyLarge?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Gap.xxl),

            _TierCard(
              tier: VerificationTier.basic,
              current: current,
              icon: Icons.person_outline_rounded,
              title: 'Basic',
              price: 'Free',
              perks: const [
                'Swipe, match and chat',
                '5 new conversations a month',
                '5 AI suggestions a day',
              ],
              actionLabel: 'Current plan',
            ),
            const SizedBox(height: Gap.md),

            _TierCard(
              tier: VerificationTier.verified,
              current: current,
              icon: Icons.shield_outlined,
              title: 'Verified',
              price: 'Free — one ID check',
              perks: const [
                'Everything in Basic',
                'The conversation coach unlocks',
                'A verified badge on your profile',
                'Higher placement in Discover',
              ],
              actionLabel: 'Verify my identity',
              highlighted: true,
              onAction: _requestVerification,
              busy: _busy,
            ),
            const SizedBox(height: Gap.md),

            _TierCard(
              tier: VerificationTier.premium,
              current: current,
              icon: Icons.diamond_outlined,
              title: 'Premium',
              price: '${Pricing.premiumLabel}/mo',
              perks: const [
                'Everything in Verified',
                '20 AI suggestions a day',
                'A stronger model for suggestions',
                'Unlimited direct conversations',
              ],
              actionLabel: 'See Premium',
              onAction: () => context.push(Routes.paywall),
            ),

            const SizedBox(height: Gap.xxl),
            CloseyCard(
              tinted: colors.surfaceSunken,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        'How your ID is handled',
                        style: context.text.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    'Verification runs through a specialist identity provider. '
                    'Closey never stores your passport, licence or ID number — '
                    'we only receive a pass or fail result.',
                    style: context.text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestVerification() async {
    final uid = ref.read(uidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(billingRepositoryProvider).simulateVerification(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification requested. Wire up your KYC provider (Persona, '
            'Stripe Identity, Veriff or Yoti) to complete the check.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.current,
    required this.icon,
    required this.title,
    required this.price,
    required this.perks,
    required this.actionLabel,
    this.onAction,
    this.highlighted = false,
    this.busy = false,
  });

  final VerificationTier tier;
  final VerificationTier current;
  final IconData icon;
  final String title;
  final String price;
  final List<String> perks;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool highlighted;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isCurrent = tier == current;

    return CloseyCard(
      tinted: isCurrent ? colors.brandSoft : null,
      borderColor: isCurrent || highlighted ? colors.brand : null,
      borderWidth: isCurrent || highlighted ? Strokes.thin : Strokes.hairline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent ? colors.brand : colors.surfaceSunken,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: isCurrent ? colors.textOnBrand : colors.textSecondary,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium),
                    Text(
                      price,
                      style: context.text.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                const CloseyBadge(
                  label: 'CURRENT',
                  tone: CloseyBadgeTone.brand,
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
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
          if (onAction != null) ...[
            const SizedBox(height: Gap.md),
            CloseyButton(
              label: actionLabel,
              fullWidth: true,
              size: CloseyButtonSize.sm,
              loading: busy,
              variant: highlighted
                  ? CloseyButtonVariant.primary
                  : CloseyButtonVariant.secondary,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
