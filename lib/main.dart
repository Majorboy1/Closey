import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/firebase/firebase_bootstrap.dart';

/// Background message handler.
///
/// Must be a top-level function annotated with `@pragma('vm:entry-point')` —
/// Android runs it in a separate isolate where the Flutter binding does not yet
/// exist. Getting this wrong is the classic "works in the foreground, silently
/// drops every notification when backgrounded" bug.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Deliberately does nothing visible. The notification is composed by the
  // Cloud Function, which knows the sender's name and respects the recipient's
  // preferences.
  //
  // This is also where a private nudge must NEVER be surfaced: the spec forbids
  // leaking one through any notification channel.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only. The swipe deck and the chat composer are both designed for a
  // single orientation, and rotating produced a broken deck in the Expo build.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Boot Firebase before the first frame, so the router's redirect has a real
  // answer to work with instead of flashing the wrong screen.
  //
  // This never throws: `init()` returns a `BackendMode`, and when it cannot
  // reach Firebase the app routes to the setup screen. That is the difference
  // between a helpful first run and the Expo behaviour, which was a null error
  // somewhere inside the first network call.
  await FirebaseBootstrap.init();

  if (FirebaseBootstrap.isConfigured) {
    try {
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {
      // Notifications are optional; never block startup on them.
    }
  }

  runApp(const ProviderScope(child: _Bootstrap()));
}

/// Applies the system overlay style once, so status-bar icons stay legible in
/// both themes. The Expo app hardcoded `style="light"`, which would have made
/// the clock invisible against the light background it never actually shipped.
class _Bootstrap extends StatelessWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
      child: const CloseyApp(),
    );
  }
}
