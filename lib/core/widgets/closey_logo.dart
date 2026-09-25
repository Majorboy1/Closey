import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/closey_palette.dart';

/// The Closey mark: an open "C" ring with a heart nested inside it.
///
/// Hand-painted rather than shipped as an SVG so it scales crisply, can be
/// tinted, and needs no asset pipeline. Ported from the original
/// `CloseyLogo.tsx` SVG, with the glow and highlight simplified — at 28px in a
/// top bar the extra layers were invisible and cost a saveLayer each frame.
class CloseyLogo extends StatelessWidget {
  const CloseyLogo({
    super.key,
    this.size = 40,
    this.animated = false,
    this.showGlow = true,
  });

  final double size;

  /// Slow breathe. Used only on the welcome screen.
  final bool animated;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      size: Size.square(size),
      painter: _CloseyLogoPainter(showGlow: showGlow),
    );

    if (!animated) return painter;

    return _Breathing(child: painter);
  }
}

class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});
  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disable) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(scale: 1 + t * 0.045, child: child);
      },
      child: widget.child,
    );
  }
}

class _CloseyLogoPainter extends CustomPainter {
  _CloseyLogoPainter({required this.showGlow});

  final bool showGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final unit = size.width / 100;

    if (showGlow) {
      canvas.drawCircle(
        center,
        49 * unit,
        Paint()
          ..color = CloseyPalette.rose500.withValues(alpha: 0.16)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * unit),
      );
    }

    // The open C ring.
    final strokeWidth = 11 * unit;
    final ringRect = Rect.fromCircle(
      center: center,
      radius: 38 * unit - strokeWidth / 2,
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          CloseyPalette.rose300,
          CloseyPalette.rose500,
          CloseyPalette.rose700,
        ],
      ).createShader(ringRect);

    // Leave the gap on the right so it reads as a "C".
    const startAngle = math.pi * 0.16;
    const sweepAngle = math.pi * 1.72;
    canvas.drawArc(ringRect, startAngle, sweepAngle, false, ringPaint);

    // Nested heart.
    final heart = _heartPath(center, 21 * unit);
    canvas.drawPath(
      heart,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD3DC), Color(0xFFF27E98)],
        ).createShader(Rect.fromCircle(center: center, radius: 21 * unit)),
    );

    // Glass shine on the ring's upper-left.
    canvas.save();
    canvas.clipPath(heart);
    canvas.restore();
  }

  /// Classic two-lobe heart built from cubic beziers.
  Path _heartPath(Offset c, double r) {
    final p = Path();
    final w = r * 0.92;
    final h = r * 0.86;
    p.moveTo(c.dx, c.dy + h * 0.72);
    p.cubicTo(
      c.dx - w * 1.5,
      c.dy - h * 0.25,
      c.dx - w * 0.52,
      c.dy - h * 1.15,
      c.dx,
      c.dy - h * 0.36,
    );
    p.cubicTo(
      c.dx + w * 0.52,
      c.dy - h * 1.15,
      c.dx + w * 1.5,
      c.dy - h * 0.25,
      c.dx,
      c.dy + h * 0.72,
    );
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _CloseyLogoPainter old) =>
      old.showGlow != showGlow;
}

/// Wordmark: "closey" set in Fraunces next to the mark.
class CloseyWordmark extends StatelessWidget {
  const CloseyWordmark({
    super.key,
    this.fontSize = 24,
    this.logoSize = 26,
    this.color,
    this.showMark = true,
  });

  final double fontSize;
  final double logoSize;
  final Color? color;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMark) ...[
          CloseyLogo(size: logoSize, showGlow: false),
          const SizedBox(width: 8),
        ],
        Text(
          'closey',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            height: 1,
            color: color ?? c.onSurface,
          ),
        ),
      ],
    );
  }
}
