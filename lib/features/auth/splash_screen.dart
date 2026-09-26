import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/closey_colors.dart';
import '../../core/widgets/closey_logo.dart';
import '../../data/firebase/firebase_bootstrap.dart';
import '../../state/services.dart';

/// Startup splash.
///
/// The router holds here while `sessionStatusProvider` is `unknown`, so a
/// failure to resolve the session shows up as an indefinite splash rather than a
/// wrong screen — which is why this screen carries a temporary diagnostic
/// readout.
///
/// The readout can be deleted once the session reliably resolves. It answers a
/// question that could not be answered from outside the running app: whether the
/// auth stream is loading, errored, or resolving to null. The emulators logged
/// no incoming requests and the browser logged no failed ones, so the answer had
/// to come from inside.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  /// Set true to show a debug panel with session-resolution state.
  static const bool showDiagnostics = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    final auth = ref.watch(authStateProvider);
    final profile = ref.watch(currentUserProvider);
    final status = ref.watch(sessionStatusProvider);

    final authText = auth.isLoading
        ? 'auth: LOADING'
        : auth.hasError
        ? 'auth: ERROR ${auth.error}'
        : auth.value == null
        ? 'auth: null (signed out)'
        : 'auth: user ${auth.value!.uid}';

    final profileText = profile.isLoading
        ? 'profile: LOADING'
        : profile.hasError
        ? 'profile: ERROR ${profile.error}'
        : profile.value == null
        ? 'profile: null'
        : 'profile: ${profile.value!.fullName}';

    final watchdog = ref.watch(bootstrapWatchdogProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CloseyLogo(size: 88, animated: true),
              const SizedBox(height: 22),
              Text(
                'closey',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(colors.brand),
                ),
              ),

              if (showDiagnostics) ...[
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('mode: ${FirebaseBootstrap.mode.name}'),
                      Text('status: ${status.name}'),
                      Text('watchdog: $watchdog'),
                      Text(authText),
                      Text(profileText),
                      Text('init: ${FirebaseBootstrap.failure ?? "ok"}'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
