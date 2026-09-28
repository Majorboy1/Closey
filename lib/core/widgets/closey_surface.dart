import 'package:flutter/material.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import '../theme/closey_typography.dart';
import 'pressable.dart';

/// The one card shape used across the app.
///
/// The Expo build had five different card recipes (`rgba(255,255,255,0.05)`,
/// `0.04`, `0.08`, `#26253A`, `palette.white`) that were visually inconsistent
/// and unreadable in the case of the white `DateCard` sitting on a dark shell.
class CloseyCard extends StatelessWidget {
  const CloseyCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = Gap.cardInsets,
    this.radius = Radii.lg,
    this.elevated = true,
    this.tinted,
    this.borderColor,
    this.borderWidth = Strokes.hairline,
    this.showBorder = false,
    this.clip = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool elevated;

  /// Overrides the surface colour — used by the coach card.
  final Color? tinted;
  final Color? borderColor;
  final double borderWidth;
  final bool showBorder;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final content = AnimatedContainer(
      duration: context.motion(Motion.quick),
      curve: Motion.standard,
      padding: padding,
      decoration: BoxDecoration(
        color: tinted ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: showBorder
            ? Border.all(
                color: borderColor ?? c.border,
                width: Strokes.hairline,
              )
            : null,
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: child,
    );

    final wrapped = clip
        ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: content)
        : content;

    if (onTap == null) return wrapped;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: wrapped,
    );
  }
}

/// Uppercase section label with an optional trailing action.
///
/// Replaces the copy-pasted `13px/800 uppercase letterSpacing 0.6` Text style
/// that appeared verbatim in most of the old screens.
class CloseySectionHeader extends StatelessWidget {
  const CloseySectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      Gap.page,
      Gap.sm,
      Gap.page,
      Gap.md,
    ),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: CloseyTypography.eyebrow.copyWith(color: c.textTertiary),
            ),
          ),
          if (action != null)
            Pressable(
              onTap: onAction,
              borderRadius: Radii.pill,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: Gap.xs,
                ),
                child: Text(
                  action!,
                  style: context.text.labelLarge?.copyWith(color: c.brandText),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small status pill — verification tier, meeting status, "friend".
class CloseyBadge extends StatelessWidget {
  const CloseyBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = CloseyBadgeTone.neutral,
  });

  final String label;
  final IconData? icon;
  final CloseyBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      CloseyBadgeTone.neutral => (c.surfaceSunken, c.textSecondary),
      CloseyBadgeTone.brand => (c.brandSoft, c.brandText),
      CloseyBadgeTone.success => (c.successSoft, c.successText),
      CloseyBadgeTone.warning => (c.accentSoft, c.accentText),
      CloseyBadgeTone.danger => (c.dangerSoft, c.danger),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

enum CloseyBadgeTone { neutral, brand, success, warning, danger }

/// Row used inside settings / list cards. Guarantees a 48dp tap target and
/// puts the chevron in a consistent place — the old implementation used 36dp
/// icon circles with 18dp chevrons at three different indents.
class CloseyListRow extends StatelessWidget {
  const CloseyListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = destructive ? c.danger : c.textPrimary;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: Radii.allLg,
          child: Container(
            constraints: const BoxConstraints(minHeight: TapTarget.comfortable),
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.md,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: destructive ? c.dangerSoft : c.brandSoft,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(
                      icon,
                      size: 19,
                      color: destructive ? c.danger : c.brandText,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: context.text.titleSmall?.copyWith(color: fg),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: context.text.bodySmall?.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: c.textTertiary,
                    ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(left: icon != null ? 66 : Gap.lg),
            child: Divider(height: 1, color: c.border),
          ),
      ],
    );
  }
}
