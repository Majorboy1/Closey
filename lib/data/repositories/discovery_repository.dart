import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/widgets/async_section.dart';
import '../models/app_user.dart';
import '../models/connection.dart';
import '../models/discovery.dart';
import 'user_repository.dart';

/// The swipe deck and match creation.
///
/// **This is a rebuilt feature, not a port.** `SwipeDeck.tsx` and
/// `MatchModal.tsx` existed in the Expo app but *no screen ever rendered
/// them* — `likeProfile`, `passProfile` and `listMutualLikes` were likewise
/// never called. The entire discovery loop was dead code. It is now the app's
/// primary tab.
///
/// Firestore layout:
/// ```
/// likes/{likerId}__{likeeId}      ← readable by both parties, writable by liker
/// passes/{passerId}__{passeeId}
/// connections/{a}__{b}            ← created inside a transaction on mutual like
/// ```
///
/// Match creation is a client-side **transaction**, so it is atomic: two people
/// swiping right on each other at the same instant cannot both create a
/// connection, because the deterministic doc id makes the second write a no-op
/// and the transaction re-reads the reciprocal like under a lock.
///
/// Side effects — push notifications and the AI opener — are handled by a
/// Firestore `onCreate` trigger on `connections`, not by the client. That keeps
/// the write path fast and means a match still produces an opener even if both
/// devices go offline immediately after swiping.
class DiscoveryRepository {
  DiscoveryRepository({FirebaseFirestore? db, UserRepository? users})
    : _db = db ?? FirebaseFirestore.instance,
      _users = users ?? UserRepository(db: db);

  final FirebaseFirestore _db;
  final UserRepository _users;

  CollectionReference<Map<String, dynamic>> get _likes =>
      _db.collection('likes');
  CollectionReference<Map<String, dynamic>> get _passes =>
      _db.collection('passes');
  CollectionReference<Map<String, dynamic>> get _connections =>
      _db.collection('connections');

  static String _pairId(String a, String b) => '${a}__$b';

  /// Builds the deck for [viewer].
  ///
  /// Postgres did this in one `discover_candidates` RPC with a PostGIS distance
  /// join. Firestore has no joins, so this fans out four cheap indexed queries
  /// and merges in memory. The candidate window is deliberately bounded
  /// ([scanWindow]) because the filtering Firestore cannot express — mutual
  /// blocks, already-swiped, reciprocal likes — has to happen client-side.
  ///
  /// At real scale the right answer is a `discoveryPool/{uid}` document that a
  /// scheduled Cloud Function refreshes nightly; the scan window keeps this
  /// correct and cheap until then.
  Future<List<DiscoveryCandidate>> fetchCandidates(
    AppUser viewer, {
    int limit = 40,
    int scanWindow = 120,
  }) async {
    final swiped = await _swipedIds(viewer.id);

    final snap = await _db
        .collection('users')
        .where('onboarded', isEqualTo: true)
        .where('age', isGreaterThanOrEqualTo: viewer.minAge)
        .where('age', isLessThanOrEqualTo: viewer.maxAge)
        .orderBy('age')
        .limit(scanWindow)
        .get();

    final candidates = <AppUser>[];
    for (final doc in snap.docs) {
      final user = AppUser.fromDoc(doc);
      if (!eligibleForDiscovery(user, viewer)) continue;
      if (swiped.contains(user.id)) continue;
      candidates.add(user);
    }

    if (candidates.isEmpty) return const [];

    // Who has already liked *me* — powers the "Likes you" ribbon and is
    // required to know whether a like will instantly match.
    final likedMe = await _likersOfMe(viewer.id);

    final results = <DiscoveryCandidate>[];
    for (final user in candidates.take(limit)) {
      final shared = user.interests
          .where(viewer.interests.contains)
          .toList(growable: false);

      double? distance;
      if (viewer.latitude != null &&
          viewer.longitude != null &&
          user.latitude != null &&
          user.longitude != null) {
        distance = haversineKm(
          lat1: viewer.latitude!,
          lon1: viewer.longitude!,
          lat2: user.latitude!,
          lon2: user.longitude!,
        );
        if (distance > viewer.maxDistanceKm) continue;
      }

      results.add(
        DiscoveryCandidate(
          user: user,
          distanceKm: distance,
          sharedInterests: shared,
          sharedInterestCount: shared.length,
          likedYou: likedMe.contains(user.id),
        ),
      );
    }

    // Best-first: people who liked you, then strongest shared-interest overlap,
    // then nearest. The Expo deck had no ordering at all, so the first card was
    // arbitrary — a poor first impression for a discovery product.
    results.sort((a, b) {
      if (a.likedYou != b.likedYou) return a.likedYou ? -1 : 1;
      if (a.sharedInterestCount != b.sharedInterestCount) {
        return b.sharedInterestCount.compareTo(a.sharedInterestCount);
      }
      final ad = a.distanceKm ?? double.infinity;
      final bd = b.distanceKm ?? double.infinity;
      return ad.compareTo(bd);
    });

    return results;
  }

  Future<Set<String>> _swipedIds(String uid) async {
    final results = await Future.wait([
      _likes.where('likerId', isEqualTo: uid).get(),
      _passes.where('passerId', isEqualTo: uid).get(),
    ]);
    return {
      ...results[0].docs.map((d) => (d.data()['likeeId'] as String?) ?? ''),
      ...results[1].docs.map((d) => (d.data()['passeeId'] as String?) ?? ''),
    }..remove('');
  }

  Future<Set<String>> _likersOfMe(String uid) async {
    final snap = await _likes.where('likeeId', isEqualTo: uid).get();
    return snap.docs
        .map((d) => (d.data()['likerId'] as String?) ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Records a right swipe and, if it is mutual, creates the connection.
  ///
  /// For a `superlike` the like is written with `super: true`; the recipient
  /// sees a "They super liked you" treatment in the deck.
  Future<SwipeOutcome> like({
    required AppUser viewer,
    required AppUser target,
    bool superLike = false,
  }) async {
    final likeRef = _likes.doc(_pairId(viewer.id, target.id));
    final reciprocalRef = _likes.doc(_pairId(target.id, viewer.id));
    final connectionRef = _connections.doc(
      Connection.idFor(viewer.id, target.id),
    );

    try {
      return await _db.runTransaction((tx) async {
        final reciprocal = await tx.get(reciprocalRef);

        tx.set(likeRef, {
          'likerId': viewer.id,
          'likeeId': target.id,
          'super': superLike,
          'members': [viewer.id, target.id],
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!reciprocal.exists) return SwipeOutcome.none;

        final existing = await tx.get(connectionRef);
        if (existing.exists) {
          return SwipeOutcome(isMatch: true, connectionId: connectionRef.id);
        }

        tx.set(connectionRef, {
          'members': Connection.sortedPair(viewer.id, target.id),
          'memberSummaries': {
            viewer.id: viewer.toSummary(),
            target.id: target.toSummary(),
          },
          'kind': 'dm',
          'aiEnabled': false,
          'lastMessage': null,
          'lastMessageAt': null,
          'unread': {viewer.id: 0, target.id: 0},
          'muted': false,
          'matchedFrom': 'swipe',
          'createdAt': FieldValue.serverTimestamp(),
        });

        return SwipeOutcome(isMatch: true, connectionId: connectionRef.id);
      });
    } on FirebaseException catch (e) {
      throw CloseyFailure(
        'Could not save that swipe: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }

  Future<void> pass({
    required String viewerId,
    required String targetId,
  }) async {
    await _passes.doc(_pairId(viewerId, targetId)).set({
      'passerId': viewerId,
      'passeeId': targetId,
      'members': [viewerId, targetId],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Undo. Removes the last pass or like so the card can come back.
  ///
  /// New feature: the Expo deck had no undo, which is a harsh experience for a
  /// gesture that is easy to mistrigger on a small screen. This is free for
  /// everyone — gating an accidental-swipe correction behind Premium is the
  /// kind of thing that makes people distrust a dating app.
  Future<void> undo({
    required String viewerId,
    required String targetId,
  }) async {
    final batch = _db.batch();
    batch.delete(_likes.doc(_pairId(viewerId, targetId)));
    batch.delete(_passes.doc(_pairId(viewerId, targetId)));
    await batch.commit();
  }

  /// Ids of people who liked you and whom you have not yet decided on —
  /// drives the "Likes you" count on the Discover tab.
  Future<int> incomingLikeCount(String uid) async {
    final likers = await _likersOfMe(uid);
    if (likers.isEmpty) return 0;
    final swiped = await _swipedIds(uid);
    return likers.difference(swiped).length;
  }

  /// Streams the number of new people who liked you.
  Stream<int> watchIncomingLikeCount(String uid) {
    return _likes.where('likeeId', isEqualTo: uid).snapshots().map((snap) {
      final ids = snap.docs
          .map((d) => (d.data()['likerId'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      return ids.length;
    });
  }

  /// People who liked you, resolved to full profiles, newest first.
  Future<List<AppUser>> listLikedYou(String uid, {int limit = 30}) async {
    final snap = await _likes
        .where('likeeId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    final ids = snap.docs
        .map((d) => (d.data()['likerId'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    final users = await _users.getUsersByIds(ids);
    return ids
        .map((id) => users[id])
        .whereType<AppUser>()
        .toList(growable: false);
  }

  @visibleForTesting
  static String pairIdForTesting(String a, String b) => _pairId(a, b);
}
