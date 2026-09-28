import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/closey_colors.dart';
import 'core/theme/closey_theme.dart';
import 'state/app_providers.dart';

/// The widest the app ever gets.
///
/// Above this the layout is centred rather than stretched. See the note in
/// [CloseyApp.build] for why a phone-shaped product wants this on a desktop.
const double kMaxAppColumnWidth = 440;

/// The application root.
///
/// Two things worth noting about the theme wiring:
///
/// * **`themeMode` is user-controlled** through `themeModeProvider`, defaulting
///   to `ThemeMode.system`. The Expo app declared `userInterfaceStyle: "light"`
///   in `app.json` while shipping a dark UI — a direct contradiction that
///   prevented the OS from ever applying a dark palette. Here both themes are
///   first-class and the setting is real.
/// * **Both themes are passed**, so there is no flash of the wrong palette on
///   launch and the transition animates through `CloseyColors.lerp`.
class CloseyApp extends ConsumerWidget {
  const CloseyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Closey',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: themeMode,
      theme: CloseyTheme.light(),
      darkTheme: CloseyTheme.dark(),

      // Respect the platform's text scaling, but clamp the extreme end so a
      // 2.0x setting cannot break the swipe deck or the chat header.
      //
      // The same builder constrains the app to a phone-shaped column. A dating
      // app stretched edge to edge across a desktop window is wrong in a way
      // that is hard to name: every layout was tuned against a 390pt phone, so
      // a wide viewport just makes the deck and the tab bar look inflated. A
      // centred column on a gradient frame is the Flutter equivalent of the UX
      // Architect's container system, and it costs nothing on a real phone
      // because the constraint only bites above the maximum width.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final c = context.colors;

        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.4,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: c.isDark
                    ? const [Color(0xFF0E0A16), Color(0xFF2A1545)]
                    : const [Color(0xFFFDE4EE), Color(0xFFEFE7FF)],
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kMaxAppColumnWidth,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}
