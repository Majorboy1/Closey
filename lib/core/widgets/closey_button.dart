import 'package:flutter/material.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import '../theme/closey_typography.dart';
import 'pressable.dart';

/// Button variants. `danger` and `primary` were literally the same code path in
/// the Expo `Button`, which made destructive actions impossible to signal
/// visually; here they are distinct.
enum CloseyButtonVariant {
  /// Solid brand fill. One per screen.
  primary,

  /// Outlined, uses the plain surface. The default secondary action.
  secondary,

  /// Tinted brand container — used for soft affirmative actions.
  tonal,

  /// Sage fill, reserved for "friend"/unlimited/positive-commitment actions.
  success,

  /// Text only.
  ghost,

  /// Destructive: solid rose tint with danger text, never a filled red block.
  danger,
}

enum CloseyButtonSize { sm, md, lg }

class CloseyButton extends StatelessWidget {
  const CloseyButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = CloseyButtonVariant.primary,
    this.size = CloseyButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
    this.expand = false,
    this.semanticLabel,
    this.disabledReason,
  });

  final String label;
  final VoidCallback? onPressed;
  final CloseyButtonVariant variant;
  final CloseyButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool fullWidth;

  /// Stretch to fill the parent's width (used inside `Expanded`/`Flexible`).
  final bool expand;
  final String? semanticLabel;

  /// Why the button is unavailable. A disabled button with no explanation is a
  /// dead end, so this is shown as a tooltip and fed to the screen reader.
  final String? disabledReason;

  bool get _enabled => onPressed != null && !loading;

  double get _height => switch (size) {
    CloseyButtonSize.sm => 40,
    CloseyButtonSize.md => 50,
    CloseyButtonSize.lg => 56,
  };

  double get _fontSize => switch (size) {
    CloseyButtonSize.sm => 13.5,
    CloseyButtonSize.md => 15,
    CloseyButtonSize.lg => 16,
  };

  double get _iconSize => switch (size) {
    CloseyButtonSize.sm => 17,
    CloseyButtonSize.md => 19,
    CloseyButtonSize.lg => 20,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, border) = _resolve(c);

    final child = AnimatedContainer(
      duration: context.motion(Motion.quick),
      curve: Motion.standard,
      height: _height,
      padding: EdgeInsets.symmetric(
        horizontal: size == CloseyButtonSize.sm ? Gap.lg : Gap.xxl,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.pill,
        border: Border.all(
          color: border,
          width: variant == CloseyButtonVariant.secondary
              ? Strokes.thin
              : Strokes.hairline,
        ),
      ),
      child: AnimatedOpacity(
        duration: context.motion(Motion.instant),
        opacity: _enabled ? 1 : 0.45,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: _iconSize,
                height: _iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              ),
              const SizedBox(width: Gap.sm),
            ] else if (icon != null) ...[
              Icon(icon, size: _iconSize, color: fg),
              const SizedBox(width: Gap.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  color: fg,
                ),
              ),
            ),
            if (trailingIcon != null && !loading) ...[
              const SizedBox(width: Gap.sm),
              Icon(trailingIcon, size: _iconSize, color: fg),
            ],
          ],
        ),
      ),
    );

    final sized = fullWidth
        ? SizedBox(width: double.infinity, child: child)
        : child;

    final button = Pressable(
      onTap: _enabled ? onPressed : null,
      borderRadius: Radii.pill,
      semanticLabel: semanticLabel ?? label,
      child: sized,
    );

    // A disabled control should say why it is disabled. Without this the user
    // just sees a dead button.
    if (!_enabled && disabledReason != null) {
      return Tooltip(message: disabledReason!, child: button);
    }
    return button;
  }

  (Color bg, Color fg, Color border) _resolve(CloseyColors c) {
    switch (variant) {
      case CloseyButtonVariant.primary:
        return (c.brand, c.textOnBrand, c.brand);
      case CloseyButtonVariant.secondary:
        return (c.surface, c.textPrimary, c.borderStrong);
      case CloseyButtonVariant.tonal:
        return (c.brandSoft, c.brandText, c.brandBorder);
      case CloseyButtonVariant.success:
        return (
          c.success,
          c.brightness == Brightness.light
              ? Colors.white
              : CloseyColors.dark.textPrimary,
          c.success,
        );
      case CloseyButtonVariant.ghost:
        return (Colors.transparent, c.textSecondary, Colors.transparent);
      case CloseyButtonVariant.danger:
        return (c.dangerSoft, c.danger, c.brandBorder);
    }
  }
}

/// A circular icon button that always meets the 48dp tap target.
class CloseyIconButton extends StatelessWidget {
  const CloseyIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.semanticLabel,
    this.size = 44,
    this.iconSize = 21,
    this.filled = false,
    this.background,
    this.foreground,
    this.badgeCount,
    this.showBadgeDot = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final double size;
  final double iconSize;
  final bool filled;
  final Color? background;
  final Color? foreground;
  final int? badgeCount;
  final bool showBadgeDot;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget button = Pressable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(size),
      semanticLabel: semanticLabel ?? tooltip,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? (background ?? c.surface)
              : (background ?? Colors.transparent),
          shape: BoxShape.circle,
          border: filled ? Border.all(color: c.border) : null,
        ),
        child: Icon(icon, size: iconSize, color: foreground ?? c.textSecondary),
      ),
    );

    if (showBadgeDot) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: c.brand,
                shape: BoxShape.circle,
                border: Border.all(color: c.background, width: 1.6),
              ),
            ),
          ),
        ],
      );
    } else if (badgeCount != null && badgeCount! > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            right: 4,
            top: 5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.brand,
                borderRadius: Radii.pill,
                border: Border.all(color: c.background, width: 1.6),
              ),
              child: Text(
                badgeCount! > 99 ? '99+' : '$badgeCount',
                style: CloseyTypography.numeric.copyWith(
                  fontSize: 10,
                  color: c.textOnBrand,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
