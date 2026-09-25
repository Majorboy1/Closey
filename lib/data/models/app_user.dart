import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/config/app_config.dart';
import 'enums.dart';

/// A Closey user.
///
/// Firestore layout: `users/{uid}`.
///
/// Notable differences from the Postgres `profiles` table:
/// * `interests` is a plain `List<String>` of labels rather than a join table
///   (`interests` + `profile_interests`). Firestore has no joins, and profile
///   reads are far more frequent than interest-list edits, so denormalising is
///   the right trade here. The canonical list still lives in
///   `interests/{label}` for the picker UI.
/// * `photos` is authoritative; `avatarUrl` mirrors `photos.first` so list
///   screens can render an avatar without reading the whole array.
/// * `age` is stored alongside `birthDate` because Firestore cannot compute it
///   in a `where` clause, and discovery filters on age range.
/// * `handle` is a stable, unique-ish slug used for `closey.app/{handle}`.
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    this.handle,
    this.birthDate,
    this.age,
    this.gender,
    this.city,
    this.country,
    this.bio,
    this.photos = const [],
    this.avatarUrl,
    this.interests = const [],
    this.conversationTopics = const [],
    this.promptQuestion,
    this.promptAnswer,
    this.verificationTier = VerificationTier.basic,
    this.onboarded = false,
    this.online = false,
    this.lastSeenAt,
    this.latitude,
    this.longitude,
    this.lookingFor = const [],
    this.minAge = DiscoveryDefaults.defaultMinAge,
    this.maxAge = DiscoveryDefaults.defaultMaxAge,
    this.maxDistanceKm = DiscoveryDefaults.defaultRadiusKm,
    this.notifyMatches = true,
    this.notifyMessages = true,
    this.notifySuggestions = true,
    this.showDistance = true,
    this.showOnline = true,
    this.blockedUserIds = const [],
    this.postCount = 0,
    this.connectionCount = 0,
    this.friendCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String fullName;

  /// Lowercased slug, e.g. `ada.lovelace`.
  final String? handle;
  final DateTime? birthDate;
  final int? age;
  final Gender? gender;
  final String? city;
  final String? country;
  final String? bio;
  final List<String> photos;
  final String? avatarUrl;
  final List<String> interests;

  /// "3 things you love talking about" — the free-form field that gives the
  /// coach richer material than interest tags alone (spec §5.1).
  final List<String> conversationTopics;
  final String? promptQuestion;
  final String? promptAnswer;
  final VerificationTier verificationTier;
  final bool onboarded;
  final bool online;
  final DateTime? lastSeenAt;
  final double? latitude;
  final double? longitude;
  final List<String> lookingFor;
  final int minAge;
  final int maxAge;
  final int maxDistanceKm;
  final bool notifyMatches;
  final bool notifyMessages;
  final bool notifySuggestions;
  final bool showDistance;
  final bool showOnline;

  /// Denormalised block list. Lets security rules and discovery queries exclude
  /// blocked people without an extra read per candidate.
  final List<String> blockedUserIds;

  final int postCount;
  final int connectionCount;
  final int friendCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayHandle => handle ?? _slug(fullName);

  /// Best available image for an avatar.
  String? get primaryPhoto => avatarUrl ?? photos.firstOrNull;

  bool get canUseCoach => verificationTier.canUseCoach && onboarded;

  List<String> get sharedPhotoList =>
      photos.isNotEmpty ? photos : [?primaryPhoto];

  static String _slug(String name) {
    final s = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '.');
    return s.replaceAll(RegExp(r'^\.+|\.+$'), '');
  }

  // ------------------------------------------------------------- Firestore --

  static AppUser fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? const {});

  static AppUser fromMap(String id, Map<String, dynamic> d) {
    final tier = d['verificationTier'] as String?;
    return AppUser(
      id: id,
      fullName: (d['fullName'] as String?) ?? '',
      handle: d['handle'] as String?,
      birthDate: dateField(d, 'birthDate'),
      age: (d['age'] as num?)?.toInt(),
      gender: Gender.fromWire(d['gender'] as String?),
      city: d['city'] as String?,
      country: d['country'] as String?,
      bio: d['bio'] as String?,
      photos: stringList(d, 'photos'),
      avatarUrl: d['avatarUrl'] as String?,
      interests: stringList(d, 'interests'),
      conversationTopics: stringList(d, 'conversationTopics'),
      promptQuestion: d['promptQuestion'] as String?,
      promptAnswer: d['promptAnswer'] as String?,
      verificationTier:
          VerificationTier.values.where((e) => e.name == tier).firstOrNull ??
          VerificationTier.basic,
      onboarded: (d['onboarded'] as bool?) ?? false,
      online: (d['online'] as bool?) ?? false,
      lastSeenAt: dateField(d, 'lastSeenAt'),
      latitude: (d['location'] as GeoPoint?)?.latitude,
      longitude: (d['location'] as GeoPoint?)?.longitude,
      lookingFor: stringList(d, 'lookingFor'),
      minAge: (d['minAge'] as num?)?.toInt() ?? DiscoveryDefaults.defaultMinAge,
      maxAge: (d['maxAge'] as num?)?.toInt() ?? DiscoveryDefaults.defaultMaxAge,
      maxDistanceKm:
          (d['maxDistanceKm'] as num?)?.toInt() ??
          DiscoveryDefaults.defaultRadiusKm,
      notifyMatches: (d['notifyMatches'] as bool?) ?? true,
      notifyMessages: (d['notifyMessages'] as bool?) ?? true,
      notifySuggestions: (d['notifySuggestions'] as bool?) ?? true,
      showDistance: (d['showDistance'] as bool?) ?? true,
      showOnline: (d['showOnline'] as bool?) ?? true,
      blockedUserIds: stringList(d, 'blockedUserIds'),
      postCount: (d['postCount'] as num?)?.toInt() ?? 0,
      connectionCount: (d['connectionCount'] as num?)?.toInt() ?? 0,
      friendCount: (d['friendCount'] as num?)?.toInt() ?? 0,
      createdAt: dateField(d, 'createdAt'),
      updatedAt: dateField(d, 'updatedAt'),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'fullName': fullName,
    'handle': displayHandle,
    'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
    'age': age,
    'gender': gender?.wire,
    'city': city,
    'country': country,
    'bio': bio,
    'photos': photos,
    'avatarUrl': primaryPhoto,
    'interests': interests,
    'conversationTopics': conversationTopics,
    'promptQuestion': promptQuestion,
    'promptAnswer': promptAnswer,
    'verificationTier': verificationTier.name,
    'onboarded': onboarded,
    'online': true,
    'lastSeenAt': FieldValue.serverTimestamp(),
    'location': (latitude != null && longitude != null)
        ? GeoPoint(latitude!, longitude!)
        : null,
    'lookingFor': lookingFor,
    'minAge': minAge,
    'maxAge': maxAge,
    'maxDistanceKm': maxDistanceKm,
    'notifyMatches': notifyMatches,
    'notifyMessages': notifyMessages,
    'notifySuggestions': notifySuggestions,
    'showDistance': showDistance,
    'showOnline': showOnline,
    'blockedUserIds': blockedUserIds,
    'postCount': postCount,
    'connectionCount': connectionCount,
    'friendCount': friendCount,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Partial update map — only the supplied fields are written.
  Map<String, dynamic> patch({
    String? fullName,
    DateTime? birthDate,
    int? age,
    Gender? gender,
    String? city,
    String? country,
    String? bio,
    List<String>? photos,
    List<String>? interests,
    List<String>? conversationTopics,
    String? promptQuestion,
    String? promptAnswer,
    List<String>? lookingFor,
    int? minAge,
    int? maxAge,
    int? maxDistanceKm,
    bool? onboarded,
    bool? notifyMatches,
    bool? notifyMessages,
    bool? notifySuggestions,
    bool? showDistance,
    bool? showOnline,
    VerificationTier? verificationTier,
    GeoPoint? location,
  }) {
    // Null-aware map entries (`'key': ?value`) omit the entry entirely when the
    // value is null, which is exactly the "only write what changed" semantics a
    // merge update needs — and it keeps this list declarative instead of a wall
    // of `if (x != null)` statements.
    final m = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'fullName': ?fullName,
      'age': ?age,
      'city': ?city,
      'country': ?country,
      'bio': ?bio,
      'interests': ?interests,
      'conversationTopics': ?conversationTopics,
      'promptQuestion': ?promptQuestion,
      'promptAnswer': ?promptAnswer,
      'lookingFor': ?lookingFor,
      'minAge': ?minAge,
      'maxAge': ?maxAge,
      'maxDistanceKm': ?maxDistanceKm,
      'onboarded': ?onboarded,
      'notifyMatches': ?notifyMatches,
      'notifyMessages': ?notifyMessages,
      'notifySuggestions': ?notifySuggestions,
      'showDistance': ?showDistance,
      'showOnline': ?showOnline,
    };

    // Entries that need a transform, or where writing `null` is meaningful.
    if (fullName != null) m['handle'] = _slug(fullName);
    if (birthDate != null) m['birthDate'] = Timestamp.fromDate(birthDate);
    if (gender != null) m['gender'] = gender.wire;
    if (verificationTier != null) m['verificationTier'] = verificationTier.name;
    if (location != null) m['location'] = location;
    if (photos != null) {
      m['photos'] = photos;
      // Mirror the first photo so list queries never read the whole array.
      m['avatarUrl'] = photos.firstOrNull;
    }

    return m;
  }

  /// Compact projection embedded in other documents (chat headers, posts) so
  /// list screens need one read instead of one per row.
  Map<String, dynamic> toSummary() => {
    'fullName': fullName,
    'handle': displayHandle,
    'avatarUrl': primaryPhoto,
    'verificationTier': verificationTier.name,
  };

  static AppUser fromSummary(String id, Map<String, dynamic> d) => AppUser(
    id: id,
    fullName: (d['fullName'] as String?) ?? '',
    handle: d['handle'] as String?,
    avatarUrl: d['avatarUrl'] as String?,
    verificationTier:
        VerificationTier.values
            .where((e) => e.name == d['verificationTier'])
            .firstOrNull ??
        VerificationTier.basic,
  );

  AppUser copyWith({
    String? id,
    String? fullName,
    String? handle,
    DateTime? birthDate,
    int? age,
    Gender? gender,
    String? city,
    String? country,
    String? bio,
    List<String>? photos,
    String? avatarUrl,
    List<String>? interests,
    List<String>? conversationTopics,
    String? promptQuestion,
    String? promptAnswer,
    VerificationTier? verificationTier,
    bool? onboarded,
    bool? online,
    DateTime? lastSeenAt,
    List<String>? lookingFor,
    int? minAge,
    int? maxAge,
    int? maxDistanceKm,
    bool? notifyMatches,
    bool? notifyMessages,
    bool? notifySuggestions,
    bool? showDistance,
    bool? showOnline,
    List<String>? blockedUserIds,
    int? postCount,
    int? connectionCount,
    int? friendCount,
  }) => AppUser(
    id: id ?? this.id,
    fullName: fullName ?? this.fullName,
    handle: handle ?? this.handle,
    birthDate: birthDate ?? this.birthDate,
    age: age ?? this.age,
    gender: gender ?? this.gender,
    city: city ?? this.city,
    country: country ?? this.country,
    bio: bio ?? this.bio,
    photos: photos ?? this.photos,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    interests: interests ?? this.interests,
    conversationTopics: conversationTopics ?? this.conversationTopics,
    promptQuestion: promptQuestion ?? this.promptQuestion,
    promptAnswer: promptAnswer ?? this.promptAnswer,
    verificationTier: verificationTier ?? this.verificationTier,
    onboarded: onboarded ?? this.onboarded,
    online: online ?? this.online,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    lookingFor: lookingFor ?? this.lookingFor,
    minAge: minAge ?? this.minAge,
    maxAge: maxAge ?? this.maxAge,
    maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
    notifyMatches: notifyMatches ?? this.notifyMatches,
    notifyMessages: notifyMessages ?? this.notifyMessages,
    notifySuggestions: notifySuggestions ?? this.notifySuggestions,
    showDistance: showDistance ?? this.showDistance,
    showOnline: showOnline ?? this.showOnline,
    blockedUserIds: blockedUserIds ?? this.blockedUserIds,
    postCount: postCount ?? this.postCount,
    connectionCount: connectionCount ?? this.connectionCount,
    friendCount: friendCount ?? this.friendCount,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// A brand-new, un-onboarded account created the moment auth succeeds.
  factory AppUser.empty(String id, {String fullName = ''}) =>
      AppUser(id: id, fullName: fullName);
}
