import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';
import 'enums.dart';

/// A social feed post.
///
/// Firestore layout: `posts/{postId}`, newest-first index on `createdAt`.
///
/// The Postgres schema never actually had a posts table — the Expo feed read
/// from a `MOCK_FEED` constant and "Create post" just showed an alert. This
/// models it properly so the feed and composer are real.
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.body,
    this.author,
    this.imageUrls = const [],
    this.audience = PostAudience.everyone,
    this.tags = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String body;

  /// Denormalised author so the feed renders from one query.
  final AppUser? author;
  final List<String> imageUrls;
  final PostAudience audience;
  final List<String> tags;
  final int likeCount;
  final int commentCount;

  /// Derived from a `likes/{postId}__{uid}` marker document.
  final bool likedByMe;
  final DateTime? createdAt;

  static String likeDocId(String postId, String uid) => '${postId}__$uid';

  static Post fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool likedByMe = false,
  }) => fromMap(doc.id, doc.data() ?? const {}, likedByMe: likedByMe);

  static Post fromMap(
    String id,
    Map<String, dynamic> d, {
    bool likedByMe = false,
  }) {
    final author = d['author'];
    return Post(
      id: id,
      authorId: (d['authorId'] as String?) ?? '',
      body: (d['body'] as String?) ?? '',
      author: author is Map
          ? AppUser.fromSummary(
              (d['authorId'] as String?) ?? '',
              Map<String, dynamic>.from(author),
            )
          : null,
      imageUrls: stringList(d, 'imageUrls'),
      audience: PostAudience.fromWire(d['audience'] as String?),
      tags: stringList(d, 'tags'),
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
      likedByMe: likedByMe,
      createdAt: dateField(d, 'createdAt'),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'authorId': authorId,
    'author': author?.toSummary(),
    'body': body,
    'imageUrls': imageUrls,
    'audience': audience.wire,
    'tags': tags,
    'likeCount': 0,
    'commentCount': 0,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Post copyWith({int? likeCount, bool? likedByMe}) => Post(
    id: id,
    authorId: authorId,
    body: body,
    author: author,
    imageUrls: imageUrls,
    audience: audience,
    tags: tags,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount,
    likedByMe: likedByMe ?? this.likedByMe,
    createdAt: createdAt,
  );
}
