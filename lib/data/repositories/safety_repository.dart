import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/widgets/async_section.dart';
import '../firebase/firebase_bootstrap.dart';
import '../models/app_user.dart';
import '../models/safety.dart';

/// Reporting, blocking, unmatching and account deletion.
///
/// Firestore layout:
/// ```
/// reports/{reportId}                     ← create-only for clients
/// users/{uid}/blocks/{blockedId}         ← plus a mirror in blockedUserIds
/// users/{uid}/private/account
/// ```
///
/// Block and unblock are **callable Cloud Functions** because a block has to
/// touch several documents across two users' data (block list on both sides,
/// tear down the connection, hide future posts). A client that could write the
/// other person's block list would be a serious privilege problem.
class SafetyRepository {
  SafetyRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FirebaseBootstrap.functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  // --------------------------------------------------------------- reports

  /// Files a report.
  ///
  /// Written straight to Firestore rather than through a function: the rules
  /// allow `create` and deny `read`/`update`/`delete`, so a reporter can submit
  /// but cannot browse or tamper with reports afterwards. Fails soft — if the
  /// write is rejected we still let the caller block the person, because
  /// blocking is the action that actually protects the user.
  Future<void> reportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
    String? details,
    String context = 'profile',
  }) async {
    try {
      await _db
          .collection('reports')
          .add(
            Report(
              id: '',
              reporterId: reporterId,
              reportedId: reportedId,
              reason: reason,
              details: details,
              context: context,
            ).toCreateMap(),
          );
    } on FirebaseException catch (e) {
      throw CloseyFailure(
        'We could not submit that report. Try blocking them instead — '
        'that takes effect immediately. (${e.code})',
      );
    }
  }

  // ---------------------------------------------------------------- blocks

  Future<void> blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      await _functions.httpsCallable('blockUser').call<Map<String, dynamic>>({
        'blockedId': blockedId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw CloseyFailure(
        e.message ?? 'Could not block that person right now.',
        code: e.code,
      );
    }
  }

  Future<void> unblockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      await _functions.httpsCallable('unblockUser').call<Map<String, dynamic>>({
        'blockedId': blockedId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw CloseyFailure(
        e.message ?? 'Could not unblock that person right now.',
        code: e.code,
      );
    }
  }

  /// Live list of blocked people, resolved to profiles for the settings screen.
  Stream<List<BlockedUser>> watchBlockedUsers(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('blocks')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .asyncMap((snap) async {
        final ids = snap.docs.map((d) => d.id).toList(growable: false);
        if (ids.isEmpty) return <BlockedUser>[];

        final profiles = <String, AppUser>{};
        for (var i = 0; i < ids.length; i += 30) {
          final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
          final users = await _db
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final doc in users.docs) {
            profiles[doc.id] = AppUser.fromDoc(doc);
          }
        }

        return snap.docs
            .where((d) => profiles.containsKey(d.id))
            .map(
              (d) => BlockedUser(
                user: profiles[d.id]!,
                blockedAt: (d.data()['createdAt'] as Timestamp?)?.toDate(),
              ),
            )
            .toList(growable: false);
      });

  // -------------------------------------------------------------- unmatch

  /// Ends a connection. Server-side because it has to delete the message and
  /// suggestion subcollections — Firestore does not cascade deletes, and a
  /// client can only delete documents one at a time.
  Future<void> unmatch(String connectionId) async {
    try {
      await _functions
          .httpsCallable('unmatchConnection')
          .call<Map<String, dynamic>>({'connectionId': connectionId});
    } on FirebaseFunctionsException catch (e) {
      throw CloseyFailure(
        e.message ?? 'Could not end that connection.',
        code: e.code,
      );
    }
  }

  // --------------------------------------------------------------- account

  /// Removes the signed-in user's data, then their auth record.
  ///
  /// Split deliberately: the client deletes its own profile document and
  /// private subcollection (it has permission), then calls this to have the
  /// function sweep the *other* documents that reference the user — their side
  /// of connections, messages they sent, likes they gave, posts they wrote.
  /// An `onUserDeleted` auth trigger is the backstop if the app dies midway.
  Future<void> requestDataSweep() async {
    try {
      await _functions.httpsCallable('deleteAccountData').call<void>({});
    } on FirebaseFunctionsException catch (e) {
      // Non-fatal: the auth trigger will finish the job.
      throw CloseyFailure(
        'Your account is deleted, but some data cleanup was queued for later '
        '(${e.code}).',
        isRetryable: false,
      );
    }
  }
}
