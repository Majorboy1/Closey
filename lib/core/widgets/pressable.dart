import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/closey_motion.dart';

/// A tappable surface that scales down slightly and fires haptics.
///
/// Every interactive element in the app goes through this so press feedback is
/// consistent. The Expo build only ever changed `opacity`, which reads as
/// unresponsive on 120Hz displays.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = HapticFeedback.selectionClick,
    this.borderRadius,
    this.semanticLabel,
    this.semanticButton = true,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final VoidCallback? haptic;
  final BorderRadius? borderRadius;
  final String? semanticLabel;
  final bool semanticButton;
  final MouseCursor cursor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;

    return Semantics(
      label: widget.semanticLabel,
      button: widget.semanticButton && _enabled,
      enabled: _enabled,
      child: MouseRegion(
        cursor: _enabled ? widget.cursor : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => _set(true) : null,
          onTapUp: _enabled ? (_) => _set(false) : null,
          onTapCancel: _enabled ? () => _set(false) : null,
          onTap: _enabled
              ? () {
                  widget.haptic?.call();
                  widget.onTap?.call();
                }
              : null,
          onLongPress: _enabled && widget.onLongPress != null
              ? () {
                  HapticFeedback.mediumImpact();
                  widget.onLongPress!.call();
                }
              : null,
          child: AnimatedScale(
            scale: _down && !reduce ? widget.scale : 1.0,
            duration: context.motion(Motion.instant),
            curve: Motion.standard,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
