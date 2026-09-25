import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/widgets/async_section.dart';
import '../firebase/firebase_bootstrap.dart';
import '../models/app_user.dart';
import '../models/connection.dart';
import '../models/enums.dart';

/// Connections, friend requests and starting new threads.
///
/// Firestore layout:
/// ```
/// connections/{a}__{b}                     ← deterministic id, sorted members
/// connections/{a}__{b}/optIns/{uid}
/// connections/{a}__{b}/messages/{id}
/// connections/{a}__{b}/suggestions/{id}
/// friendRequests/{sender}__{receiver}
/// ```
///
/// Quota-enforcing operations are **callable Cloud Functions**, never client
/// writes. That preserves the guarantee the Expo app established in Postgres
/// (`try_consume_suggestion`, `start_dm`): a user cannot grant themselves more
/// DM conversations or AI credits by tampering with the client. The
/// `users/{uid}/private` subcollection is read-only to the client for the same
/// reason.
class ConnectionRepository {
  ConnectionRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FirebaseBootstrap.functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _connections =>
      _db.collection('connections');
  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('friendRequests');

  // ------------------------------------------------------------- chat list

  /// Live chat list, newest activity first.
  ///
  /// This is a single query. The Expo version joined both profile sides on
  /// every render and hardcoded `unread: 0`; here the summaries are denormalised
  /// onto the connection (kept fresh by an `onUserUpdated` trigger) and unread
  /// counts are real per-member counters.
  Stream<List<Connection>> watchConnections(String uid) => _connections
      .where('members', arrayContains: uid)
      .orderBy('lastMessageAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => Connection.fromDoc(d)).toList(growable: false),
      );

  Future<List<Connection>> listConnections(String uid) async {
    final snap = await _connections
        .where('members', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(100)
        .get();
    return snap.docs.map((d) => Connection.fromDoc(d)).toList(growable: false);
  }

  Stream<Connection?> watchConnection(String connectionId) => _connections
      .doc(connectionId)
      .snapshots()
      .map((d) => d.exists ? Connection.fromDoc(d) : null);

  Future<Connection?> getConnection(String connectionId) async {
    final doc = await _connections.doc(connectionId).get();
    return doc.exists ? Connection.fromDoc(doc) : null;
  }

  /// Friends first, then most recent activity. Used by the Chats tab.
  Stream<List<Connection>> watchChatList(String uid) =>
      watchConnections(uid).map((list) {
        final sorted = [...list];
        sorted.sort((a, b) {
          if (a.isFriend != b.isFriend) return a.isFriend ? -1 : 1;
          final at = a.lastMessageAt ?? a.createdAt ?? DateTime(1970);
          final bt = b.lastMessageAt ?? b.createdAt ?? DateTime(1970);
          return bt.compareTo(at);
        });
        return sorted;
      });

  // --------------------------------------------------------- friend requests

  Stream<List<FriendRequest>> watchIncomingRequests(String uid) => _requests
      .where('receiverId', isEqualTo: uid)
      .where('status', isEqualTo: FriendRequestStatus.pending.wire)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snap) => snap.docs.map(FriendRequest.fromDoc).toList(growable: false),
      );

  Stream<List<FriendRequest>> watchOutgoingRequests(String uid) => _requests
      .where('senderId', isEqualTo: uid)
      .where('status', isEqualTo: FriendRequestStatus.pending.wire)
      .snapshots()
      .map(
        (snap) => snap.docs.map(FriendRequest.fromDoc).toList(growable: false),
      );

  /// Sends a friend request. The deterministic id means a double-tap, a retry,
  /// or two devices cannot produce duplicates — the Expo version relied on a
  /// client-side check and could create two pending rows.
  Future<void> sendFriendRequest({
    required AppUser from,
    required AppUser to,
    String? message,
  }) async {
    final existing = await _connections
        .doc(Connection.idFor(from.id, to.id))
        .get();
    if (existing.exists) {
      throw const CloseyFailure(
        'You are already connected with them.',
        isRetryable: false,
      );
    }

    final request = FriendRequest(
      id: FriendRequest.idFor(from.id, to.id),
      senderId: from.id,
      receiverId: to.id,
      sender: from,
      message: message,
    );

    await _requests.doc(request.id).set(request.toCreateMap());
  }

  Future<void> cancelFriendRequest({
    required String fromId,
    required String toId,
  }) => _requests.doc(FriendRequest.idFor(fromId, toId)).update({
    'status': FriendRequestStatus.cancelled.wire,
    'respondedAt': FieldValue.serverTimestamp(),
  });

  /// Accepts or declines. Accepting creates the connection server-side so the
  /// friend-bonus counters on both profiles stay consistent.
  Future<String?> respondToFriendRequest({
    required String requestId,
    required bool accept,
  }) async {
    if (!accept) {
      await _requests.doc(requestId).update({
        'status': FriendRequestStatus.declined.wire,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return null;
    }

    try {
      final result = await _functions
          .httpsCallable('acceptFriendRequest')
          .call<Map<String, dynamic>>({'requestId': requestId});
      return result.data['connectionId'] as String?;
    } on FirebaseFunctionsException catch (e) {
      throw CloseyFailure(
        e.message ?? 'Could not accept that request.',
        code: e.code,
      );
    }
  }

  // ------------------------------------------------------------------- DMs

  /// Opens a direct conversation, consuming one of the monthly DM credits on
  /// the free tier. Enforced server-side; the client never sees or writes the
  /// counter except to display it.
  ///
  /// Throws a [CloseyFailure] with code `DM_LIMIT_REACHED` when the monthly
  /// allowance is gone, which the UI turns into the paywall sheet rather than
  /// a dead end.
  Future<String> startDm({required String otherUserId}) async {
    try {
      final result = await _functions
          .httpsCallable('startDm')
          .call<Map<String, dynamic>>({'otherUserId': otherUserId});

      final id = result.data['connectionId'] as String?;
      if (id == null) {
        throw const CloseyFailure('Could not open that conversation.');
      }
      return id;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted' ||
          (e.message ?? '').contains('DM_LIMIT_REACHED')) {
        throw const CloseyFailure(
          'You have used all 5 free conversations this month. '
          'Add them as a friend for unlimited chat, or go Premium.',
          code: 'DM_LIMIT_REACHED',
          isRetryable: false,
        );
      }
      if (e.code == 'unauthenticated') {
        throw const CloseyFailure(
          'Please sign in again to start a conversation.',
          isRetryable: false,
        );
      }
      throw CloseyFailure(
        e.message ?? 'Could not open that conversation.',
        code: e.code,
      );
    }
  }

  /// Looks up an existing thread without consuming quota, so opening a chat
  /// from the list never charges the user.
  Future<String?> findExistingConnection(String uid, String otherId) async {
    final doc = await _connections.doc(Connection.idFor(uid, otherId)).get();
    return doc.exists ? doc.id : null;
  }

  // --------------------------------------------------------------- opt-in

  /// Records this user's consent for the AI coach in this thread.
  ///
  /// Consent is **mutual**: the coach stays silent until
  /// [watchCoachConsent] reports both members opted in. The Expo prototype did
  /// not model this at all — every chat behaved as if the AI were always on,
  /// which the DECISIONS log flagged as an unresolved open question. Making it
  /// per-thread and mutual is the privacy-correct answer.
  Future<void> setCoachOptIn({
    required String connectionId,
    required String uid,
    required bool optedIn,
  }) async {
    await _connections.doc(connectionId).collection('optIns').doc(uid).set({
      'userId': uid,
      'optedIn': optedIn,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Denormalised mirror so the chat header can render consent state without
    // a second listener.
    await _connections.doc(connectionId).set({
      'optInFlags': {uid: optedIn},
    }, SetOptions(merge: true));
  }

  Stream<CoachConsent> watchCoachConsent({
    required String connectionId,
    required String uid,
  }) => _connections.doc(connectionId).collection('optIns').snapshots().map((
    snap,
  ) {
    var mine = false;
    var optedInCount = 0;
    for (final doc in snap.docs) {
      final isIn = (doc.data()['optedIn'] as bool?) ?? false;
      if (isIn) optedInCount++;
      if (doc.id == uid) mine = isIn;
    }
    // Two members, both must be in.
    return CoachConsent(myOptIn: mine, bothOptedIn: mine && optedInCount >= 2);
  });

  // --------------------------------------------------------------- unread

  /// Clears this member's unread counter. Called when the chat opens.
  Future<void> markRead({
    required String connectionId,
    required String uid,
  }) async {
    try {
      await _connections.doc(connectionId).update({'unread.$uid': 0});
    } catch (_) {
      // Firestore rejects dotted paths on some rule shapes; fall back to a
      // merge write of the whole map.
      await _connections.doc(connectionId).set({
        'unread': {uid: 0},
      }, SetOptions(merge: true));
    }
  }

  /// Total unread across all threads — powers the Chats tab badge.
  Stream<int> watchTotalUnread(String uid) => watchConnections(
    uid,
  ).map((list) => list.fold<int>(0, (total, c) => total + c.unreadFor(uid)));
}
