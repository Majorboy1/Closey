import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_avatar.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_chip.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/models/connection.dart';
import '../../state/app_providers.dart';
import '../../state/services.dart';

/// The Chats tab.
///
/// Rebuilt from `matches.tsx`, which rendered fake previews, timestamps chosen
/// by list index, and unread badges derived from the row number. Now: real last
/// messages, real per-member unread counters, real pending requests.
///
/// Friend threads are visually separated from metered DMs because that
/// distinction is the app's growth loop â€” friends get unlimited chat, and the
/// list should make the upgrade path obvious.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  int _tab = 0;
  bool _initialisedTab = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uid = ref.watch(uidProvider);
    final connections = ref.watch(chatListProvider);
    final requests = ref.watch(incomingRequestsProvider);

    final all = connections.value ?? const <Connection>[];
    final pending = requests.value ?? const [];

    // Land on Requests when there is something waiting â€” the one thing on this
    // screen that actually needs a decision.
    if (!_initialisedTab && pending.isNotEmpty) {
      _initialisedTab = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tab = 2);
      });
    }

    final showFriendsOnly = _tab == 1;
    final showRequestsOnly = _tab == 2;

    return CloseyScaffold(
      scrollable: false,
      appBar: CloseyAppBar(
        largeTitle: 'Chats',
        subtitle: pending.isNotEmpty
            ? '${pending.length} waiting on you'
            : 'Everyone you have matched with.',
        showBack: false,
        actions: [
          IconButton(
            tooltip: 'Meetups',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push(Routes.plans),
          ),
        ],
      ),
      child: Column(
        children: [
          CloseyFilterBar(
            tabs: [
              const CloseyFilterTab('All'),
              const CloseyFilterTab('Friends'),
              CloseyFilterTab('Requests', badge: pending.length),
            ],
            selectedIndex: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: Gap.md),
          Expanded(
            child: connections.when(
              loading: () => const CloseySkeletonList(rows: 6),
              error: (e, _) => CloseyErrorState(
                message: e is CloseyFailure
                    ? e.message
                    : 'Could not load your conversations.',
              ),
              data: (_) {
                final rows = <Widget>[
                  if (!showFriendsOnly)
                    ...pending.map(
                      (r) => _RequestRow(
                        request: r,
                        onOpen: () {
                          final sender = r.sender;
                          if (sender != null) {
                            context.push(Routes.publicProfile(sender.id));
                          }
                        },
                      ),
                    ),
                  if (!showRequestsOnly)
                    ...all
                        .where((c) => !showFriendsOnly || c.isFriend)
                        .map(
                          (c) => _ConnectionRow(
                            connection: c,
                            uid: uid,
                            onOpen: () => context.push(Routes.chat(c.id)),
                          ),
                        ),
                ];

                if (rows.isEmpty) {
                  return ListView(
                    children: [
                      CloseyEmptyState(
                        icon: showRequestsOnly
                            ? Icons.mark_email_unread_outlined
                            : Icons.forum_outlined,
                        title: showRequestsOnly
                            ? 'No requests waiting'
                            : 'No conversations yet',
                        message: showRequestsOnly
                            ? 'Friend requests you receive will appear here.'
                            : 'Swipe right on someone in Discover, or add '
                                  'someone as a friend. When you match, the '
                                  'coach drafts an opener you can both see.',
                        actionLabel: showRequestsOnly ? null : 'Open Discover',
                        onAction: showRequestsOnly
                            ? null
                            : () => context.go(Routes.discover),
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: Gap.scrollBottomInset),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, indent: 84, color: colors.border),
                  itemBuilder: (_, i) => rows[i],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends ConsumerStatefulWidget {
  const _RequestRow({required this.request, required this.onOpen});

  final dynamic request;
  final VoidCallback onOpen;

  @override
  ConsumerState<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends ConsumerState<_RequestRow> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(connectionRepositoryProvider)
          .respondToFriendRequest(
            requestId: widget.request.id as String,
            accept: accept,
          );
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
    final sender = widget.request.sender as AppUser?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.md),
      child: CloseyCard(
        tinted: colors.brandSoft,
        borderColor: colors.brandBorder,
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          children: [
            CloseyAvatar(
              name: sender?.fullName ?? 'Someone',
              imageUrl: sender?.primaryPhoto,
              size: 48,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: GestureDetector(
                onTap: widget.onOpen,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sender?.fullName ?? 'Someone',
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Wants to connect · unlimited free chat',
                      style: context.text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            CloseyButton(
              label: 'Accept',
              size: CloseyButtonSize.sm,
              loading: _busy,
              onPressed: () => _respond(true),
            ),
            const SizedBox(width: Gap.xs),
            CloseyIconButton(
              icon: Icons.close_rounded,
              size: 38,
              iconSize: 18,
              semanticLabel: 'Decline request',
              onPressed: _busy ? null : () => _respond(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.connection,
    required this.uid,
    required this.onOpen,
  });

  final Connection connection;
  final String? uid;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final other = connection.otherUser(uid ?? '');
    final unread = connection.unreadFor(uid ?? '');
    final isFriend = connection.isFriend;

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.page,
          vertical: Gap.md,
        ),
        child: Row(
          children: [
            CloseyAvatar(
              name: other.fullName,
              imageUrl: other.primaryPhoto,
              size: 56,
              showPresence: true,
              online: other.online,
              ringColor: isFriend ? colors.success : null,
              ringWidth: 2.5,
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          other.fullName,
                          style: context.text.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isFriend) ...[
                        const SizedBox(width: Gap.sm),
                        const CloseyBadge(
                          label: 'FRIEND',
                          tone: CloseyBadgeTone.success,
                          icon: Icons.handshake_outlined,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    connection.lastMessage ?? 'You matched — say hello.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: unread > 0
                          ? colors.textPrimary
                          : colors.textTertiary,
                      fontWeight: unread > 0
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _relative(connection.lastMessageAt ?? connection.createdAt),
                  style: context.text.bodySmall?.copyWith(
                    fontSize: 11,
                    color: colors.textTertiary,
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(height: Gap.sm),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.brand,
                      borderRadius: Radii.pill,
                    ),
                    child: Text(
                      '$unread',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: colors.textOnBrand,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Compact relative time: 2m, 1h, 3d, then a date.
  static String _relative(DateTime? when) {
    if (when == null) return '';
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat.MMMd().format(when);
  }
}
