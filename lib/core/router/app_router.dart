import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screens.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chats/chats_screen.dart';
import '../../features/discover/discover_screen.dart';
import '../../features/discover/likes_you_screen.dart';
import '../../features/home/home_screens.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/plans/plans_screen.dart';
import '../../features/profile/profile_screens.dart';
import '../../features/settings/settings_screens.dart';
import '../../features/shell/app_shell.dart';
import '../../features/system/backend_setup_screen.dart';
import '../../data/firebase/firebase_bootstrap.dart';
import '../../state/services.dart';

/// Routes.
///
/// Replaces Expo Router's file-based tree. The important structural change is
/// [StatefulShellRoute.indexedStack]: each tab keeps its own navigation stack
/// and its own scroll position. The Expo version used `Stack.Protected` on a
/// flat stack, so switching tabs destroyed the previous tab's scroll offset and
/// any in-progress form.
abstract final class Routes {
  static const splash = '/';
  static const backendSetup = '/backend-setup';

  // Auth
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const verifyPhone = '/verify-phone';

  // Onboarding
  static const onboarding = '/onboarding';

  // Shell tabs
  static const home = '/home';
  static const discover = '/discover';
  static const compose = '/compose';
  static const chats = '/chats';
  static const profile = '/profile';

  // Pushed routes
  static const likes = '/likes';
  static const plans = '/plans';
  static const paywall = '/paywall';
  static const settings = '/settings';
  static const editProfile = '/edit-profile';
  static const blocked = '/blocked';
  static const verification = '/verification';

  static String chat(String connectionId) => '/chat/$connectionId';
  static String publicProfile(String userId) => '/user/$userId';
  static String report(String userId) => '/report/$userId';
}

final routerProvider = Provider<GoRouter>((ref) {
  // go_router needs a `Listenable` to re-evaluate redirects. Rather than
  // rebuilding the router (which would lose every tab's state), we bump a
  // notifier whenever the session changes so `redirect` runs again.
  final refresh = _RouterRefreshNotifier(ref);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final location = state.matchedLocation;

      // Backend not connected: every route funnels to the setup screen, which
      // explains exactly what to run. Previously a missing Supabase env var
      // surfaced as a null-crash inside the first network call.
      if (!FirebaseBootstrap.isConfigured) {
        return location == Routes.backendSetup ? null : Routes.backendSetup;
      }

      final status = ref.read(sessionStatusProvider);
      final onAuthRoute =
          location == Routes.welcome ||
          location == Routes.signIn ||
          location == Routes.signUp ||
          location == Routes.verifyPhone;
      final onSplash = location == Routes.splash;
      final onOnboarding = location == Routes.onboarding;

      return switch (status) {
        // Still resolving — hold on the splash so we never flash onboarding at
        // an existing user or the deck at a signed-out one. But if it stays
        // unresolved past the watchdog, say so instead of hanging.
        SessionStatus.unknown =>
          ref.read(bootstrapWatchdogProvider)
              ? Routes.backendSetup
              : (onSplash ? null : Routes.splash),

        SessionStatus.signedOut => onAuthRoute ? null : Routes.welcome,

        SessionStatus.needsOnboarding =>
          onOnboarding ? null : Routes.onboarding,

        SessionStatus.ready =>
          (onAuthRoute || onSplash || onOnboarding) ? Routes.discover : null,
      };
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.backendSetup,
        builder: (context, state) => const BackendSetupScreen(),
      ),

      // ------------------------------------------------------------- auth --
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.verifyPhone,
        builder: (context, state) =>
            VerifyPhoneScreen(phoneNumber: state.uri.queryParameters['phone']),
      ),

      // -------------------------------------------------------- onboarding --
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 260),
        ),
      ),

      // ---------------------------------------------------------- the shell --
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.discover,
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.chats,
                builder: (context, state) => const ChatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // --------------------------------------------------------- the rest --
      GoRoute(
        path: Routes.compose,
        pageBuilder: (context, state) =>
            const MaterialPage(fullscreenDialog: true, child: ComposeScreen()),
      ),
      GoRoute(
        path: Routes.likes,
        builder: (context, state) => const LikesYouScreen(),
      ),
      GoRoute(
        path: Routes.plans,
        builder: (context, state) => const PlansScreen(),
      ),
      GoRoute(
        path: Routes.paywall,
        builder: (context, state) =>
            PaywallScreen(reason: state.uri.queryParameters['reason']),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: Routes.blocked,
        builder: (context, state) => const BlockedScreen(),
      ),
      GoRoute(
        path: Routes.verification,
        builder: (context, state) => const VerificationScreen(),
      ),
      GoRoute(
        path: '/chat/:connectionId',
        builder: (context, state) =>
            ChatScreen(connectionId: state.pathParameters['connectionId']!),
      ),
      GoRoute(
        path: '/user/:userId',
        builder: (context, state) =>
            PublicProfileScreen(userId: state.pathParameters['userId']!),
      ),
      GoRoute(
        path: '/report/:userId',
        builder: (context, state) => ReportScreen(
          reportedUserId: state.pathParameters['userId']!,
          contextLabel: state.uri.queryParameters['from'] ?? 'profile',
        ),
      ),
    ],
    errorBuilder: (context, state) =>
        _RouteNotFound(location: state.uri.toString()),
  );

  ref.onDispose(refresh.dispose);
  return router;
});

/// Bridges Riverpod state changes into a `Listenable` for go_router.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    // Any of these changing can flip where the user should be.
    _subs.add(
      ref.listen<AsyncValue<Object?>>(
        authStateProvider,
        (_, _) => notifyListeners(),
      ),
    );
    _subs.add(
      ref.listen<AsyncValue<Object?>>(
        currentUserProvider,
        (_, _) => notifyListeners(),
      ),
    );
    // The watchdog tripping is itself a reason to re-evaluate the redirect.
    _subs.add(
      ref.listen<bool>(bootstrapWatchdogProvider, (_, _) => notifyListeners()),
    );
  }

  /// `Object?` rather than a specific value type, because the list holds
  /// subscriptions to providers of different shapes.
  final List<ProviderSubscription<Object?>> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    super.dispose();
  }
}

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Page not found'),
              const SizedBox(height: 8),
              Text(location, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.go(Routes.discover),
                child: const Text('Back to Discover'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
