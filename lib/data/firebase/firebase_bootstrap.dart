import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';

/// Where the app's data is coming from.
enum BackendMode {
  /// A real Firebase project, configured via `flutterfire configure`.
  live,

  /// The Firebase Local Emulator Suite, against project `demo-closey`.
  emulator,

  /// Firebase could not be initialised. The UI still runs, and every screen
  /// that needs data shows an explanatory state instead of crashing.
  offline,
}

/// Boots Firebase and exposes the service handles.
///
/// Design goal: **`flutter run` should never crash on a fresh clone.** If
/// `firebase_options.dart` has not been generated yet, we fall back to the
/// emulator project id rather than throwing from `main()`, and if that is not
/// reachable the app degrades to [BackendMode.offline] with a route that
/// explains how to connect a project. The Expo app had no such path — it read
/// `EXPO_PUBLIC_SUPABASE_URL` and would throw a null error deep in the first
/// network call, with no indication of what was missing.
abstract final class FirebaseBootstrap {
  static BackendMode mode = BackendMode.offline;
  static Object? failure;

  /// Set `CLOSEY_EMULATOR=true` (or pass `--dart-define=CLOSEY_EMULATOR=true`).
  static const bool _preferEmulator = bool.fromEnvironment('CLOSEY_EMULATOR');

  /// Emulator host. `10.0.2.2` is the Android emulator's alias for the host
  /// machine — a detail that trips up almost everyone the first time.
  static String get emulatorHost {
    const configured = String.fromEnvironment('CLOSEY_EMULATOR_HOST');
    if (configured.isNotEmpty) return configured;
    return defaultTargetPlatform == TargetPlatform.android && !kIsWeb
        ? '10.0.2.2'
        : 'localhost';
  }

  static FirebaseFirestore get db => FirebaseFirestore.instance;
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static bool get isConfigured => mode != BackendMode.offline;

  static Future<BackendMode> init() async {
    if (!AppConfig.preferLiveBackend) {
      mode = BackendMode.offline;
      return mode;
    }

    try {
      await Firebase.initializeApp(options: FirebaseOptionsHolder.current);

      // Either the developer asked for the emulator, or this checkout has not
      // been connected to a real project yet. Both mean: use the emulator.
      if (_preferEmulator || !FirebaseOptionsHolder.isRealProject) {
        _connectEmulators();
        mode = BackendMode.emulator;
      } else {
        mode = BackendMode.live;
      }

      _configureSettings();
      return mode;
    } catch (error) {
      failure = error;
      mode = BackendMode.offline;
      debugPrint('Closey: Firebase unavailable → offline mode ($error)');
      return mode;
    }
  }

  static void _configureSettings() {
    // Offline persistence is a mobile/desktop feature. On web the Firestore SDK
    // uses an in-memory cache and **rejects** `persistenceEnabled: true`, which
    // throws out of this method. That mattered: this runs after the emulator
    // wiring, so a throw here used to abort initialisation and leave the app
    // unable to reach any backend at all.
    if (kIsWeb) return;

    try {
      db.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      // Settings are an optimisation, never a reason to fail startup.
      debugPrint('Closey: could not apply Firestore settings ($e)');
    }
  }

  static void _connectEmulators() {
    const firestorePort = 8080;
    const authPort = 9099;
    const functionsPort = 5001;
    const storagePort = 9199;

    // Each connection is isolated, so one failure cannot prevent the others.
    // Previously these were sequential in a single try block: if the emulator
    // wiring for one service threw, auth was never pointed at the emulator and
    // the session stream could never resolve.
    _attempt('firestore', () => db.useFirestoreEmulator(emulatorHost, firestorePort));
    _attempt('auth', () => auth.useAuthEmulator(emulatorHost, authPort));
    _attempt('storage', () => storage.useStorageEmulator(emulatorHost, storagePort));
    _attempt('functions', () {
      FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).useFunctionsEmulator(emulatorHost, functionsPort);
    });

    debugPrint('Closey: emulators configured for $emulatorHost');
  }

  static void _attempt(String service, void Function() connect) {
    try {
      connect();
    } catch (e) {
      debugPrint('Closey: could not connect the $service emulator ($e)');
    }
  }

  static Future<void> signOutLocal() async {
    if (isConfigured) await auth.signOut();
  }
}

/// Holds the `FirebaseOptions` used to boot.
///
/// `flutterfire configure` overwrites this file's [current] value with real
/// credentials. Keeping it as a hand-written class rather than the generated
/// `DefaultFirebaseOptions` means the project still compiles before that step —
/// which is the difference between "clone and run" and "clone and read a
/// 40-step setup doc first".
abstract final class FirebaseOptionsHolder {
  static const FirebaseOptions emulatorProject = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-closey',
    storageBucket: 'demo-closey.appspot.com',

    // Required on web. Without `authDomain` the JS SDK's auth component cannot
    // initialise, and `authStateChanges()` never emits — which leaves the app
    // stuck on the splash screen forever, because session resolution never
    // settles. The emulator overrides the actual endpoint via
    // `useAuthEmulator`, but the field still has to be present.
    authDomain: 'demo-closey.firebaseapp.com',

    androidClientId: 'demo-android-client',
    iosClientId: 'demo-ios-client',
  );

  /// Replace with `DefaultFirebaseOptions.currentPlatform` after running
  /// `flutterfire configure`. Leaving the demo value is safe: the app then
  /// talks to the emulator instead of production.
  static FirebaseOptions get current => emulatorProject;

  static bool get isRealProject =>
      current.projectId != emulatorProject.projectId;
}
