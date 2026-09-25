import 'package:flutter/material.dart';

import '../../../core/theme/closey_colors.dart';
import '../../../core/theme/closey_motion.dart';
import '../../../core/theme/closey_spacing.dart';
import '../../../core/widgets/closey_button.dart';
import '../../../core/widgets/closey_chip.dart';
import '../../../data/models/chat.dart';

/// The AI coach card — the product's hero component.
///
/// This is the piece that has to earn the whole concept, so the design is
/// deliberate about four things:
///
/// **1. Shared cards are attributed to both people.** A pair of overlapping
/// avatars plus "you can both see this" makes it unambiguous that this is a
/// joint prompt, not a message from one of them. The old `SuggestionCard` was
/// left-aligned like an incoming message, which made it read as the AI
/// speaking on someone's behalf — precisely what the spec forbids.
///
/// **2. Private nudges are visually a different object.** Recessed rose
/// surface, a lock, a "just for you" tag, and an explicit sentence that the
/// other person cannot see it. Trust in this mechanic depends entirely on the
/// user believing it, so the UI states it rather than relying on styling alone.
///
/// **3. The reason is always shown.** "One person answered without asking back"
/// turns an unexplained interruption into a legible bit of help.
///
/// **4. The primary action fills the composer rather than sending.** The copy
/// is "Use this" but the effect is "put this in your box so you can edit it",
/// which keeps the human in the loop. Auto-sending would cross the line the
/// spec draws.
class CoachCard extends StatelessWidget {
  const CoachCard({
    super.key,
    required this.suggestion,
    required this.onUse,
    required this.onDismiss,
    required this.onBuyMore,
    this.remaining,
    this.otherName,
    this.otherAvatarUrl,
    this.myName,
    this.myAvatarUrl,
  });

  final AiSuggestion suggestion;

  /// Null for private cards — the shared pool is not relevant to a nudge.
  final int? remaining;

  final String? otherName;
  final String? otherAvatarUrl;
  final String? myName;
  final String? myAvatarUrl;

  final VoidCallback onUse;
  final VoidCallback onDismiss;
  final VoidCallback onBuyMore;

  bool get _isPrivate => suggestion.isPrivate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final outOfCredits = remaining != null && remaining! <= 0;

    return AnimatedSize(
      duration: context.motion(Motion.quick),
      curve: Motion.standard,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Gap.lg),
        decoration: BoxDecoration(
          color: _isPrivate ? colors.privateSurface : colors.coachSurface,
          borderRadius: Radii.allLg,
          border: Border.all(
            color: _isPrivate ? colors.brandBorder : colors.coachBorder,
            width: Strokes.thin,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --------------------------------------------------------- header
            Row(
              children: [
                _AvatarCluster(
                  myName: myName,
                  myAvatarUrl: myAvatarUrl,
                  otherName: otherName,
                  otherAvatarUrl: otherAvatarUrl,
                  isPrivate: _isPrivate,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPrivate
                            ? 'JUST FOR YOU'
                            : (suggestion.type?.label ?? 'SUGGESTED')
                                  .toUpperCase(),
                        style: CloseyEyebrowStyle.of(
                          _isPrivate ? colors.brandText : colors.accentText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isPrivate
                            ? 'They cannot see this'
                            : suggestion.type?.hint ?? 'A prompt for you both',
                        style: context.text.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (remaining != null && !_isPrivate)
                  Text(
                    outOfCredits ? 'No credits left' : '$remaining left today',
                    style: context.text.bodySmall?.copyWith(
                      fontSize: 11,
                      color: outOfCredits ? colors.danger : colors.textTertiary,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: Gap.lg),

            // ----------------------------------------------------------- copy
            // Set in Fraunces deliberately: it should read as a written line
            // somebody could say, not as system output.
            Text(
              suggestion.content,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 17.5,
                height: 1.42,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),

            const SizedBox(height: Gap.md),

            // --------------------------------------------------------- reason
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    suggestion.whyThis,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: Gap.lg),

            // -------------------------------------------------------- actions
            Row(
              children: [
                Expanded(
                  child: CloseyButton(
                    label: 'Use this',
                    size: CloseyButtonSize.sm,
                    fullWidth: true,
                    disabledReason: outOfCredits
                        ? 'No suggestions left today'
                        : null,
                    onPressed: outOfCredits ? null : onUse,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                if (_isPrivate)
                  CloseyButton(
                    label: 'Dismiss',
                    icon: Icons.close_rounded,
                    variant: CloseyButtonVariant.ghost,
                    size: CloseyButtonSize.sm,
                    onPressed: onDismiss,
                  )
                else
                  CloseyButton(
                    // The state change *is* the call to action: same position,
                    // different label, icon and colour, so the transition from
                    // "ask again" to "you need credits" is unmissable.
                    label: outOfCredits ? 'Buy more' : 'Another',
                    icon: outOfCredits
                        ? Icons.add_rounded
                        : Icons.refresh_rounded,
                    variant: outOfCredits
                        ? CloseyButtonVariant.success
                        : CloseyButtonVariant.secondary,
                    size: CloseyButtonSize.sm,
                    onPressed: outOfCredits ? onBuyMore : onDismiss,
                  ),
              ],
            ),

            if (_isPrivate) ...[
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 12,
                    color: colors.brandText,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Only you can see this. Your match is never told a nudge '
                      'was sent.',
                      style: context.text.bodySmall?.copyWith(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: colors.brandText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Overlapping avatars, or a single lock badge for private cards.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({
    this.myName,
    this.myAvatarUrl,
    this.otherName,
    this.otherAvatarUrl,
    required this.isPrivate,
  });

  final String? myName;
  final String? myAvatarUrl;
  final String? otherName;
  final String? otherAvatarUrl;
  final bool isPrivate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (isPrivate) {
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.brand, shape: BoxShape.circle),
        child: Icon(
          Icons.visibility_off_rounded,
          size: 16,
          color: colors.textOnBrand,
        ),
      );
    }

    Widget dot(String? name, String? url, Color ring) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.coachSurface,
        shape: BoxShape.circle,
      ),
      child: _MiniAvatar(name: name ?? '?', url: url, ring: ring),
    );

    return SizedBox(
      width: 50,
      height: 34,
      child: Stack(
        children: [
          dot(myName, myAvatarUrl, colors.border),
          Positioned(
            left: 16,
            child: dot(otherName, otherAvatarUrl, colors.brandBorder),
          ),
          Positioned(
            left: 32,
            top: 4,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: colors.coachSurface, width: 2),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name, this.url, required this.ring});

  final String name;
  final String? url;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
        image: url != null
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      child: url == null
          ? Text(
              name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            )
          : null,
    );
  }
}

/// Shared eyebrow style so the coach card does not need to import the whole
/// typography extension.
abstract final class CloseyEyebrowStyle {
  static TextStyle of(Color color) => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.0,
    height: 1.2,
    color: color,
  );
}

/// Compact inline quota chip for the composer row.
class CoachQuotaChip extends StatelessWidget {
  const CoachQuotaChip({
    super.key,
    required this.remaining,
    required this.limit,
    this.onBuyMore,
  });

  final int remaining;
  final int limit;
  final VoidCallback? onBuyMore;

  @override
  Widget build(BuildContext context) {
    final empty = remaining <= 0;

    return GestureDetector(
      onTap: empty ? onBuyMore : null,
      child: CloseyTag(
        label: empty ? 'Buy more' : '$remaining of $limit left',
        tone: empty ? CloseyTagTone.brand : CloseyTagTone.accent,
        icon: empty ? Icons.add_rounded : Icons.bolt_rounded,
      ),
    );
  }
}
