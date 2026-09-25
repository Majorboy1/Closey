import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp({
  // Large message payloads and the coach's context window both benefit from
  // ignoring undefined rather than throwing.
  ignoreUndefinedProperties: true,
});

export const db = getFirestore();

/**
 * Collection and field names, in one place.
 *
 * These mirror the Dart models in `lib/data/models/` exactly. Keeping the
 * strings here (rather than scattered through call sites) is what makes it
 * possible to spot drift between client and server.
 */
export const Col = {
  users: 'users',
  connections: 'connections',
  messages: 'messages',
  suggestions: 'suggestions',
  optIns: 'optIns',
  likes: 'likes',
  passes: 'passes',
  friendRequests: 'friendRequests',
  meetings: 'meetings',
  posts: 'posts',
  reports: 'reports',
  interests: 'interests',
  config: 'config',
} as const;

/**
 * Product constants.
 *
 * These are the numbers the whole freemium model rests on, so they live here
 * and in `lib/core/config/app_config.dart` — change both together.
 *
 * Ported from `supabase/migrations/0004_quotas_monetization.sql`.
 */
export const Quota = {
  /** Free tier baseline: AI generations per day, from ONE app-wide pool. */
  freeAiPerDay: 5,
  /** Premium: AI generations per day. */
  premiumAiPerDay: 20,
  /** One-off top-up: extra generations, valid for that day only. */
  topUpGrant: 5,
  /** Free tier: NEW direct conversations started per calendar month. */
  freeDmPerMonth: 5,
  /** Guardrail: minimum gap between two unprompted coach cards in a thread. */
  coachQuietMinutes: 20,
  /** How long a thread may sit silent before the coach may re-open it. */
  stallHours: 6,
  /** Recent-message window sent to the model, to bound token cost. */
  contextWindow: 20,
} as const;

/**
 * Allowed origins for CORS on callable functions.
 *
 * The old edge functions used `*`; locking this down matters because
 * `createCheckoutSession` returns a Stripe URL.
 */
export const ALLOWED_ORIGINS = [
  'http://localhost',
  'http://localhost:8080',
  'https://closey.app',
];
