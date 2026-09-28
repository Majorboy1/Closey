import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_motion.dart';
import '../../core/theme/closey_spacing.dart';
import '../../state/app_providers.dart';

/// The bottom navigation shell.
///
/// Navigation changes from the Expo app, which had five slots (Home, Connect,
/// a centre FAB, Chats, Profile) plus a sixth `plans` route registered with
/// `href: null` — unreachable from anywhere, along with the entire swipe deck
/// and match celebration.
///
/// * **Discover is the landing tab.** The end-to-end flow in the spec puts the
///   user on Discovery after onboarding; the old build dropped them on a social
///   feed instead.
/// * **Plans is reached contextually** from Chats and Profile rather than
///   occupying a tab. Plans are per-conversation, so surfacing them next to
///   conversations is better information architecture than a fifth icon.
/// * **Unread and likes badges are real** — driven by Firestore counters, not
///   by a list index as in the old `matches.tsx`.
/// * Every tab keeps its own stack and scroll position via
///   `StatefulShellRoute.indexedStack`.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final unread = ref.watch(totalUnreadProvider).value ?? 0;
    final likes = ref.watch(incomingLikesProvider).value ?? 0;

    // Discover (index 1) shows the likes badge, Chats (index 2) shows unread.
    final badges = <int, int>{1: likes, 2: unread};

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(color: colors.border, width: Strokes.hairline),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  selected: navigationShell.currentIndex == 0,
                  onTap: () => _go(0),
                ),
                _NavItem(
                  icon: Icons.local_fire_department_outlined,
                  activeIcon: Icons.local_fire_department_rounded,
                  label: 'Discover',
                  selected: navigationShell.currentIndex == 1,
                  badge: badges[1],
                  onTap: () => _go(1),
                ),
                _CreateButton(onTap: () => context.push(Routes.compose)),
                _NavItem(
                  icon: Icons.forum_outlined,
                  activeIcon: Icons.forum_rounded,
                  label: 'Chats',
                  selected: navigationShell.currentIndex == 2,
                  badge: badges[2],
                  onTap: () => _go(2),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'You',
                  selected: navigationShell.currentIndex == 3,
                  onTap: () => _go(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tapping the active tab pops that branch back to its root — the standard
  /// tab-bar affordance, and something the Expo build did not implement.
  void _go(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: badge != null && badge! > 0 ? '$label, $badge new' : label,
        child: InkWell(
          onTap: onTap,
          // 62px tall and full width, so every target clears the 48dp minimum
          // the old 10px-label tab bar did not guarantee.
          child: Stack(
            children: [
              // The active marker is a rule, not a colour swap. It is the same
              // device the profile spread and the coach's margin note use, and
              // it leaves the brand colour free for actions — which is what
              // brand means everywhere else in the app.
              Positioned(
                top: 0,
                left: Gap.lg,
                right: Gap.lg,
                child: AnimatedContainer(
                  duration: context.motion(Motion.quick),
                  curve: Motion.standard,
                  height: Strokes.thick,
                  color: selected ? colors.textPrimary : Colors.transparent,
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedSwitcher(
                        duration: context.motion(Motion.instant),
                        child: Icon(
                          selected ? activeIcon : icon,
                          key: ValueKey(selected),
                          size: 21,
                          // Ink for "you are here", not brand. Colour is reserved
                          // for things you can act on.
                          color: selected
                              ? colors.textPrimary
                              : colors.textTertiary,
                        ),
                      ),
                      if (badge != null && badge! > 0)
                        Positioned(
                          right: -7,
                          top: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17),
                            height: 17,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.brand,
                              borderRadius: Radii.pill,
                              border: Border.all(
                                color: colors.surface,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              badge! > 99 ? '99+' : '$badge',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: colors.textOnBrand,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    // Small caps in the same letterspaced style as every other
                    // label in the app, so the bar reads as part of the page rather
                    // than as chrome bolted underneath it.
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: selected
                          ? colors.textPrimary
                          : colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The centre create button. It keeps a visible label rather than reading as
/// decoration — the old FAB was an unlabelled `add` icon that pushed straight to
/// a full-screen route.
class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: 'Create a post',
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.pill,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.brand,
                  // A crisp rectangle rather than a pill: this is the one action
                  // in the bar, and squaring it makes it read as a button
                  // instead of as another tab.
                  borderRadius: Radii.allMd,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: colors.textOnBrand,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'CREATE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
