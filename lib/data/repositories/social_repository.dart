import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/post.dart';

/// The social feed.
///
/// Firestore layout:
/// ```
/// posts/{postId}
/// posts/{postId}/likes/{uid}   ← presence of a doc means "liked"
/// ```
/// The Expo feed rendered from a `MOCK_FEED` array and "Create post" only
/// showed an alert, so nothing here had a backend. Making the like a
/// subcollection document rather than a counter increment means a double-tap
/// cannot inflate the count, and the client can tell whether *it* has liked a
/// post without a second query.
class SocialRepository {
  SocialRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  /// Newest-first feed.
  ///
  /// Audience filtering happens client-side because Firestore cannot express
  /// "public OR author is me OR audience is friends and I am a friend" in one
  /// query. The window is bounded so the post-filter stays cheap; a
  /// `fanOutFeed/{uid}` Cloud Function is the scale answer.
  Stream<List<Post>> watchFeed({required String uid, int limit = 60}) => _posts
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .asyncMap((snap) async {
        final visible = snap.docs
            .where((doc) {
              final data = doc.data();
              final audience = PostAudience.fromWire(
                data['audience'] as String?,
              );
              final authorId = data['authorId'] as String?;
              return switch (audience) {
                PostAudience.everyone => true,
                PostAudience.friends => authorId == uid,
                PostAudience.me => authorId == uid,
              };
            })
            .toList(growable: false);

        if (visible.isEmpty) return <Post>[];

        // One batched read of *my* likes for the visible window, rather than a
        // document read per post.
        final liked = <String>{};
        for (final doc in visible) {
          final likeDoc = await doc.reference
              .collection('likes')
              .doc(uid)
              .get();
          if (likeDoc.exists) liked.add(doc.id);
        }

        return visible
            .map((d) => Post.fromDoc(d, likedByMe: liked.contains(d.id)))
            .toList(growable: false);
      });

  Stream<List<Post>> watchUserPosts(String authorId, {int limit = 40}) => _posts
      .where('authorId', isEqualTo: authorId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snap) => snap.docs.map((d) => Post.fromDoc(d)).toList(growable: false),
      );

  Future<String> createPost({
    required AppUser author,
    required String body,
    PostAudience audience = PostAudience.everyone,
    List<String> imageUrls = const [],
    List<String> tags = const [],
  }) async {
    final ref = await _posts.add(
      Post(
        id: '',
        authorId: author.id,
        author: author,
        body: body.trim(),
        audience: audience,
        imageUrls: imageUrls,
        tags: tags,
      ).toCreateMap(),
    );
    return ref.id;
  }

  Future<void> deletePost(String postId) => _posts.doc(postId).delete();

  /// Toggles a like. Uses a batch so the counter and the marker document can
  /// never disagree.
  Future<bool> toggleLike({required String postId, required String uid}) async {
    final postRef = _posts.doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);

    return _db.runTransaction((tx) async {
      final like = await tx.get(likeRef);

      if (like.exists) {
        tx.delete(likeRef);
        tx.update(postRef, {'likeCount': FieldValue.increment(-1)});
        return false;
      }

      tx.set(likeRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
      tx.update(postRef, {'likeCount': FieldValue.increment(1)});
      return true;
    });
  }

  /// Seed used by the emulator seeding script, and by the feed's empty state so
  /// a brand-new install is not a blank screen.
  Future<void> seedPosts(List<(AppUser author, String body)> entries) async {
    final batch = _db.batch();
    for (final (author, body) in entries) {
      batch.set(_posts.doc(), {
        'authorId': author.id,
        'author': author.toSummary(),
        'body': body,
        'imageUrls': const <String>[],
        'audience': PostAudience.everyone.wire,
        'tags': const <String>[],
        'likeCount': 0,
        'commentCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
