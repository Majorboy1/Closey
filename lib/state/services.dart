import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase/firebase_bootstrap.dart';
import '../data/models/app_user.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/billing_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/connection_repository.dart';
import '../data/repositories/discovery_repository.dart';
import '../data/repositories/meeting_repository.dart';
import '../data/repositories/safety_repository.dart';
import '../data/repositories/social_repository.dart';
import '../data/repositories/user_repository.dart';

/// Service locator.
///
/// Everything is a plain `Provider`, which means tests can override any single
/// repository with a fake via `ProviderScope(overrides: [...])` â€” no mocking
/// framework and no service-locator globals. The Expo app's `api.ts` was a
/// module of 48 free functions calling a module-level `supabase` singleton,
/// which made it untestable without network stubs.

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseBootstrap.functions,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(db: ref.watch(firestoreProvider)),
);

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => DiscoveryRepository(
    db: ref.watch(firestoreProvider),
    users: ref.watch(userRepositoryProvider),
  ),
);

final connectionRepositoryProvider = Provider<ConnectionRepository>(
  (ref) => ConnectionRepository(
    db: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  ),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(
    db: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  ),
);

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(
    db: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  ),
);

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepository(
    db: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  ),
);

final meetingRepositoryProvider = Provider<MeetingRepository>(
  (ref) => MeetingRepository(db: ref.watch(firestoreProvider)),
);

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => SocialRepository(db: ref.watch(firestoreProvider)),
);

// ---------------------------------------------------------------- session --

/// Raw Firebase auth user.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// The signed-in user's id, or null.
final uidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).value?.uid,
);

/// The signed-in user's Firestore profile, or null if there is no document yet.
///
/// This single stream is the app's source of truth for identity. Because it is
/// a `snapshots()` listener rather than a one-shot fetch, a Cloud Function
/// changing `verificationTier`, or a quota counter updating after a suggestion
/// is used, re-renders every dependent widget automatically. The Expo build
/// called `refreshProfile()` manually after each mutation and still drifted.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchUser(uid);
});

/// Convenience: the profile value, or null when loading or signed out.
final currentUserValueProvider = Provider<AppUser?>(
  (ref) => ref.watch(currentUserProvider).value,
);

/// True once we know whether the user is signed in *and* whether they have a
/// completed profile â€” the router uses this to choose between splash,
/// onboarding and the main app.
final sessionStatusProvider = Provider<SessionStatus>((ref) {
  final auth = ref.watch(authStateProvider);

  if (auth.isLoading) return SessionStatus.unknown;
  if (auth.hasError) return SessionStatus.signedOut;
  if (auth.value == null) return SessionStatus.signedOut;

  final profile = ref.watch(currentUserProvider);
  // Still waiting on the first Firestore snapshot â€” show the splash rather
  // than flashing the onboarding wizard at an existing user.
  if (profile.isLoading) return SessionStatus.unknown;

  final user = profile.value;
  if (user == null || !user.onboarded) return SessionStatus.needsOnboarding;

  return SessionStatus.ready;
});

enum SessionStatus { unknown, signedOut, needsOnboarding, ready }

/// Fires once if session resolution has not settled in reasonable time.
///
/// This exists because of a real bug: when `Firebase.initializeApp` succeeds but
/// its backend never responds — an emulator that is not running, no network —
/// the auth stream never emits, `sessionStatusProvider` stays `unknown`, and the
/// router holds `/` forever. The user sees the splash and nothing else, with no
/// indication of what went wrong.
///
/// Ten seconds is long enough that a slow-but-working connection never sees it,
/// and short enough that a broken one is explained rather than hung on.
final bootstrapWatchdogProvider = NotifierProvider<BootstrapWatchdog, bool>(
  BootstrapWatchdog.new,
);

class BootstrapWatchdog extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    // Already resolved? Never fire.
    final status = ref.watch(sessionStatusProvider);
    if (status != SessionStatus.unknown) return false;

    _timer = Timer(const Duration(seconds: 10), () {
      // Re-check: the stream may have settled while the timer was pending.
      if (ref.read(sessionStatusProvider) == SessionStatus.unknown) {
        state = true;
      }
    });

    ref.onDispose(() => _timer?.cancel());
    return false;
  }
}
