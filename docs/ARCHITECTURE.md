# How Closey works

A dating app whose differentiator is a **shared AI conversation coach**: an AI
that sits in the thread with both people. Shared suggestions are visible to both;
**private nudges are visible only to the person being nudged.**

Read this before changing anything. It explains the invariants that are easy to
break by accident.

---

## 1. Startup sequence

```
main()
 ├─ SystemChrome.setPreferredOrientations(portrait)   // deck + composer assume portrait
 ├─ FirebaseBootstrap.init()  → BackendMode            // never throws
 └─ ProviderScope → _Bootstrap → CloseyApp → MaterialApp.router
```

`FirebaseBootstrap.init()` returns a `BackendMode` instead of throwing:

| Mode | When | Consequence |
|---|---|---|
| `live` | real `FirebaseOptions` from `flutterfire configure` | production |
| `emulator` | `--dart-define=CLOSEY_EMULATOR=true`, **or** the options are still the `demo-closey` placeholder | talks to localhost:8080/9099/5001/9199 |
| `offline` | initialisation failed | app boots to `BackendSetupScreen` |

**Invariant:** a fresh clone must never crash on launch. Any change that makes
`init()` throw breaks the first-run experience for everyone.

## 2. Session and routing

`app_router.dart` is a `GoRouter` whose `redirect` reads `sessionStatusProvider`:

```
authStateProvider          FirebaseAuth.authStateChanges()
   └─ uidProvider
        └─ currentUserProvider      users/{uid} snapshot   ← source of truth
             └─ sessionStatusProvider
                  unknown          → /            (splash, hold here)
                  signedOut        → /welcome
                  needsOnboarding  → /onboarding
                  ready            → /discover
```

`currentUserProvider` is a **stream**, not a fetch. A Cloud Function changing
`verificationTier`, or a quota counter updating, re-renders every dependent
widget with no manual refresh. Do not replace it with a one-shot read.

Redirects are driven by a `ChangeNotifier` that `ref.listen`s to both auth and
profile, so the router is never rebuilt (rebuilding would lose every tab's state).

Tabs live in a `StatefulShellRoute.indexedStack`: Home, Discover, Chats, You,
plus a Create button outside the branches. **Each branch keeps its own stack and
scroll offset.**

## 3. Layer rules

```
features/**        screens. Composes widgets + reads providers. No Firebase, no SQL.
  ↓
state/**           Riverpod providers. Wires repositories to the widget tree.
  ↓
data/repositories  ALL data access. The only place Firebase types appear.
  ↓
data/models        Firestore-shaped immutable models + toMap/fromMap.
```

**Hard rules**

1. **Screens never import `cloud_firestore` / `firebase_auth`.** All access goes
   through a repository. This is what keeps screens testable.
2. **Screens never hardcode a colour, radius, duration or font size.** They read
   `context.colors` / `context.text` / `Gap` / `Radii` / `Motion`.
3. **Services are plain `Provider`s** so any repository can be faked with
   `ProviderScope(overrides: [...])`.

## 4. Firestore layout

```
users/{uid}                                   profile (public read)
users/{uid}/private/account                   quota, subscription, pushTokens
users/{uid}/blocks/{blockedId}
connections/{a}__{b}                          a,b sorted → deterministic id
connections/{id}/messages/{id}
connections/{id}/suggestions/{id}
connections/{id}/optIns/{uid}
likes/{likerId}__{likeeId}
passes/{passerId}__{passeeId}
friendRequests/{senderId}__{receiverId}
meetings/{id}
posts/{id}                                    posts/{id}/likes/{uid}
reports/{id}
interests/{label}                             config/{doc}
```

Two conventions worth internalising:

- **Deterministic document ids.** Every pairwise or directed relationship uses a
  derived id (`Connection.idFor`, `FriendRequest.idFor`, `Post.likeDocId`). A
  double-tap, a retry, or two devices cannot create duplicates.
- **`members` is a sorted 2-element array.** Security rules express membership as
  `uid in resource.data.members` — one index check, no extra read.

**Denormalised copies** (`connection.memberSummaries`, `post.author`,
`meeting.otherUser`) exist so list screens are one query instead of N+1.
`onProfileUpdated` in `functions/src/triggers.ts` keeps them fresh. If you add a
denormalised field, add it to that trigger too — otherwise it silently rots.

## 5. The coach lifecycle

This is the product. Two entry points:

**On-demand** (`requestSuggestion` callable) — the user taps "Help me continue
this". Always produces a **shared** card: it is a deliberate action, not a
coaching moment.

**Unprompted** (`onMessageCreated` trigger) — after each message:

```
1. one active card already?             → stop
2. last card < coachQuietMinutes ago?   → stop
3. analyzeConversation(history):
     reciprocity gap   → private nudge, targeted at the person who answered
                         without asking back          [priority 1]
     silent > stallHours → topic_continuation or new_topic   [priority 2]
     ≥12 turns, still short → deepening_question              [priority 3]
4. loadCoachContext(perspectiveId, otherId)   ← built from the NUDGED person's POV
5. charge a credit (or skip if the pool is empty)
6. write suggestions/{id}, notify
```

**Invariants**

- `analyzeConversation` is rule-based, not model-based. It runs on every message,
  so it must stay cheap, deterministic and explainable.
- The context for a private nudge is built from the **target's** perspective.
  Building it from the other person's makes the model phrase the nudge as if the
  partner were reading it. This was a real bug once.
- Two guardrails always apply: no stacking, and a quiet period.
- The model is told to output something **the user could say**, never advice
  about the user, and never as the other person.

## 6. Quota

| Rule | Value |
|---|---|
| Free AI generations | 5/day, **one app-wide pool** (not per chat) |
| Premium | 20/day + a stronger model |
| Top-up | +5, valid for that day only, stacks |
| Charged on | every generation, **including "Another" rerolls** |
| Not charged on | "Use this" — it sends an already-generated suggestion |
| Free DMs | 5 **new conversations**/month; messages inside a thread are unlimited |
| Friends | unlimited chat (this is the growth loop) |

Enforced in `functions/src/quota.ts` inside **transactions**, because the
Postgres version used `select ... for update` for the same reason: two concurrent
requests must not both slip past the limit.

`users/{uid}/private/**` is readable by the owner and **writable only by the
Admin SDK**. `quota.ts` is the single writer. A client can display a quota and
can never grant itself credits.

## 7. Security model

`firestore.rules` is the contract. The load-bearing rule:

```
// suggestions/{id}
allow read: if isConnectionMember(connectionId) && (
  resource.data.visibility == 'shared' || resource.data.targetUserId == uid()
);
```

Firestore evaluates rules **per listener, server-side**, so a partner's device
never receives a private suggestion document at all. Under the previous Supabase
implementation the RLS policy was correct but the client still received the row
over a shared channel and filtered it in the UI.

Other non-obvious rules:

- `connections`: no permissive `list` rule. Because rules must be *provable* for
  every document in a query, an unfiltered query is rejected — the client is
  forced to include `where('members', arrayContains: uid)`.
- `connections` update: `members` and `kind` are immutable. Otherwise a user
  could invite themselves into a thread or upgrade a metered DM to an unlimited
  friend thread.
- `messages` update: only `readBy` may change. Sent messages are immutable.
- `suggestions` create: `false`. Only Cloud Functions write these, so nobody can
  inject text into a partner's chat pretending it came from the coach.
- `posts.likeCount`: not client-writable. A trigger derives it.
- `reports`: create-only. A reported user must not be able to enumerate reports
  against them.

## 8. Notifications

Private nudges must **never** leak through a push. `sendPush` in `triggers.ts`
sends a deliberately vague body for a private nudge ("Open the chat — there is a
suggestion just for you"), and `_onBackgroundMessage` in `main.dart` renders
nothing. The Cloud Function composes every visible notification, because only it
knows the sender's name and the recipient's preferences.

## 9. Design system

Tokens only, from `lib/core/theme/`:

| Concern | Access | Notes |
|---|---|---|
| Colour | `context.colors` (a `ThemeExtension`) | `brand` = fill, `brandText` = text on light |
| Type | `context.text` | Fraunces for brand/coach, Plus Jakarta Sans for UI |
| Spacing | `Gap`, `Gap.pageInsets` | strict 4pt scale |
| Shape | `Radii`, `Strokes` | cards 20, sheets 32, pills full |
| Motion | `context.motion(Motion.quick)` | respects reduce-motion |
| Tap targets | `TapTarget.min` (48dp) | |

`brand` (`#B94A5E`) and `brandText` (`#A23A4E`) are separate on purpose: the
brand rose is legible as a fill (5.0:1 with white text) but not as text on light
(4.29:1). On dark, Material 3 inverts it — a lighter fill with dark ink on top.

## 10. Firebase platform support

`firebase_core`, `cloud_firestore`, `firebase_auth` and `firebase_storage`
support **Android, iOS, macOS and Web**. They do **not** support Windows or
Linux.

Consequence: `flutter run -d windows` cannot work while the data layer is
Firebase-backed. Web and mobile only, unless an offline data layer is added.
`firebase_messaging` additionally has no desktop support at all.
