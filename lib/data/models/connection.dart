import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';
import 'enums.dart';

/// A 1:1 relationship between two people.
///
/// Firestore layout: `connections/{connectionId}` with
/// `messages/` and `suggestions/` subcollections, plus `optIns/{uid}` docs.
///
/// Two decisions worth calling out:
///
/// 1. **`members` is an array of exactly two UIDs, sorted.** Security rules can
///    then express "you can read this if you are in it" as
///    `request.auth.uid in resource.data.members` — one cheap index check,
///    no extra document read, and it cannot be bypassed by a crafted query.
///
/// 2. **`memberSummaries` is denormalised.** The Expo `listConnections()`
///    joined both profile sides on every list render, which is a per-row read
///    that Firestore would bill for and that also cannot be expressed in a
///    single query. Denormalising means the chat list is one query.
///    Cloud Functions keep the summaries fresh on profile edits.
class Connection {
  const Connection({
    required this.id,
    required this.members,
    this.memberSummaries = const {},
    this.kind = ConnectionKind.dm,
    this.aiEnabled = false,
    this.lastMessage,
    this.lastMessageAt,
    this.unread = const {},
    this.createdAt,
    this.muted = false,
  });

  final String id;

  /// Sorted pair of UIDs.
  final List<String> members;

  /// `{uid: {fullName, handle, avatarUrl, verificationTier}}`
  final Map<String, Map<String, dynamic>> memberSummaries;

  final ConnectionKind kind;

  /// Mutual AI opt-in state. Both members must opt in before the coach will
  /// speak in this thread (see [bothOptedIn]).
  final bool aiEnabled;

  final String? lastMessage;
  final DateTime? lastMessageAt;

  /// `{uid: count}` — per-member unread counter.
  ///
  /// This is new. The Expo `listConnections()` hardcoded `unread: 0` while the
  /// UI rendered unread badges from the list *index*, so the badges were
  /// decorative and wrong.
  final Map<String, int> unread;

  final DateTime? createdAt;
  final bool muted;

  String otherId(String viewerId) =>
      members.firstWhere((m) => m != viewerId, orElse: () => viewerId);

  AppUser otherUser(String viewerId) {
    final other = otherId(viewerId);
    final summary = memberSummaries[other];
    if (summary == null) return AppUser.empty(other);
    return AppUser.fromSummary(other, summary);
  }

  AppUser userById(String uid) {
    final summary = memberSummaries[uid];
    if (summary == null) return AppUser.empty(uid);
    return AppUser.fromSummary(uid, summary);
  }

  int unreadFor(String uid) => unread[uid] ?? 0;

  bool get isFriend => kind == ConnectionKind.friend;

  /// Friend threads are exempt from the DM quota — that is the whole point of
  /// adding someone as a friend, and it is the app's primary growth loop.
  bool get isUnlimited => isFriend;

  static List<String> sortedPair(String a, String b) {
    final list = [a, b]..sort();
    return list;
  }

  /// Deterministic doc id so a double-tap cannot create two threads.
  static String idFor(String a, String b) => sortedPair(a, b).join('__');

  static Connection fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    Map<String, Map<String, dynamic>>? summaries,
  }) => fromMap(doc.id, doc.data() ?? const {}, summaries: summaries);

  static Connection fromMap(
    String id,
    Map<String, dynamic> d, {
    Map<String, Map<String, dynamic>>? summaries,
  }) {
    final rawUnread = d['unread'];
    final unread = <String, int>{};
    if (rawUnread is Map) {
      rawUnread.forEach((k, v) {
        if (v is num) unread['$k'] = v.toInt();
      });
    }

    final rawSummaries = summaries ?? d['memberSummaries'];
    final summaryMap = <String, Map<String, dynamic>>{};
    if (rawSummaries is Map) {
      rawSummaries.forEach((k, v) {
        if (v is Map) summaryMap['$k'] = Map<String, dynamic>.from(v);
      });
    }

    return Connection(
      id: id,
      members: stringList(d, 'members'),
      memberSummaries: summaryMap,
      kind: ConnectionKind.fromWire(d['kind'] as String?),
      aiEnabled: (d['aiEnabled'] as bool?) ?? false,
      lastMessage: d['lastMessage'] as String?,
      lastMessageAt: dateField(d, 'lastMessageAt'),
      unread: unread,
      createdAt: dateField(d, 'createdAt'),
      muted: (d['muted'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'members': members,
    'memberSummaries': memberSummaries,
    'kind': kind.wire,
    'aiEnabled': aiEnabled,
    'lastMessage': lastMessage,
    'lastMessageAt': lastMessageAt != null
        ? Timestamp.fromDate(lastMessageAt!)
        : null,
    'unread': {for (final m in members) m: 0},
    'muted': false,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Connection copyWith({
    String? id,
    List<String>? members,
    Map<String, Map<String, dynamic>>? memberSummaries,
    ConnectionKind? kind,
    bool? aiEnabled,
    String? lastMessage,
    DateTime? lastMessageAt,
    Map<String, int>? unread,
    bool? muted,
  }) => Connection(
    id: id ?? this.id,
    members: members ?? this.members,
    memberSummaries: memberSummaries ?? this.memberSummaries,
    kind: kind ?? this.kind,
    aiEnabled: aiEnabled ?? this.aiEnabled,
    lastMessage: lastMessage ?? this.lastMessage,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    unread: unread ?? this.unread,
    createdAt: createdAt,
    muted: muted ?? this.muted,
  );
}

/// Mutual AI opt-in state for one thread.
class CoachConsent {
  const CoachConsent({required this.myOptIn, required this.bothOptedIn});

  final bool myOptIn;
  final bool bothOptedIn;

  static const CoachConsent off = CoachConsent(
    myOptIn: false,
    bothOptedIn: false,
  );
}

/// An incoming friend request.
///
/// Firestore layout: `friendRequests/{id}` where `id` is
/// `{senderId}__{receiverId}` so duplicates are impossible at the database
/// level rather than relying on a client-side check.
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.sender,
    this.status = FriendRequestStatus.pending,
    this.createdAt,
    this.respondedAt,
    this.message,
  });

  final String id;
  final String senderId;
  final String receiverId;

  /// Denormalised sender summary so the requests list needs one query.
  final AppUser? sender;
  final FriendRequestStatus status;
  final DateTime? createdAt;
  final DateTime? respondedAt;
  final String? message;

  static String idFor(String senderId, String receiverId) =>
      '${senderId}__$receiverId';

  static FriendRequest fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? const {});

  static FriendRequest fromMap(String id, Map<String, dynamic> d) {
    final senderSummary = d['sender'];
    return FriendRequest(
      id: id,
      senderId: (d['senderId'] as String?) ?? '',
      receiverId: (d['receiverId'] as String?) ?? '',
      sender: senderSummary is Map
          ? AppUser.fromSummary(
              (d['senderId'] as String?) ?? '',
              Map<String, dynamic>.from(senderSummary),
            )
          : null,
      status: FriendRequestStatus.fromWire(d['status'] as String?),
      createdAt: dateField(d, 'createdAt'),
      respondedAt: dateField(d, 'respondedAt'),
      message: d['message'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'senderId': senderId,
    'receiverId': receiverId,
    'members': [senderId, receiverId],
    'sender': sender?.toSummary(),
    'status': status.wire,
    'message': message,
    'createdAt': FieldValue.serverTimestamp(),
    'respondedAt': null,
  };
}
