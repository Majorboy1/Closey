import 'package:flutter/material.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import 'closey_button.dart';

/// Page shell.
///
/// The Expo `Screen` component had a `scroll` prop that was **never used** —
/// children were always dropped into a plain `View`, so any screen that grew
/// past the viewport silently overflowed. Here scrolling is the default and
/// opting out is explicit.
class CloseyScaffold extends StatelessWidget {
  const CloseyScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.scrollable = true,
    this.padding,
    this.bottomBar,
    this.floatingActionButton,
    this.background,
    this.refreshIndicator,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final Color? background;
  final Future<void> Function()? refreshIndicator;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget body = child;
    if (scrollable) {
      body = SingleChildScrollView(
        padding:
            padding ??
            const EdgeInsets.fromLTRB(0, 0, 0, Gap.scrollBottomInset),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: child,
      );
    } else if (padding != null) {
      body = Padding(padding: padding!, child: child);
    }

    if (refreshIndicator != null) {
      body = RefreshIndicator(
        onRefresh: refreshIndicator!,
        color: c.brand,
        backgroundColor: c.surface,
        child: body is SingleChildScrollView
            ? body
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: body,
              ),
      );
    }

    return Scaffold(
      backgroundColor: background ?? c.background,
      appBar: appBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar,
      body: SafeArea(bottom: false, child: body),
    );
  }
}

/// App bar with two type roles:
/// * [title] — inline, 17px, for detail screens with a back button.
/// * [largeTitle] — Fraunces 30px, for top-level destinations, which scrolls
///   away. Sets the editorial tone the old flat 28px/900 sans titles never did.
class CloseyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CloseyAppBar({
    super.key,
    this.title,
    this.largeTitle,
    this.subtitle,
    this.leading,
    this.actions,
    this.showBack = true,
    this.bottom,
    this.floating = false,
  });

  final String? title;
  final String? largeTitle;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showBack;
  final PreferredSizeWidget? bottom;
  final bool floating;

  bool get _isLarge => largeTitle != null;

  @override
  Size get preferredSize {
    final base = _isLarge ? 96.0 : 60.0;
    return Size.fromHeight(base + (bottom?.preferredSize.height ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canPop = Navigator.of(context).canPop();

    return AppBar(
      backgroundColor: floating ? Colors.transparent : c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: _isLarge ? 68 : 60,
      automaticallyImplyLeading: false,
      leadingWidth: showBack && canPop ? 60 : 0,
      leading:
          leading ??
          (showBack && canPop
              ? Padding(
                  padding: const EdgeInsets.only(left: Gap.sm),
                  child: Center(
                    child: CloseyIconButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: 'Go back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                )
              : null),
      title: _isLarge
          ? null
          : (title != null
                ? Text(title!, style: context.text.titleLarge)
                : null),
      actions: [
        ...?actions,
        const SizedBox(width: Gap.sm),
      ],
      bottom: _isLarge
          ? PreferredSize(
              preferredSize: Size.fromHeight(
                34 +
                    (subtitle != null ? 22 : 0) +
                    (bottom?.preferredSize.height ?? 0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.page,
                      0,
                      Gap.page,
                      Gap.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(largeTitle!, style: context.text.displayMedium),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
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
                  if (bottom != null) ?bottom,
                ],
              ),
            )
          : bottom,
    );
  }
}

/// Sticky footer bar for wizard/sheet screens.
///
/// Adds the top hairline and a background scrim that the Expo onboarding
/// footer lacked, so content scrolling underneath never collides with the CTA.
class CloseyBottomBar extends StatelessWidget {
  const CloseyBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      Gap.page,
      Gap.md,
      Gap.page,
      Gap.md,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AnimatedContainer(
      duration: context.motion(Motion.quick),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(
          top: BorderSide(color: c.border, width: Strokes.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
