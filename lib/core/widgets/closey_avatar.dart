import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_palette.dart';
import '../theme/closey_spacing.dart';

/// Circular avatar with deterministic, consent-safe fallbacks.
///
/// Keeps the `DECISIONS.md` call to use DiceBear *illustrated* portraits rather
/// than stock photos of real people, but adds a proper offline path: if the
/// network image fails or the device is offline we render a generated monogram
/// from the palette, so an avatar is never a blank grey circle.
class CloseyAvatar extends StatelessWidget {
  const CloseyAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 48,
    this.online = false,
    this.showPresence = false,
    this.ringColor,
    this.ringWidth = Strokes.ring,
    this.badge,
  });

  final String? imageUrl;
  final String name;
  final double size;
  final bool online;
  final bool showPresence;
  final Color? ringColor;
  final double ringWidth;
  final Widget? badge;

  /// DiceBear `notionists` — warm, hand-drawn, and clearly not a real person.
  static String illustratedUrl(String seed) {
    final safe = Uri.encodeComponent(
      seed.trim().isEmpty ? 'closey' : seed.trim(),
    );
    return 'https://api.dicebear.com/7.x/notionists/svg'
        '?seed=$safe&backgroundColor=f1e9df,f3d9a8,dce9dd,fbe0e5';
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Stable colour assignment so the same person always gets the same tint.
  static Color _seedColor(String name) {
    const ramp = [
      CloseyPalette.rose200,
      CloseyPalette.amber200,
      CloseyPalette.sage200,
      CloseyPalette.rose100,
      CloseyPalette.amber100,
      CloseyPalette.sage100,
    ];
    return ramp[name.hashCode.abs() % ramp.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final resolved = imageUrl ?? illustratedUrl(name);
    final presenceSize = size * 0.26;

    Widget circle = SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: resolved,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 180),
          placeholder: (_, _) => _fallback(c),
          errorWidget: (_, _, _) => _fallback(c),
        ),
      ),
    );

    if (ringColor != null) {
      circle = Container(
        padding: EdgeInsets.all(ringWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor!, width: ringWidth),
        ),
        child: circle,
      );
    }

    final stack = <Widget>[circle];

    if (showPresence) {
      stack.add(
        Positioned(
          right: 0,
          bottom: 0,
          child: Semantics(
            label: online ? 'Online now' : 'Offline',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: presenceSize,
              height: presenceSize,
              decoration: BoxDecoration(
                color: online ? c.success : c.textTertiary,
                shape: BoxShape.circle,
                border: Border.all(color: c.surface, width: size * 0.05 + 1.2),
              ),
            ),
          ),
        ),
      );
    }

    if (badge != null) {
      stack.add(Positioned(right: -2, bottom: -2, child: badge!));
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: stack),
    );
  }

  Widget _fallback(CloseyColors c) {
    final bg = _seedColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: bg,
      child: Text(
        initials(name),
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: CloseyPalette.ink800,
          height: 1,
        ),
      ),
    );
  }
}

/// Overlapping avatar pair — used by the coach card and match celebration to
/// show that a suggestion belongs to *both* people.
class CloseyAvatarPair extends StatelessWidget {
  const CloseyAvatarPair({
    super.key,
    required this.leftName,
    required this.rightName,
    this.leftImageUrl,
    this.rightImageUrl,
    this.size = 32,
    this.overlap = 10,
    this.center,
  });

  final String leftName;
  final String rightName;
  final String? leftImageUrl;
  final String? rightImageUrl;
  final double size;
  final double overlap;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget ringed(Widget child) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
      child: child,
    );

    return SizedBox(
      width: size * 2 - overlap + (center != null ? size * 0.5 : 0),
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ringed(
            CloseyAvatar(
              name: leftName,
              imageUrl: leftImageUrl,
              size: size - 4,
            ),
          ),
          Positioned(
            left: size - overlap,
            child: ringed(
              CloseyAvatar(
                name: rightName,
                imageUrl: rightImageUrl,
                size: size - 4,
              ),
            ),
          ),
          if (center != null)
            Positioned(
              left: size + size * 0.5 - overlap - 6,
              top: 0,
              child: center!,
            ),
        ],
      ),
    );
  }
}
