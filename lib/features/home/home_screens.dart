import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/theme/closey_typography.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_avatar.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_chip.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_surface.dart';
import '../../data/models/enums.dart';
import '../../data/models/post.dart';
import '../../state/app_providers.dart';
import '../../state/services.dart';

/// The social feed.
///
/// Rebuilt: the Expo version rendered a hardcoded `MOCK_FEED` constant, its
/// like button was local-only state, and "Create post" showed an alert. Likes
/// are now real (marker document + counter in a transaction, so a double-tap
/// cannot inflate the count) and posts persist.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserValueProvider);
    final feed = ref.watch(feedProvider);

    return CloseyScaffold(
      scrollable: false,
      appBar: CloseyAppBar(
        largeTitle: 'Home',
        subtitle: 'The people in your world.',
        showBack: false,
        actions: [
          if (me != null)
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: CloseyIconButton(
                icon: Icons.search_rounded,
                semanticLabel: 'Find people',
                onPressed: () => context.go(Routes.discover),
              ),
            ),
        ],
      ),
      child: Column(
        children: [
          CloseyFilterBar(
            tabs: const [
              CloseyFilterTab('For you'),
              CloseyFilterTab('Following'),
            ],
            selectedIndex: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: Gap.md),
          Padding(
            padding: Gap.pageInsets,
            child: _ComposerPrompt(
              name: me?.fullName ?? 'you',
              avatarUrl: me?.primaryPhoto,
              onTap: () => context.push(Routes.compose),
            ),
          ),
          const SizedBox(height: Gap.md),
          Expanded(
            child: feed.when(
              loading: () => const CloseySkeletonList(rows: 4),
              error: (e, _) => CloseyErrorState(
                message: e is CloseyFailure
                    ? e.message
                    : 'Could not load your feed.',
              ),
              data: (posts) {
                if (posts.isEmpty) {
                  return ListView(
                    children: [
                      CloseyEmptyState(
                        icon: Icons.article_outlined,
                        title: 'Nothing here yet',
                        message:
                            'Posts from the people you connect with show up '
                            'here. Start something with Discovery instead.',
                        actionLabel: 'Open Discover',
                        onAction: () => context.go(Routes.discover),
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: Gap.scrollBottomInset),
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
                  itemBuilder: (context, i) => PostCard(post: posts[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerPrompt extends StatelessWidget {
  const _ComposerPrompt({
    required this.name,
    required this.avatarUrl,
    required this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CloseyCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gap.md),
      child: Row(
        children: [
          CloseyAvatar(name: name, imageUrl: avatarUrl, size: 40),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.md,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: Radii.pill,
              ),
              child: Text(
                'Share something with your circle…',
                style: context.text.bodyMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A feed post.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _liked = false;
  int _likeCount = 0;
  bool _busy = false;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.likedByMe;
    _likeCount = widget.post.likeCount;
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt server state once, then never fight the local optimistic value.
    if (!_synced && widget.post.likedByMe != oldWidget.post.likedByMe) {
      _synced = true;
      _liked = widget.post.likedByMe;
      _likeCount = widget.post.likeCount;
    }
  }

  Future<void> _toggle() async {
    final uid = ref.read(uidProvider);
    if (uid == null || _busy) return;

    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
      _busy = true;
    });

    try {
      await ref
          .read(socialRepositoryProvider)
          .toggleLike(postId: widget.post.id, uid: uid);
    } catch (_) {
      // Roll back so the counter never lies.
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likeCount += _liked ? 1 : -1;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final author = widget.post.author;
    final name = author?.fullName ?? 'Someone';

    return Padding(
      padding: Gap.pageInsets,
      child: CloseyCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: [
                  CloseyAvatar(
                    name: name,
                    imageUrl: author?.primaryPhoto,
                    size: 42,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: context.text.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (author?.verificationTier.canUseCoach ??
                                false) ...[
                              const SizedBox(width: 4),
                              const CloseyBadge(
                                label: 'VERIFIED',
                                tone: CloseyBadgeTone.warning,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          _when(widget.post.createdAt),
                          style: context.text.bodySmall?.copyWith(
                            color: colors.textTertiary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.post.audience != PostAudience.everyone)
                    const CloseyBadge(
                      label: 'LIMITED',
                      tone: CloseyBadgeTone.neutral,
                      icon: Icons.lock_outline_rounded,
                    ),
                ],
              ),
            ),

            if (widget.post.body.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
                child: Text(widget.post.body, style: context.text.bodyLarge),
              ),

            if (widget.post.imageUrls.isNotEmpty)
              AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  widget.post.imageUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: colors.surfaceSunken),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: [
                  _Action(
                    icon: _liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: '$_likeCount',
                    color: _liked ? colors.brand : colors.textSecondary,
                    onTap: _toggle,
                    semanticLabel: _liked ? 'Unlike post' : 'Like post',
                  ),
                  const SizedBox(width: Gap.lg),
                  _Action(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '${widget.post.commentCount}',
                    onTap: null,
                  ),
                  const Spacer(),
                  _Action(
                    icon: Icons.send_outlined,
                    onTap: () => context.push(
                      Routes.publicProfile(widget.post.authorId),
                    ),
                    semanticLabel: 'Open profile',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime? date) {
    if (date == null) return 'Just now';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(date);
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    this.label,
    this.onTap,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color ?? colors.textSecondary),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: context.text.bodySmall?.copyWith(
                    color: color ?? colors.textSecondary,
                    fontWeight: FontWeight.w600,
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

/// Full-screen composer, with an audience picker the old build never had.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _controller = TextEditingController();
  PostAudience _audience = PostAudience.everyone;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final me = ref.read(currentUserValueProvider);
    final body = _controller.text.trim();
    if (me == null || body.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(socialRepositoryProvider)
          .createPost(author: me, body: body, audience: _audience);
      if (mounted) Navigator.of(context).pop();
    } on CloseyFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final me = ref.watch(currentUserValueProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        leading: CloseyIconButton(
          icon: Icons.close_rounded,
          onPressed: () => Navigator.of(context).maybePop(),
          semanticLabel: 'Close',
        ),
        title: Text('New post', style: context.text.titleLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.md),
            child: Center(
              child: CloseyButton(
                label: 'Post',
                size: CloseyButtonSize.sm,
                loading: _busy,
                onPressed: _controller.text.trim().isEmpty ? null : _post,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: Gap.pageInsets,
        children: [
          Row(
            children: [
              CloseyAvatar(
                name: me?.fullName ?? 'You',
                imageUrl: me?.primaryPhoto,
                size: 44,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  me?.fullName ?? 'You',
                  style: context.text.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Container(
            constraints: const BoxConstraints(minHeight: 160),
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: Radii.allLg,
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: _controller,
              maxLines: null,
              minLines: 6,
              maxLength: 1000,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: context.text.bodyLarge,
              cursorColor: colors.brand,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              decoration: InputDecoration(
                hintText: 'What is on your mind?',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
          Text('WHO CAN SEE THIS', style: context.eyebrow()),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: PostAudience.values
                .map(
                  (a) => CloseyChip(
                    label: a.label,
                    selected: _audience == a,
                    onTap: () => setState(() => _audience = a),
                    dense: true,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
