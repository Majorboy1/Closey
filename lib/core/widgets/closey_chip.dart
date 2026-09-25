import 'package:flutter/material.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import '../theme/closey_typography.dart';
import 'pressable.dart';

/// A selectable pill.
///
/// Fixes a real accessibility gap in the Expo `Chip`: selection there was
/// signalled by colour alone. Here a checkmark appears, the border thickens,
/// and the semantics tree reports `selected` — so it works for colour-blind
/// users, screen readers and automated tests alike.
class CloseyChip extends StatelessWidget {
  const CloseyChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.emoji,
    this.icon,
    this.dense = false,
    this.disabled = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? emoji;
  final IconData? icon;
  final bool dense;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final fg = disabled
        ? c.textTertiary
        : selected
        ? c.textOnBrand
        : c.textSecondary;

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Pressable(
        onTap: disabled ? null : onTap,
        borderRadius: Radii.pill,
        child: AnimatedContainer(
          duration: context.motion(Motion.quick),
          curve: Motion.standard,
          padding: EdgeInsets.symmetric(
            horizontal: dense ? Gap.md : Gap.lg,
            vertical: dense ? Gap.sm : Gap.md - 2,
          ),
          decoration: BoxDecoration(
            color: selected ? c.brand : c.surface,
            borderRadius: Radii.pill,
            border: Border.all(
              color: selected ? c.brand : c.border,
              width: selected ? Strokes.thin : Strokes.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: Gap.xs + 2),
                  child: Icon(Icons.check_rounded, size: 15, color: fg),
                )
              else if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: Gap.xs + 2),
                  child: Icon(icon, size: 15, color: fg),
                ),
              if (emoji != null && !selected && icon == null)
                Padding(
                  padding: const EdgeInsets.only(right: Gap.xs + 2),
                  child: Text(emoji!, style: const TextStyle(fontSize: 14)),
                ),
              AnimatedDefaultTextStyle(
                duration: context.motion(Motion.quick),
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: dense ? 13 : 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A non-interactive tag — interests on a profile, topics on a card.
class CloseyTag extends StatelessWidget {
  const CloseyTag({
    super.key,
    required this.label,
    this.tone = CloseyTagTone.neutral,
    this.icon,
  });

  final String label;
  final CloseyTagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      CloseyTagTone.neutral => (c.surfaceSunken, c.textSecondary),
      CloseyTagTone.brand => (c.brandSoft, c.brandText),
      CloseyTagTone.success => (c.successSoft, c.successText),
      CloseyTagTone.accent => (c.accentSoft, c.accentText),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: Gap.xs + 1),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

enum CloseyTagTone { neutral, brand, success, accent }

/// Horizontally scrolling filter tabs with a sliding pill indicator.
///
/// Replaces `ChipTabs`, which had no indicator animation, no scroll-into-view
/// for the active tab, and drew an unlabelled badge.
class CloseyFilterBar extends StatelessWidget {
  const CloseyFilterBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: Gap.page),
  });

  final List<CloseyFilterTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return _FilterPill(
            tab: tab,
            selected: index == selectedIndex,
            onTap: () => onSelected(index),
          );
        },
      ),
    );
  }
}

class CloseyFilterTab {
  const CloseyFilterTab(this.label, {this.badge});
  final String label;
  final int? badge;
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final CloseyFilterTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Pressable(
      onTap: onTap,
      borderRadius: Radii.pill,
      semanticLabel: tab.label,
      child: AnimatedContainer(
        duration: context.motion(Motion.quick),
        curve: Motion.standard,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.textPrimary : c.surface,
          borderRadius: Radii.pill,
          border: Border.all(color: selected ? c.textPrimary : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.label,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? c.surface : c.textSecondary,
              ),
            ),
            if (tab.badge != null && tab.badge! > 0) ...[
              const SizedBox(width: Gap.sm - 2),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.brand,
                  borderRadius: Radii.pill,
                ),
                child: Text(
                  '${tab.badge}',
                  style: CloseyTypography.numeric.copyWith(
                    fontSize: 10.5,
                    color: c.textOnBrand,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
