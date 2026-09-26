import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_palette.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_logo.dart';
import '../../core/widgets/closey_surface.dart';
import '../../data/firebase/firebase_bootstrap.dart';

/// Shown when Firebase could not be initialised.
///
/// This screen does not exist in the Expo app â€” a missing `EXPO_PUBLIC_SUPABASE_URL`
/// produced a null error somewhere inside the first network call, with no hint
/// about what was wrong. Here the app tells you exactly what to run.
class BackendSetupScreen extends StatelessWidget {
  const BackendSetupScreen({super.key});

  static const _steps = [
    (
      'Install the Firebase CLI and the FlutterFire CLI',
      'npm i -g firebase-tools\n'
          'dart pub global activate flutterfire_cli',
    ),
    (
      'Start the local emulator suite (zero cloud setup)',
      'firebase emulators:start --project demo-closey',
    ),
    (
      'Run the app against the emulators',
      'flutter run --dart-define=CLOSEY_EMULATOR=true',
    ),
    (
      'Or connect a real project instead',
      'flutterfire configure --project=<your-project-id>',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gap.page,
            Gap.xxxl,
            Gap.page,
            Gap.xxxl,
          ),
          children: [
            const Center(child: CloseyWordmark(fontSize: 30, logoSize: 34)),
            const SizedBox(height: Gap.xxl),

            Text('Backend not connected', style: context.text.displaySmall),
            const SizedBox(height: Gap.sm),
            Text(
              'Firebase did not initialise, so nothing can load yet. Pick one '
              'of the paths below — the emulator route needs no cloud account '
              'at all.',
              style: context.text.bodyLarge?.copyWith(
                color: colors.textSecondary,
              ),
            ),

            if (FirebaseBootstrap.failure != null) ...[
              const SizedBox(height: Gap.xl),
              CloseyCard(
                tinted: colors.dangerSoft,
                borderColor: colors.brandBorder,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: colors.danger,
                        ),
                        const SizedBox(width: Gap.sm),
                        Text(
                          'Reported error',
                          style: context.text.titleSmall?.copyWith(
                            color: colors.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    SelectableText(
                      '${FirebaseBootstrap.failure}',
                      style: context.text.bodySmall?.copyWith(
                        color: colors.danger,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: Gap.xxl),

            ..._steps.indexed.map((entry) {
              final (index, step) = entry;
              return Padding(
                padding: const EdgeInsets.only(bottom: Gap.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.brand,
                            borderRadius: Radii.pill,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: colors.textOnBrand,
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Text(step.$1, style: context.text.titleSmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    Padding(
                      padding: const EdgeInsets.only(left: 34),
                      child: _CommandBlock(command: step.$2),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: Gap.sm),
            CloseyCard(
              tinted: colors.accentSoft,
              borderColor: CloseyPalette.amber200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why the emulator first?',
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    'It gives you Auth, Firestore, Storage and Functions locally '
                    'in one process, so you can verify the whole product before '
                    'creating a real Firebase project. Run the seeder to load '
                    'demo profiles: dart run tool/seed_emulator.dart',
                    style: context.text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Gap.xxl),
            CloseyButton(
              label: 'I have connected it — try again',
              fullWidth: true,
              icon: Icons.refresh_rounded,
              onPressed: () => SystemNavigator.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Monospace command with a copy button.
class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.command});
  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: Radii.allSm,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: context.text.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colors.textPrimary,
                height: 1.6,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            iconSize: 17,
            color: colors.textSecondary,
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
          ),
        ],
      ),
    );
  }
}
