import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_avatar.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_margin_note.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_sheet.dart';
import '../../core/widgets/closey_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/models/chat.dart';
import '../../data/models/connection.dart';
import '../../data/models/enums.dart';
import '../../data/models/quota.dart';
import '../../data/repositories/chat_repository.dart';
import '../../state/app_providers.dart';
import '../../state/services.dart';

/// Chat with the shared AI coach.
///
/// The single most important screen in the product, and the one with the most
/// deliberate design decisions:
///
/// 1. **The coach is a hand in the margin, not a third participant.** Notes
///    render indented and unfilled, in italic serif, with a rule to their left
///    — see [CloseyMarginNote]. The previous design gave the coach the same
///    surface, radius and type as a message, so it read as somebody having
///    joined the thread.
/// 2. **Private nudges are marked rather than coloured.** A dashed rule, a
///    label reading "only you see this", and no quota counter. The dash is the
///    entire difference, deliberately: the privacy promise is the product.
/// 3. **"Use this" fills the composer instead of sending.** The spec's open
///    question §12 was whether to auto-send; auto-sending violates the stated
///    guardrail that the AI never speaks as you. The user edits, then sends.
/// 4. **The coach explains itself.** Every card carries the reason it fired
///    ("one person answered without asking back"), because an unexplained
///    interruption feels like being graded.
/// 5. **A quiet period is visible.** When the coach has spoken recently the
///    request button says so, so nobody wonders why nothing is happening.
/// 6. **Messages are optimistic.** Firestore's local write shows the bubble
///    instantly with a "sending" tick; the old chat waited for the realtime
///    round trip and looked broken on a slow connection.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  bool _sending = false;
  bool _requestingCoach = false;
  bool _markedRead = false;
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animated) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  Future<void> _send({
    String? overrideText,
    bool fromSuggestion = false,
  }) async {
    final uid = ref.read(uidProvider);
    final connection = ref.read(connectionProvider(widget.connectionId)).value;
    final text = (overrideText ?? _controller.text).trim();
    if (uid == null || connection == null || text.isEmpty) return;

    _controller.clear();
    setState(() => _sending = true);

    try {
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            connectionId: widget.connectionId,
            senderId: uid,
            recipientId: connection.otherId(uid),
            body: text,
            sentFromSuggestion: fromSuggestion,
          );

      // The server no-ops unless the other member is simulated, so there is
      // nothing to branch on here. Not awaited: the reply arrives through the
      // normal message listener, which is what gives it the same latency and
      // ordering as a real one.
      ref
          .read(chatRepositoryProvider)
          .simulatePartnerReply(widget.connectionId)
          .ignore();

      _scrollToBottom();
    } on CloseyFailure catch (e) {
      if (mounted) {
        // Put the text back so nothing is lost.
        _controller.text = text;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _askCoach() async {
    setState(() => _requestingCoach = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .requestSuggestion(connectionId: widget.connectionId);
      _scrollToBottom();
    } on CloseyFailure catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'QUOTA_EXCEEDED':
          context.push('${Routes.paywall}?reason=quota');
        case 'VERIFICATION_REQUIRED':
          context.push(Routes.verification);
        case 'FUNCTIONS_UNAVAILABLE':
          _insertLocalFallback();
        default:
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _requestingCoach = false);
    }
  }

  /// When Cloud Functions are not deployed yet, still give the user a usable
  /// card so the UI is explorable. Clearly local, and no API key involved.
  void _insertLocalFallback() {
    final other = ref
        .read(
          profileByIdProvider(
            ref
                    .read(connectionProvider(widget.connectionId))
                    .value
                    ?.otherId(ref.read(uidProvider) ?? '') ??
                '',
          ),
        )
        .value;
    final me = ref.read(currentUserValueProvider);
    final shared = ChatRepositoryShared.interests(me, other);

    final suggestion = ref
        .read(chatRepositoryProvider)
        .localFallbackSuggestion(
          connectionId: widget.connectionId,
          sharedInterests: shared,
          type: SuggestionType.opener,
          requestedBy: me?.id,
        );

    setState(() => _localSuggestion = suggestion);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cloud Functions are not deployed, so this card was generated '
          'locally for preview only.',
        ),
      ),
    );
  }

  AiSuggestion? _localSuggestion;

  Future<void> _setOptIn(bool value) async {
    final uid = ref.read(uidProvider);
    if (uid == null) return;
    try {
      await ref
          .read(connectionRepositoryProvider)
          .setCoachOptIn(
            connectionId: widget.connectionId,
            uid: uid,
            optedIn: value,
          );
    } on CloseyFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _showChatMenu() async {
    final uid = ref.read(uidProvider);
    final connection = ref.read(connectionProvider(widget.connectionId)).value;
    if (connection == null || uid == null) return;
    final other = connection.otherUser(uid);

    await showCloseySheet<void>(
      context: context,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CloseySheetHeader(
              title: other.fullName,
              subtitle: '@${other.displayHandle}',
              leading: CloseyAvatar(
                name: other.fullName,
                imageUrl: other.primaryPhoto,
                size: 44,
              ),
            ),
            CloseyListRow(
              title: 'View profile',
              icon: Icons.person_outline_rounded,
              onTap: () {
                Navigator.pop(context);
                context.push(Routes.publicProfile(other.id));
              },
            ),
            CloseyListRow(
              title: connection.isFriend
                  ? 'You are friends'
                  : 'Add as a friend',
              subtitle: connection.isFriend
                  ? 'Unlimited free chat enabled'
                  : 'Unlimited free chat, no DM limit',
              icon: Icons.handshake_outlined,
              trailing: connection.isFriend
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: context.colors.success,
                    )
                  : null,
              onTap: connection.isFriend
                  ? null
                  : () async {
                      Navigator.pop(context);
                      try {
                        await ref
                            .read(connectionRepositoryProvider)
                            .sendFriendRequest(from: _me(), to: other);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Friend request sent'),
                            ),
                          );
                        }
                      } on CloseyFailure catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
            ),
            CloseyListRow(
              title: 'Report',
              icon: Icons.flag_outlined,
              onTap: () {
                Navigator.pop(context);
                context.push('${Routes.report(other.id)}?from=chat');
              },
            ),
            CloseyListRow(
              title: 'Unmatch',
              subtitle: 'Removes the conversation for both of you',
              icon: Icons.heart_broken_outlined,
              destructive: true,
              showDivider: false,
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showCloseyConfirm(
                  context: context,
                  title: 'Unmatch ${other.fullName}?',
                  message:
                      'This deletes the conversation for both of you and cannot '
                      'be undone.',
                  confirmLabel: 'Unmatch',
                  destructive: true,
                );
                if (!confirmed) return;
                await ref
                    .read(safetyRepositoryProvider)
                    .unmatch(widget.connectionId);
                if (mounted) context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  AppUser _me() {
    final me = ref.read(currentUserValueProvider);
    if (me == null) {
      throw const CloseyFailure('Your session expired. Sign in again.');
    }
    return me;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uid = ref.watch(uidProvider) ?? '';
    final connectionAsync = ref.watch(connectionProvider(widget.connectionId));
    final messagesAsync = ref.watch(messagesProvider(widget.connectionId));
    final consent =
        ref.watch(coachConsentProvider(widget.connectionId)).value ??
        CoachConsent.off;
    final coachCards =
        ref.watch(coachCardsProvider(widget.connectionId)).value ??
        CoachCards.none;
    final quota = ref.watch(quotaProvider).value ?? SuggestionQuota.unknown;
    final quiet = ref.watch(coachQuietProvider(widget.connectionId));

    final connection = connectionAsync.value;
    final messages = messagesAsync.value ?? const <Message>[];

    // Auto-scroll when new messages arrive.
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    // Clear the unread counter once the thread is actually open.
    if (!_markedRead && uid.isNotEmpty && connection != null) {
      _markedRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(connectionRepositoryProvider)
            .markRead(connectionId: widget.connectionId, uid: uid);
      });
    }

    if (connection == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: CloseyAppBar(title: ''),
        body: connectionAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const CloseyEmptyState(
                icon: Icons.link_off_rounded,
                title: 'Conversation unavailable',
                message:
                    'This conversation was removed, possibly because one of you '
                    'unmatched.',
              ),
      );
    }

    final other = connection.otherUser(uid);
    final cards = [...coachCards.ordered, ?_localSuggestion];

    return Scaffold(
      backgroundColor: colors.background,
      appBar: _ChatAppBar(
        name: other.fullName,
        handle: other.displayHandle,
        avatarUrl: other.primaryPhoto,
        online: other.online,
        isFriend: connection.isFriend,
        onOpenProfile: () => context.push(Routes.publicProfile(other.id)),
        onMenu: _showChatMenu,
      ),
      body: Column(
        children: [
          if (!connection.isFriend)
            _DmUpsellBanner(
              onTap: () async {
                try {
                  await ref
                      .read(connectionRepositoryProvider)
                      .sendFriendRequest(from: _me(), to: other);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Friend request sent')),
                    );
                  }
                } on CloseyFailure catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      this.context,
                    ).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
            ),

          _CoachZone(
            consent: consent,
            cards: cards,
            quota: quota,
            quiet: quiet,
            loading: _requestingCoach,
            canUseCoach: other.verificationTier.canUseCoach,
            onOptIn: _setOptIn,
            onVerify: () => context.push(Routes.verification),
            onAskCoach: _askCoach,
            onBuyMore: () => context.push('${Routes.paywall}?reason=quota'),
            onUse: (suggestion) {
              // Fill the composer so the sender can edit before sending â€”
              // the AI never speaks as the user.
              _controller.text = suggestion.content;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
              if (suggestion.id == _localSuggestion?.id) {
                setState(() => _localSuggestion = null);
              } else {
                ref
                    .read(chatRepositoryProvider)
                    .markSuggestion(
                      connectionId: widget.connectionId,
                      suggestionId: suggestion.id,
                      status: SuggestionStatus.used,
                    );
              }
              _focus.requestFocus();
            },
            onDismiss: (suggestion) {
              if (suggestion.id == _localSuggestion?.id) {
                setState(() => _localSuggestion = null);
                return;
              }
              ref
                  .read(chatRepositoryProvider)
                  .markSuggestion(
                    connectionId: widget.connectionId,
                    suggestionId: suggestion.id,
                    status: SuggestionStatus.dismissed,
                  );
            },
          ),

          Expanded(
            child: messagesAsync.isLoading
                ? const CloseySkeletonList(rows: 6, showAvatar: false)
                : messages.isEmpty
                ? _EmptyThread(
                    name: other.fullName,
                    isFriend: connection.isFriend,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      Gap.lg,
                      Gap.md,
                      Gap.lg,
                      Gap.md,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final message = messages[i];
                      final previous = i > 0 ? messages[i - 1] : null;
                      final showDay =
                          previous == null ||
                          !_sameDay(previous.createdAt, message.createdAt);

                      return Column(
                        children: [
                          if (showDay) _DayDivider(date: message.createdAt),
                          MessageBubble(
                            message: message,
                            isMine: message.isMine(uid),
                            showTail: previous?.senderId != message.senderId,
                          ),
                        ],
                      );
                    },
                  ),
          ),

          _Composer(
            controller: _controller,
            focusNode: _focus,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

typedef AppUserFallback = AppUser;

/// Slimmer chat header than the Expo version, with the friend/unlimited state
/// stated in words instead of implied by a colour.
class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.online,
    required this.isFriend,
    required this.onOpenProfile,
    required this.onMenu,
  });

  final String name;
  final String handle;
  final String? avatarUrl;
  final bool online;
  final bool isFriend;
  final VoidCallback onOpenProfile;
  final VoidCallback onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppBar(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: Gap.xs),
        child: Center(
          child: CloseyIconButton(
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Go back',
          ),
        ),
      ),
      titleSpacing: 0,
      title: InkWell(
        onTap: onOpenProfile,
        borderRadius: Radii.pill,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              CloseyAvatar(
                name: name,
                imageUrl: avatarUrl,
                size: 40,
                showPresence: true,
                online: online,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: context.text.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isFriend
                          ? 'Friend · unlimited chat'
                          : online
                          ? 'Online now'
                          : '@$handle',
                      style: context.text.bodySmall?.copyWith(
                        color: isFriend
                            ? colors.successText
                            : colors.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        CloseyIconButton(
          icon: Icons.more_horiz_rounded,
          onPressed: onMenu,
          semanticLabel: 'Conversation options',
        ),
        const SizedBox(width: Gap.sm),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: colors.border),
      ),
    );
  }
}

/// Banner that converts a metered DM into a friend connection â€” the app's main
/// growth loop, so it is worth stating the benefit rather than the limit.
class _DmUpsellBanner extends StatelessWidget {
  const _DmUpsellBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
      child: Material(
        color: colors.brandSoft,
        borderRadius: Radii.allMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.allMd,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Icon(
                  Icons.handshake_outlined,
                  size: 18,
                  color: colors.brandText,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    'Add as a friend for unlimited free chat. DMs on the free '
                    'plan are limited to 5 new conversations a month.',
                    style: context.text.bodySmall?.copyWith(
                      color: colors.brandText,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.brandText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The coach area above the messages: consent state, cards, and the manual
/// request button.
class _CoachZone extends StatelessWidget {
  const _CoachZone({
    required this.consent,
    required this.cards,
    required this.quota,
    required this.quiet,
    required this.loading,
    required this.canUseCoach,
    required this.onOptIn,
    required this.onVerify,
    required this.onAskCoach,
    required this.onBuyMore,
    required this.onUse,
    required this.onDismiss,
  });

  final CoachConsent consent;
  final List<AiSuggestion> cards;
  final SuggestionQuota quota;
  final bool quiet;
  final bool loading;
  final bool canUseCoach;
  final ValueChanged<bool> onOptIn;
  final VoidCallback onVerify;
  final VoidCallback onAskCoach;
  final VoidCallback onBuyMore;
  final ValueChanged<AiSuggestion> onUse;
  final ValueChanged<AiSuggestion> onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!canUseCoach) {
      return _CoachNotice(
        title: 'The other person is not verified yet',
        body:
            'The coach only works when both people are verified, so nobody is '
            'coached without knowing it is available.',
        icon: Icons.shield_outlined,
      );
    }

    if (!consent.bothOptedIn) {
      return _CoachNotice(
        title: consent.myOptIn
            ? 'Waiting for them to switch it on'
            : 'Turn on the conversation coach?',
        body: consent.myOptIn
            ? 'You are in. They will see the same shared suggestions once they '
                  'opt in too — nothing is generated until you both agree.'
            : 'You will both see the same starter suggestions. If the thread '
                  'goes one-sided, only you see your nudge, and they are never '
                  'told. You can turn this off any time.',
        icon: Icons.auto_awesome_outlined,
        action: consent.myOptIn
            ? ('Turn off', () => onOptIn(false))
            : ('Turn it on', () => onOptIn(true)),
      );
    }

    return Column(
      children: [
        // Notes sit in the margin of the thread rather than above the composer.
        // No horizontal padding here: the note owns its own indent, so that it
        // lines up with neither the message column nor the page edge.
        for (final card in cards)
          CloseyMarginNote(
            suggestion: card,
            onUse: onUse,
            onDismiss: () => onDismiss(card),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.sm),
          child: Row(
            children: [
              Expanded(
                child: CloseyButton(
                  label: loading
                      ? 'Reading the conversation…'
                      : quiet
                      ? 'Coach is resting for a bit'
                      : 'Help me continue this',
                  icon: Icons.auto_awesome_rounded,
                  variant: CloseyButtonVariant.secondary,
                  size: CloseyButtonSize.sm,
                  fullWidth: true,
                  loading: loading,
                  onPressed: (loading || quota.isEmpty) ? null : onAskCoach,
                ),
              ),
              const SizedBox(width: Gap.md),
              QuotaPill(quota: quota, onTap: onBuyMore),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoachNotice extends StatelessWidget {
  const _CoachNotice({
    required this.title,
    required this.body,
    required this.icon,
    this.action,
  });

  final String title;
  final String body;
  final IconData icon;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
      child: CloseyCard(
        tinted: colors.coachSurface,
        borderColor: colors.coachBorder,
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: colors.accentText),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    title,
                    style: context.text.titleSmall?.copyWith(
                      color: colors.accentText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(
              body,
              style: context.text.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: Gap.md),
              CloseyButton(
                label: action!.$1,
                size: CloseyButtonSize.sm,
                variant: CloseyButtonVariant.tonal,
                onPressed: action!.$2,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.name, required this.isFriend});

  final String name;
  final bool isFriend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CloseyAvatar(name: name, size: 76),
            const SizedBox(height: Gap.lg),
            Text(
              'You matched with $name',
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              isFriend
                  ? 'Unlimited chat — no limits from here.'
                  : 'Nothing sent yet. Use a starter above, or type your own.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final label = date == null
        ? ''
        : date!.year == now.year &&
              date!.month == now.month &&
              date!.day == now.day
        ? 'Today'
        : '${date!.day}/${date!.month}/${date!.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.lg),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(
              label,
              style: context.text.bodySmall?.copyWith(
                color: colors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(child: Divider(color: colors.border)),
        ],
      ),
    );
  }
}

/// A chat bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showTail = true,
  });

  final Message message;
  final bool isMine;
  final bool showTail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        margin: EdgeInsets.only(top: showTail ? Gap.md : 3, bottom: 0),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          color: isMine ? colors.chatMine : colors.chatTheirs,
          border: isMine ? null : Border.all(color: colors.chatTheirsBorder),
          borderRadius: showTail
              ? (isMine ? Radii.bubbleMine : Radii.bubbleTheirs)
              : Radii.allLg,
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 15.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: isMine ? colors.chatMineText : colors.chatTheirsText,
              ),
            ),
            if (isMine && message.sendState == MessageSendState.sending)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Sending…',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.chatMineText.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The composer. Grows to a cap, sends on Enter for hardware keyboards, and
/// keeps a 48dp send target.
class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final Future<void> Function({String? overrideText, bool fromSuggestion})
  onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          top: BorderSide(color: colors.border, width: Strokes.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.md, Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 128),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: Radii.allXl,
                    border: Border.all(color: colors.border),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    maxLines: null,
                    maxLength: kMaxMessageLength,
                    textCapitalization: TextCapitalization.sentences,
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
                      hintText: 'Message…',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Gap.lg,
                        vertical: Gap.md,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              _SendButton(
                enabled: _hasText && !widget.sending,
                loading: widget.sending,
                onTap: () => widget.onSend(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: 'Send message',
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? colors.brand : colors.surfaceSunken,
            shape: BoxShape.circle,
          ),
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(colors.textOnBrand),
                  ),
                )
              : Icon(
                  Icons.arrow_upward_rounded,
                  size: 21,
                  color: enabled ? colors.textOnBrand : colors.textTertiary,
                ),
        ),
      ),
    );
  }
}

/// Helper used by the local fallback path.
abstract final class ChatRepositoryShared {
  static List<String> interests(AppUser? me, AppUser? other) {
    final mine = me?.interests ?? const <String>[];
    final theirs = other?.interests ?? const <String>[];
    return theirs.where(mine.contains).toList(growable: false);
  }
}

/// Small quota indicator.
class QuotaPill extends StatelessWidget {
  const QuotaPill({super.key, required this.quota, this.onTap});

  final SuggestionQuota quota;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final empty = quota.isEmpty;

    return GestureDetector(
      onTap: empty ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 8),
        decoration: BoxDecoration(
          color: empty ? colors.brand : colors.brandSoft,
          borderRadius: Radii.pill,
          border: Border.all(color: colors.brandBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              empty ? Icons.add_circle_outline_rounded : Icons.bolt_rounded,
              size: 14,
              color: empty ? colors.textOnBrand : colors.brandText,
            ),
            const SizedBox(width: 5),
            Text(
              empty ? 'Buy more' : '${quota.remaining} left',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: empty ? colors.textOnBrand : colors.brandText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
