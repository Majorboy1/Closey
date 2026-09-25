import { HttpsError } from 'firebase-functions/v2/https';
import { db, Quota, Col } from './config';

/**
 * Quota enforcement.
 *
 * Direct port of `try_consume_suggestion()` and `get_dm_count_this_month()`
 * from `supabase/migrations/0005_atomic_consume.sql` and `0004_quotas_....sql`.
 *
 * Why this must live server-side, and why it must be a transaction:
 *
 * 1. The client must never be able to grant itself credits. The Firestore rules
 *    make `users/{uid}/private/**` write-only to the Admin SDK, so this file is
 *    the only thing that can change a counter.
 *
 * 2. It must be atomic. The Postgres version took a row lock (`for update`)
 *    precisely so two concurrent requests could not both slip past the limit.
 *    A Firestore transaction gives the same guarantee: the read of the counter
 *    and the write of `used + 1` happen under optimistic concurrency control,
 *    and a losing transaction retries against fresh data.
 *
 * 3. Every generation costs a credit — including "Another" rerolls. The
 *    DECISIONS log records this being built wrong once (rerolls were free),
 *    which let a user burn an unbounded number of API calls. Only "Use this"
 *    is free, because that sends an already-generated suggestion.
 */

export interface QuotaState {
  usedToday: number;
  dailyLimit: number;
  tier: string;
  smarterAi: boolean;
  isUnlimited: boolean;
}

/** `YYYY-MM-DD` in UTC. Matches the Dart client's reset semantics. */
export function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/** `YYYY-MM` in UTC. */
export function thisMonth(): string {
  return new Date().toISOString().slice(0, 7);
}

function accountRef(uid: string) {
  return db.collection(Col.users).doc(uid).collection('private').doc('account');
}

/**
 * Resolves the effective daily limit for a user.
 *
 * Mirrors the SQL: active subscriptions stack, top-ups add on top of the plan,
 * and a user with no active plan falls back to the free baseline.
 */
async function resolveLimits(uid: string): Promise<{
  dailyLimit: number;
  dmLimit: number | null;
  smarterAi: boolean;
}> {
  const snap = await accountRef(uid).get();
  const data = snap.data() ?? {};
  const subscription = data.subscription ?? {};
  const topUp = data.topUp ?? {};

  const isPremium = subscription.status === 'active' && subscription.planKey === 'premium';

  // Top-ups are only valid on the day they were bought.
  const topUpActive = topUp.date === today();
  const topUpCredits = topUpActive ? (topUp.credits ?? 0) : 0;

  if (isPremium) {
    return {
      dailyLimit: Quota.premiumAiPerDay + topUpCredits,
      // Premium removes the DM cap entirely.
      dmLimit: null,
      smarterAi: true,
    };
  }

  return {
    dailyLimit: Quota.freeAiPerDay + topUpCredits,
    dmLimit: Quota.freeDmPerMonth,
    smarterAi: false,
  };
}

export async function getQuotaState(uid: string): Promise<QuotaState> {
  const { dailyLimit, smarterAi } = await resolveLimits(uid);
  const snap = await accountRef(uid).get();
  const quota = snap.data()?.suggestionQuota ?? {};

  const usedToday = quota.date === today() ? (quota.usedToday ?? 0) : 0;

  return {
    usedToday,
    dailyLimit,
    tier: snap.data()?.tier ?? 'basic',
    smarterAi,
    isUnlimited: false,
  };
}

/**
 * Consumes one AI credit and returns the remaining balance.
 *
 * Throws `resource-exhausted` when the pool is empty, which the client maps to
 * the paywall (`QUOTA_EXCEEDED`).
 */
export async function tryConsumeSuggestion(uid: string): Promise<number> {
  const { dailyLimit, smarterAi } = await resolveLimits(uid);
  const ref = accountRef(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const quota = data.suggestionQuota ?? {};

    // A stored date that is not today means the daily pool has reset.
    const usedToday = quota.date === today() ? (quota.usedToday ?? 0) : 0;

    if (usedToday >= dailyLimit) {
      throw new HttpsError(
        'resource-exhausted',
        'QUOTA_EXCEEDED: You have used all your AI suggestions for today.',
      );
    }

    const nextUsed = usedToday + 1;

    tx.set(
      ref,
      {
        suggestionQuota: {
          date: today(),
          usedToday: nextUsed,
          dailyLimit,
          tier: data.tier ?? 'basic',
          smarterAi,
        },
        updatedAt: new Date(),
      },
      { merge: true },
    );

    return dailyLimit - nextUsed;
  });
}

/**
 * Verifies the caller is allowed to use the coach in this thread, and consumes
 * a credit if so.
 *
 * Three gates, all of which the spec requires:
 *  1. The caller's own tier must be Verified or Premium.
 *  2. BOTH members of the thread must have opted in — mutual consent, per chat.
 *  3. The thread must be a real connection the caller belongs to.
 */
export async function authorizeCoachUse(
  uid: string,
  connectionId: string,
): Promise<{ hasCredit: boolean }> {
  const connectionRef = db.collection(Col.connections).doc(connectionId);
  const [connection, profile, optIns] = await Promise.all([
    connectionRef.get(),
    db.collection(Col.users).doc(uid).get(),
    connectionRef.collection(Col.optIns).get(),
  ]);

  if (!connection.exists) {
    throw new HttpsError('not-found', 'That conversation no longer exists.');
  }

  const members: string[] = connection.data()?.members ?? [];
  if (!members.includes(uid)) {
    throw new HttpsError('permission-denied', 'You are not part of this conversation.');
  }

  const tier = profile.data()?.verificationTier ?? 'basic';
  if (tier !== 'verified' && tier !== 'premium') {
    throw new HttpsError(
      'permission-denied',
      'VERIFICATION_REQUIRED: Verify your identity to unlock the conversation coach.',
    );
  }

  const optedIn = optIns.docs.filter((d) => d.data().optedIn === true);
  if (optedIn.length < 2) {
    throw new HttpsError(
      'failed-precondition',
      'NOT_ENABLED: The coach needs both of you to switch it on for this chat.',
    );
  }

  await tryConsumeSuggestion(uid);
  return { hasCredit: true };
}

/**
 * Enforces the monthly DM allowance when starting a NEW conversation.
 *
 * Friends are exempt — that is the entire point of the friend mechanic, and it
 * is the app's primary growth loop. Messages inside an existing thread are
 * always unlimited and are not counted here.
 */
export async function authorizeNewDm(uid: string): Promise<void> {
  const { dmLimit } = await resolveLimits(uid);
  if (dmLimit === null) return; // Premium: unlimited.

  const ref = accountRef(uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const dmUsage = data.dmUsage ?? {};

    const usedThisMonth =
      dmUsage.month === thisMonth() ? (dmUsage.count ?? 0) : 0;

    if (usedThisMonth >= dmLimit) {
      throw new HttpsError(
        'resource-exhausted',
        'DM_LIMIT_REACHED: You have used all 5 free conversations this month. ' +
          'Add them as a friend for unlimited chat, or go Premium.',
      );
    }

    tx.set(
      ref,
      {
        dmUsage: {
          month: thisMonth(),
          count: usedThisMonth + 1,
          limit: dmLimit,
        },
        updatedAt: new Date(),
      },
      { merge: true },
    );
  });
}

/** Grants a purchased top-up. Called by the Stripe webhook only. */
export async function grantTopUp(uid: string, credits: number): Promise<void> {
  await accountRef(uid).set(
    {
      topUp: { date: today(), credits },
      updatedAt: new Date(),
    },
    { merge: true },
  );
}

/** Records a successful subscription. Called by the Stripe webhook only. */
export async function activatePremium(
  uid: string,
  stripeCustomerId: string,
  stripeSubscriptionId: string,
  currentPeriodEnd: Date,
): Promise<void> {
  await accountRef(uid).set(
    {
      subscription: {
        planKey: 'premium',
        status: 'active',
        currentPeriodEnd,
        stripeCustomerId,
        stripeSubscriptionId,
      },
      updatedAt: new Date(),
    },
    { merge: true },
  );
}

/** Reverts to free. Called by the Stripe webhook on cancellation / failure. */
export async function deactivatePremium(
  uid: string,
  status: 'canceled' | 'past_due',
): Promise<void> {
  await accountRef(uid).set(
    {
      subscription: { planKey: 'free', status },
      updatedAt: new Date(),
    },
    { merge: true },
  );
}
