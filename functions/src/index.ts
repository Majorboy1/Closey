/**
 * Closey Cloud Functions — entry point.
 *
 * Everything is declared in one of two places, by intent:
 *
 *  - `api.ts`      — callables the client is *waiting on* (start a DM, ask the
 *                    coach, check out) and the Stripe webhook.
 *  - `triggers.ts` — side effects of writes the client already made (a match
 *                    creates an opener, a message triggers analysis, a profile
 *                    edit refreshes the denormalised copies).
 *
 * The reason for the split is latency: the swipe and send paths never wait on
 * the model, and a match still produces an opener even if both phones go offline
 * the instant after swiping.
 *
 * Deploy: `npm run deploy`, or run everything locally with
 * `firebase emulators:start --project demo-closey`.
 */

export {
  requestSuggestion,
  startDm,
  acceptFriendRequest,
  unmatchConnection,
  blockUser,
  unblockUser,
  deleteAccountData,
  createCheckoutSession,
  stripeWebhook,
  getMyQuota,
} from './api';

export {
  onConnectionCreated,
  onMessageCreated,
  onPostLikeCreated,
  onPostLikeDeleted,
  onProfileUpdated,
  onUserDeleted,
  nightlyMaintenance,
} from './triggers';
