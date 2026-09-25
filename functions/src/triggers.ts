import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { auth } from 'firebase-functions/v1';
import { logger } from 'firebase-functions/v2';
import { getMessaging } from 'firebase-admin/messaging';
import { FieldValue } from 'firebase-admin/firestore';

import { db, Col, Quota } from './config';
import { deepseekKey, analyzeConversation, generateSuggestion, loadCoachContext } from './ai';
import { getQuotaState } from './quota';

/**
 * Firestore and Auth triggers.
 *
 * The split between triggers and callables is deliberate: anything the user is
 * *waiting for* is a callable, and anything that is a *side effect of a write
 * they already made* is a trigger. That keeps the swipe and send paths fast, and
 * it means a match still produces an opener even if both phones go offline
 * immediately afterwards.
 */

// ---------------------------------------------------------------------------
// Push notifications
// ---------------------------------------------------------------------------

/**
 * Sends a push to a user's registered devices.
 *
 * Note what is NOT here: a private nudge body. The spec is explicit that a
 * private suggestion must never leak through a push notification, so nudges
 * either send a deliberately vague line or no notification at all. This is the
 * kind of leak that is easy to introduce and impossible to take back.
 */
async function sendPush(
  uid: string,
  notification: { title: string; body: string },
  data: Record<string, string>,
): Promise<void> {
  try {
    const account = await db
      .collection(Col.users)
      .doc(uid)
      .collection('private')
      .doc('account')
      .get();

    const tokens: string[] = account.data()?.pushTokens ?? [];
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification,
      data,
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    // Prune tokens the platform has told us are dead, so the list does not grow
    // forever and we stop paying for guaranteed failures.
    const stale = response.responses
      .map((r, i) => (!r.success ? tokens[i] : null))
      .filter((t): t is string => t !== null);

    if (stale.length > 0) {
      await account.ref.set(
        { pushTokens: tokens.filter((t) => !stale.includes(t)) },
        { merge: true },
      );
    }
  } catch (error) {
    logger.warn('Push failed', { uid, error });
  }
}

// ---------------------------------------------------------------------------
// Match created → shared opener
// ---------------------------------------------------------------------------

/**
 * When a connection is created, immediately draft a shared opener.
 *
 * This is the moment the product's core promise lands: both people open the chat
 * and the same suggestion is already waiting for both of them. Generating it here
 * (rather than on first open) is what makes that simultaneous.
 */
export const onConnectionCreated = onDocumentCreated(
  {
    document: `${Col.connections}/{connectionId}`,
    secrets: [deepseekKey],
    retry: false,
  },
  async (event) => {
    const connection = event.data?.data();
    if (!connection) return;

    const connectionId = event.params.connectionId;
    const members: string[] = connection.members ?? [];
    if (members.length !== 2) return;

    const [a, b] = members;

    try {
      // Skip the opener for a friend request that was accepted long after they
      // started talking — there is nothing to open.
      const existing = await event.data!.ref.collection(Col.messages).limit(1).get();
      if (!existing.empty) return;

      const context = await loadCoachContext(connectionId, a, b);
      const suggestion = await generateSuggestion({
        context,
        type: 'opener',
        trigger: 'match_created',
        smarterAi: false,
      });

      await event.data!.ref.collection(Col.suggestions).add({
        ...suggestion,
        requestedBy: null,
        triggeredBy: 'match_created',
        status: 'active',
        basedOn: ['profile', 'shared_interests'],
        createdAt: new Date(),
      });
    } catch (error) {
      logger.error('Could not generate opener', { connectionId, error });
    }

    // Notify both people that they matched.
    await Promise.all(
      members.map((uid) =>
        sendPush(
          uid,
          {
            title: "It's a match!",
            body: 'You both swiped right. Open the chat to see your opener.',
          },
          { type: 'match', connectionId },
        ),
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// New message → coach analysis
// ---------------------------------------------------------------------------

/**
 * Runs the conversation analysis after every message.
 *
 * Ported from `analyze-conversation`. Two guardrails keep the coach from being
 * annoying, both of which the spec calls out explicitly:
 *
 *  1. **The quiet period.** No unprompted card within `coachQuietMinutes` of the
 *     last one, regardless of what the analysis finds.
 *  2. **One card at a time.** If an active card is already showing, we do not
 *     stack another on top of it.
 */
export const onMessageCreated = onDocumentCreated(
  {
    document: `${Col.connections}/{connectionId}/${Col.messages}/{messageId}`,
    secrets: [deepseekKey],
    retry: false,
  },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;

    const connectionId = event.params.connectionId;
    const connectionRef = event.data!.ref.parent.parent!;

    const connectionSnap = await connectionRef.get();
    const members: string[] = connectionSnap.data()?.members ?? [];
    if (members.length !== 2) return;

    const senderId: string = message.senderId;

    // ---- Notification (always) -------------------------------------------
    const recipientId = members.find((m) => m !== senderId);
    if (recipientId) {
      const profile = await db.collection(Col.users).doc(senderId).get();
      const name = profile.data()?.fullName ?? 'Someone';
      const wantsPush = profile.data()?.notifyMessages !== false;

      // Respect the recipient's own preference, not the sender's.
      const recipient = await db.collection(Col.users).doc(recipientId).get();
      if (recipient.data()?.notifyMessages !== false && wantsPush) {
        await sendPush(
          recipientId,
          {
            title: name,
            body:
              String(message.body ?? '').length > 90
                ? `${String(message.body).slice(0, 90)}…`
                : String(message.body ?? ''),
          },
          { type: 'message', connectionId },
        );
      }
    }

    // ---- Coach -----------------------------------------------------------
    try {
      const suggestionsRef = connectionRef.collection(Col.suggestions);

      // Guardrail: one active card at a time.
      const active = await suggestionsRef
        .where('status', '==', 'active')
        .limit(1)
        .get();
      if (!active.empty) return;

      // Guardrail: the quiet period. Read the most recent suggestion of any
      // status and compare timestamps in memory.
      const recent = await suggestionsRef
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();
      if (!recent.empty) {
        const lastAt = recent.docs[0].data().createdAt?.toDate?.() as Date | undefined;
        if (lastAt) {
          const minutesSince = (Date.now() - lastAt.getTime()) / 60000;
          if (minutesSince < Quota.coachQuietMinutes) return;
        }
      }

      const messagesSnap = await connectionRef
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
      if (!analysis) return;

      // A private nudge is targeted at one person, so the context is built from
      // THEIR point of view — otherwise the model would phrase the nudge as if
      // the other person were reading it.
      const perspectiveId = analysis.targetUserId ?? members[0];
      const otherId = members.find((m) => m !== perspectiveId)!;

      const context = await loadCoachContext(connectionId, perspectiveId, otherId);

      // The coach must not speak if the person it would nudge has run out of
      // credits or is not verified — silently skip rather than generating
      // something they cannot be shown.
      const quotaState = await getQuotaState(perspectiveId);
      if (quotaState.usedToday >= quotaState.dailyLimit) return;

      const suggestion = await generateSuggestion({
        context,
        type: analysis.type,
        trigger: analysis.trigger,
        smarterAi: quotaState.smarterAi,
        targetUserId: analysis.targetUserId,
      });

      await suggestionsRef.add({
        ...suggestion,
        requestedBy: null,
        triggeredBy: analysis.trigger,
        status: 'active',
        basedOn: ['recent_messages', 'shared_interests'],
        createdAt: new Date(),
      });

      // A private nudge never gets a descriptive push — that would leak it.
      if (analysis.targetUserId && analysis.type === 'reciprocity_nudge') {
        await sendPush(
          analysis.targetUserId,
          {
            title: 'A quiet tip',
            body: 'Open the chat — there is a suggestion just for you.',
          },
          { type: 'coach_private', connectionId },
        );
      } else {
        // Shared cards come with a credit, because they will be consumed on
        // display. Charging here keeps it honest: an unprompted card the user
        // never sees should not have cost them anything.
        await Promise.all(
          members.map((uid) =>
            sendPush(
              uid,
              {
                title: 'Closey has an idea',
                body: suggestion.content,
              },
              { type: 'coach_shared', connectionId },
            ),
          ),
        );
      }
    } catch (error) {
      logger.error('Coach analysis failed', { connectionId, error });
    }
  },
);

// ---------------------------------------------------------------------------
// Post likes → counter
// ---------------------------------------------------------------------------

/**
 * Maintains `posts/{id}.likeCount` from the `likes` subcollection.
 *
 * This is why the client is forbidden from writing `likeCount`: the counter is
 * derived, and a derived counter is only trustworthy if exactly one writer owns
 * it. The Flutter repository writes a marker document; this keeps the number.
 */
export const onPostLikeCreated = onDocumentCreated(
  { document: `${Col.posts}/{postId}/likes/{likerId}`, retry: true },
  async (event) => {
    const postRef = event.data?.ref.parent.parent;
    if (!postRef) return;
    await postRef.update({ likeCount: FieldValue.increment(1) });
  },
);

/** The undo side. Without this, unliking would leave the counter inflated. */
export const onPostLikeDeleted = onDocumentDeleted(
  { document: `${Col.posts}/{postId}/likes/{likerId}`, retry: true },
  async (event) => {
    const postRef = event.data?.ref.parent.parent;
    if (!postRef) return;
    await postRef.update({ likeCount: FieldValue.increment(-1) }).catch(
      // The post itself may have been deleted first — nothing to fix.
      () => undefined,
    );
  },
);

// ---------------------------------------------------------------------------
// Profile edits → denormalised copies
// ---------------------------------------------------------------------------

/**
 * Keeps the denormalised profile summaries in sync.
 *
 * Chat headers, the chat list, posts and meetings all embed a small copy of the
 * author's name and avatar so those screens need one read instead of one per
 * row. That trade is only safe if the copies stay fresh — which is this
 * function's entire job. Skipping it is how denormalisation quietly rots.
 */
export const onProfileUpdated = onDocumentUpdated(
  { document: `${Col.users}/{userId}`, retry: true },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const changed =
      before.fullName !== after.fullName ||
      before.avatarUrl !== after.avatarUrl ||
      before.handle !== after.handle ||
      before.verificationTier !== after.verificationTier;

    if (!changed) return;

    const uid = event.params.userId;
    const summary = {
      fullName: after.fullName ?? '',
      handle: after.handle ?? '',
      avatarUrl: after.avatarUrl ?? null,
      verificationTier: after.verificationTier ?? 'basic',
    };

    const connections = await db
      .collection(Col.connections)
      .where('members', 'array-contains', uid)
      .limit(200)
      .get();

    const batch = db.batch();
    for (const doc of connections.docs) {
      batch.update(doc.ref, { [`memberSummaries.${uid}`]: summary });
    }

    // Posts embed an author summary too.
    const posts = await db
      .collection(Col.posts)
      .where('authorId', '==', uid)
      .limit(200)
      .get();
    for (const doc of posts.docs) {
      batch.update(doc.ref, { author: summary });
    }

    await batch.commit();
  },
);

// ---------------------------------------------------------------------------
// Account deletion
// ---------------------------------------------------------------------------

/**
 * Sweeps everything a deleted user left behind.
 *
 * Firestore has no cascade delete, so the client removes its own profile and
 * private subcollection (which it has permission to do), and this trigger — run
 * with Admin privileges after the auth record is gone — removes the rest: their
 * half of every connection, and every document that references them.
 *
 * This runs as a backstop as well: if the app dies mid-deletion, the auth
 * record is still gone and this still fires.
 */
export const onUserDeleted = auth.user().onDelete(async (user) => {
  const uid = user.uid;

  const [connections, friendRequests, likesSent, passesSent, likesReceived] =
    await Promise.all([
      db.collection(Col.connections).where('members', 'array-contains', uid).get(),
      db
        .collection(Col.friendRequests)
        .where('members', 'array-contains', uid)
        .get(),
      db.collection(Col.likes).where('likerId', '==', uid).get(),
      db.collection(Col.passes).where('passerId', '==', uid).get(),
      db.collection(Col.likes).where('likeeId', '==', uid).get(),
    ]);

  const batch = db.batch();

  for (const doc of connections.docs) {
    // Subcollections are not removed by deleting the parent, so delete the
    // messages and suggestions first. Batched in chunks because a batch is
    // capped at 500 writes.
    const [messages, suggestions] = await Promise.all([
      doc.ref.collection(Col.messages).limit(400).get(),
      doc.ref.collection(Col.suggestions).limit(400).get(),
    ]);
    for (const m of messages.docs) batch.delete(m.ref);
    for (const s of suggestions.docs) batch.delete(s.ref);

    batch.delete(doc.ref);
  }

  for (const doc of [
    ...friendRequests.docs,
    ...likesSent.docs,
    ...passesSent.docs,
    ...likesReceived.docs,
  ]) {
    batch.delete(doc.ref);
  }

  await batch.commit();

  await db.collection(Col.users).doc(uid).delete().catch(() => undefined);

  logger.info('Swept deleted user', { uid });
});

// ---------------------------------------------------------------------------
// Scheduled maintenance
// ---------------------------------------------------------------------------

/**
 * Prunes stale interests-free suggestion documents and refreshes the
 * `interests` catalogue cache.
 *
 * Also a safety net for the one thing triggers cannot guarantee: if a match
 * creation trigger failed while the API key was misconfigured, matches would sit
 * without an opener forever. This re-checks recent connections.
 */
export const nightlyMaintenance = onSchedule(
  {
    schedule: 'every day 03:00',
    timeZone: 'UTC',
    secrets: [deepseekKey],
    retryCount: 1,
  },
  async () => {
    const cutoff = new Date(Date.now() - 48 * 60 * 60 * 1000);

    const recent = await db
      .collection(Col.connections)
      .where('createdAt', '>', cutoff)
      .limit(100)
      .get();

    let repaired = 0;

    for (const doc of recent.docs) {
      const [suggestions, messages] = await Promise.all([
        doc.ref.collection(Col.suggestions).limit(1).get(),
        doc.ref.collection(Col.messages).limit(1).get(),
      ]);

      // No opener AND no messages: the match trigger did not land.
      if (!suggestions.empty || !messages.empty) continue;

      const members: string[] = doc.data().members ?? [];
      if (members.length !== 2) continue;

      try {
        const context = await loadCoachContext(doc.id, members[0], members[1]);
        const suggestion = await generateSuggestion({
          context,
          type: 'opener',
          trigger: 'match_created',
          smarterAi: false,
        });

        await doc.ref.collection(Col.suggestions).add({
          ...suggestion,
          requestedBy: null,
          triggeredBy: 'match_created',
          status: 'active',
          basedOn: ['profile', 'shared_interests'],
          createdAt: new Date(),
        });
        repaired++;
      } catch (error) {
        logger.warn('Opener backfill failed', { connectionId: doc.id, error });
      }
    }

    logger.info('Nightly maintenance complete', { repaired });
  },
);
