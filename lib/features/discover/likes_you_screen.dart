import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/closey_avatar.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_surface.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/async_section.dart';
import '../../state/app_providers.dart';
import '../../core/router/app_router.dart';
import 'package:go_router/go_router.dart';

/// People who already liked you.
///
/// New screen. The old build had no "likes you" surface at all, even though
/// `listMutualLikes` existed — so an incoming like was invisible until it
/// happened to match. Showing it converts far better than a blind deck, and
/// because we know they are interested, the copy can say so.
class LikesYouScreen extends ConsumerWidget {
  const LikesYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likesYouProvider);

    return CloseyScaffold(
      scrollable: false,
      appBar: const CloseyAppBar(title: 'Likes you'),
      child: AsyncSection(
        value: likes,
        loading: const CloseySkeletonList(rows: 6),
        builder: (context, users) {
          if (users.isEmpty) {
            return const CloseyEmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'No likes yet',
              message:
                  'When someone swipes right on you, they will show up here '
                  'before you have even seen them.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.sm,
              Gap.page,
              Gap.scrollBottomInset,
            ),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gap.md),
            itemBuilder: (context, i) {
              final user = users[i];
              return CloseyCard(
                padding: const EdgeInsets.all(Gap.md),
                onTap: () => context.push(Routes.publicProfile(user.id)),
                child: Row(
                  children: [
                    CloseyAvatar(
                      name: user.fullName,
                      imageUrl: user.primaryPhoto,
                      size: 56,
                      ringColor: context.colors.brandBorder,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.fullName, style: context.text.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Already likes you',
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.brandText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CloseyButton(
                      label: 'View',
                      size: CloseyButtonSize.sm,
                      variant: CloseyButtonVariant.tonal,
                      onPressed: () =>
                          context.push(Routes.publicProfile(user.id)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
