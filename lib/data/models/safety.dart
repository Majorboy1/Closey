import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';
import 'enums.dart';

/// A moderation report.
///
/// Firestore layout: `reports/{reportId}`, client-writable but
/// **not client-readable** (rules allow create, deny read/update/delete).
/// Otherwise a reported user could enumerate their own reports.
class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.reportedId,
    required this.reason,
    this.details,
    this.context,
    this.status = 'open',
    this.createdAt,
  });

  final String id;
  final String reporterId;
  final String reportedId;
  final String reason;
  final String? details;

  /// Where the report came from — `profile`, `chat`, `post`.
  final String? context;
  final String status;
  final DateTime? createdAt;

  static Report fromMap(String id, Map<String, dynamic> d) => Report(
    id: id,
    reporterId: (d['reporterId'] as String?) ?? '',
    reportedId: (d['reportedId'] as String?) ?? '',
    reason: (d['reason'] as String?) ?? '',
    details: d['details'] as String?,
    context: d['context'] as String?,
    status: (d['status'] as String?) ?? 'open',
    createdAt: dateField(d, 'createdAt'),
  );

  Map<String, dynamic> toCreateMap() => {
    'reporterId': reporterId,
    'reportedId': reportedId,
    'reason': reason,
    'details': details,
    'context': context,
    'status': 'open',
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// A blocked person, resolved with their profile for the blocked list.
///
/// Firestore layout: `users/{uid}/blocks/{blockedUid}` **and** a mirrored
/// entry in the blocker's `blockedUserIds` array.
///
/// The mirror matters: discovery runs `whereNotIn('blockedUserIds', ...)`, which
/// can only filter on a field of the document being queried. Without the array
/// the client would have to post-filter, leaking blocked people into the deck.
class BlockedUser {
  const BlockedUser({required this.user, this.blockedAt});

  final AppUser user;
  final DateTime? blockedAt;

  String get id => user.id;

  static String docId(String blockerId, String blockedId) =>
      '${blockerId}__$blockedId';
}
