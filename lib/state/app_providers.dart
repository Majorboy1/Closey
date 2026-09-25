import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_user.dart';
import '../data/models/chat.dart';
import '../data/models/connection.dart';
import '../data/models/discovery.dart';
import '../data/models/meeting.dart';
import '../data/models/post.dart';
import '../data/models/quota.dart';
import '../data/models/safety.dart';
import '../data/repositories/chat_repository.dart';
import 'services.dart';

/// Domain providers.
///
/// Convention used throughout: `StreamProvider.family` for anything backed by a
/// Firestore listener, `FutureProvider.family` for one-shot reads, and
/// `NotifierProvider` only for genuinely local UI state. Riverpod 3 moved
/// `StateProvider`/`StateNotifierProvider` to `package:riverpod/legacy.dart`;
/// nothing here uses them, so the app is already on the supported API surface.

// ------------------------------------------------------------------ theme --

/// Light / dark / system. Persisted in `shared_preferences` by `SettingsStore`
/// and seeded at startup so the app never flashes the wrong theme.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;

  void toggle() {
    state = switch (state) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
  }
}

// ------------------------------------------------------------------ quota --

final quotaProvider = StreamProvider<SuggestionQuota>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(SuggestionQuota.unknown);
  return ref.watch(billingRepositoryProvider).watchQuota(uid);
});

final dmUsageProvider = StreamProvider<DmUsage>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(DmUsage.unknown);
  return ref.watch(billingRepositoryProvider).watchDmUsage(uid);
});

final subscriptionProvider = StreamProvider<Subscription>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(Subscription.free);
  return ref.watch(billingRepositoryProvider).watchSubscription(uid);
});

// -------------------------------------------------------------- discovery --

/// The swipe deck. Kept in a `Notifier` rather than a `FutureProvider` because
/// swiping mutates it optimistically â€” the card must leave the deck instantly,
/// and the write is allowed to fail quietly in the background.
final deckProvider = AsyncNotifierProvider<DeckNotifier, DeckState>(
  DeckNotifier.new,
);

class DeckState {
  const DeckState({
    this.queue = const [],
    this.index = 0,
    this.exhausted = false,
    this.lastSwiped,
    this.matchResult,
  });

  final List<DiscoveryCandidate> queue;
  final int index;
  final bool exhausted;

  /// The most recent swipe, so Undo can restore it.
  final DiscoveryCandidate? lastSwiped;

  /// Set when a swipe produced a match; the UI shows the celebration and then
  /// calls `clearMatch()`.
  final SwipeOutcome? matchResult;

  DiscoveryCandidate? get current => index < queue.length ? queue[index] : null;

  DiscoveryCandidate? get next =>
      index + 1 < queue.length ? queue[index + 1] : null;

  bool get isFinished => current == null;

  int get remainingCount => (queue.length - index).clamp(0, queue.length);

  DeckState copyWith({
    List<DiscoveryCandidate>? queue,
    int? index,
    bool? exhausted,
    DiscoveryCandidate? lastSwiped,
    SwipeOutcome? matchResult,
    bool clearMatch = false,
  }) => DeckState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    exhausted: exhausted ?? this.exhausted,
    lastSwiped: lastSwiped ?? this.lastSwiped,
    matchResult: clearMatch ? null : (matchResult ?? this.matchResult),
  );
}

class DeckNotifier extends AsyncNotifier<DeckState> {
  @override
  Future<DeckState> build() async {
    final viewer = ref.watch(currentUserValueProvider);
    if (viewer == null) return const DeckState();

    final candidates = await ref
        .watch(discoveryRepositoryProvider)
        .fetchCandidates(viewer);

    return DeckState(queue: candidates, exhausted: candidates.isEmpty);
  }

  /// Refetches, preserving nothing. Used by pull-to-refresh and after the
  /// deck runs out.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }

  Future<void> like({bool superLike = false}) async {
    final viewer = ref.read(currentUserValueProvider);
    final deck = state.value;
    final card = deck?.current;
    if (viewer == null || deck == null || card == null) return;

    // Advance immediately â€” the network write must not gate the animation.
    state = AsyncValue.data(
      deck.copyWith(index: deck.index + 1, lastSwiped: card),
    );

    try {
      final outcome = await ref
          .read(discoveryRepositoryProvider)
          .like(viewer: viewer, target: card.user, superLike: superLike);

      if (outcome.isMatch) {
        final current = state.value;
        if (current != null) {
          state = AsyncValue.data(current.copyWith(matchResult: outcome));
        }
      }
    } catch (_) {
      // Put the card back so the user can retry, rather than silently losing it.
      final current = state.value;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(index: deck.index));
      }
      rethrow;
    }
  }

  Future<void> pass() async {
    final viewer = ref.read(currentUserValueProvider);
    final deck = state.value;
    final card = deck?.current;
    if (viewer == null || deck == null || card == null) return;

    state = AsyncValue.data(
      deck.copyWith(index: deck.index + 1, lastSwiped: card),
    );

    try {
      await ref
          .read(discoveryRepositoryProvider)
          .pass(viewerId: viewer.id, targetId: card.user.id);
    } catch (_) {
      // A failed pass is not worth interrupting the user for.
    }
  }

  Future<void> undo() async {
    final deck = state.value;
    final last = deck?.lastSwiped;
    final viewer = ref.read(currentUserValueProvider);
    if (deck == null || last == null || viewer == null) return;
    if (deck.index == 0) return;

    state = AsyncValue.data(
      deck.copyWith(index: deck.index - 1, clearMatch: true),
    );

    try {
      await ref
          .read(discoveryRepositoryProvider)
          .undo(viewerId: viewer.id, targetId: last.user.id);
    } catch (_) {
      /* best effort */
    }
  }

  void clearMatch() {
    final deck = state.value;
    if (deck == null) return;
    state = AsyncValue.data(deck.copyWith(clearMatch: true));
  }
}

final incomingLikesProvider = StreamProvider<int>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(0);
  return ref.watch(discoveryRepositoryProvider).watchIncomingLikeCount(uid);
});

// ------------------------------------------------------------ connections --

final chatListProvider = StreamProvider<List<Connection>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(connectionRepositoryProvider).watchChatList(uid);
});

final totalUnreadProvider = StreamProvider<int>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(0);
  return ref.watch(connectionRepositoryProvider).watchTotalUnread(uid);
});

final incomingRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(connectionRepositoryProvider).watchIncomingRequests(uid);
});

final connectionProvider = StreamProvider.family<Connection?, String>((
  ref,
  connectionId,
) {
  return ref.watch(connectionRepositoryProvider).watchConnection(connectionId);
});

final coachConsentProvider = StreamProvider.family<CoachConsent, String>((
  ref,
  connectionId,
) {
  final uid = ref.watch(uidProvider);
  if (uid == null) {
    return Stream.value(CoachConsent.off);
  }
  return ref
      .watch(connectionRepositoryProvider)
      .watchCoachConsent(connectionId: connectionId, uid: uid);
});

// ------------------------------------------------------------------- chat --

final messagesProvider = StreamProvider.family<List<Message>, String>((
  ref,
  connectionId,
) {
  return ref.watch(chatRepositoryProvider).watchMessages(connectionId);
});

final coachCardsProvider = StreamProvider.family<CoachCards, String>((
  ref,
  connectionId,
) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(CoachCards.none);
  return ref
      .watch(chatRepositoryProvider)
      .watchCoachCards(connectionId: connectionId, uid: uid);
});

/// When the coach last spoke in this thread, for the "quiet period" indicator.
final coachQuietProvider = Provider.family<bool, String>((ref, connectionId) {
  final messages = ref.watch(messagesProvider(connectionId)).value;
  if (messages == null) return false;
  return ref
      .watch(chatRepositoryProvider)
      .shouldSuppressUnprompted(messages: messages, now: DateTime.now());
});

// ------------------------------------------------------------------ feed --

final feedProvider = StreamProvider<List<Post>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchFeed(uid: uid);
});

final userPostsProvider = StreamProvider.family<List<Post>, String>((
  ref,
  authorId,
) {
  return ref.watch(socialRepositoryProvider).watchUserPosts(authorId);
});

// ---------------------------------------------------------------- safety --

final blockedUsersProvider = StreamProvider<List<BlockedUser>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(safetyRepositoryProvider).watchBlockedUsers(uid);
});

// -------------------------------------------------------------- meetings --

final meetingsProvider = StreamProvider<List<Meeting>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(meetingRepositoryProvider).watchMyMeetings(uid);
});

// -------------------------------------------------------------- profiles --

final profileByIdProvider = StreamProvider.family<AppUser?, String>((
  ref,
  userId,
) {
  return ref.watch(userRepositoryProvider).watchUser(userId);
});

/// Mutual-likes list, resolved to profiles.
final likesYouProvider = FutureProvider<List<AppUser>>((ref) async {
  final uid = ref.watch(uidProvider);
  if (uid == null) return const [];
  return ref.watch(discoveryRepositoryProvider).listLikedYou(uid);
});

/// Shared interests between me and someone else â€” the coach's favourite signal,
/// surfaced in the UI so suggestions feel grounded rather than random.
final sharedInterestsProvider = Provider.family<List<String>, String>((
  ref,
  otherId,
) {
  final me = ref.watch(currentUserValueProvider);
  final other = ref.watch(profileByIdProvider(otherId)).value;
  if (me == null || other == null) return const [];
  return other.interests.where(me.interests.contains).toList(growable: false);
});

// ------------------------------------------------------------- misc UI --

/// Transient, screen-level error text. Replaces the Expo app's habit of pushing
/// every failure into a blocking `Alert.alert`.
final inlineErrorProvider = NotifierProvider<InlineErrorNotifier, String?>(
  InlineErrorNotifier.new,
);

class InlineErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;
  void clear() => state = null;
}

/// Long-lived success/notice banner (e.g. "Report submitted").
final noticeProvider = NotifierProvider<NoticeNotifier, String?>(
  NoticeNotifier.new,
);

class NoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;
  void clear() => state = null;
}

/// Anything the coach might need from the profile, in one place.
typedef CoachContext = ({
  List<String> sharedInterests,
  List<String> myTopics,
  List<String> theirTopics,
  String? myPrompt,
  String? theirPrompt,
});

final coachContextProvider = Provider.family<CoachContext, String>((
  ref,
  otherId,
) {
  final me = ref.watch(currentUserValueProvider);
  final other = ref.watch(profileByIdProvider(otherId)).value;
  return (
    sharedInterests: ref.watch(sharedInterestsProvider(otherId)),
    myTopics: me?.conversationTopics ?? const [],
    theirTopics: other?.conversationTopics ?? const [],
    myPrompt: me?.promptAnswer,
    theirPrompt: other?.promptAnswer,
  );
});

/// Suggestions rendered in the chat, ordered so the shared card sits first and
/// the private nudge — the most actionable one — sits closest to the composer.
extension CoachCardsOrdering on CoachCards {
  List<AiSuggestion> get ordered => [?shared, ?privateNudge];
}
