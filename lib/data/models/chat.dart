import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A single chat message.
///
/// Firestore layout: `connections/{connectionId}/messages/{messageId}`.
///
/// Kept as a subcollection rather than a top-level `messages` collection so
/// that security rules inherit from the parent connection — a message can only
/// ever be read by the two people in it, and there is no way to write a message
/// into someone else's thread.
class Message {
  const Message({
    required this.id,
    required this.connectionId,
    required this.senderId,
    required this.body,
    this.createdAt,
    this.sendState = MessageSendState.sent,
    this.readBy = const [],
  });

  final String id;
  final String connectionId;
  final String senderId;
  final String body;
  final DateTime? createdAt;

  /// Optimistic-send state. New: the Expo chat waited for the realtime round
  /// trip before showing anything, so a slow network looked like a failed send.
  final MessageSendState sendState;
  final List<String> readBy;

  bool isMine(String viewerId) => senderId == viewerId;

  static Message fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String connectionId,
  }) => fromMap(doc.id, doc.data() ?? const {}, connectionId: connectionId);

  static Message fromMap(
    String id,
    Map<String, dynamic> d, {
    required String connectionId,
  }) => Message(
    id: id,
    connectionId: connectionId,
    senderId: (d['senderId'] as String?) ?? '',
    body: (d['body'] as String?) ?? '',
    createdAt: dateField(d, 'createdAt'),
    readBy: stringList(d, 'readBy'),
  );

  Map<String, dynamic> toCreateMap() => {
    'senderId': senderId,
    'body': body,
    'readBy': const <String>[],
    'createdAt': FieldValue.serverTimestamp(),
  };

  Message copyWith({
    String? id,
    String? body,
    DateTime? createdAt,
    MessageSendState? sendState,
  }) => Message(
    id: id ?? this.id,
    connectionId: connectionId,
    senderId: senderId,
    body: body ?? this.body,
    createdAt: createdAt ?? this.createdAt,
    sendState: sendState ?? this.sendState,
    readBy: readBy,
  );

  /// A locally-created message that has not yet been acknowledged by the server.
  factory Message.pending({
    required String id,
    required String connectionId,
    required String senderId,
    required String body,
  }) => Message(
    id: id,
    connectionId: connectionId,
    senderId: senderId,
    body: body,
    createdAt: DateTime.now(),
    sendState: MessageSendState.sending,
  );
}

enum MessageSendState { sending, sent, failed }

/// A coach suggestion.
///
/// Firestore layout: `connections/{connectionId}/suggestions/{suggestionId}`.
///
/// **Security note.** A `private` suggestion carries a `targetUserId`, and the
/// security rules must restrict reads of such a document to that user only.
/// The Expo implementation got this right at the RLS layer but the client also
/// received private suggestions over a *shared* realtime channel; Firestore
/// snapshots are rule-filtered per listener, so the partner's device genuinely
/// never sees the document. That is a real upgrade in the privacy guarantee
/// behind the product's core differentiator.
class AiSuggestion {
  const AiSuggestion({
    required this.id,
    required this.connectionId,
    required this.content,
    this.reason,
    this.status = SuggestionStatus.active,
    this.type,
    this.visibility = SuggestionVisibility.shared,
    this.targetUserId,
    this.trigger,
    this.requestedBy,
    this.basedOn = const [],
    this.createdAt,
  });

  final String id;
  final String connectionId;

  /// What the user could actually say. Phrased as a message, not as advice —
  /// the spec is explicit that the coach must not speak *as* the user.
  final String content;

  /// Why the coach surfaced this. Surfaced in the UI so unprompted cards never
  /// feel arbitrary.
  final String? reason;

  final SuggestionStatus status;
  final SuggestionType? type;
  final SuggestionVisibility visibility;
  final String? targetUserId;
  final SuggestionTrigger? trigger;
  final String? requestedBy;

  /// Which signals the model used — message ids, interests, profile fields.
  final List<String> basedOn;
  final DateTime? createdAt;

  bool get isPrivate => visibility == SuggestionVisibility.private;

  bool isVisibleTo(String uid) => !isPrivate || targetUserId == uid;

  /// Human explanation of why this appeared.
  String get whyThis =>
      reason ??
      trigger?.explanation ??
      type?.hint ??
      'A suggestion to keep things moving.';

  static AiSuggestion fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String connectionId,
  }) => fromMap(doc.id, doc.data() ?? const {}, connectionId: connectionId);

  static AiSuggestion fromMap(
    String id,
    Map<String, dynamic> d, {
    required String connectionId,
  }) => AiSuggestion(
    id: id,
    connectionId: connectionId,
    content: (d['content'] as String?) ?? '',
    reason: d['reason'] as String?,
    status: SuggestionStatus.fromWire(d['status'] as String?),
    type: SuggestionType.fromWire(d['suggestionType'] as String?),
    visibility: SuggestionVisibility.fromWire(d['visibility'] as String?),
    targetUserId: d['targetUserId'] as String?,
    trigger: SuggestionTrigger.fromWire(d['triggeredBy'] as String?),
    requestedBy: d['requestedBy'] as String?,
    basedOn: stringList(d, 'basedOn'),
    createdAt: dateField(d, 'createdAt'),
  );

  Map<String, dynamic> toCreateMap() => {
    'content': content,
    'reason': reason,
    'status': status.wire,
    'suggestionType': type?.wire,
    'visibility': visibility.wire,
    'targetUserId': targetUserId,
    'triggeredBy': trigger?.wire,
    'requestedBy': requestedBy,
    'basedOn': basedOn,
    'createdAt': FieldValue.serverTimestamp(),
  };
}
