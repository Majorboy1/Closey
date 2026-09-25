import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/widgets/async_section.dart';

/// Everything auth.
///
/// All of the Expo app's auth lived in five loose functions inside a 605-line
/// `api.ts`, errors surfaced through `Alert.alert`, and `signInWithGoogle`
/// called `WebBrowser.openAuthSessionAsync` against a Supabase redirect. With
/// Firebase Auth the platform handles the consent screen natively, so Google
/// and Apple sign-in need no browser round trip at all.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => _auth.currentUser != null;

  /// True for "Continue as guest" accounts — real anonymous sessions that can
  /// later be upgraded to a permanent account without losing data.
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  // ------------------------------------------------------------------ email

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.updateDisplayName(fullName.trim());
      await cred.user?.sendEmailVerification();
      return cred;
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(_authMessage(e), code: e.code);
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(_authMessage(e), code: e.code);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(_authMessage(e), code: e.code);
    }
  }

  // ----------------------------------------------------------------- social

  /// Google sign-in.
  ///
  /// Two genuinely different code paths, because the platforms need different
  /// things:
  ///
  /// * **Web** uses Firebase Auth's own `signInWithPopup`. The `google_sign_in`
  ///   plugin requires a Google Identity Services client ID, which is exactly
  ///   the configuration a local emulator does not have. The popup path works
  ///   with the Auth emulator out of the box — the emulator intercepts the flow
  ///   and shows its own account chooser — so Gmail login is testable locally
  ///   with no Google Cloud project at all.
  /// * **Mobile** uses `google_sign_in` and exchanges the ID token for a
  ///   Firebase credential. This needs a real project with the app's SHA-1
  ///   registered.
  ///
  /// Adds `accessToken` when the account granted it, because some Firebase
  /// projects are configured to require both tokens.
  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        return await _auth.signInWithPopup(GoogleAuthProvider());
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request') {
          throw const CloseyFailure('Sign-in cancelled.', isRetryable: false);
        }
        throw CloseyFailure(
          e.code == 'operation-not-allowed'
              ? 'Google sign-in is not enabled. Turn on the Google provider in '
                    'Firebase Console → Authentication → Sign-in method.'
              : _authMessage(e),
          code: e.code,
        );
      }
    }

    try {
      final gsi = GoogleSignIn.instance;
      await gsi.initialize();
      final account = await gsi.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null) {
        throw const CloseyFailure(
          'Google did not return an identity token. Check that the OAuth '
          'client ID in your Firebase project matches this app\'s package '
          'name and SHA-1 fingerprint.',
          isRetryable: false,
        );
      }

      String? accessToken;
      try {
        final authz = await gsi.authorizationClient.authorizeScopes([
          'email',
          'profile',
        ]);
        accessToken = authz.accessToken;
      } catch (_) {
        // Optional — some configurations do not need it.
      }

      return await _auth.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: idToken,
          accessToken: accessToken,
        ),
      );
    } on CloseyFailure {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(_authMessage(e), code: e.code);
    } on Exception catch (e) {
      throw CloseyFailure(_googleMessage(e));
    }
  }

  Future<UserCredential> signInWithApple() async {
    try {
      if (kIsWeb) {
        return await _auth.signInWithPopup(AppleAuthProvider());
      }

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauth = OAuthProvider('apple.com').credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
      );
      return await _auth.signInWithCredential(oauth);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const CloseyFailure('Sign-in cancelled.', isRetryable: false);
      }
      throw CloseyFailure('Apple sign-in failed: ${e.message}');
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(_authMessage(e), code: e.code);
    }
  }

  /// A real anonymous Firebase session — not a fake local mode. The account can
  /// be upgraded later with `linkWithCredential` and keeps its history.
  Future<UserCredential> signInAsGuest() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(
        e.code == 'operation-not-allowed'
            ? 'Guest access is not enabled. Turn on the Anonymous provider in '
                  'Firebase Console → Authentication → Sign-in method.'
            : _authMessage(e),
        code: e.code,
      );
    }
  }

  // ------------------------------------------------------------------ phone

  /// Starts phone verification. Returns the verification id needed by
  /// [confirmPhoneCode] when the code is entered manually.
  Future<String?> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(CloseyFailure failure) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    final completer = Completer<String?>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber.trim(),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) {
          onAutoVerified?.call(credential);
          if (!completer.isCompleted) completer.complete(null);
        },
        verificationFailed: (e) {
          final failure = CloseyFailure(_authMessage(e), code: e.code);
          onError(failure);
          if (!completer.isCompleted) completer.completeError(failure);
        },
        codeSent: (verificationId, resendToken) {
          onCodeSent(verificationId, resendToken);
          if (!completer.isCompleted) completer.complete(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!completer.isCompleted) completer.complete(verificationId);
        },
      );
    } on Exception catch (e) {
      final failure = CloseyFailure(
        'Could not start phone verification. ${_short(e)}',
      );
      onError(failure);
      throw failure;
    }

    return completer.future;
  }

  Future<UserCredential> confirmPhoneCode({
    required String verificationId,
    required String code,
  }) async {
    try {
      return await _auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code.trim(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(
        e.code == 'invalid-verification-code'
            ? 'That code is not right. Check the SMS and try again.'
            : _authMessage(e),
        code: e.code,
      );
    }
  }

  Future<void> signInWithPhoneCredential(PhoneAuthCredential credential) =>
      _auth.signInWithCredential(credential);

  // ------------------------------------------------------------------ misc

  Future<void> signOut() async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
        // Apple requires the app to revoke on iOS; Google does not.
        await GoogleSignIn.instance.signOut();
      } else {
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {
      // Not signed in with Google — fine.
    }
    await _auth.signOut();
  }

  /// Deletes the Firestore document tree first, then the auth account.
  ///
  /// Order matters: if the auth user is deleted first the client loses the
  /// permission to remove its own data, and a Cloud Function has to clean up
  /// instead. Doing it here keeps the user's data under their own control.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw const CloseyFailure('You are not signed in.');

    try {
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      // Remove the private subcollection and the profile document. Matches,
      // connections and messages are removed by the `onUserDeleted` Cloud
      // Function, which has the privileges to sweep across other documents.
      await db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('account')
          .delete();
      await db.collection('users').doc(uid).delete();

      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const CloseyFailure(
          'For security, please sign in again before deleting your account.',
          code: 'requires-recent-login',
          isRetryable: false,
        );
      }
      throw CloseyFailure(_authMessage(e), code: e.code);
    }
  }

  /// Upgrades a guest account to email/password without losing its history.
  Future<UserCredential> linkEmailToGuest({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const CloseyFailure('You are not signed in.');
    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      return await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw CloseyFailure(_authMessage(e), code: e.code);
    }
  }

  // --------------------------------------------------------------- messages

  String _authMessage(FirebaseAuthException e) => switch (e.code) {
    'invalid-email' => 'That email address does not look right.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' => 'No account with that email. Try signing up instead.',
    'wrong-password' ||
    'invalid-credential' => 'That email and password do not match.',
    'email-already-in-use' =>
      'That email is already registered. Try signing in instead.',
    'weak-password' => 'Please choose a password of at least 8 characters.',
    'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
    'network-request-failed' =>
      'No connection. Check your internet and try again.',
    'operation-not-allowed' =>
      'This sign-in method is not enabled for the project yet.',
    _ => e.message ?? 'Something went wrong signing you in.',
  };

  String _googleMessage(Object e) {
    final text = e.toString();
    if (text.contains('ApiException: 10') || text.contains('DEVELOPER_ERROR')) {
      return 'Google sign-in is misconfigured. Add this app\'s SHA-1 '
          'fingerprint to the Firebase project, then re-download '
          'google-services.json.';
    }
    if (text.contains('sign_in_canceled') || text.contains('canceled')) {
      return 'Sign-in cancelled.';
    }
    return 'Google sign-in failed. ${_short(e)}';
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
