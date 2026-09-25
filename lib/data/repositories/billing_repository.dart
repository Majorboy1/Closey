import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/async_section.dart';
import '../firebase/firebase_bootstrap.dart';
import '../models/quota.dart';

/// Quota display and Stripe checkout.
///
/// Firestore layout: `users/{uid}/private/account`
/// ```
/// { suggestionQuota: {...}, dmUsage: {...}, subscription: {...} }
/// ```
/// The client may **read** this document and may **never write** the quota,
/// usage or subscription fields — the rules require those to come from a Cloud
/// Function with the Admin SDK. That is the Firestore equivalent of the Postgres
/// `try_consume_suggestion` function the Expo app relied on, and it is what
/// makes the "one shared pool, 5 per day" rule tamper-proof.
class BillingRepository {
  BillingRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FirebaseBootstrap.functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _account(String uid) =>
      _db.collection('users').doc(uid).collection('private').doc('account');

  /// Live quota. Drives the quota pill and the paywall trigger, and updates the
  /// instant a suggestion is consumed anywhere in the app — the Expo version
  /// needed an explicit refetch after every generation.
  Stream<SuggestionQuota> watchQuota(String uid) =>
      _account(uid).snapshots().map((doc) {
        final data = doc.data();
        final raw = data?['suggestionQuota'];
        if (raw is! Map) return SuggestionQuota.unknown;
        return SuggestionQuota.fromMap(Map<String, dynamic>.from(raw));
      });

  Stream<DmUsage> watchDmUsage(String uid) =>
      _account(uid).snapshots().map((doc) {
        final data = doc.data();
        final raw = data?['dmUsage'];
        if (raw is! Map) return DmUsage.unknown;
        return DmUsage.fromMap(Map<String, dynamic>.from(raw));
      });

  Stream<Subscription> watchSubscription(String uid) =>
      _account(uid).snapshots().map((doc) {
        final data = doc.data();
        final raw = data?['subscription'];
        if (raw is! Map) return Subscription.free;
        return Subscription.fromMap(Map<String, dynamic>.from(raw));
      });

  Future<SuggestionQuota> getQuota(String uid) async {
    final doc = await _account(uid).get();
    final raw = doc.data()?['suggestionQuota'];
    if (raw is! Map) return SuggestionQuota.unknown;
    return SuggestionQuota.fromMap(Map<String, dynamic>.from(raw));
  }

  /// Opens a Stripe Checkout session and returns its URL.
  ///
  /// The two-path model (a one-off top-up *and* a subscription) is deliberate:
  /// the DECISIONS log argues that a subscription-only model loses the heavy
  /// occasional user, and that the "+5 for $1.99" escape hatch is what stops
  /// someone hitting the daily cap from simply closing the app.
  Future<String> createCheckoutSession(SubscriptionPlan plan) async {
    try {
      final result = await _functions
          .httpsCallable('createCheckoutSession')
          .call<Map<String, dynamic>>({'planKey': plan.key});

      final url = result.data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const CloseyFailure(
          'Stripe did not return a checkout link.',
          isRetryable: false,
        );
      }
      return url;
    } on CloseyFailure {
      rethrow;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable' || e.code == 'not-found') {
        throw const CloseyFailure(
          'Checkout is not configured yet. Deploy the Cloud Functions and set '
          'the STRIPE_SECRET_KEY, STRIPE_PRICE_TOPUP_5 and '
          'STRIPE_PRICE_PREMIUM secrets.',
          code: 'STRIPE_NOT_CONFIGURED',
          isRetryable: false,
        );
      }
      throw CloseyFailure(
        e.message ?? 'Could not start checkout.',
        code: e.code,
      );
    }
  }

  /// Reads the human-readable pricing from `config/pricing` if it exists, so
  /// prices can change without an app release. Falls back to the compiled-in
  /// constants so the paywall always renders.
  Future<Map<String, String>> loadPricing() async {
    try {
      final doc = await _db.collection('config').doc('pricing').get();
      final data = doc.data();
      if (data == null) return _fallbackPricing;

      return {
        'topup': (data['topupLabel'] as String?) ?? Pricing.topUpLabel,
        'premium': (data['premiumLabel'] as String?) ?? Pricing.premiumLabel,
      };
    } catch (_) {
      return _fallbackPricing;
    }
  }

  static final Map<String, String> _fallbackPricing = {
    'topup': Pricing.topUpLabel,
    'premium': '${Pricing.premiumLabel}/mo',
  };

  /// Marks the user as Verified. In production this is called by the KYC
  /// provider's webhook (`stripeWebhook` / a Persona hook), not by the app —
  /// the client is not permitted to raise its own tier.
  ///
  /// Exposed here for the demo flow so the coach can be explored without a KYC
  /// vendor wired up; the Firestore rules decide whether it is allowed.
  Future<void> simulateVerification(String uid) => _account(uid).set({
    'verificationRequest': {
      'requestedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    },
  }, SetOptions(merge: true));
}
