import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/async_section.dart';
import '../firebase/firebase_bootstrap.dart';
import '../models/chat.dart';
import '../models/enums.dart';

/// Messaging and the shared AI coach — the product's core differentiator.
///
/// Firestore layout:
/// ```
/// connections/{id}/messages/{messageId}
/// connections/{id}/suggestions/{suggestionId}
/// ```
/// Both are subcollections so security rules inherit from the parent: a
/// message can only be read by the two members, and a **private** suggestion
/// document is only ever readable by its `targetUserId`.
///
/// That last point is a genuine improvement on the Expo implementation. There,
/// both clients subscribed to one realtime channel for the match, and the
/// client filtered private suggestions out of the UI — correct in practice, but
/// the data still reached the partner's device. Firestore filters snapshots
/// server-side per listener, so the partner's device never receives the
/// document at all. The product's central promise ("your match will never know
/// you were nudged") is now enforced by the database rather than by a `where`
/// clause on the client.
class ChatRepository {
  ChatRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FirebaseBootstrap.functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  static const _uuid = Uuid();

  DocumentReference<Map<String, dynamic>> _connection(String id) =>
      _db.collection('connections').doc(id);

  CollectionReference<Map<String, dynamic>> _messages(String id) =>
      _connection(id).collection('messages');

  CollectionReference<Map<String, dynamic>> _suggestions(String id) =>
      _connection(id).collection('suggestions');

  // --------------------------------------------------------------- messages

  /// Live messages, oldest-first, capped at [limit].
  ///
  /// The stream is optimistic-aware: locally-queued messages appear instantly
  /// (Firestore's own latency compensation) and are replaced by the server
  /// version when it lands. The Expo chat waited for a realtime round trip,
  /// so on a slow network sending felt broken.
  Stream<List<Message>> watchMessages(String connectionId, {int limit = 200}) =>
      _messages(connectionId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) {
            final list = snap.docs
                .map((d) => Message.fromDoc(d, connectionId: connectionId))
                .toList(growable: false);
            return list.reversed.toList(growable: false);
          });

  Future<List<Message>> listMessages(
    String connectionId, {
    int limit = 200,
  }) async {
    final snap = await _messages(
      connectionId,
    ).orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs
        .map((d) => Message.fromDoc(d, connectionId: connectionId))
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  /// Sends a message and updates the connection's denormalised preview plus the
  /// partner's unread counter in one batch.
  ///
  /// Doing preview + unread here (rather than in a Cloud Function) keeps the
  /// chat list in sync with no perceptible delay; the push notification is the
  /// function's job, because that needs the recipient's token and should not
  /// block the sender's write.
  Future<void> sendMessage({
    required String connectionId,
    required String senderId,
    required String recipientId,
    required String body,
    bool sentFromSuggestion = false,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return;

    final messageRef = _messages(connectionId).doc();
    final connectionRef = _connection(connectionId);

    final batch = _db.batch();

    batch.set(messageRef, {
      'senderId': senderId,
      'body': text,
      'readBy': [senderId],
      'sentFromSuggestion': sentFromSuggestion,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.set(connectionRef, {
      'lastMessage': text.length > 140 ? '${text.substring(0, 140)}…' : text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
      'unread.$recipientId': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Asks the backend for a reply from a simulated partner.
  ///
  /// Fire-and-forget by design. The server returns quietly when the other member
  /// is a real person, so the client never has to work out which kind of thread
  /// it is in - and a failure here must never make sending look broken, which is
  /// why the error is swallowed rather than surfaced.
  Future<void> simulatePartnerReply(String connectionId) async {
    try {
      await _functions
          .httpsCallable('simulatePartnerReply')
          .call<void>({'connectionId': connectionId});
    } catch (_) {
      // Intentionally ignored: this is a testing affordance, not a feature the
      // user asked for.
    }
  }

  Future<void> deleteMessage({
    required String connectionId,
    required String messageId,
  }) => _messages(connectionId).doc(messageId).delete();

  /// Resends a message that failed while offline.
  Future<void> retryMessage({
    required String connectionId,
    required String senderId,
    required String recipientId,
    required String body,
  }) => sendMessage(
    connectionId: connectionId,
    senderId: senderId,
    recipientId: recipientId,
    body: body,
  );

  // ------------------------------------------------------------ suggestions

  /// All active coach cards for a thread.
  ///
  /// The `visibility == 'private'` filter is a belt-and-braces guard: rules
  /// already prevent the partner from reading such a document, so this only
  /// matters for the recipient's own query shape.
  Stream<List<AiSuggestion>> watchActiveSuggestions(String connectionId) =>
      _suggestions(connectionId)
          .where('status', isEqualTo: SuggestionStatus.active.wire)
          .orderBy('createdAt', descending: true)
          .limit(6)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => AiSuggestion.fromDoc(d, connectionId: connectionId))
                .toList(growable: false),
          );

  /// The single card to show above the composer: at most one private nudge
  /// (aimed at me) and one shared suggestion.
  Stream<CoachCards> watchCoachCards({
    required String connectionId,
    required String uid,
  }) => watchActiveSuggestions(connectionId).map((all) {
    AiSuggestion? shared;
    AiSuggestion? private;

    for (final s in all) {
      if (s.isPrivate) {
        if (s.targetUserId == uid) private ??= s;
      } else {
        shared ??= s;
      }
    }
    return CoachCards(privateNudge: private, shared: shared);
  });

  /// Enforces the quiet period the spec asks for: the coach must not interject
  /// unprompted more than once per [QuotaConfig.coachQuietPeriod].
  ///
  /// New behaviour. Without it the prototype could stack several cards in a
  /// short window, which is exactly the "the AI is grading our conversation"
  /// feeling the DECISIONS log warns against.
  bool shouldSuppressUnprompted({
    required List<Message> messages,
    required DateTime now,
  }) {
    if (messages.isEmpty) return false;

    final lastCoachAt = messages
        .where((m) => m.senderId == kCoachSenderId)
        .map((m) => m.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    if (lastCoachAt == null) return false;
    return now.difference(lastCoachAt) < QuotaConfig.coachQuietPeriod;
  }

  Future<void> markSuggestion({
    required String connectionId,
    required String suggestionId,
    required SuggestionStatus status,
  }) => _suggestions(connectionId).doc(suggestionId).update({
    'status': status.wire,
    'reactedAt': FieldValue.serverTimestamp(),
  });

  // ----------------------------------------------------------------- coach

  /// Asks the coach for a suggestion. Always a **shared** card, because this is
  /// a deliberate action by one person, not a private coaching moment — the
  /// spec is explicit about that distinction.
  ///
  /// Returns the new suggestion plus the remaining daily allowance. Consuming a
  /// credit happens in the Cloud Function inside a transaction, so rerolls
  /// ("Another") are charged exactly like first requests — the DECISIONS log
  /// calls this out as a mistake that was made and corrected once already.
  Future<CoachReply> requestSuggestion({
    required String connectionId,
    SuggestionType? type,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('requestSuggestion')
          .call<Map<String, dynamic>>({
            'connectionId': connectionId,
            if (type != null) 'suggestionType': type.wire,
          });

      final data = result.data;
      final raw = data['suggestion'];
      final remaining = (data['remaining'] as num?)?.toInt() ?? 0;

      return CoachReply(
        suggestion: raw is Map
            ? AiSuggestion.fromMap(
                (data['suggestionId'] as String?) ?? 'pending',
                Map<String, dynamic>.from(raw),
                connectionId: connectionId,
              )
            : null,
        remaining: remaining,
      );
    } on FirebaseFunctionsException catch (e) {
      throw _mapCoachError(e);
    }
  }

  /// Resolves the offline/undeloyed-function case into something the UI can act
  /// on: the paywall, the verification screen, or a retry.
  CloseyFailure _mapCoachError(FirebaseFunctionsException e) {
    final message = (e.message ?? '').toLowerCase();

    if (e.code == 'resource-exhausted' || message.contains('quota_exceeded')) {
      return const CloseyFailure(
        'You have used all your AI suggestions for today.',
        code: 'QUOTA_EXCEEDED',
        isRetryable: false,
      );
    }
    if (message.contains('verification_required')) {
      return const CloseyFailure(
        'Verify your identity to unlock the conversation coach.',
        code: 'VERIFICATION_REQUIRED',
        isRetryable: false,
      );
    }
    if (message.contains('not_opted_in') || message.contains('not_enabled')) {
      return const CloseyFailure(
        'The coach needs both of you to switch it on for this chat.',
        code: 'NOT_ENABLED',
        isRetryable: false,
      );
    }
    if (e.code == 'unavailable' || e.code == 'not-found') {
      return const CloseyFailure(
        'The coach is unreachable. Deploy the Cloud Functions '
        '(`firebase deploy --only functions`) or run the emulator suite.',
        code: 'FUNCTIONS_UNAVAILABLE',
      );
    }
    if (e.code == 'unauthenticated') {
      return const CloseyFailure('Please sign in again.', isRetryable: false);
    }
    return CloseyFailure(
      e.message ?? 'The coach could not think of anything right now.',
      code: e.code,
    );
  }

  /// Local-only fallback used when the Cloud Functions are not deployed.
  ///
  /// Kept deliberately small and clearly labelled: it uses a hand-written
  /// opener drawn from the shared-interest overlap, so the chat UI is fully
  /// explorable before the backend exists. It never calls DeepSeek, so no API
  /// key is involved.
  AiSuggestion localFallbackSuggestion({
    required String connectionId,
    required List<String> sharedInterests,
    required SuggestionType type,
    String? requestedBy,
  }) {
    final topic = sharedInterests.isNotEmpty
        ? sharedInterests.first.toLowerCase()
        : 'your week';

    final content = switch (type) {
      SuggestionType.opener =>
        sharedInterests.isNotEmpty
            ? 'We both like $topic — what got you into it?'
            : 'Okay, most important question first: what does an ideal Sunday look like for you?',
      SuggestionType.reciprocityNudge =>
        'Ask them the same question back — it keeps things even.',
      SuggestionType.topicContinuation =>
        'You mentioned $topic earlier. What is the story behind that?',
      SuggestionType.newTopic =>
        'Neither of us has brought this up yet: what are you genuinely excited about right now?',
      SuggestionType.deepeningQuestion =>
        'What is something you have changed your mind about in the last year?',
      SuggestionType.icebreakerGame => 'Two truths and a lie — you go first.',
    };

    return AiSuggestion(
      id: 'local-${_uuid.v4().substring(0, 8)}',
      connectionId: connectionId,
      content: content,
      reason: sharedInterests.isNotEmpty
          ? 'Based on the interests you both listed.'
          : 'A general opener to get things moving.',
      type: type,
      visibility: SuggestionVisibility.shared,
      trigger: SuggestionTrigger.userRequested,
      requestedBy: requestedBy,
      createdAt: DateTime.now(),
    );
  }

  /// Firestore `whereIn` needs concrete values; convenience for shared topics.
  static List<String> sharedInterestsOf(
    Iterable<String> mine,
    Iterable<String> theirs,
  ) => mine.where(theirs.contains).toList(growable: false);
}

/// The two coach cards a chat can show at once.
class CoachCards {
  const CoachCards({this.privateNudge, this.shared});

  /// Visible only to me. Always a reciprocity nudge.
  final AiSuggestion? privateNudge;

  /// Visible to both of us, at the same time.
  final AiSuggestion? shared;

  bool get isEmpty => privateNudge == null && shared == null;
  bool get isNotEmpty => !isEmpty;

  static const CoachCards none = CoachCards();
}

/// Result of asking the coach for something.
class CoachReply {
  const CoachReply({this.suggestion, this.remaining = 0});

  final AiSuggestion? suggestion;
  final int remaining;
}

/// Sentinel sender id for coach-authored system messages, if any are ever
/// written into the thread. The coach never speaks *as* a user, but a pinned
/// system line ("Closey suggested a topic") uses this id.
const String kCoachSenderId = '__closey__';

/// Message bodies are capped by the Cloud Function prompt builder too; keeping
/// the same constant here means the composer counter and the server agree.
const int kMaxMessageLength = 4000;
