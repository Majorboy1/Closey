import 'app_user.dart';

/// A discovery candidate: a profile plus the computed signals the deck needs.
///
/// In Postgres this was the `discover_candidates` RPC. Firestore has no
/// server-side joins, so the composition happens in
/// `DiscoveryRepository`, which fans out a handful of indexed queries
/// (shared-interest overlap, likes received, connections) and merges them.
/// The result is cached in memory for the session so swiping stays instant.
class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.user,
    this.distanceKm,
    this.sharedInterestCount = 0,
    this.sharedInterests = const [],
    this.likedYou = false,
    this.likedByMe = false,
  });

  final AppUser user;
  final double? distanceKm;
  final int sharedInterestCount;
  final List<String> sharedInterests;

  /// They already liked you. Surfaced in the deck as a "Likes you" ribbon â€”
  /// a confident, low-cost signal that also nudges the user to act.
  final bool likedYou;
  final bool likedByMe;

  String get id => user.id;

  DiscoveryCandidate copyWith({bool? likedByMe}) => DiscoveryCandidate(
    user: user,
    distanceKm: distanceKm,
    sharedInterestCount: sharedInterestCount,
    sharedInterests: sharedInterests,
    likedYou: likedYou,
    likedByMe: likedByMe ?? this.likedByMe,
  );
}

/// The outcome of a swipe, returned so the caller can decide whether to show
/// the match celebration.
class SwipeOutcome {
  const SwipeOutcome({required this.isMatch, this.connectionId});

  final bool isMatch;
  final String? connectionId;

  static const SwipeOutcome none = SwipeOutcome(isMatch: false);
}
