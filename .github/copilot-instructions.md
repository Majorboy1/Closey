# Closey — project guidelines

Flutter dating app with a shared AI conversation coach, backed by Firebase.
**Read `docs/ARCHITECTURE.md` before changing anything non-trivial** — it
documents the invariants (coach privacy, quota, rule-provable queries) that are
easy to break by accident.

## Commands

```bash
flutter analyze                       # must be clean; there is no test suite yet
dart fix --apply                      # mechanical lint fixes
flutter run -d chrome                 # web
flutter run --dart-define=CLOSEY_EMULATOR=true

cd functions && npm run build         # type-check the Cloud Functions
firebase emulators:start --project demo-closey
firebase deploy --only firestore:rules,storage,functions
```

## Layout

| Path | Contains |
|---|---|
| `lib/core/theme/` | design tokens — the only place colours/sizes/durations are defined |
| `lib/core/widgets/` | reusable component library |
| `lib/core/router/` | `go_router` config and auth guards |
| `lib/data/models/` | Firestore-shaped immutable models (`toXMap` / `fromXMap`) |
| `lib/data/repositories/` | **all** data access |
| `lib/features/<area>/` | screens, one folder per area |
| `lib/state/` | Riverpod providers |
| `functions/src/` | quota, AI coach, triggers, callables, Stripe |
| `firestore.rules` | the security contract — read it before touching data shapes |

## Conventions

**Screens never import Firebase.** All access goes through a repository in
`lib/data/repositories/`. Screens compose widgets and read providers.

**Screens never hardcode visual values.** Use `context.colors`, `context.text`,
`Gap`, `Radii`, `Strokes`, `Motion`, `TapTarget`. If a value you need has no
token, add one to `lib/core/theme/` rather than inlining a literal — the previous
React Native codebase accumulated ~40 ad-hoc greys and two conflicting palettes
this way.

**Riverpod 3.** `StateProvider` / `StateNotifierProvider` moved to
`package:riverpod/legacy.dart` — do not use them. `AsyncValue.valueOrNull` no
longer exists; `.value` is nullable. Prefer `Provider`, `FutureProvider`,
`StreamProvider`, `NotifierProvider`, `AsyncNotifierProvider`.

**Firestore reads must be rule-provable.** There is deliberately no permissive
`list` rule on `connections`. A query must carry the filter the rule checks
(`where('members', arrayContains: uid)`), or Firestore rejects it.

**Deterministic document ids** for pairwise relationships (`Connection.idFor`,
`FriendRequest.idFor`, `Post.likeDocId`). Never let a retry create a second row.

**Denormalised copies must be maintained.** If you add a field to
`connection.memberSummaries`, `post.author` or `meeting.otherUser`, add it to the
`onProfileUpdated` trigger in `functions/src/triggers.ts`.

## Product invariants

Breaking any of these is a product bug, not a style issue.

1. **A private suggestion is readable only by its `targetUserId`.** It must never
   leak through a push notification, a log, an export, or a client-side filter.
2. **The coach never sends anything.** It suggests; the human edits and sends.
   "Use this" fills the composer — it does not auto-send.
3. **The coach never speaks as the other person.**
4. **Every generation costs a credit, including "Another".** "Use this" is free.
5. **The free AI pool is 5/day app-wide**, not per conversation.
6. **Friends get unlimited chat; DMs are 5 new conversations/month.**
7. **The coach requires mutual, per-conversation opt-in** and a Verified tier.
8. **Quota is enforced server-side in a transaction.** Never trust a client value.

## Tone of the code

Comments explain **why**, especially where a decision is non-obvious or where a
bug was already made once (e.g. building a private nudge's context from the wrong
person's perspective). Do not narrate what the code plainly does.
