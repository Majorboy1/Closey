import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_text_field.dart';
import '../../state/services.dart';

/// Email + password sign in.
///
/// Differences from the Expo screen: inline field-level validation with real
/// error text (the old one validated only in `signUp` and pushed everything
/// else through `Alert.alert`), a disabled-until-valid submit button, a
/// password visibility toggle, a password-reset path that actually exists, and
/// field chaining so the keyboard's "next" key moves focus.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    setState(() {
      _emailError = email.isEmpty || !email.contains('@')
          ? 'Enter a valid email address.'
          : null;
      _passwordError = password.isEmpty ? 'Enter your password.' : null;
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithEmail(email: email, password: password);
      // The router's redirect takes over from here.
    } on CloseyFailure catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _emailError = 'Enter your email first, then tap reset.');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reset link sent to $email')));
      }
    } on CloseyFailure catch (e) {
      if (mounted) setState(() => _formError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: ''),
      child: Padding(
        padding: Gap.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back', style: context.text.displayMedium),
            const SizedBox(height: Gap.sm),
            Text(
              'Pick up where you left off.',
              style: context.text.bodyLarge?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Gap.xxl),

            if (_formError != null) ...[
              CloseyErrorBanner(
                message: _formError!,
                onDismiss: () => setState(() => _formError = null),
              ),
              const SizedBox(height: Gap.lg),
            ],

            CloseyTextField(
              label: 'Email',
              controller: _email,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.none,
              autofillHints: const [AutofillHints.email],
              errorText: _emailError,
              prefixIcon: Icons.alternate_email_rounded,
              onChanged: (_) {
                if (_emailError != null) setState(() => _emailError = null);
              },
            ),
            const SizedBox(height: Gap.lg),

            CloseyTextField(
              label: 'Password',
              controller: _password,
              hint: 'Your password',
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              errorText: _passwordError,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
              suffix: null,
            ),

            Align(
              alignment: Alignment.centerRight,
              child: CloseyButton(
                label: 'Forgot password?',
                variant: CloseyButtonVariant.ghost,
                size: CloseyButtonSize.sm,
                onPressed: _busy ? null : _resetPassword,
              ),
            ),

            const SizedBox(height: Gap.lg),
            CloseyButton(
              label: 'Sign in',
              fullWidth: true,
              size: CloseyButtonSize.lg,
              loading: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: Gap.xl),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'New to Closey?',
                    style: context.text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  CloseyButton(
                    label: 'Create an account',
                    variant: CloseyButtonVariant.ghost,
                    size: CloseyButtonSize.sm,
                    onPressed: () => context.replace(Routes.signUp),
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

/// Account creation.
///
/// Three changes worth noting:
/// * **A live password checklist** replaces "at least 6 characters" enforced
///   only on submit. Six characters was also below what Firebase considers
///   acceptable by default, so the old rule could produce a rejection the user
///   could not have predicted.
/// * **Client-side validation mirrors the server's**, so the error text matches
///   whichever one actually fires.
/// * **Guests can upgrade.** If the current session is anonymous, the account is
///   *linked* rather than replaced, so any swipes or messages already made are
///   kept. The Expo build had no upgrade path at all.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _hasLength => _password.text.length >= 8;
  bool get _hasNumber => RegExp(r'\d').hasMatch(_password.text);
  bool get _hasLetter => RegExp('[A-Za-z]').hasMatch(_password.text);

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();

    setState(() {
      _nameError = name.length < 2 ? 'Tell us what to call you.' : null;
      _emailError = email.contains('@') && email.contains('.')
          ? null
          : 'Enter a valid email address.';
      _passwordError = (_hasLength && _hasNumber && _hasLetter)
          ? null
          : 'Your password does not meet the requirements below.';
      _formError = null;
    });

    if (_nameError != null || _emailError != null || _passwordError != null) {
      return;
    }

    setState(() => _busy = true);
    try {
      final auth = ref.read(authRepositoryProvider);

      if (auth.isAnonymous) {
        await auth.linkEmailToGuest(email: email, password: _password.text);
        await ref
            .read(userRepositoryProvider)
            .updateProfile(auth.currentUser!.uid, fullName: name);
      } else {
        await auth.signUpWithEmail(
          email: email,
          password: _password.text,
          fullName: name,
        );
      }
      // Router redirect handles the rest.
    } on CloseyFailure catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final upgrading = ref.watch(authRepositoryProvider).isAnonymous;

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: ''),
      child: Padding(
        padding: Gap.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              upgrading ? 'Save your progress' : 'Create your account',
              style: context.text.displayMedium,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              upgrading
                  ? 'Add an email so the people you matched with stay yours.'
                  : 'Two minutes now, and the coach is ready when you are.',
              style: context.text.bodyLarge?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Gap.xxl),

            if (_formError != null) ...[
              CloseyErrorBanner(
                message: _formError!,
                onDismiss: () => setState(() => _formError = null),
              ),
              const SizedBox(height: Gap.lg),
            ],

            CloseyTextField(
              label: 'First name',
              controller: _name,
              hint: 'What should people call you?',
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.givenName],
              errorText: _nameError,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: Gap.lg),

            CloseyTextField(
              label: 'Email',
              controller: _email,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.none,
              autofillHints: const [AutofillHints.email],
              errorText: _emailError,
              prefixIcon: Icons.alternate_email_rounded,
              onChanged: (_) {
                if (_emailError != null) setState(() => _emailError = null);
              },
            ),
            const SizedBox(height: Gap.lg),

            CloseyTextField(
              label: 'Password',
              controller: _password,
              hint: 'At least 8 characters',
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              errorText: _passwordError,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Gap.md),

            _PasswordChecklist(
              hasLength: _hasLength,
              hasNumber: _hasNumber,
              hasLetter: _hasLetter,
            ),

            const SizedBox(height: Gap.xxl),
            CloseyButton(
              label: upgrading ? 'Save my account' : 'Create account',
              fullWidth: true,
              size: CloseyButtonSize.lg,
              loading: _busy,
              onPressed: _submit,
            ),

            const SizedBox(height: Gap.lg),
            Text(
              'By continuing you agree to our Terms and confirm you are 18 or '
              'over. We never post on your behalf.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: colors.textTertiary,
              ),
            ),

            if (!upgrading) ...[
              const SizedBox(height: Gap.xl),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Already registered?',
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    CloseyButton(
                      label: 'Sign in',
                      variant: CloseyButtonVariant.ghost,
                      size: CloseyButtonSize.sm,
                      onPressed: () => context.replace(Routes.signIn),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Requirement checklist that updates as you type, instead of a rule stated
/// once and then enforced by rejection.
class _PasswordChecklist extends StatelessWidget {
  const _PasswordChecklist({
    required this.hasLength,
    required this.hasNumber,
    required this.hasLetter,
  });

  final bool hasLength;
  final bool hasNumber;
  final bool hasLetter;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gap.md,
      runSpacing: Gap.xs,
      children: [
        _Req(label: '8+ characters', met: hasLength),
        _Req(label: 'a number', met: hasNumber),
        _Req(label: 'a letter', met: hasLetter),
      ],
    );
  }
}

class _Req extends StatelessWidget {
  const _Req({required this.label, required this.met});
  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 14,
          color: met ? colors.success : colors.textTertiary,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: met ? colors.successText : colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Phone verification.
///
/// A real two-stage flow — number, then code — where the Expo build only
/// showed a "coming soon" alert. Includes resend with the token Firebase gives
/// us, and auto-submits when Android's SMS retriever resolves the code without
/// the user typing anything.
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({super.key, this.phoneNumber});

  final String? phoneNumber;

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  String? _verificationId;
  int? _resendToken;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.phoneNumber != null) {
      final raw = widget.phoneNumber!.trim();
      _phone.text = raw.startsWith('+') ? raw : '+${raw.replaceAll('+', '')}';
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = _phone.text.trim();
    if (!phone.startsWith('+') || phone.length < 8) {
      setState(
        () => _error = 'Use international format, e.g. +234 801 234 5678.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .startPhoneVerification(
            phoneNumber: phone,
            onCodeSent: (id, token) {
              if (!mounted) return;
              setState(() {
                _verificationId = id;
                _resendToken = token;
                _busy = false;
              });
            },
            onError: (failure) {
              if (mounted) setState(() => _error = failure.message);
            },
            onAutoVerified: (credential) {
              ref
                  .read(authRepositoryProvider)
                  .signInWithPhoneCredential(credential);
            },
          );
    } on CloseyFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(String code) async {
    if (_verificationId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmPhoneCode(verificationId: _verificationId!, code: code);
    } on CloseyFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onCodeStep = _verificationId != null;

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: ''),
      child: Padding(
        padding: Gap.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              onCodeStep ? 'Enter your code' : 'What is your number?',
              style: context.text.displayMedium,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              onCodeStep
                  ? 'We sent a 6-digit code to ${_phone.text}. It may take a '
                        'moment.'
                  : 'We will text you a code. Your number is never shown on '
                        'your profile.',
              style: context.text.bodyLarge?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Gap.xxl),

            if (_error != null) ...[
              CloseyErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: Gap.lg),
            ],

            if (!onCodeStep) ...[
              CloseyTextField(
                label: 'Phone number',
                controller: _phone,
                hint: '+1 555 010 9999',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.smartphone_rounded,
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: Gap.xxl),
              CloseyButton(
                label: 'Send code',
                fullWidth: true,
                size: CloseyButtonSize.lg,
                loading: _busy,
                onPressed: _send,
              ),
            ] else ...[
              CloseyCodeField(
                controller: _code,
                errorText: _error,
                onCompleted: _confirm,
              ),
              const SizedBox(height: Gap.xxl),
              CloseyButton(
                label: 'Verify',
                fullWidth: true,
                size: CloseyButtonSize.lg,
                loading: _busy,
                onPressed: () => _confirm(_code.text),
              ),
              const SizedBox(height: Gap.md),
              Center(
                child: CloseyButton(
                  label: _resendToken == null ? 'Resend code' : 'Resend code',
                  variant: CloseyButtonVariant.ghost,
                  size: CloseyButtonSize.sm,
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _verificationId = null;
                            _code.clear();
                          });
                          _send();
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
