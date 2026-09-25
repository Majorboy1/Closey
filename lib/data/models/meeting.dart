import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';
import 'enums.dart';

/// A planned real-world meetup between two connections.
///
/// Firestore layout: `meetings/{meetingId}`.
///
/// Kept top-level (not a subcollection of the connection) because the Plans
/// screen queries *across* all of a user's connections by date range. A
/// `members` array plus a `scheduledAt` index makes that one query; a
/// collection-group query would have required a much looser security rule.
class Meeting {
  const Meeting({
    required this.id,
    required this.connectionId,
    required this.members,
    required this.proposedBy,
    required this.scheduledAt,
    this.note,
    this.status = MeetingStatus.proposed,
    this.otherUser,
    this.createdAt,
  });

  final String id;
  final String connectionId;
  final List<String> members;
  final String proposedBy;
  final DateTime scheduledAt;
  final String? note;
  final MeetingStatus status;

  /// Denormalised partner summary so the Plans list stays a single query.
  final AppUser? otherUser;
  final DateTime? createdAt;

  bool isMine(String uid) => proposedBy == uid;

  bool canRespond(String uid) =>
      status == MeetingStatus.proposed && !isMine(uid);

  bool get isUpcoming =>
      scheduledAt.isAfter(DateTime.now()) &&
      status != MeetingStatus.cancelled &&
      status != MeetingStatus.declined;

  /// Google Calendar deep link — a 1-hour block with the note as the
  /// description. The Expo build produced the same URL, but the screen that
  /// used it was unreachable from anywhere in the app.
  String googleCalendarUrl() {
    String fmt(DateTime d) {
      final iso = d.toUtc().toIso8601String().split('.').first;
      return '${iso.replaceAll(RegExp(r'[-:]'), '')}Z';
    }

    final title = Uri.encodeComponent(
      'Closey: meet ${otherUser?.fullName ?? 'your match'}',
    );
    final details = Uri.encodeComponent(note ?? 'Planned on Closey.');
    final end = scheduledAt.add(const Duration(hours: 1));

    return 'https://calendar.google.com/calendar/render?action=TEMPLATE'
        '&text=$title'
        '&dates=${fmt(scheduledAt)}/${fmt(end)}'
        '&details=$details';
  }

  static Meeting fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? const {});

  static Meeting fromMap(String id, Map<String, dynamic> d) {
    final other = d['otherUser'];
    return Meeting(
      id: id,
      connectionId: (d['connectionId'] as String?) ?? '',
      members: stringList(d, 'members'),
      proposedBy: (d['proposedBy'] as String?) ?? '',
      scheduledAt: dateField(d, 'scheduledAt') ?? DateTime.now(),
      note: d['note'] as String?,
      status: MeetingStatus.fromWire(d['status'] as String?),
      otherUser: other is Map
          ? AppUser.fromSummary(
              (d['otherUserId'] as String?) ?? '',
              Map<String, dynamic>.from(other),
            )
          : null,
      createdAt: dateField(d, 'createdAt'),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'connectionId': connectionId,
    'members': members,
    'proposedBy': proposedBy,
    'scheduledAt': Timestamp.fromDate(scheduledAt),
    'note': note,
    'status': status.wire,
    'otherUserId': otherUser?.id,
    'otherUser': otherUser?.toSummary(),
    'createdAt': FieldValue.serverTimestamp(),
  };
}
