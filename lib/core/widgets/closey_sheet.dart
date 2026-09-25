import 'package:flutter/material.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_spacing.dart';
import 'closey_button.dart';

/// Bottom sheets, done once.
///
/// The Expo `Sheet` was a `Modal` with `animationType="slide"` and carried a
/// TODO to migrate to a real bottom sheet. Problems it had: it could not be
/// dragged to dismiss, it did not resize for the keyboard, and its backdrop
/// was not scroll-aware. This is the real thing.
Future<T?> showCloseySheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = true,
  bool dismissible = true,
  double? maxHeightFactor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.colors.scrim,
    builder: (context) {
      final maxH =
          MediaQuery.sizeOf(context).height * (maxHeightFactor ?? 0.92);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: _SheetShell(child: child),
      );
    },
  );
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: Radii.allSheet,
        border: Border(
          top: BorderSide(color: c.border, width: Strokes.hairline),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Gap.md),
          // Drag handle.
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: c.borderStrong,
              borderRadius: Radii.pill,
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Header for a sheet: title, optional supporting copy and a close button.
class CloseySheetHeader extends StatelessWidget {
  const CloseySheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showClose = true,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final bool showClose;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xxl, Gap.lg, Gap.md, Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Gap.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: Gap.xs + 2),
                  Text(
                    subtitle!,
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showClose)
            CloseyIconButton(
              icon: Icons.close_rounded,
              semanticLabel: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }
}

/// Confirmation dialog styled to match the app. Replaces the Expo app's use of
/// the platform `Alert.alert` for destructive confirms, which could not be
/// themed and looked foreign on Android.
Future<bool> showCloseyConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final c = context.colors;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        message,
        style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
      actions: [
        CloseyButton(
          label: cancelLabel,
          variant: CloseyButtonVariant.ghost,
          size: CloseyButtonSize.sm,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CloseyButton(
          label: confirmLabel,
          variant: destructive
              ? CloseyButtonVariant.danger
              : CloseyButtonVariant.primary,
          size: CloseyButtonSize.sm,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
