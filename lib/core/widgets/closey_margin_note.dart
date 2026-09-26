import 'package:flutter/material.dart';

import '../../data/models/chat.dart';
import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import '../theme/closey_typography.dart';

/// The coach's suggestion, set as a note in the margin of the conversation.
///
/// This replaces a floating card that sat above the composer. The card was
/// legible but it was *wrong*, for a reason worth recording: it used the same
/// surface, radius and type as a message, so it read as a third participant in
/// the thread — which is precisely the "the AI is in our chat" feeling the
/// product is meant to avoid. The coach is a hand in the margin, not a voice in
/// the room.
///
/// So the note deliberately breaks every convention a message bubble follows:
///
///  * **No fill and no shadow.** It is ink on the page, not a card on top of it.
///    The only thing separating it from the thread is a rule to its left.
///  * **It is indented and narrowed**, so it sits in the margin rather than in
///    the column of messages.
///  * **Serif and italic**, smaller than the conversation, so the eye reads it
///    as annotation and never as something someone said.
///  * **A vertical rule** in accent ink, *dashed for private notes*. The dash is
///    the only visual difference between a shared suggestion and a private
///    nudge, which is deliberate — the privacy is the product's central promise,
///    so it gets a mark that is quiet but unmistakable.
///
/// It animates in as a short slide from the right, as though written.
class CloseyMarginNote extends StatelessWidget {
  const CloseyMarginNote({
    super.key,
    required this.suggestion,
    this.onUse,
    this.onDismiss,
  });

  final AiSuggestion suggestion;

  /// Inserts the suggestion into the composer so it can be edited before it is
  /// sent. The coach offers; the human decides and sends.
  final ValueChanged<AiSuggestion>? onUse;

  final VoidCallback? onDismiss;

  bool get _isPrivate => suggestion.isPrivate;

  /// The label above the note. Phrased as an offer rather than an instruction —
  /// "you could send" rather than "send this" — because the product's stance is
  /// that the AI suggests and the person chooses.
  String get _label =>
      _isPrivate ? 'Only you see this' : 'You could send this';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = _isPrivate ? c.brandText : c.accentText;
    final rule = _isPrivate ? c.brandBorder : c.coachBorder;

    return TweenAnimationBuilder<double>(
      // One-shot: the note arrives once. Re-running this on every rebuild would
      // make the margin twitch whenever any unrelated state changed.
      tween: Tween(begin: 0, end: 1),
      duration: context.motion(Motion.slow),
      curve: Motion.standard,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset((1 - t) * 18, 0), child: child),
      ),
      child: Padding(
        // Indented well past the "mine" bubbles, so it never lines up with the
        // message column and cannot be mistaken for one.
        padding: const EdgeInsets.only(
          left: Gap.giant,
          right: Gap.page,
          top: Gap.lg,
          bottom: Gap.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Rule(color: rule, dashed: _isPrivate),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_isPrivate) ...[
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 12,
                          color: ink,
                        ),
                        const SizedBox(width: Gap.xs),
                      ],
                      Text(
                        _label.toUpperCase(),
                        style: context.eyebrow(ink).copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    suggestion.content,
                    style: CloseyTypography.marginNote(c).copyWith(color: ink),
                  ),
                  if (suggestion.reason case final reason?
                      when reason.trim().isNotEmpty) ...[
                    const SizedBox(height: Gap.sm),
                    Text(
                      reason,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.md),
                  Row(
                    children: [
                      _NoteAction(
                        label: 'Use this',
                        onTap: onUse == null
                            ? null
                            : () => onUse!(suggestion),
                        emphasis: ink,
                      ),
                      const SizedBox(width: Gap.lg),
                      _NoteAction(label: 'Not now', onTap: onDismiss),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The vertical rule that ties a note to the thread.
///
/// Private notes get a dashed rule. Flutter has no dashed [Border], and a
/// [DottedBorder]-style package would be a dependency for one rule, so this
/// paints it directly.
class _Rule extends StatelessWidget {
  const _Rule({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: Strokes.thick,
    child: CustomPaint(painter: _RulePainter(color: color, dashed: dashed)),
  );
}

class _RulePainter extends CustomPainter {
  _RulePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = Strokes.thick
      ..strokeCap = StrokeCap.round;

    final x = size.width / 2;

    if (!dashed) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }

    const dash = 4.0;
    const gapSize = 4.0;
    var y = 0.0;
    while (y < size.height) {
      final end = (y + dash).clamp(0.0, size.height);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y += dash + gapSize;
    }
  }

  @override
  bool shouldRepaint(_RulePainter old) =>
      old.color != color || old.dashed != dashed;
}

/// A deliberately understated action. Marginalia should not compete with the
/// conversation, so these are text, not buttons.
class _NoteAction extends StatelessWidget {
  const _NoteAction({required this.label, this.onTap, this.emphasis});

  final String label;
  final VoidCallback? onTap;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = onTap == null
        ? c.textTertiary
        : (emphasis ?? c.textSecondary);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Still a comfortable target even though it reads as plain text.
        constraints: const BoxConstraints(minHeight: 32),
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color.withValues(alpha: 0.4),
            decorationThickness: 1,
          ),
        ),
      ),
    );
  }
}
