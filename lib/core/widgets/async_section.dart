import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import 'closey_button.dart';

/// One loading/empty/error system for the whole app.
///
/// The Expo build handled these three states inconsistently: some screens used
/// a bare `ActivityIndicator` on a full-screen background, some showed nothing
/// at all while loading, empty states were ad-hoc strings, and errors were
/// pushed into `Alert.alert` — which is modal, blocking, and loses context.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.value,
    required this.builder,
    this.loading,
    this.empty,
    this.sliver = false,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext, T) builder;

  /// Custom skeleton matching the eventual content's shape.
  final Widget? loading;
  final Widget? empty;
  final bool sliver;

  @override
  Widget build(BuildContext context) {
    final child = value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (data) => builder(context, data),
      loading: () => loading ?? const CloseySkeletonList(),
      error: (error, stack) => CloseyErrorState(
        message: error is CloseyFailure
            ? error.message
            : 'Something went wrong on our end.',
        onRetry: null,
      ),
    );

    if (!sliver) return child;
    return SliverToBoxAdapter(child: child);
  }
}

/// A typed failure so the UI can show the user a sentence, not a stack trace.
class CloseyFailure implements Exception {
  const CloseyFailure(this.message, {this.code, this.isRetryable = true});

  final String message;
  final String? code;
  final bool isRetryable;

  @override
  String toString() => message;
}

/// Shimmer block — used to build content-shaped skeletons.
class CloseySkeleton extends StatelessWidget {
  const CloseySkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = Radii.xs,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = context.reduceMotion;

    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.skeleton,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (reduce) return box;

    return Shimmer.fromColors(
      baseColor: c.skeleton,
      highlightColor: Color.lerp(c.skeleton, c.surface, 0.55)!,
      period: Motion.loop,
      child: box,
    );
  }
}

/// Skeleton shaped like the chat/matches cards, so the layout does not jump
/// when real content arrives.
class CloseySkeletonList extends StatelessWidget {
  const CloseySkeletonList({super.key, this.rows = 5, this.showAvatar = true});

  final int rows;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.page,
        vertical: Gap.md,
      ),
      child: Column(
        children: List.generate(
          rows,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: Gap.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAvatar) ...[
                  const CloseySkeleton(width: 52, height: 52, radius: 26),
                  const SizedBox(width: Gap.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CloseySkeleton(
                        width: (120 + (i % 3) * 40).toDouble(),
                        height: 13,
                      ),
                      const SizedBox(height: Gap.sm + 2),
                      const CloseySkeleton(height: 11),
                      const SizedBox(height: Gap.sm),
                      CloseySkeleton(
                        width: (180 - (i % 2) * 40).toDouble(),
                        height: 11,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state with an optional action. Every list in the app uses this so
/// "nothing here yet" always looks intentional.
class CloseyEmptyState extends StatelessWidget {
  const CloseyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Gap.xxxl,
        vertical: compact ? Gap.xxl : Gap.giant,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: c.brandText),
          ),
          const SizedBox(height: Gap.xl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.titleMedium,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: Gap.xl),
            CloseyButton(
              label: actionLabel!,
              onPressed: onAction,
              size: CloseyButtonSize.sm,
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline error state — non-modal, always offers a retry when possible.
class CloseyErrorState extends StatelessWidget {
  const CloseyErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.all(compact ? Gap.lg : Gap.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.dangerSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_off_rounded, size: 24, color: c.danger),
          ),
          const SizedBox(height: Gap.lg),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: Gap.lg),
            CloseyButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              variant: CloseyButtonVariant.secondary,
              size: CloseyButtonSize.sm,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline, dismissible error banner for transient failures. Preferred over
/// `Alert.alert` for anything the user can simply retry.
class CloseyErrorBanner extends StatelessWidget {
  const CloseyErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AnimatedSize(
      duration: context.motion(Motion.quick),
      curve: Motion.standard,
      child: Container(
        margin: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.md),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          color: c.dangerSoft,
          borderRadius: Radii.allMd,
          border: Border.all(color: c.brandBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.danger),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                message,
                style: context.text.bodySmall?.copyWith(color: c.danger),
              ),
            ),
            if (onRetry != null)
              GestureDetector(
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                  child: Text(
                    'Retry',
                    style: context.text.labelMedium?.copyWith(color: c.danger),
                  ),
                ),
              ),
            if (onDismiss != null)
              GestureDetector(
                onTap: onDismiss,
                child: Icon(Icons.close_rounded, size: 17, color: c.danger),
              ),
          ],
        ),
      ),
    );
  }
}
