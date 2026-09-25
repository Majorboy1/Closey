import { onCall, HttpsError, onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import Stripe from 'stripe';
import { FieldValue } from 'firebase-admin/firestore';

import { db, Col, Quota, ALLOWED_ORIGINS } from './config';
import {
  authorizeCoachUse,
  authorizeNewDm,
  getQuotaState,
  grantTopUp,
  activatePremium,
  deactivatePremium,
  thisMonth,
} from './quota';
import {
  deepseekKey,
  generateSuggestion,
  analyzeConversation,
  loadCoachContext,
  type SuggestionType,
} from './ai';

const stripeKey = defineSecret('STRIPE_SECRET_KEY');
const stripeWebhookSecret = defineSecret('STRIPE_WEBHOOK_SECRET');
const priceTopUp = defineSecret('STRIPE_PRICE_TOPUP_5');
const pricePremium = defineSecret('STRIPE_PRICE_PREMIUM');

const REGION = 'us-central1';

function requireAuth(auth: { uid?: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Please sign in again.');
  }
  return auth.uid;
}

// ---------------------------------------------------------------------------
// Coach: on-demand suggestion
// ---------------------------------------------------------------------------

/**
 * "Help me continue this" — and "Another".
 *
 * Always produces a **shared** card, because this is a deliberate action by one
 * person rather than a private coaching moment. The spec is explicit about that
 * distinction, and the DECISIONS log notes that every generation costs a credit
 * including rerolls — which is enforced inside `authorizeCoachUse`.
 */
export const requestSuggestion = onCall(
  { region: REGION, secrets: [deepseekKey], cors: ALLOWED_ORIGINS },
  async (request) => {
    const uid = requireAuth(request.auth);
    const connectionId = String(request.data?.connectionId ?? '');
    if (!connectionId) {
      throw new HttpsError('invalid-argument', 'connectionId is required.');
    }

    const requestedType = request.data?.suggestionType as SuggestionType | undefined;

    // Gates + credit consumption, atomically and server-side.
    await authorizeCoachUse(uid, connectionId);

    const connection = await db.collection(Col.connections).doc(connectionId).get();
    const members: string[] = connection.data()?.members ?? [];
    const otherId = members.find((m) => m !== uid);
    if (!otherId) {
      throw new HttpsError('failed-precondition', 'This conversation has no other member.');
    }

    const quotaState = await getQuotaState(uid);
    const context = await loadCoachContext(connectionId, uid, otherId);

    // Decide the type: an explicit request wins; otherwise let the analysis
    // choose based on the current state of the thread.
    let type: SuggestionType = requestedType ?? 'topic_continuation';
    let trigger = 'user_requested' as const;

    if (!requestedType) {
      const messagesSnap = await connection.ref
        .collection(Col.messages)
        .orderBy('createdAt', 'desc')
        .limit(Quota.contextWindow)
        .get();

      const history = messagesSnap.docs
        .reverse()
        .map((d) => ({
          senderId: String(d.data().senderId ?? ''),
          body: String(d.data().body ?? ''),
          createdAt: d.data().createdAt?.toDate?.() ?? new Date(),
        }));

      const analysis = analyzeConversation(history, members);
      // A user-requested suggestion is never a private nudge — that would
      // defeat the point of asking for help out loud.
      if (analysis && analysis.type !== 'reciprocity_nudge') {
        type = analysis.type;
      }
    }

    const suggestion = await generateSuggestion({
      context,
      type,
      trigger,
      smarterAi: quotaState.smarterAi,
    });

    // Force shared: a user-initiated request is always visible to both.
    const payload = { ...suggestion, visibility: 'shared' as const, targetUserId: undefined };

    const ref = await connection.ref.collection(Col.suggestions).add({
      ...payload,
      requestedBy: uid,
      triggeredBy: trigger,
      status: 'active',
      basedOn: ['recent_messages', 'shared_interests'],
      createdAt: new Date(),
    });

    const after = await getQuotaState(uid);

    return {
      suggestionId: ref.id,
      suggestion: payload,
      remaining: Math.max(0, after.dailyLimit - after.usedToday),
    };
  },
);

// ---------------------------------------------------------------------------
// Conversations
// ---------------------------------------------------------------------------

/**
 * Opens a direct conversation, consuming one monthly DM credit on the free tier.
 *
 * Idempotent: if the two people already have a thread, it is returned without
 * charging. The iOS/Android double-tap case is the reason this matters.
 */
export const startDm = onCall({ region: REGION, cors: ALLOWED_ORIGINS }, async (request) => {
  const uid = requireAuth(request.auth);
  const otherUserId = String(request.data?.otherUserId ?? '');
  if (!otherUserId || otherUserId === uid) {
    throw new HttpsError('invalid-argument', 'A valid otherUserId is required.');
  }

  const connectionId = [uid, otherUserId].sort().join('__');
  const ref = db.collection(Col.connections).doc(connectionId);

  const existing = await ref.get();
  if (existing.exists) {
    return { connectionId, charged: false };
  }

  await authorizeNewDm(uid);

  const [me, them] = await Promise.all([
    db.collection(Col.users).doc(uid).get(),
    db.collection(Col.users).doc(otherUserId).get(),
  ]);

  await ref.set({
    members: [uid, otherUserId].sort(),
    memberSummaries: {
      [uid]: {
        fullName: me.data()?.fullName ?? '',
        handle: me.data()?.handle ?? '',
        avatarUrl: me.data()?.avatarUrl ?? null,
        verificationTier: me.data()?.verificationTier ?? 'basic',
      },
      [otherUserId]: {
        fullName: them.data()?.fullName ?? '',
        handle: them.data()?.handle ?? '',
        avatarUrl: them.data()?.avatarUrl ?? null,
        verificationTier: them.data()?.verificationTier ?? 'basic',
      },
    },
    kind: 'dm',
    aiEnabled: false,
    lastMessage: null,
    lastMessageAt: null,
    unread: { [uid]: 0, [otherUserId]: 0 },
    muted: false,
    createdFrom: 'dm',
    createdAt: FieldValue.serverTimestamp(),
  });

  const usage = await db
    .collection(Col.users)
    .doc(uid)
    .collection('private')
    .doc('account')
    .get();

  const dm = usage.data()?.dmUsage ?? {};

  return {
    connectionId,
    charged: true,
    remaining:
      dm.month === thisMonth() && typeof dm.limit === 'number'
        ? Math.max(0, dm.limit - dm.count)
        : null,
  };
});

/**
 * Accepting a friend request creates an unlimited connection.
 *
 * Server-side because it also has to bump the friend counters on both profiles,
 * which the rules forbid the client from touching.
 */
export const acceptFriendRequest = onCall(
  { region: REGION, cors: ALLOWED_ORIGINS },
  async (request) => {
    const uid = requireAuth(request.auth);
    const requestId = String(request.data?.requestId ?? '');
    if (!requestId) throw new HttpsError('invalid-argument', 'requestId is required.');

    const requestRef = db.collection(Col.friendRequests).doc(requestId);

    const connectionId = await db.runTransaction(async (tx) => {
      const snap = await tx.get(requestRef);
      if (!snap.exists) throw new HttpsError('not-found', 'That request is gone.');

      const data = snap.data()!;
      if (data.receiverId !== uid) {
        throw new HttpsError('permission-denied', 'That request is not yours to accept.');
      }
      if (data.status !== 'pending') {
        throw new HttpsError('failed-precondition', 'That request was already answered.');
      }

      const senderId = data.senderId as string;
      const id = [senderId, uid].sort().join('__');

      tx.update(requestRef, { status: 'accepted', respondedAt: FieldValue.serverTimestamp() });
      tx.set(
        db.collection(Col.connections).doc(id),
        {
          members: [senderId, uid].sort(),
          memberSummaries: data.sender ? { [senderId]: data.sender } : {},
          kind: 'friend',
          aiEnabled: false,
          unread: { [senderId]: 0, [uid]: 0 },
          muted: false,
          createdFrom: 'friend_request',
          createdAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      // Friend counters live on the profile document, which the client may not
      // write — hence doing it here.
      tx.set(
        db.collection(Col.users).doc(senderId),
        { friendCount: FieldValue.increment(1), connectionCount: FieldValue.increment(1) },
        { merge: true },
      );
      tx.set(
        db.collection(Col.users).doc(uid),
        { friendCount: FieldValue.increment(1), connectionCount: FieldValue.increment(1) },
        { merge: true },
      );

      return id;
    });

    return { connectionId };
  },
);

/**
 * Ends a connection for both people.
 *
 * Server-side because Firestore does not cascade: the messages and suggestions
 * subcollections have to be removed explicitly, and a client cannot delete 400
 * documents it does not own one at a time.
 */
export const unmatchConnection = onCall(
  { region: REGION, cors: ALLOWED_ORIGINS },
  async (request) => {
    const uid = requireAuth(request.auth);
    const connectionId = String(request.data?.connectionId ?? '');

    const ref = db.collection(Col.connections).doc(connectionId);
    const snap = await ref.get();
    if (!snap.exists) return { deleted: true }; // Already gone — idempotent.

    const members: string[] = snap.data()?.members ?? [];
    if (!members.includes(uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this conversation.');
    }

    const [messages, suggestions] = await Promise.all([
      ref.collection(Col.messages).limit(450).get(),
      ref.collection(Col.suggestions).limit(450).get(),
    ]);

    const batch = db.batch();
    for (const doc of [...messages.docs, ...suggestions.docs]) batch.delete(doc.ref);
    batch.delete(ref);
    await batch.commit();

    // The other person gets told their side is gone too.
    for (const other of members.filter((m) => m !== uid)) {
      await db
        .collection(Col.users)
        .doc(other)
        .collection('private')
        .doc('account')
        .set({ lastUnmatchAt: FieldValue.serverTimestamp() }, { merge: true });
    }

    return { deleted: true };
  },
);

// ---------------------------------------------------------------------------
// Safety
// ---------------------------------------------------------------------------

/**
 * Blocks someone.
 *
 * Written as a function, not a client write, because a block has to update two
 * users' documents plus the connection — and `blockedUserIds` is deliberately
 * not client-writable, since it drives discovery exclusion.
 */
export const blockUser = onCall({ region: REGION, cors: ALLOWED_ORIGINS }, async (request) => {
  const uid = requireAuth(request.auth);
  const blockedId = String(request.data?.blockedId ?? '');
  if (!blockedId || blockedId === uid) {
    throw new HttpsError('invalid-argument', 'A valid blockedId is required.');
  }

  const meRef = db.collection(Col.users).doc(uid);
  const connectionRef = db.collection(Col.connections).doc([uid, blockedId].sort().join('__'));

  await meRef.collection('blocks').doc(blockedId).set({
    blockedId,
    createdAt: FieldValue.serverTimestamp(),
  });

  // The array mirror is what discovery queries against — a `whereNotIn` can
  // only filter on a field of the document being queried, so without this the
  // blocked person would still appear in the deck.
  await meRef.set({ blockedUserIds: FieldValue.arrayUnion([blockedId]) }, { merge: true });

  const connection = await connectionRef.get();
  if (connection.exists) {
    const [messages, suggestions] = await Promise.all([
      connectionRef.collection(Col.messages).limit(450).get(),
      connectionRef.collection(Col.suggestions).limit(450).get(),
    ]);
    const batch = db.batch();
    for (const doc of [...messages.docs, ...suggestions.docs]) batch.delete(doc.ref);
    batch.delete(connectionRef);
    await batch.commit();
  }

  return { blocked: true };
});

export const unblockUser = onCall({ region: REGION, cors: ALLOWED_ORIGINS }, async (request) => {
  const uid = requireAuth(request.auth);
  const blockedId = String(request.data?.blockedId ?? '');
  if (!blockedId) throw new HttpsError('invalid-argument', 'blockedId is required.');

  const meRef = db.collection(Col.users).doc(uid);
  await meRef.collection('blocks').doc(blockedId).delete().catch(() => undefined);
  await meRef.set({ blockedUserIds: FieldValue.arrayRemove([blockedId]) }, { merge: true });

  return { unblocked: true };
});

/**
 * Sweeps the data a deleted account left behind.
 *
 * The client deletes its own profile document first (it has permission), then
 * calls this. The `onUserDeleted` auth trigger is the backstop.
 */
export const deleteAccountData = onCall(
  { region: REGION, cors: ALLOWED_ORIGINS },
  async (request) => {
    const uid = requireAuth(request.auth);

    const [connections, posts, likes, passes, requests] = await Promise.all([
      db.collection(Col.connections).where('members', 'array-contains', uid).limit(200).get(),
      db.collection(Col.posts).where('authorId', '==', uid).limit(200).get(),
      db.collection(Col.likes).where('likerId', '==', uid).limit(200).get(),
      db.collection(Col.passes).where('passerId', '==', uid).limit(200).get(),
      db.collection(Col.friendRequests).where('members', 'array-contains', uid).limit(200).get(),
    ]);

    const batch = db.batch();
    for (const doc of [...connections.docs, ...posts.docs, ...likes.docs, ...passes.docs, ...requests.docs]) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    logger.info('Account data swept', { uid });
    return { swept: true };
  },
);

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

/**
 * Creates a Stripe Checkout session.
 *
 * The two-path model (a one-off top-up *and* a subscription) is deliberate: the
 * DECISIONS log argues a subscription-only model loses the heavy occasional
 * user, and that the "+5 for $1.99" escape hatch is what stops someone who hits
 * the daily cap from closing the app.
 */
export const createCheckoutSession = onCall(
  {
    region: REGION,
    cors: ALLOWED_ORIGINS,
    secrets: [stripeKey, priceTopUp, pricePremium],
  },
  async (request) => {
    const uid = requireAuth(request.auth);
    const planKey = String(request.data?.planKey ?? '');

    if (planKey !== 'topup_5' && planKey !== 'premium') {
      throw new HttpsError('invalid-argument', 'Unknown plan.');
    }

    const stripe = new Stripe(stripeKey.value());
    const price = planKey === 'premium' ? pricePremium.value() : priceTopUp.value();

    const accountRef = db.collection(Col.users).doc(uid).collection('private').doc('account');
    const account = await accountRef.get();
    let customerId = account.data()?.subscription?.stripeCustomerId as string | undefined;

    if (!customerId) {
      const user = await db.collection(Col.users).doc(uid).get();
      const customer = await stripe.customers.create({
        email: user.data()?.email ?? undefined,
        metadata: { firebaseUid: uid },
      });
      customerId = customer.id;
      await accountRef.set(
        { subscription: { stripeCustomerId: customerId } },
        { merge: true },
      );
    }

    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      mode: planKey === 'premium' ? 'subscription' : 'payment',
      line_items: [{ price, quantity: 1 }],
      success_url: 'closey://paywall/success',
      cancel_url: 'closey://paywall/cancelled',
      // The webhook is the only thing that grants entitlements, so the uid must
      // travel with the session.
      metadata: { firebaseUid: uid, planKey },
      client_reference_id: uid,
    });

    if (!session.url) {
      throw new HttpsError('internal', 'Stripe did not return a checkout URL.');
    }

    return { url: session.url };
  },
);

/**
 * Stripe webhook — the only place entitlements are ever granted.
 *
 * Signature-verified, and idempotent per event id. The client can never grant
 * itself Premium, and neither can a replayed webhook.
 */
export const stripeWebhook = onRequest(
  {
    region: REGION,
    secrets: [stripeKey, stripeWebhookSecret],
  },
  async (req, res) => {
    const stripe = new Stripe(stripeKey.value());
    const signature = req.headers['stripe-signature'];

    if (!signature || Array.isArray(signature)) {
      res.status(400).send('Missing stripe-signature');
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        signature,
        stripeWebhookSecret.value(),
      );
    } catch (error) {
      logger.warn('Stripe signature verification failed', error);
      res.status(400).send('Invalid signature');
      return;
    }

    // Idempotency: a replayed event must not double-grant credits.
    const eventRef = db.collection('stripeEvents').doc(event.id);
    if ((await eventRef.get()).exists) {
      res.json({ received: true, duplicate: true });
      return;
    }
    await eventRef.set({ type: event.type, receivedAt: FieldValue.serverTimestamp() });

    try {
      switch (event.type) {
        case 'checkout.session.completed': {
          const session = event.data.object as Stripe.Checkout.Session;
          const uid = session.metadata?.firebaseUid ?? session.client_reference_id;
          const planKey = session.metadata?.planKey;

          if (uid && planKey === 'topup_5') {
            await grantTopUp(uid, Quota.topUpGrant);
            logger.info('Top-up granted', { uid, credits: Quota.topUpGrant });
          }
          break;
        }

        case 'customer.subscription.created':
        case 'customer.subscription.updated': {
          const subscription = event.data.object as Stripe.Subscription;
          const uid = subscription.metadata?.firebaseUid;

          if (uid) {
            const periodEnd = subscription.items.data[0]?.current_period_end;
            if (subscription.status === 'active') {
              await activatePremium(
                uid,
                String(subscription.customer),
                subscription.id,
                periodEnd ? new Date(periodEnd * 1000) : new Date(Date.now() + 30 * 86_400_000),
              );
            } else if (subscription.status === 'past_due') {
              await deactivatePremium(uid, 'past_due');
            }
            logger.info('Subscription synced', { uid, status: subscription.status });
          }
          break;
        }

        case 'customer.subscription.deleted': {
          const subscription = event.data.object as Stripe.Subscription;
          const uid = subscription.metadata?.firebaseUid;
          if (uid) await deactivatePremium(uid, 'canceled');
          break;
        }

        default:
          // Unhandled event types are acknowledged so Stripe stops retrying.
          break;
      }
    } catch (error) {
      logger.error('Stripe webhook handling failed', { type: event.type, error });
      // Clear the idempotency marker so Stripe's retry can succeed.
      await eventRef.delete().catch(() => undefined);
      res.status(500).send('Handler failed');
      return;
    }

    res.json({ received: true });
  },
);

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

/** Lets the client show accurate quota numbers without reading private data. */
export const getMyQuota = onCall({ region: REGION, cors: ALLOWED_ORIGINS }, async (request) => {
  const uid = requireAuth(request.auth);
  const state = await getQuotaState(uid);
  return {
    ...state,
    usedToday: state.usedToday,
    remaining: Math.max(0, state.dailyLimit - state.usedToday),
  };
});
