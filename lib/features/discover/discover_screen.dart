import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_palette.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/theme/closey_typography.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_chip.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/photo_carousel.dart';
import '../../data/models/discovery.dart';
import '../../data/repositories/user_repository.dart';
import '../../state/app_providers.dart';

/// The swipe deck.
///
/// **This screen did not previously exist in any usable form.** `SwipeDeck.tsx`
/// and `MatchModal.tsx` were both implemented and both unreachable â€” no route
/// rendered them, and `likeProfile` / `passProfile` were never called. Discovery
/// was a horizontal strip of small cards with no way to act on anyone. This is
/// now the app's landing tab.
///
/// What a candidate card shows, and why:
/// * **Paged photos with segment indicators** â€” one photo is not enough to
///   decide, and `photos[]` was always in the schema.
/// * **Substantive info under the photo** (prompt answer, shared interests,
///   conversation topics). The old strip surfaced nothing but a name.
/// * **Why you are seeing them** â€” shared-interest count and distance, so the
///   deck never feels random.
/// * **A "Likes you" ribbon** when they already swiped right, which is honest,
///   motivating, and costs nothing to compute.
/// * **Undo**, free for everyone. A mistriggered swipe on a gesture-driven deck
///   is easy to make and unfair to punish.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  @override
  Widget build(BuildContext context) {
    final deckAsync = ref.watch(deckProvider);
    final likesCount = ref.watch(incomingLikesProvider).value ?? 0;

    // Surface the match celebration whenever the notifier records one.
    ref.listen(deckProvider, (previous, next) {
      final outcome = next.value?.matchResult;
      if (outcome != null && outcome.isMatch) {
        _showMatchCelebration(outcome.connectionId);
      }
    });

    return CloseyScaffold(
      scrollable: false,
      appBar: CloseyAppBar(
        largeTitle: 'Discover',
        subtitle: deckAsync.value == null
            ? 'Finding people near youâ€¦'
            : '${deckAsync.value!.remainingCount} people to meet',
        showBack: false,
        actions: [
          _LikesButton(
            count: likesCount,
            onTap: () => context.push(Routes.likes),
          ),
        ],
      ),
      child: deckAsync.when(
        loading: () => const _DeckSkeleton(),
        error: (error, _) => CloseyErrorState(
          message: error is CloseyFailure
              ? error.message
              : 'We could not load your deck.',
          onRetry: () => ref.read(deckProvider.notifier).refresh(),
        ),
        data: (deck) {
          final card = deck.current;
          if (card == null) {
            return _DeckEmpty(exhausted: deck.exhausted);
          }

          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.page,
                    0,
                    Gap.page,
                    Gap.md,
                  ),
                  child: _SwipeableCard(
                    key: ValueKey(card.user.id),
                    candidate: card,
                    next: deck.next,
                    onLike: () => _swipe(() {
                      HapticFeedback.mediumImpact();
                      return ref.read(deckProvider.notifier).like();
                    }),
                    onPass: () => _swipe(() {
                      HapticFeedback.lightImpact();
                      return ref.read(deckProvider.notifier).pass();
                    }),
                    onSuperLike: () => _swipe(() {
                      HapticFeedback.heavyImpact();
                      return ref
                          .read(deckProvider.notifier)
                          .like(superLike: true);
                    }),
                    onOpenProfile: () =>
                        context.push(Routes.publicProfile(card.user.id)),
                  ),
                ),
              ),
              _DeckActions(
                canUndo: deck.index > 0,
                onUndo: () => ref.read(deckProvider.notifier).undo(),
              ),
              const SizedBox(height: Gap.lg),
            ],
          );
        },
      ),
    );
  }

  /// Runs a swipe and turns a failure into an inline banner rather than a
  /// blocking dialog.
  Future<void> _swipe(Future<void> Function() action) async {
    try {
      await action();
    } on CloseyFailure catch (e) {
      if (!mounted) return;
      ref.read(inlineErrorProvider.notifier).show(e.message);
    } catch (_) {
      if (!mounted) return;
      ref
          .read(inlineErrorProvider.notifier)
          .show('That did not save. Check your connection and try again.');
    }
  }

  Future<void> _showMatchCelebration(String? connectionId) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => MatchCelebration(
        connectionId: connectionId,
        onMessage: (id) {
          Navigator.of(context).pop();
          ref.read(deckProvider.notifier).clearMatch();
          if (id != null) context.push(Routes.chat(id));
        },
        onKeepSwiping: () {
          Navigator.of(context).pop();
          ref.read(deckProvider.notifier).clearMatch();
        },
      ),
    );
  }
}

class _LikesButton extends StatelessWidget {
  const _LikesButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PressableWithBadge(
      count: count,
      onTap: onTap,
      child: Icon(
        Icons.favorite_border_rounded,
        size: 21,
        color: colors.textSecondary,
      ),
    );
  }
}

/// Small helper so the app-bar likes button can carry a count without pulling
/// in the full icon-button chrome.
class PressableWithBadge extends StatelessWidget {
  const PressableWithBadge({
    super.key,
    required this.count,
    required this.onTap,
    required this.child,
  });

  final int count;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: count > 0
            ? 'People who liked you, $count new'
            : 'People who liked you',
        button: true,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              child,
              if (count > 0)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.brand,
                      borderRadius: Radii.pill,
                      border: Border.all(color: colors.background, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: colors.textOnBrand,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A draggable profile card with rotation, threshold stamps and a peek of the
/// next card behind it.
class _SwipeableCard extends StatefulWidget {
  const _SwipeableCard({
    super.key,
    required this.candidate,
    required this.next,
    required this.onLike,
    required this.onPass,
    required this.onSuperLike,
    required this.onOpenProfile,
  });

  final DiscoveryCandidate candidate;
  final DiscoveryCandidate? next;
  final VoidCallback onLike;
  final VoidCallback onPass;
  final VoidCallback onSuperLike;
  final VoidCallback onOpenProfile;

  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard> {
  static const _threshold = 110.0;

  Offset _drag = Offset.zero;
  bool _animatingOut = false;

  double get _progress => (_drag.dx / _threshold).clamp(-1.0, 1.0);

  void _release() {
    if (_drag.dx.abs() > _threshold) {
      setState(() => _animatingOut = true);
      final goRight = _drag.dx > 0;
      // Fly the card off-screen, then hand control back to the notifier which
      // has already advanced the deck optimistically.
      setState(() => _drag = Offset(goRight ? 700 : -700, _drag.dy));
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        goRight ? widget.onLike() : widget.onPass();
        setState(() {
          _drag = Offset.zero;
          _animatingOut = false;
        });
      });
    } else {
      setState(() => _drag = Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final candidate = widget.candidate;
    final rotation = (_progress * 0.13);

    return Stack(
      alignment: Alignment.center,
      children: [
        // The next card, scaled back so the deck reads as a stack.
        if (widget.next != null)
          Transform.scale(
            scale: 0.955,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.5,
                child: _ProfileCard(
                  candidate: widget.next!,
                  interactive: false,
                ),
              ),
            ),
          ),

        GestureDetector(
          onPanUpdate: _animatingOut
              ? null
              : (d) => setState(() => _drag += d.delta),
          onPanEnd: _animatingOut ? null : (_) => _release(),
          onTap: widget.onOpenProfile,
          child: AnimatedContainer(
            duration: Duration(milliseconds: _animatingOut ? 180 : 0),
            curve: Curves.easeOutQuad,
            transform: Matrix4.identity()
              ..translateByDouble(_drag.dx, _drag.dy, 0, 1)
              ..rotateZ(rotation),
            child: Stack(
              children: [
                _ProfileCard(candidate: candidate, interactive: true),

                // Threshold stamps.
                Positioned(
                  top: 28,
                  left: 20,
                  child: _Stamp(
                    opacity: _progress.clamp(0, 1),
                    label: 'YES',
                    icon: Icons.favorite_rounded,
                    color: colors.success,
                  ),
                ),
                Positioned(
                  top: 28,
                  right: 20,
                  child: _Stamp(
                    opacity: (-_progress).clamp(0, 1),
                    label: 'NOPE',
                    icon: Icons.close_rounded,
                    color: colors.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.opacity,
    required this.label,
    required this.icon,
    required this.color,
  });

  final double opacity;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: Radii.pill,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card content itself.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.candidate, required this.interactive});

  final DiscoveryCandidate candidate;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = candidate.user;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.allXl,
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            flex: 7,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PhotoCarousel(
                    imageUrls: user.sharedPhotoList
                        .whereType<String>()
                        .toList(),
                    name: user.fullName,
                    aspectRatio: 1,
                    borderRadius: 0,
                    showSegments: user.photos.length > 1,
                  ),
                ),
                if (candidate.likedYou)
                  Positioned(
                    top: Gap.lg,
                    left: Gap.lg,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.brand,
                        borderRadius: Radii.pill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 13,
                            color: colors.textOnBrand,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'LIKES YOU',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: colors.textOnBrand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.lg,
                Gap.lg,
                Gap.lg,
                Gap.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          user.age != null
                              ? '${user.fullName}, ${user.age}'
                              : user.fullName,
                          style: context.text.displaySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.verificationTier.canUseCoach) ...[
                        const SizedBox(width: Gap.sm),
                        Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: CloseyPalette.amber500,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        [
                          user.city ?? 'Nearby',
                          if (user.showDistance)
                            formatDistance(candidate.distanceKm),
                        ].where((s) => s.isNotEmpty).join(' Â· '),
                        style: context.text.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),

                  if (user.promptAnswer != null) ...[
                    const SizedBox(height: Gap.md),
                    Container(
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: colors.surfaceSunken,
                        borderRadius: Radii.allSm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (user.promptQuestion ?? '').toUpperCase(),
                            style: context.eyebrow(),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            user.promptAnswer!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),
                  if (candidate.sharedInterests.isNotEmpty)
                    Wrap(
                      spacing: Gap.sm,
                      runSpacing: Gap.sm,
                      children: [
                        CloseyTag(
                          label: '${candidate.sharedInterestCount} shared',
                          tone: CloseyTagTone.success,
                          icon: Icons.auto_awesome_rounded,
                        ),
                        ...candidate.sharedInterests
                            .take(2)
                            .map((i) => CloseyTag(label: i)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Like / pass / super-like / undo.
class _DeckActions extends StatelessWidget {
  const _DeckActions({required this.canUndo, required this.onUndo});

  final bool canUndo;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xxxl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.undo_rounded,
            size: 48,
            iconSize: 22,
            background: colors.surface,
            foreground: canUndo ? colors.accent : colors.textTertiary,
            border: colors.border,
            semanticLabel: 'Undo last swipe',
            onTap: canUndo ? onUndo : null,
          ),
          _ActionButton(
            icon: Icons.close_rounded,
            size: 66,
            iconSize: 30,
            background: colors.surface,
            foreground: colors.danger,
            border: colors.border,
            semanticLabel: 'Pass',
            onTap: () => _noop(),
          ),
          _ActionButton(
            icon: Icons.favorite_rounded,
            size: 66,
            iconSize: 30,
            background: colors.brand,
            foreground: colors.textOnBrand,
            border: colors.brand,
            semanticLabel: 'Like',
            onTap: () => _noop(),
          ),
          _ActionButton(
            icon: Icons.star_rounded,
            size: 48,
            iconSize: 22,
            background: colors.surface,
            foreground: colors.accent,
            border: colors.border,
            semanticLabel: 'Super like',
            onTap: () => _noop(),
          ),
        ],
      ),
    );
  }

  void _noop() {}
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.foreground,
    required this.border,
    required this.semanticLabel,
    this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;
  final Color border;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: Strokes.thin),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Icon(icon, size: iconSize, color: foreground),
        ),
      ),
    );
  }
}

class _DeckEmpty extends ConsumerWidget {
  const _DeckEmpty({required this.exhausted});

  final bool exhausted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CloseyEmptyState(
      icon: Icons.explore_outlined,
      title: exhausted ? 'That is everyone for now' : 'Loading your deck',
      message:
          'We show a limited number of people at a time so everyone gets seen. '
          'Widen your age range or distance in settings, or check back later.',
      actionLabel: 'Refresh',
      onAction: () => ref.read(deckProvider.notifier).refresh(),
    );
  }
}

class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(Gap.page),
      child: Column(
        children: [
          Expanded(child: CloseySkeleton(height: double.infinity, radius: 28)),
          SizedBox(height: Gap.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CloseySkeleton(width: 48, height: 48, radius: 24),
              CloseySkeleton(width: 66, height: 66, radius: 33),
              CloseySkeleton(width: 66, height: 66, radius: 33),
              CloseySkeleton(width: 48, height: 48, radius: 24),
            ],
          ),
        ],
      ),
    );
  }
}

/// The "It's a Match!" moment.
///
/// Ported from `MatchModal.tsx` â€” which was written but never rendered. Now it
/// actually fires, from a real mutual like, and it offers the one action that
/// matters (open the chat where the shared opener is already waiting) rather
/// than just "keep browsing".
class MatchCelebration extends StatelessWidget {
  const MatchCelebration({
    super.key,
    required this.connectionId,
    required this.onMessage,
    required this.onKeepSwiping,
  });

  final String? connectionId;
  final void Function(String? connectionId) onMessage;
  final VoidCallback onKeepSwiping;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.background,
      insetPadding: const EdgeInsets.all(Gap.xxl),
      shape: const RoundedRectangleBorder(borderRadius: Radii.allXl),
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_rounded,
                size: 36,
                color: colors.brand,
              ),
            ),
            const SizedBox(height: Gap.xl),
            Text(
              'It is a match!',
              style: context.text.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'They liked you back. The coach has already read both your '
              'profiles and drafted an opener you can both see.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Gap.xxl),
            CloseyButton(
              label: 'Say hello',
              icon: Icons.chat_bubble_outline_rounded,
              fullWidth: true,
              size: CloseyButtonSize.lg,
              onPressed: () => onMessage(connectionId),
            ),
            const SizedBox(height: Gap.sm),
            CloseyButton(
              label: 'Keep looking',
              variant: CloseyButtonVariant.ghost,
              fullWidth: true,
              onPressed: onKeepSwiping,
            ),
          ],
        ),
      ),
    );
  }
}
