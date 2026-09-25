import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/connection.dart';
import '../models/enums.dart';
import '../models/meeting.dart';

/// Planned meetups.
///
/// Firestore layout: `meetings/{meetingId}` — top level rather than a
/// subcollection, because the Plans screen queries *across* every connection
/// by date range. A `members` array plus a `scheduledAt` index makes that a
/// single query; a collection-group query would have needed a much looser rule.
class MeetingRepository {
  MeetingRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _meetings =>
      _db.collection('meetings');

  /// Meetings across all of this user's connections, soonest first.
  ///
  /// Note: this is the one feature the Expo app shipped completely unreachable
  /// — `plans.tsx` was registered with `href: null` and no screen ever pushed
  /// to it, so the calendar, the time-slot picker and the Google Calendar
  /// hand-off were all dead code. It is now reachable from Chats and Profile.
  Stream<List<Meeting>> watchMyMeetings(String uid) => _meetings
      .where('members', arrayContains: uid)
      .orderBy('scheduledAt')
      .snapshots()
      .map((snap) => snap.docs.map(Meeting.fromDoc).toList(growable: false));

  /// Only meetings that have not already happened, for the "upcoming" list.
  Future<List<Meeting>> listUpcoming(String uid, {int limit = 50}) async {
    final snap = await _meetings
        .where('members', arrayContains: uid)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.now())
        .orderBy('scheduledAt')
        .limit(limit)
        .get();
    return snap.docs.map(Meeting.fromDoc).toList(growable: false);
  }

  Future<String> createMeeting({
    required Connection connection,
    required String proposedBy,
    required DateTime scheduledAt,
    String? note,
  }) async {
    final otherId = connection.otherId(proposedBy);

    final ref = await _meetings.add({
      'connectionId': connection.id,
      'members': Connection.sortedPair(proposedBy, otherId),
      'proposedBy': proposedBy,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      'status': MeetingStatus.proposed.wire,
      'otherUserId': otherId,
      'otherUser': connection.memberSummaries[otherId],
      'createdAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  Future<void> updateStatus(String meetingId, MeetingStatus status) =>
      _meetings.doc(meetingId).update({
        'status': status.wire,
        'respondedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteMeeting(String meetingId) =>
      _meetings.doc(meetingId).delete();

  /// Day keys (`yyyy-MM-dd`) that have at least one meeting — the calendar
  /// uses these to draw its dots.
  static Set<String> markedDays(Iterable<Meeting> meetings) =>
      meetings.map((m) => isoDay(m.scheduledAt)).toSet();

  static String isoDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
