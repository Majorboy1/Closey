import 'package:flutter/material.dart';

import '../../core/theme/closey_colors.dart';
import '../../core/widgets/closey_logo.dart';

/// Startup splash.
///
/// The old build had no splash route at all: `index.tsx` rendered `null` while
/// the session resolved, so a cold start showed a blank coloured screen and
/// then snapped to a destination. This one holds the brand and cross-fades, and
/// because the router waits on `SessionStatus.unknown` it can never flash
/// onboarding at an existing user.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
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
          ],
        ),
      ),
    );
  }
}
