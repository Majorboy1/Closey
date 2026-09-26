# Closey — Flutter

A dating app whose differentiator is a **shared AI conversation coach**: an AI
that sits in the thread with both people, offering openers you can both see, and
private nudges only you ever see.

Rewritten from the Expo/React Native app in Flutter, on **Firebase** instead of
Supabase.

---

## Quick start

The app runs with **no Firebase project at all**:

```bash
# firebase-tools is pinned to 13.x in ../.devtools — the Firestore emulator
# bundled with 14+ requires JDK 21, and 13.x works on 17.
# `--project demo-closey` is explicit: .firebaserc defaults to the real
# closey-ai-coach project, so that a bare `firebase deploy` targets something
# that can accept a deploy.
& "..\.devtools\node_modules\.bin\firebase.cmd" `
  emulators:start --project demo-closey --only "auth,firestore,storage,functions"

flutter run -d chrome --dart-define=CLOSEY_EMULATOR=true
```

Quote the `--only` list: in PowerShell a bare `--only auth,firestore` is parsed as
an *array*, reaches the CLI mangled, and fails with the misleading *"No emulators
to start"*.

The AI coach needs a DeepSeek key — without one `requestSuggestion` fails and the
chat screen sits on *"Reading the conversation…"*, because the emulator cannot
reach Secret Manager to substitute a value:

```bash
copy functions\.secret.local.example functions\.secret.local   # then fill it in
```

To use a real project (`closey-ai-coach` is the one this checkout is configured
for):

```bash
flutterfire configure --project=<your-project-id>
firebase deploy --only firestore:rules,storage,functions
flutter run -d chrome
```

If Firebase cannot be reached, the app does not crash — it routes to
`BackendSetupScreen`, which prints the exact commands and the underlying error.
That path did not exist before; a missing env var used to surface as a null error
inside the first network call.

---

## Layout

```
lib/
  core/
    config/         app-wide constants and the freemium rules
    router/         go_router config + auth guards
    theme/          the design system (see below)
    widgets/        the reusable component library
  data/
    models/         Firestore-shaped models, one file per aggregate
    repositories/   all data access; screens never touch Firebase directly
    firebase/       bootstrap + emulator wiring
  features/         one folder per screen area
  state/            Riverpod providers

functions/src/      Cloud Functions (TypeScript)
firestore.rules     security rules — the privacy guarantees live here
storage.rules
firestore.indexes.json

../_archive/        the previous Expo app, web prototype, specs and SQL
```

---

## Architecture

**State** — Riverpod 3. Services are plain `Provider`s, so any repository can be
swapped for a fake in a test with `ProviderScope(overrides: [...])`. The old
`api.ts` was 48 free functions over a module-level Supabase singleton, which
could not be tested without network stubs.

**Routing** — `go_router` with a `StatefulShellRoute.indexedStack`, so each tab
keeps its own navigation stack and scroll position. The Expo build used
`Stack.Protected` on a flat stack, which destroyed the previous tab's state on
every switch.

**Identity** — one `currentUserProvider` Firestore listener is the app's source
of truth. Because it is a listener rather than a one-shot fetch, a Cloud Function
changing `verificationTier` or a quota counter updates every dependent widget
automatically. The old app called `refreshProfile()` by hand after each mutation
and still drifted.

**Write path** — anything the user waits for is a callable function; anything
that is a side effect of a write is a trigger. So swiping and sending never block
on the model, and a match still produces an opener even if both phones go offline
immediately afterwards.

---

## Design system

`lib/core/theme/`. One token source, two themes, no hardcoded values.

| File | Contents |
|---|---|
| `closey_palette.dart` | Raw brand ramps (rose, sage, amber, ink, paper) |
| `closey_colors.dart` | Semantic `ThemeExtension` + `context.colors` |
| `closey_typography.dart` | Fraunces + Plus Jakarta Sans type scale |
| `closey_spacing.dart` | 4pt spacing scale, radii, stroke widths, tap targets |
| `closey_motion.dart` | Four durations, three curves, reduce-motion aware |
| `closey_theme.dart` | Assembles light and dark `ThemeData` |

### What changed, and why

**One palette, not two.** The Expo app documented warm ink/paper/amber/sage in
`theme.ts` but rendered a near-black UI with ~40 ad-hoc greys (`#999999`,
`#666666`, `rgba(255,255,255,0.05)`…) hardcoded across 22 screen files. Those are
gone; every colour resolves through `context.colors`.

**Warm paper is the default.** Light-first, with a full dark mode. It reads
editorial and trustworthy, and distinguishes Closey from the dark purple
"AI app" look. `app.json` previously declared `userInterfaceStyle: "light"`
while shipping a dark UI — a contradiction that meant the OS could never apply a
dark palette.

**Contrast is deliberate.** Brand rose `#C4576B` is legible as a *fill* but not
as *text* on light (4.29:1). So there are two tokens: `brand` for fills
(`#B94A5E`, 5.0:1 with white text) and `brandText` for text (`#A23A4E`, 6.5:1).
On dark, Material 3 inverts it — a lighter fill with dark ink on top — because
keeping the light-mode fill would have shipped a 4.29:1 button label.

**Fraunces + Plus Jakarta Sans.** A soft optical-sized serif for brand moments
and screen titles, a friendly geometric grotesque for UI. Chosen so the coach's
copy reads like something a person could say rather than system output.

**Accessibility fixes.** Selected chips get a checkmark and report `selected` to
screen readers (selection was colour-only before). Text fields have a visible
focus ring (there was no focus state at all). Icon buttons meet a 48dp target.
Swipe actions carry semantic labels. Text scaling is respected and clamped to
1.4× so the deck cannot break.

---

## UI/UX changes

The previous build had three fully-implemented features that **no screen ever
rendered**: the swipe deck, the match celebration, and the Plans/calendar screen.
`likeProfile`, `passProfile` and `listMutualLikes` were never called. Discovery
was a static horizontal strip with no way to act on anyone.

**Now reachable and rebuilt:**

- **Discover is the landing tab** — the swipe deck with paged photos, shared-
  interest reasons, a "Likes you" ribbon, undo, haptics, and a real "It's a
  Match!" celebration that leads somewhere useful.
- **Plans** is reached contextually from Chats and Profile rather than as a
  fifth tab. Plans are per-conversation, so sitting next to conversations is
  better information architecture than competing for an icon.
- **Home, Create post, Profile, Settings, Paywall, Verification, Report/Block**
  all work against real data. The feed read from a `MOCK_FEED` constant and
  "Create post" only showed an alert; the profile displayed eight hardcoded
  numbers and a random `picsum.photos` cover.

**The coach card (`features/chat/widgets/coach_card.dart`)** is the piece that
has to earn the concept:

1. **Shared cards are attributed to both people** — an overlapping avatar cluster
   and "you can both see this". The old card was left-aligned like an incoming
   message, which made it read as the AI speaking on someone's behalf.
2. **Private nudges are a visually different object** — recessed rose surface, a
   lock, "just for you", and an explicit sentence that the other person cannot
   see it. Trust in this mechanic depends on the user believing it.
3. **The reason is always shown.** "One person answered without asking back"
   turns an unexplained interruption into legible help.
4. **"Use this" fills the composer instead of sending.** The spec (§12) left this
   open; auto-sending would violate the guardrail that the AI never speaks as
   you. You edit, then send.
5. **The quota state change is the call to action.** At zero credits the
   secondary button becomes "Buy more" with a plus icon and the sage colour —
   carried over from the DECISIONS log because it was a genuinely good idea.
6. **A quiet period is visible.** The coach cannot fire twice in a row inside
   `QuotaConfig.coachQuietPeriod`, and the button says so.

**Onboarding** became a real wizard: animated progress, per-step validation,
back navigation that preserves answers, and a "save and finish later" exit.
Previously all four sections stacked on one page and validation only surfaced on
the final button. The "3 things you love talking about" step now explains that it
feeds the coach, because it looks like busywork otherwise.

**State system.** `AsyncSection` gives every async surface loading, empty and
error states from one place. Failures render as inline, retryable banners rather
than blocking `Alert.alert` dialogs. List loads use content-shaped skeletons so
the layout does not jump.

---

## Backend

### Firestore layout

```
users/{uid}                              profile
users/{uid}/private/account              quota, subscription, push tokens
users/{uid}/blocks/{blockedId}
connections/{a}__{b}                     sorted pair → deterministic id
connections/{id}/messages/{id}
connections/{id}/suggestions/{id}
connections/{id}/optIns/{uid}
likes/{likerId}__{likeeId}
passes/{passerId}__{passeeId}
friendRequests/{senderId}__{receiverId}
meetings/{id}
posts/{id}   posts/{id}/likes/{uid}
reports/{id}
interests/{label}                        config/{doc}
```

### Where the product rules live

**The central privacy rule.** A `private` suggestion carries a `targetUserId`,
and `firestore.rules` allows a read only when `visibility == 'shared'` or
`targetUserId == request.auth.uid`. Firestore evaluates rules per listener,
server-side, so **the partner's device never receives the document at all**.

This is a real improvement on the previous implementation. Under Supabase, the
RLS policy was correct but the client still received the row over the shared
match channel and filtered it in the UI. The promise "your match will never know
you were nudged" is now enforced by the database rather than by client code.

**Tamper-proof quota.** `users/{uid}/private/**` is readable by the owner and
**never writable** by a client. Only the Admin SDK can change a counter, so
`tryConsumeSuggestion` in `functions/src/quota.ts` is the single writer. It is a
transaction, which is what stops two concurrent requests both slipping past the
daily limit — the same guarantee the Postgres version got from
`select ... for update`.

**Ported rules** (from `_archive/supabase/migrations/`):

| Rule | Where |
|---|---|
| 5 AI/day free, 20/day Premium, one app-wide pool | `functions/src/quota.ts` |
| Every generation costs a credit, including "Another" | `authorizeCoachUse` |
| "Use this" is free | nothing to charge — it never calls the model |
| Top-ups stack, valid for the day only | `resolveLimits` |
| 5 new DM conversations/month; friends unlimited | `authorizeNewDm` |
| AI requires the Verified tier | `authorizeCoachUse` |
| Mutual opt-in required, per conversation | `authorizeCoachUse` |
| Private nudges readable only by the target | `firestore.rules` |
| One unprompted card per quiet period, no stacking | `triggers.ts` |
| `likeCount` derived by trigger, not client-writable | `onPostLikeCreated` |

### Functions

**Callables** — `requestSuggestion`, `startDm`, `acceptFriendRequest`,
`unmatchConnection`, `blockUser`, `unblockUser`, `deleteAccountData`,
`createCheckoutSession`, `getMyQuota`
**Triggers** — `onConnectionCreated` (shared opener + match push),
`onMessageCreated` (reciprocity/stall/deepening analysis + push),
`onPostLikeCreated`/`Deleted`, `onProfileUpdated` (keeps denormalised copies
fresh), `onUserDeleted` (cascade sweep), `nightlyMaintenance` (backfills openers
that failed while the API key was misconfigured)
**HTTP** — `stripeWebhook` (signature-verified and idempotent per event id; the
only place entitlements are granted)

`DEEPSEEK_API_KEY` is a Firebase secret. The model is **never** called from the
client, so the key cannot leak.

---

## Known gaps

Honest list of what is not finished:

- **A reachable backend with an unreachable *data* backend hangs on the splash.**
  `BackendSetupScreen` only triggers when `Firebase.initializeApp` throws. If init
  succeeds but Auth never responds (no emulator running, no network), the auth
  stream never resolves, `sessionStatusProvider` stays `unknown`, and the router
  holds `/` forever with no explanation. Verified on the web build. Fix: give
  session resolution a timeout that falls through to an error state.
- **The Firestore emulator needs JDK 21+, not 17.** `firebase-tools` 15 refuses to
  start it on older Java: *"no longer supports Java version before 21"*. The Auth
  emulator is Node-based and works on 17, which is why `--only auth` succeeds and
  `--only auth,firestore` fails.
- **On Windows PowerShell, quote the `--only` list.** A bare
  `--only auth,firestore` is parsed as a PowerShell *array*, reaches the CLI
  mangled, and fails with the misleading *"No emulators to start"*. Use
  `--only "auth,firestore"`.
- **Windows and Linux desktop cannot run the app at all** while the data layer is
  Firebase-backed: `firebase_core`, `cloud_firestore`, `firebase_auth` and
  `firebase_storage` support Android, iOS, macOS and Web only. Web works (verified:
  `flutter build web` succeeds and the app boots); desktop needs an offline data
  layer first.
- **`functions/` has not been type-checked or deployed.** Run `npm install &&
  npm run build` inside it before deploying.
- **No tests.** The template `test/widget_test.dart` was deleted because it
  referenced a scaffold class that does not exist. The repository layer is
  injectable, so this is straightforward to add.
- **Verification is not wired to a KYC vendor.** `simulateVerification` records a
  request; plug in Persona / Stripe Identity / Veriff / Yoti.
- **`google_fonts` fetches at runtime.** Run `dart run google_fonts:google_fonts`
  or bundle the TTFs before release so text renders offline on first launch.
- **Discovery post-filters in memory** — mutual blocks, already-swiped and
  reciprocal likes cannot be expressed in a single Firestore query. Bounded by a
  120-document scan window; the scale answer is a `discoveryPool/{uid}` document
  refreshed nightly.
- **`watchFeed` does one small read per visible post** to resolve "did I like
  this". Fine at feed scale; worth a `fanOutFeed/{uid}` function later.
- **`getMyQuota` in `api.ts` reads private data directly** rather than through
  `quota.ts` helpers; harmless but inconsistent.
- Packages held back by constraints: `flutter_riverpod 3.3.2` (3.4.3),
  `go_router 17.5.0` (18.0.1).

## Running locally, end to end

No Firebase project is needed. Everything below runs against the emulator suite
on project `demo-closey`.

### 1. Start the emulators

```bash
# firebase-tools is pinned to 13.x locally (see .devtools/) because the
# Firestore emulator bundled with 14+ requires JDK 21, and 13.x works on 17.
npm install --prefix ../.devtools firebase-tools@13 --no-audit --no-fund

& "..\.devtools\node_modules\\.bin\firebase.cmd" `
  emulators:start --project demo-closey --only "auth,firestore,storage,functions"
```

Two gotchas worth knowing:

- **Quote the `--only` list.** In PowerShell a bare `--only auth,firestore` is
  parsed as an *array*, reaches the CLI mangled, and fails with the misleading
  *"No emulators to start"*.
- **`.firebaserc` must exist.** Without it there is no project association and
  `emulators:start` refuses to start anything.

Emulator ports: Auth `9099`, Firestore `8080`, Storage `9199`, UI `4000`.

### 2. Run the app

```bash
flutter run -d chrome
```

Windows and Linux desktop are not available — see *Platform support* below.

### 3. Create the demo account and sign in

**Google sign-in does not work against the Auth emulator.** There is no real
OAuth server, and `signInWithPopup` fails with *"Unable to establish a connection
with the popup"*: the popup is served from `authDomain`, which for a demo project
does not resolve.

Create the account the seed expects. This prints a uid, which step 4 needs — this
Auth emulator answers `405` to `accounts:batchGet`, so the seed cannot discover a
signed-in user on its own:

```bash
$u = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key'
$b = '{"email":"demo@closey.app","password":"closeydemo","displayName":"You","returnSecureToken":true}'
(Invoke-RestMethod $u -Method Post -ContentType 'application/json' -Body $b).localId
```

Then, in the app: **Continue with email → Sign in**, with `demo@closey.app` /
`closeydemo`.

Real Gmail login needs a real Firebase project with the Google provider enabled;
mobile additionally needs the app's SHA-1 registered.

### 4. Seed the account

The rules forbid a client from creating other people's profiles or any AI
suggestion — deliberately — so the demo data is written with emulator owner
privileges:

```bash
# --uid is required: this Auth emulator answers 405 to accounts:batchGet, so the
# script cannot discover the signed-in user. Use the uid printed in step 3, or
# read it from the browser via indexedDB.open('firebaseLocalStorageDb').
node tool/seed_emulator.js --fresh --uid=<uid>
```

`--probe` checks connectivity to the emulator REST API without writing anything.

This creates five people, three conversations with real message history, a shared
opener, a **private reciprocity nudge addressed to you**, two meetups and four
posts. It also marks your profile `onboarded` and `premium` so the journey skips
the wizard and the coach's tier gate — a real account gets neither.

Hard-refresh the page if the app was already open.

### Platform support

Web, Android, iOS and macOS work. **Windows and Linux cannot run the app** while
the data layer is Firebase-backed: `firebase_core`, `cloud_firestore`,
`firebase_auth` and `firebase_storage` support Android, iOS, macOS and Web only.
A `windows/` folder exists but the plugins will not register.


