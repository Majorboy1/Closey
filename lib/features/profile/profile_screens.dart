import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/theme/closey_typography.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_avatar.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_chip.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_sheet.dart';
import '../../core/widgets/closey_surface.dart';
import '../../core/widgets/photo_carousel.dart';
import '../../data/models/app_user.dart';
import '../../state/app_providers.dart';
import '../../state/services.dart';
import '../onboarding/onboarding_screen.dart';

/// My profile.
///
/// The Expo version displayed eight hardcoded numbers ("Posts 128",
/// "Connections 1.2K") and a random `picsum.photos` cover image. Everything
/// here is real: counts come from the profile document, the cover is the user's
/// own photo, and the tabs render actual content or an honest empty state.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final me = ref.watch(currentUserValueProvider);

    if (me == null) {
      return const CloseyScaffold(
        child: Padding(
          padding: EdgeInsets.all(Gap.xxxl),
          child: CloseySkeletonList(rows: 4),
        ),
      );
    }

    final posts = ref.watch(userPostsProvider(me.id));

    return CloseyScaffold(
      scrollable: false,
      appBar: CloseyAppBar(
        title: 'You',
        showBack: false,
        actions: [
          CloseyIconButton(
            icon: Icons.workspace_premium_outlined,
            semanticLabel: 'Plans and premium',
            onPressed: () => context.push(Routes.paywall),
          ),
          CloseyIconButton(
            icon: Icons.settings_outlined,
            semanticLabel: 'Settings',
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      child: RefreshIndicator(
        color: colors.brand,
        backgroundColor: colors.surface,
        onRefresh: () async =>
            Future<void>.delayed(const Duration(milliseconds: 400)),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _ProfileHeader(user: me),
            const SizedBox(height: Gap.lg),

            Padding(
              padding: Gap.pageInsets,
              child: Row(
                children: [
                  Expanded(
                    child: CloseyButton(
                      label: 'Edit profile',
                      fullWidth: true,
                      variant: CloseyButtonVariant.secondary,
                      icon: Icons.edit_outlined,
                      onPressed: () => context.push(Routes.editProfile),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: CloseyButton(
                      label: 'Plans',
                      fullWidth: true,
                      variant: CloseyButtonVariant.tonal,
                      icon: Icons.calendar_month_outlined,
                      onPressed: () => context.push(Routes.plans),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Gap.xl),
            _ProfileCompletion(user: me),

            if (me.conversationTopics.isNotEmpty) ...[
              const CloseySectionHeader(title: 'You love talking about'),
              Padding(
                padding: Gap.pageInsets,
                child: Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: me.conversationTopics
                      .map(
                        (t) => CloseyTag(
                          label: t,
                          tone: CloseyTagTone.accent,
                          icon: Icons.auto_awesome_rounded,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],

            if (me.interests.isNotEmpty) ...[
              const CloseySectionHeader(title: 'Interests'),
              Padding(
                padding: Gap.pageInsets,
                child: Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: me.interests
                      .map((i) => CloseyTag(label: i))
                      .toList(),
                ),
              ),
            ],

            const CloseySectionHeader(title: 'Your posts'),
            posts.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: Gap.page),
                child: CloseySkeletonList(rows: 2, showAvatar: false),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: Gap.pageInsets,
                      child: CloseyEmptyState(
                        compact: true,
                        icon: Icons.article_outlined,
                        title: 'No posts yet',
                        message:
                            'Your posts live here. Share something and it '
                            'appears on Home too.',
                        actionLabel: 'Create a post',
                        onAction: () => context.push(Routes.compose),
                      ),
                    )
                  : Column(
                      children: list
                          .take(3)
                          .map(
                            (p) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Gap.page,
                                0,
                                Gap.page,
                                Gap.md,
                              ),
                              child: CloseyCard(
                                child: Text(
                                  p.body,
                                  style: context.text.bodyMedium,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),

            const SizedBox(height: Gap.xxxl),
            Padding(
              padding: Gap.pageInsets,
              child: CloseyButton(
                label: 'Sign out',
                variant: CloseyButtonVariant.ghost,
                fullWidth: true,
                onPressed: () async {
                  final ok = await showCloseyConfirm(
                    context: context,
                    title: 'Sign out?',
                    message: 'You can sign back in any time.',
                    confirmLabel: 'Sign out',
                  );
                  if (ok) await ref.read(authRepositoryProvider).signOut();
                },
              ),
            ),
            const SizedBox(height: Gap.xxxl),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cover = user.photos.length > 1 ? user.photos[1] : user.primaryPhoto;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 130,
              width: double.infinity,
              child: cover != null
                  ? Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: colors.surfaceSunken),
                    )
                  : CloseyCard(
                      radius: 0,
                      showBorder: false,
                      padding: EdgeInsets.zero,
                      child: ColoredBox(color: colors.surfaceSunken),
                    ),
            ),
            if (user.verificationTier.canUseCoach)
              Positioned(
                top: Gap.md,
                right: Gap.page,
                child: const CloseyBadge(
                  label: 'VERIFIED',
                  tone: CloseyBadgeTone.warning,
                  icon: Icons.verified_rounded,
                ),
              ),
            Positioned(
              bottom: -46,
              child: CloseyAvatar(
                name: user.fullName,
                imageUrl: user.primaryPhoto,
                size: 96,
                ringColor: colors.brand,
                ringWidth: 3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 56),
        Text(
          user.age != null ? '${user.fullName}, ${user.age}' : user.fullName,
          style: context.text.displaySmall,
        ),
        const SizedBox(height: 2),
        Text(
          '@${user.displayHandle}',
          style: context.text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        if (user.bio != null && user.bio!.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xxxl),
            child: Text(
              user.bio!,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
          ),
        ],
        if (user.city != null) ...[
          const SizedBox(height: Gap.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                user.city!,
                style: context.text.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Real completion signal, replacing the fake "92% profile strength" readout.
/// It points at the specific fields that actually improve the coach's output.
class _ProfileCompletion extends StatelessWidget {
  const _ProfileCompletion({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final checks = <(String, bool, String)>[
      (
        'At least 3 photos',
        user.photos.length >= 3,
        'More photos get more replies',
      ),
      (
        'A prompt answer',
        (user.promptAnswer ?? '').isNotEmpty,
        'Gives people something to reply to',
      ),
      (
        '3 conversation topics',
        user.conversationTopics.length >= 3,
        'The coach uses these most',
      ),
      (
        'Verified',
        user.verificationTier.canUseCoach,
        'Unlocks the coach for both of you',
      ),
    ];

    final done = checks.where((c) => c.$2).length;
    final pct = (done / checks.length * 100).round();

    return Padding(
      padding: Gap.pageInsets,
      child: CloseyCard(
        tinted: colors.coachSurface,
        borderColor: colors.coachBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Profile strength',
                    style: context.text.titleSmall,
                  ),
                ),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.accentText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            ClipRRect(
              borderRadius: Radii.pill,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: done / checks.length),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: colors.surfaceSunken,
                  valueColor: AlwaysStoppedAnimation(colors.accent),
                ),
              ),
            ),
            const SizedBox(height: Gap.lg),
            ...checks.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(
                  children: [
                    Icon(
                      c.$2
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: c.$2 ? colors.success : colors.textTertiary,
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        c.$1,
                        style: context.text.bodySmall?.copyWith(
                          color: c.$2
                              ? colors.textSecondary
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                    if (!c.$2)
                      Text(
                        c.$3,
                        style: context.text.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit profile.
///
/// Deliberately reuses the onboarding wizard with `editing: true` rather than
/// having a second, divergent profile form — the Expo app had exactly that
/// problem, where onboarding and "edit profile" could drift apart.
class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingScreen(editing: true);
}

/// Someone else's profile.
class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _busy = false;
  bool _requestSent = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uid = ref.watch(uidProvider);
    final profile = ref.watch(profileByIdProvider(widget.userId));
    final shared = ref.watch(sharedInterestsProvider(widget.userId));

    return CloseyScaffold(
      scrollable: false,
      appBar: CloseyAppBar(
        title: '',
        actions: [
          CloseyIconButton(
            icon: Icons.flag_outlined,
            semanticLabel: 'Report or block',
            onPressed: () =>
                context.push('${Routes.report(widget.userId)}?from=profile'),
          ),
        ],
      ),
      child: profile.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Gap.page),
          child: CloseySkeletonList(rows: 3),
        ),
        error: (e, _) => CloseyErrorState(
          message: e is CloseyFailure
              ? e.message
              : 'Could not load this profile.',
        ),
        data: (user) {
          if (user == null) {
            return const CloseyEmptyState(
              icon: Icons.person_off_outlined,
              title: 'Profile unavailable',
              message: 'This account may have been deleted or blocked you.',
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Gap.lg),
                  children: [
                    Padding(
                      padding: Gap.pageInsets,
                      child: PhotoCarousel(
                        imageUrls: user.sharedPhotoList
                            .whereType<String>()
                            .toList(),
                        name: user.fullName,
                        aspectRatio: 3 / 4,
                        overlay: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.age != null
                                        ? '${user.fullName}, ${user.age}'
                                        : user.fullName,
                                    style: const TextStyle(
                                      fontFamily: 'Fraunces',
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                if (user.verificationTier.canUseCoach) ...[
                                  const SizedBox(width: Gap.sm),
                                  const Icon(
                                    Icons.verified_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                user.city ?? 'Nearby',
                                if (user.showOnline && user.online)
                                  'Online now',
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (shared.isNotEmpty) ...[
                      const SizedBox(height: Gap.lg),
                      Padding(
                        padding: Gap.pageInsets,
                        child: CloseyCard(
                          tinted: colors.successSoft,
                          borderColor: colors.successSoft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 15,
                                    color: colors.successText,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'You both like',
                                    style: context.text.titleSmall?.copyWith(
                                      color: colors.successText,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Gap.sm),
                              Text(
                                shared.join(' · '),
                                style: context.text.bodyMedium?.copyWith(
                                  color: colors.successText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (user.bio != null && user.bio!.isNotEmpty) ...[
                      const CloseySectionHeader(title: 'About'),
                      Padding(
                        padding: Gap.pageInsets,
                        child: Text(user.bio!, style: context.text.bodyLarge),
                      ),
                    ],

                    if (user.promptAnswer != null) ...[
                      const CloseySectionHeader(title: 'In their words'),
                      Padding(
                        padding: Gap.pageInsets,
                        child: CloseyCard(
                          tinted: colors.surfaceSunken,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (user.promptQuestion ?? '').toUpperCase(),
                                style: context.eyebrow(),
                              ),
                              const SizedBox(height: Gap.sm),
                              Text(
                                user.promptAnswer!,
                                style: context.text.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (user.conversationTopics.isNotEmpty) ...[
                      const CloseySectionHeader(title: 'Loves talking about'),
                      Padding(
                        padding: Gap.pageInsets,
                        child: Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.sm,
                          children: user.conversationTopics
                              .map(
                                (t) => CloseyTag(
                                  label: t,
                                  tone: CloseyTagTone.accent,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],

                    if (user.interests.isNotEmpty) ...[
                      const CloseySectionHeader(title: 'Interests'),
                      Padding(
                        padding: Gap.pageInsets,
                        child: Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.sm,
                          children: user.interests
                              .map((i) => CloseyTag(label: i))
                              .toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              CloseyBottomBar(
                child: Row(
                  children: [
                    Expanded(
                      child: CloseyButton(
                        label: _requestSent ? 'Request sent' : 'Add friend',
                        icon: _requestSent
                            ? Icons.check_rounded
                            : Icons.person_add_alt_1_outlined,
                        variant: _requestSent
                            ? CloseyButtonVariant.secondary
                            : CloseyButtonVariant.success,
                        fullWidth: true,
                        size: CloseyButtonSize.lg,
                        loading: _busy && !_requestSent,
                        onPressed: _requestSent ? null : () => _addFriend(user),
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: CloseyButton(
                        label: 'Message',
                        icon: Icons.chat_bubble_outline_rounded,
                        fullWidth: true,
                        size: CloseyButtonSize.lg,
                        onPressed: uid == null ? null : () => _message(user),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addFriend(AppUser user) async {
    final me = ref.read(currentUserValueProvider);
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(connectionRepositoryProvider)
          .sendFriendRequest(from: me, to: user);
      if (mounted) setState(() => _requestSent = true);
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

  Future<void> _message(AppUser user) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(connectionRepositoryProvider);

      // Reuse an existing thread rather than charging the DM quota again.
      final existing = await repo.findExistingConnection(
        ref.read(uidProvider)!,
        user.id,
      );
      final id = existing ?? await repo.startDm(otherUserId: user.id);

      if (mounted) context.push(Routes.chat(id));
    } on CloseyFailure catch (e) {
      if (!mounted) return;
      if (e.code == 'DM_LIMIT_REACHED') {
        context.push('${Routes.paywall}?reason=dm');
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
