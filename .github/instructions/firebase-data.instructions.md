---
description: "Data layer rules for Closey. Covers Firestore read and write patterns, security-rule provability, transactions, quota enforcement, deterministic ids, denormalised fields, error mapping and index requirements."
name: "Firebase Data Layer"
applyTo: "lib/data/**, firestore.rules, storage.rules, firestore.indexes.json, functions/**"
---

# Data layer

## Layering

`lib/data/repositories/` is the **only** place Firebase types may appear. Screens
import repositories through providers; they never import `cloud_firestore`,
`firebase_auth`, `firebase_storage` or `cloud_functions`.

Models in `lib/data/models/` are immutable, expose `toCreateMap()` / `fromMap()`,
and carry the Firestore shape. `fromMap` must tolerate missing fields — documents
written by an older client, or by a Cloud Function mid-migration, will be read by
a newer one.

## Queries must be rule-provable

`firestore.rules` deliberately has **no permissive `list` rule** on `connections`.
Firestore requires that a query be provably restricted to documents the rule
allows, so:

```dart
// correct — the rule can prove every returned doc includes me
.where('members', arrayContains: uid).orderBy('lastMessageAt', descending: true)

// runtime failure, not a compile error
.orderBy('lastMessageAt', descending: true)
```

Any new query needs the matching filter **and** a composite index in
`firestore.indexes.json`.

## Writes

**Deterministic ids for relationships.** `Connection.idFor(a, b)` sorts the pair
and joins with `__`. `FriendRequest.idFor(sender, receiver)`. `Post.likeDocId`.
Never let a retry, a double-tap or a second device create a duplicate row.

**Transactions for anything that accumulates.** Quota counters, like counts and
match creation. A read-then-write races.

```dart
return db.runTransaction((tx) async {
  final snap = await tx.get(ref);
  // decide from snap, then write — under optimistic concurrency control
});
```

**Batches for paired writes.** If two documents must agree (a message plus the
conversation's unread counter), they go in one `WriteBatch`.

**Never write protected fields.** Not client-writable, ever:

- `users/{uid}/private/**` — quota, subscription, top-ups, push tokens. Admin SDK
  only; `functions/src/quota.ts` is the single writer.
- `verificationTier` — set by a KYC webhook.
- `blockedUserIds` — written by the `blockUser` callable, because it drives
  discovery exclusion.
- `posts.likeCount` — derived by a trigger from the `likes` subcollection.
- `connections/{id}/suggestions/**` — created only by Cloud Functions, so nobody
  can inject text into a partner's chat pretending it came from the coach.

## The one invariant that must never break

A `private` suggestion is readable **only** by its `targetUserId`:

```
allow read: if isConnectionMember(connectionId) && (
  resource.data.visibility == 'shared' || resource.data.targetUserId == uid()
);
```

It must not leak through a push notification, a log, an analytics event, an
export, or a client-side filter. Do not rely on the UI to hide it — the database
already does.

## Denormalised data

`connection.memberSummaries`, `post.author` and `meeting.otherUser` exist so list
screens are one query rather than N+1.

**If you add a field to one of these, add it to `onProfileUpdated` in
`functions/src/triggers.ts`.** Otherwise it silently goes stale, and a user who
changes their photo keeps the old one in every chat header.

## Error mapping

Throw `CloseyFailure` with a `code`, not a raw exception. The UI maps codes:

| `code` | UI behaviour |
|---|---|
| `QUOTA_EXCEEDED` | paywall |
| `DM_LIMIT_REACHED` | paywall |
| `VERIFICATION_REQUIRED` | verification screen |
| `NOT_ENABLED` | coach opt-in prompt |
| `FUNCTIONS_UNAVAILABLE` | local fallback or a "deploy the functions" message |
| `STRIPE_NOT_CONFIGURED` | setup instructions |

An unmapped code reaches the user as a generic failure. If a Cloud Function
introduces a new `HttpsError` code, map it here in the same change.

## Cost

Bound every listener and every scan. `watchMessages` caps at 200,
`watchConnections` at 100, discovery at a 120-document window. Discovery
post-filters in memory because mutual blocks, already-swiped and reciprocal likes
cannot be expressed in a single Firestore query — that is bounded by design, not
an oversight.
