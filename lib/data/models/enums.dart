import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain enums.
///
/// Firestore stores these as their `wire` string rather than an integer, so a
/// value read back from the console is self-describing and reordering the enum
/// can never silently remap existing documents — a hazard the Postgres version
/// avoided with CHECK constraints but which Dart enums do not give you free.

enum Gender {
  woman('woman', 'Woman'),
  man('man', 'Man'),
  nonbinary('nonbinary', 'Non-binary'),
  other('other', 'Other'),
  undisclosed('prefer_not_to_say', 'Prefer not to say');

  const Gender(this.wire, this.label);
  final String wire;
  final String label;

  static Gender? fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull;
}

enum LookingFor {
  woman('woman', 'Women'),
  man('man', 'Men'),
  nonbinary('nonbinary', 'Non-binary people'),
  everyone('everyone', 'Everyone');

  const LookingFor(this.wire, this.label);
  final String wire;
  final String label;

  static LookingFor? fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull;
}

/// The AI coach's suggestion taxonomy (spec §5.4).
enum SuggestionType {
  opener('opener', 'Conversation starter', 'Break the ice'),
  reciprocityNudge('reciprocity_nudge', 'Just for you', 'Balance the thread'),
  topicContinuation(
    'topic_continuation',
    'Keep it going',
    'Build on what you said',
  ),
  newTopic('new_topic', 'New topic', 'Try something new'),
  deepeningQuestion('deepening_question', 'Go deeper', 'Move past small talk'),
  icebreakerGame('icebreaker_game', 'Icebreaker', 'A playful prompt');

  const SuggestionType(this.wire, this.label, this.hint);
  final String wire;

  /// Chip label shown on the coach card.
  final String label;

  /// One-line explanation of what the coach is trying to do. This is new —
  /// the Expo app showed a label but never told the user *why* the suggestion
  /// appeared, which made unprompted cards feel arbitrary.
  final String hint;

  static SuggestionType? fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull;
}

/// Whether a suggestion is visible to both people or just the one being nudged.
enum SuggestionVisibility {
  shared('shared'),
  private('private');

  const SuggestionVisibility(this.wire);
  final String wire;

  static SuggestionVisibility fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ??
      SuggestionVisibility.shared;
}

/// What caused the coach to speak up.
enum SuggestionTrigger {
  matchCreated('match_created', 'You just matched'),
  oneSidedAnswer('one_sided_answer', 'One person answered without asking back'),
  silenceTimeout('silence_timeout', 'The conversation went quiet'),
  userRequested('user_requested', 'You asked for help'),
  deepening('deepening', 'This thread is staying surface-level');

  const SuggestionTrigger(this.wire, this.explanation);
  final String wire;
  final String explanation;

  static SuggestionTrigger? fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull;
}

enum SuggestionStatus {
  active('active'),
  used('used'),
  dismissed('dismissed');

  const SuggestionStatus(this.wire);
  final String wire;

  static SuggestionStatus fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? SuggestionStatus.active;
}

/// `friend` connections get unlimited chat; `dm` connections are metered.
enum ConnectionKind {
  friend('friend', 'Friend'),
  dm('dm', 'Direct message');

  const ConnectionKind(this.wire, this.label);
  final String wire;
  final String label;

  static ConnectionKind fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? ConnectionKind.dm;
}

enum FriendRequestStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  cancelled('cancelled');

  const FriendRequestStatus(this.wire);
  final String wire;

  static FriendRequestStatus fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ??
      FriendRequestStatus.pending;
}

enum MeetingStatus {
  proposed('proposed', 'Proposed'),
  accepted('accepted', 'Confirmed'),
  declined('declined', 'Declined'),
  completed('completed', 'Met up'),
  cancelled('cancelled', 'Cancelled');

  const MeetingStatus(this.wire, this.label);
  final String wire;
  final String label;

  static MeetingStatus fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? MeetingStatus.proposed;
}

enum PostAudience {
  everyone('everyone', 'Everyone'),
  friends('friends', 'Close friends only'),
  me('me', 'Only me');

  const PostAudience(this.wire, this.label);
  final String wire;
  final String label;

  static PostAudience fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? PostAudience.everyone;
}

/// Shared helpers for tolerant Firestore decoding.
extension TimestampX on Timestamp? {
  DateTime? get dateTimeOrNull => this?.toDate();
}

/// Reads a Firestore value that may legitimately be absent.
T? field<T>(Map<String, dynamic> data, String key) {
  final v = data[key];
  return v is T ? v : null;
}

DateTime? dateField(Map<String, dynamic> data, String key) {
  final v = data[key];
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

List<String> stringList(Map<String, dynamic> data, String key) {
  final v = data[key];
  if (v is List) return v.whereType<String>().toList(growable: false);
  return const <String>[];
}
