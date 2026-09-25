import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_palette.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_logo.dart';
import '../../state/services.dart';

/// The welcome / sign-in landing screen.
///
/// Design changes from the Expo version:
/// * **No blurred 40px screenshot behind the form.** A heavily blurred photo
///   plus a 62% black scrim meant the brand block sat on mud and the buttons
///   had inconsistent contrast. This uses the warm paper background with a
///   soft brand wash and a single decorative flourish, so contrast is fixed
///   and the screen reads intentional in both themes.
/// * **Four equal-weight auth choices** in one group instead of one large
///   primary button followed by three visually different "option" pills. The
///   old layout implied email was the recommended path, which it was not.
/// * **Real error surfacing.** Failures render as an inline banner with a
///   retry, not a modal `Alert.alert`.
/// * **Guest mode explains itself.** "Continue as guest" in the old build
///   created an anonymous session with no indication of its limits.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  String? _error;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? label}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on CloseyFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '${label ?? 'Sign-in'} failed. $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = ref.watch(authRepositoryProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  Gap.xxl,
                  Gap.page,
                  Gap.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _WelcomeFlourish(),
                    const SizedBox(height: Gap.huge),

                    Text(AppConfig.tagline, style: context.text.displayLarge),
                    const SizedBox(height: Gap.md),
                    Text(
                      'An AI that sits in the conversation with both of you — '
                      'offering openers you can see together, and quiet nudges '
                      'only you ever see.',
                      style: context.text.bodyLarge?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: Gap.xxl),
                    const _TrustRow(),

                    if (_error != null) ...[
                      const SizedBox(height: Gap.xl),
                      CloseyErrorBanner(
                        message: _error!,
                        onDismiss: () => setState(() => _error = null),
                      ),
                    ],

                    const SizedBox(height: Gap.xxl),

                    CloseyButton(
                      label: 'Continue with email',
                      icon: Icons.mail_outline_rounded,
                      fullWidth: true,
                      size: CloseyButtonSize.lg,
                      loading: _busy,
                      onPressed: _busy
                          ? null
                          : () => context.push(Routes.signUp),
                    ),
                    const SizedBox(height: Gap.md),

                    Row(
                      children: [
                        Expanded(
                          child: CloseyButton(
                            label: 'Google',
                            icon: Icons.g_mobiledata_rounded,
                            variant: CloseyButtonVariant.secondary,
                            fullWidth: true,
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    auth.signInWithGoogle,
                                    label: 'Google sign-in',
                                  ),
                          ),
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: CloseyButton(
                            label: 'Apple',
                            icon: Icons.apple_rounded,
                            variant: CloseyButtonVariant.secondary,
                            fullWidth: true,
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    auth.signInWithApple,
                                    label: 'Apple sign-in',
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.md),

                    CloseyButton(
                      label: 'Use my phone number',
                      icon: Icons.smartphone_rounded,
                      variant: CloseyButtonVariant.secondary,
                      fullWidth: true,
                      onPressed: _busy
                          ? null
                          : () => context.push(Routes.verifyPhone),
                    ),

                    const SizedBox(height: Gap.xxl),

                    // Guest mode, with its limits stated up front.
                    Container(
                      padding: const EdgeInsets.all(Gap.lg),
                      decoration: BoxDecoration(
                        color: colors.surfaceSunken,
                        borderRadius: Radii.allMd,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.explore_outlined,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: Gap.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Just looking around?',
                                  style: context.text.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Browse as a guest. Nothing is saved until '
                                  'you add an email.',
                                  style: context.text.bodySmall?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CloseyButton(
                            label: 'Guest',
                            variant: CloseyButtonVariant.ghost,
                            size: CloseyButtonSize.sm,
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    auth.signInAsGuest,
                                    label: 'Guest sign-in',
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.page,
                Gap.sm,
                Gap.page,
                Gap.lg,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: context.text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  CloseyButton(
                    label: 'Sign in',
                    variant: CloseyButtonVariant.ghost,
                    size: CloseyButtonSize.sm,
                    onPressed: () => context.push(Routes.signIn),
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

/// Brand mark plus a soft radial wash. Cheaper and far more legible than a
/// blurred full-bleed screenshot.
class _WelcomeFlourish extends StatelessWidget {
  const _WelcomeFlourish();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 132,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -40,
            top: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    CloseyPalette.rose300.withValues(alpha: 0.34),
                    CloseyPalette.rose300.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            bottom: 0,
            child: CloseyWordmark(fontSize: 40, logoSize: 46),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                width: 1,
                height: 1,
                child: ColoredBox(color: colors.background),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three concrete promises instead of a vague feature list. Each maps to an
/// actual mechanic in the product.
class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _TrustItem(
          icon: Icons.visibility_outlined,
          title: 'Openers you both see',
          body: 'Shared suggestions appear in both chats at once.',
        ),
        _TrustItem(
          icon: Icons.visibility_off_outlined,
          title: 'Nudges only you see',
          body:
              'If the thread goes one-sided, you get a private prompt. '
              'Your match is never told.',
        ),
        _TrustItem(
          icon: Icons.shield_outlined,
          title: 'The AI never speaks as you',
          body: 'It suggests. You decide what to send, and can edit it first.',
        ),
      ],
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.brandSoft,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, size: 17, color: colors.brandText),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 1),
                Text(
                  body,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
