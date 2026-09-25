import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/async_section.dart';
import '../models/app_user.dart';
import '../models/enums.dart';

/// Profile reads/writes, interests, presence and photo upload.
///
/// Firestore layout:
/// ```
/// users/{uid}                        ← profile document
/// users/{uid}/private/account        ← quota, subscription, push tokens
/// ```
/// The `private` subcollection is the security boundary: rules allow the owner
/// to read it but **never** to write quota or subscription fields, which only
/// Cloud Functions may change. The client cannot grant itself credits.
class UserRepository {
  UserRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ------------------------------------------------------------------ reads

  /// Live profile stream. The app's session state is driven entirely by this,
  /// so a Cloud Function flipping `verificationTier` updates the UI with no
  /// refresh — the Expo version required a manual `refreshProfile()` call
  /// after every mutation.
  Stream<AppUser?> watchUser(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);

  Future<AppUser?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  Future<Map<String, AppUser>> getUsersByIds(Iterable<String> ids) async {
    final unique = ids.toSet().toList(growable: false);
    if (unique.isEmpty) return {};

    // Firestore caps `whereIn` at 30 values per query.
    final result = <String, AppUser>{};
    for (var i = 0; i < unique.length; i += 30) {
      final chunk = unique.sublist(i, (i + 30).clamp(0, unique.length));
      final snap = await _users
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        result[doc.id] = AppUser.fromDoc(doc);
      }
    }
    return result;
  }

  /// Case-insensitive-ish name search for the Connect tab. Firestore has no
  /// `LIKE`, so this uses a prefix range scan on a lowercased `fullName` field.
  Future<List<AppUser>> searchByName(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final snap = await _users
        .orderBy('fullNameLower')
        .startAt([q])
        .endAt(['$q\uf8ff'])
        .limit(limit)
        .get();
    return snap.docs.map(AppUser.fromDoc).toList(growable: false);
  }

  // ----------------------------------------------------------------- writes

  /// Creates the profile document if it does not exist yet.
  ///
  /// Called right after any successful sign-in so that a user always has a
  /// document to read. Uses a transaction so two rapid launches cannot race
  /// into creating two documents or clobbering a real profile.
  Future<AppUser> ensureUserDocument({
    required String uid,
    String? fullName,
    String? avatarUrl,
  }) async {
    final ref = _users.doc(uid);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return AppUser.fromDoc(snap);

      final seed = AppUser(
        id: uid,
        fullName: (fullName ?? '').trim(),
        avatarUrl: avatarUrl,
        photos: avatarUrl != null ? [avatarUrl] : const [],
      );
      tx.set(ref, {
        ...seed.toCreateMap(),
        'fullNameLower': seed.fullName.toLowerCase(),
      });
      return seed;
    });
  }

  Future<void> updateProfile(
    String uid, {
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
    GeoPoint? location,
  }) async {
    final patch = AppUser.empty(uid).patch(
      fullName: fullName,
      birthDate: birthDate,
      age: age,
      gender: gender,
      city: city,
      country: country,
      bio: bio,
      photos: photos,
      interests: interests,
      conversationTopics: conversationTopics,
      promptQuestion: promptQuestion,
      promptAnswer: promptAnswer,
      lookingFor: lookingFor,
      minAge: minAge,
      maxAge: maxAge,
      maxDistanceKm: maxDistanceKm,
      onboarded: onboarded,
      notifyMatches: notifyMatches,
      notifyMessages: notifyMessages,
      notifySuggestions: notifySuggestions,
      showDistance: showDistance,
      showOnline: showOnline,
      location: location,
    );

    if (fullName != null) patch['fullNameLower'] = fullName.toLowerCase();

    // Strip the nulls the builder leaves in for absent arguments.
    patch.removeWhere((_, v) => v == null);

    if (patch.length <= 1) return;
    await _users.doc(uid).set(patch, SetOptions(merge: true));
  }

  /// Writes the tier directly. In production this is guarded by a Firestore
  /// rule that only allows client writes to `verificationTier` when a
  /// verification session has completed; the KYC webhook does it normally.
  Future<void> setVerificationTier(String uid, VerificationTier tier) =>
      _users.doc(uid).set({
        'verificationTier': tier.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // -------------------------------------------------------------- presence

  Future<void> setOnline(String uid, bool online) async {
    try {
      await _users.doc(uid).set({
        'online': online,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Presence is best-effort; never surface an error for it.
    }
  }

  // ------------------------------------------------------------- interests

  /// Canonical interest list, used to populate the picker.
  Future<List<String>> listInterestCatalog() async {
    final snap = await _db.collection('interests').orderBy('label').get();
    return snap.docs
        .map((d) => (d.data()['label'] as String?) ?? d.id)
        .toList(growable: false);
  }

  // --------------------------------------------------------------- photos

  /// Uploads a photo to Firebase Storage and returns its public download URL.
  ///
  /// Takes an [XFile] and writes bytes via `putData` rather than taking a
  /// `dart:io` `File`. `dart:io` does not exist on web, and importing it makes
  /// the whole app fail to compile for the browser — so `putFile` is not an
  /// option despite being marginally more efficient on mobile.
  ///
  /// Path is `users/{uid}/{folder}/{timestamp}-{name}`. The timestamp prefix
  /// means an interrupted update never orphans or overwrites the previous
  /// photo, which the previous implementation could do.
  Future<String> uploadPhoto({
    required String uid,
    required XFile file,
    String folder = 'photos',
    void Function(double progress)? onProgress,
  }) async {
    final originalName = file.name.trim().isEmpty
        ? 'photo.jpg'
        : file.name.trim();
    final name = '${DateTime.now().millisecondsSinceEpoch}-$originalName';
    final ref = FirebaseStorage.instance.ref('users/$uid/$folder/$name');

    final bytes = await file.readAsBytes();

    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: file.mimeType ?? _contentType(_extensionOf(originalName)),
      ),
    );

    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }

    try {
      await task;
    } on FirebaseException catch (e) {
      throw CloseyFailure(
        e.code == 'unauthorized'
            ? 'Storage rules rejected the upload. Check that '
                  'storage.rules allows writes to users/{uid}.'
            : 'Upload failed: ${e.message ?? e.code}',
        code: e.code,
      );
    }

    return ref.getDownloadURL();
  }

  Future<void> deletePhotoByUrl(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('Closey: could not delete photo ($e)');
    }
  }

  /// Registers the device for push notifications.
  Future<void> savePushToken(String uid, String token, String platform) =>
      _users.doc(uid).collection('private').doc('account').set({
        'pushTokens': FieldValue.arrayUnion(['$platform:$token']),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'jpg';
    return path.substring(dot + 1).toLowerCase();
  }

  static String _contentType(String ext) => switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    _ => 'image/jpeg',
  };
}

/// Derives a plausible age from a birthdate, clamped to the app's range.
int ageFromBirthDate(DateTime birthDate) {
  final now = DateTime.now();
  var age = now.year - birthDate.year;
  final hadBirthday =
      now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);
  if (!hadBirthday) age -= 1;
  return age.clamp(0, 130);
}

bool isAtLeast18(DateTime birthDate) => ageFromBirthDate(birthDate) >= 18;

/// Distance between two coordinates, in kilometres (great-circle).
double haversineKm({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadiusKm = 6371.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return earthRadiusKm * 2 * math.asin(math.sqrt(a));
}

double _rad(double deg) => deg * math.pi / 180.0;

/// Distance label used on profile cards, respecting the viewer's privacy
/// setting — the Expo version rendered distance unconditionally.
String formatDistance(double? km, {bool allowed = true}) {
  if (!allowed || km == null) return 'Nearby';
  if (km < 1) return 'Less than 1 km away';
  if (km < 10) return '${km.toStringAsFixed(1)} km away';
  return '${km.round()} km away';
}

/// Whether this profile is allowed to appear in the deck.
bool eligibleForDiscovery(AppUser user, AppUser viewer) {
  if (user.id == viewer.id) return false;
  if (!user.onboarded) return false;
  if (user.blockedUserIds.contains(viewer.id)) return false;
  if (viewer.blockedUserIds.contains(user.id)) return false;
  if (user.age == null) return false;
  if (user.age! < DiscoveryDefaults.minAge) return false;
  return true;
}
