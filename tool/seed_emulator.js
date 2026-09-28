/**
 * Seeds the Firebase emulator with a demo Closey account.
 *
 * Why this exists: the app is unusable until it has a signed-in user with a
 * profile, some connections, and a thread worth looking at — and the security
 * rules deliberately forbid a client from creating other people's profiles or
 * any AI suggestion. So seeding has to happen with elevated privileges.
 *
 * It talks to the emulator's REST API with `Authorization: Bearer owner`, which
 * is the documented way to bypass Firestore rules on the emulator. It never
 * touches production, and it refuses to run against anything but a demo project.
 *
 * Usage (emulators must be running):
 *   node tool/seed_emulator.js                 # seeds the newest signed-in user
 *   node tool/seed_emulator.js --email=a@b.com # seeds a specific account
 *   node tool/seed_emulator.js --fresh         # deletes prior demo data first
 */

const PROJECT = 'demo-closey';
const HOST = process.env.EMULATOR_HOST ?? 'localhost';

const FS = `http://${HOST}:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
const AUTH = `http://${HOST}:9099/identitytoolkit.googleapis.com/v1/projects/${PROJECT}`;

// Guard: this script assumes emulator privileges. Refuse anything else.
if (!PROJECT.startsWith('demo-')) {
  console.error('Refusing to run: this script is for demo projects only.');
  process.exit(1);
}

// ---------------------------------------------------------------- field DSL --

const s = (v) => ({ stringValue: String(v) });
const i = (v) => ({ integerValue: String(v) });
const b = (v) => ({ booleanValue: Boolean(v) });
const ts = (d) => ({ timestampValue: new Date(d).toISOString() });
const geo = (lat, lng) => ({
  geoPointValue: { latitude: lat, longitude: lng },
});
/**
 * Explicit null.
 *
 * A bare JS `null` is not a Firestore value and is rejected with the same
 * unhelpful "Payload isn't valid for request" as a malformed array.
 */
const nul = () => ({ nullValue: null });
/**
 * Firestore array value.
 *
 * Accepts either spread values (`arr(s('a'), s('b'))`) or a single array
 * (`arr([])`), because both spellings occur below. Calling the spread form with
 * an array nests a raw JS array inside `values`, which the emulator answers
 * with "Payload isn't valid for request" — a message that points nowhere near
 * the actual cause.
 */
const arr = (...values) => ({
  arrayValue: {
    values:
      values.length === 1 && Array.isArray(values[0]) ? values[0] : values,
  },
});
const arrStr = (list) => arr(...list.map(s));
const map = (obj) => ({ mapValue: { fields: obj } });

// --------------------------------------------------------------- transport --

async function fsRequest(path, { method = 'GET', body, allowMissing = false } = {}) {
  const res = await fetch(`${FS}/${path}`, {
    method,
    headers: {
      // The emulator's escape hatch: full read/write, security rules bypassed.
      Authorization: 'Bearer owner',
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (res.status === 404 && allowMissing) return null;
  if (!res.ok) {
    throw new Error(`${method} ${path} → ${res.status} ${await res.text()}`);
  }
  return res.status === 204 ? null : res.json();
}

const setDoc = (path, fields) => fsRequest(path, { method: 'PATCH', body: { fields } });

async function deleteDoc(path) {
  const res = await fetch(`${FS}/${path}`, {
    method: 'DELETE',
    headers: { Authorization: 'Bearer owner' },
  });
  if (!res.ok && res.status !== 404) {
    throw new Error(`DELETE ${path} → ${res.status}`);
  }
}

async function listDocs(path) {
  const data = await fsRequest(path, { allowMissing: true });
  return data?.documents ?? [];
}

// ------------------------------------------------------------------ content --

const DEMO_PEOPLE = [
  {
    id: 'demo-layla',
    fullName: 'Layla Adeyemi',
    age: 29,
    city: 'London',
    bio: 'Architect by trade, cook by obsession. Ask me about the worst building in London.',
    interests: ['Coffee', 'Art', 'Cooking', 'Travel', 'Reading'],
    topics: ['Why cities feel different at night', 'Growing up between two places', 'Food as memory'],
    promptQ: 'The way to my heart is',
    promptA: 'A really good jollof and an argument about whether it is better than fried rice.',
    seed: 'layla',
  },
  {
    id: 'demo-tomas',
    fullName: 'Tomás Rivera',
    age: 33,
    city: 'Manchester',
    bio: 'Runs a tiny record label. Owns more vinyl than furniture.',
    interests: ['Live Music', 'Podcasts', 'Cycling', 'Coffee'],
    topics: ['Records nobody else has heard', 'How songs get stuck in your head', 'Cycling at 6am'],
    promptQ: 'Currently learning',
    promptA: 'How to mix a record properly instead of guessing.',
    seed: 'tomas',
  },
  {
    id: 'demo-chiara',
    fullName: 'Chiara Bellini',
    age: 27,
    city: 'Bristol',
    bio: 'Marine biologist. I will absolutely show you photos of octopuses unprompted.',
    interests: ['Hiking', 'Reading', 'Photography', 'Travel', 'Volunteering'],
    topics: ['The ethics of AI', 'Things under the sea that seem fictional', 'Why we protect what we can see'],
    promptQ: 'I go crazy for',
    promptA: 'Rock pools. Genuinely. I could spend a whole afternoon in one.',
    seed: 'chiara',
  },
  {
    id: 'demo-idris',
    fullName: 'Idris Bello',
    age: 31,
    city: 'Lagos',
    bio: 'Data engineer. Building a football analytics side project nobody asked for.',
    interests: ['Football', 'Tech / AI', 'Fitness', 'Gaming'],
    topics: ['Football tactics that actually matter', 'Machine learning in plain English', 'Lagos traffic as a design problem'],
    promptQ: 'My ideal Sunday',
    promptA: 'Five-a-side at 9, then absolutely nothing until Monday.',
    seed: 'idris',
  },
  {
    id: 'demo-nora',
    fullName: 'Nora Haddad',
    age: 30,
    city: 'Birmingham',
    bio: 'Bookseller. I will recommend you something you did not ask for.',
    interests: ['Reading', 'Writing', 'Bible Study', 'Worship', 'Coffee'],
    topics: ['Books that changed how I think', 'Faith and doubt together', 'Why endings matter more than beginnings'],
    promptQ: 'A movie that changed how I think',
    promptA: 'Arrival. I have not stopped thinking about how it treats time.',
    seed: 'nora',
  },
];

const CONVERSATIONS = [
  {
    person: 'demo-layla',
    kind: 'dm',
    messages: [
      ['them', 'Okay, your prompt answer about jollof has me invested. Where do you stand on the rice question?'],
      ['me', 'Firmly jollof, no notes. Though I will say the fried rice at my auntie place is genuinely a problem.'],
      ['them', 'That is the diplomatic answer. I respect it.'],
      ['them', 'Did you always want to do what you do now?'],
      ['me', 'Not remotely. It took me about four years and one very bad job to work it out.'],
      ['them', 'What was the bad job?'],
      ['me', 'Cold calling. I lasted eleven weeks and learned nothing except how to sound cheerful while being told to go away.'],
    ],
    opener: 'We both list cooking — what is the one dish you make when you want to impress someone?',
  },
  {
    person: 'demo-tomas',
    kind: 'friend',
    messages: [
      ['them', 'Right, I need a second opinion. Best album of the last five years, and you cannot say a greatest hits.'],
      ['me', 'That is a trap and I am walking into it. Give me a minute.'],
      ['them', 'No minute. Answer.'],
      ['me', 'Fine. Something quieter than I would normally pick. I am not naming it until you go first.'],
      ['them', 'Coward.'],
      ['me', 'Correct. But a coward with taste.'],
    ],
  },
  {
    person: 'demo-chiara',
    kind: 'dm',
    messages: [
      ['them', 'I saw you like hiking. Have you done the coastal path?'],
      ['me', 'Parts of it. I keep meaning to do the whole thing and keep not doing it.'],
      ['them', 'Same. I have planned it three times and cancelled twice.'],
      ['them', 'What is the best thing you have seen on a walk?'],
      ['me', 'A seal just watching me from about ten metres out. Sat there for maybe five minutes.'],
    ],
  },
];

const POSTS = [
  ['demo-chiara', 'Spent two hours in a rock pool today and found four species I could not name. Best afternoon in weeks.'],
  ['demo-idris', 'Built a model that predicts throw-ins. It is 61% accurate. I am choosing to be proud of this.'],
  ['demo-nora', 'Someone bought the book I recommended last month and came back to argue about the ending. This is the whole job, honestly.'],
  ['demo-tomas', 'Pressed the last of a run today. 200 copies, all gone to people who actually wanted them. Better than a chart position.'],
];

// --------------------------------------------------------------------- main --

function parseArgs(argv) {
  return {
    email: argv.find((a) => a.startsWith('--email='))?.slice(8) ?? null,
    uid: argv.find((a) => a.startsWith('--uid='))?.slice(6) ?? null,
    fresh: argv.includes('--fresh'),
    probe: argv.includes('--probe'),
  };
}

/**
 * Transport check.
 *
 * Points at the same endpoints the seeding itself uses, so a failure here is
 * unambiguously a connectivity/permissions problem rather than a bad document.
 * Emulator REST behaviour varies between versions, and "400 Payload isn't
 * valid" is reported for both a malformed body and a route the build does not
 * implement — this tells the two apart.
 */
async function probe() {
  const show = async (label, res) => {
    const text = await res.text();
    console.log(
      `${label}: ${res.status} ${text.slice(0, 240).replace(/\s+/g, ' ')}`,
    );
  };

  await show(
    'GET  documents root',
    await fetch(FS, { headers: { Authorization: 'Bearer owner' } }),
  );

  const body = { fields: { a: { stringValue: 'x' } } };

  // Paths must be `collection/document`. A bare root path is rejected with
  // 'Document name ... lacks "/"', which looks like a body error but is not.
  await show(
    'PATCH minimal body',
    await fetch(`${FS}/probe_min/one`, {
      method: 'PATCH',
      headers: {
        Authorization: 'Bearer owner',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    }),
  );

  await show(
    'GET  that document back',
    await fetch(`${FS}/probe_min/one`, {
      headers: { Authorization: 'Bearer owner' },
    }),
  );

  await show(
    'PATCH empty array',
    await fetch(`${FS}/probe_min/two`, {
      method: 'PATCH',
      headers: {
        Authorization: 'Bearer owner',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields: { a: arr([]) } }),
    }),
  );
}

/**
 * Finds the account to seed for.
 *
 * The signed-in uid is not knowable ahead of time: with the Auth emulator's
 * Google popup, an account is created the first time someone signs in. So we
 * ask the emulator's admin API for its accounts and take the most recent
 * non-demo user, which is whoever just logged in.
 *
 * Note the verb: the Identity Toolkit admin API lists users via
 * `accounts:batchGet` (a POST). A plain `GET /accounts` returns 405.
 *
 * Some Auth emulator builds do not implement that route at all, and answer 405
 * regardless of verb. Where that happens, pass `--uid=` instead: the signed-in
 * uid is visible in the browser by opening DevTools and running
 * `indexedDB.open('firebaseLocalStorageDb')`, or in the app's splash
 * diagnostics. Guessing is not an option — the uid is a random string.
 */
async function findTargetUser({ email, uid }) {
  // Explicit uid wins: some emulator builds cannot enumerate accounts at all.
  if (uid) return { localId: uid, email: null };

  const res = await fetch(`${AUTH}/accounts:batchGet?maxResults=1000`, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer owner',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({}),
  });

  if (!res.ok) {
    throw new Error(
      `Could not list Auth users (${res.status} ${res.statusText}). ` +
        'Is the Auth emulator running? If it is, this build may not support ' +
        'the admin account list — re-run with --uid=<signed-in uid>.',
    );
  }

  const users = (await res.json()).users ?? [];
  const real = users.filter((u) => !String(u.localId).startsWith('demo-'));

  if (real.length === 0) {
    throw new Error(
      'No signed-in account found. Open the app and sign in first, then run ' +
        'this again.',
    );
  }

  if (email) {
    const match = real.find(
      (u) => String(u.email).toLowerCase() === email.toLowerCase(),
    );
    if (!match) {
      throw new Error(
        `No account with email ${email}. Signed-in accounts: ` +
          real.map((u) => u.email).join(', '),
      );
    }
    return match;
  }

  return real[real.length - 1];
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.probe) {
    console.log(`Probing ${PROJECT} via ${HOST}…\n`);
    await probe();
    return;
  }

  console.log(`Seeding ${PROJECT} via ${HOST}…\n`);

  const target = await findTargetUser(args);
  const uid = target.localId;
  console.log(`Target account: ${target.email ?? '(no email)'}`);
  console.log(`  uid: ${uid}\n`);

  if (args.fresh) {
    console.log('Clearing previous demo data…');
    for (const person of DEMO_PEOPLE) {
      await deleteDoc(`users/${person.id}`);
      await deleteDoc(`connections/${[uid, person.id].sort().join('__')}`);
    }
  }

  // --- the signed-in user's own profile -----------------------------------
  //
  // `onboarded: true` and a premium tier are what let the journey skip the
  // four-step wizard and reach the coach in one step. This is a demo seed, not
  // a shortcut in the product: a real account gets neither.
  const now = Date.now();

  await setDoc(`users/${uid}`, {
    // Note the `s(...)` wrappers. The REST API needs explicitly typed values —
    // a bare JS string is rejected with a 400 "Payload isn't valid".
    fullName: s(target.displayName ?? 'You'),
    handle: s('you'),
    fullNameLower: s(String(target.displayName ?? 'you').toLowerCase()),
    age: i(30),
    onboarded: b(true),
    verificationTier: s('premium'),
    bio: s('Seeded demo account. Everything here is fake and local.'),
    interests: arrStr(['Coffee', 'Reading', 'Tech / AI']),
    conversationTopics: arrStr(['Things I changed my mind about']),
    photos: arrStr([
      `https://api.dicebear.com/7.x/notionists/svg?seed=${uid}&backgroundColor=f1e9df`,
    ]),
    avatarUrl: s(
      `https://api.dicebear.com/7.x/notionists/svg?seed=${uid}&backgroundColor=f1e9df`,
    ),
    lookingFor: arrStr(['everyone']),
    minAge: i(18),
    maxAge: i(99),
    maxDistanceKm: i(200),
    online: b(true),
    notifyMatches: b(true),
    notifyMessages: b(true),
    notifySuggestions: b(true),
    showDistance: b(true),
    showOnline: b(true),
    blockedUserIds: arr([]),
    postCount: i(0),
    connectionCount: i(CONVERSATIONS.length),
    friendCount: i(1),
    location: geo(51.5074, -0.1278),
    lastSeenAt: ts(now),
    createdAt: ts(now - 30 * 86400000),
    updatedAt: ts(now),
  });

  // Private account doc: quota and subscription.
  //
  // The rules make this read-only to the client, so seeding it here (with owner
  // privileges) is the only way a demo account can start with credits.
  await setDoc(`users/${uid}/private/account`, {
    tier: s('premium'),
    suggestionQuota: map({
      date: s(new Date().toISOString().slice(0, 10)),
      usedToday: i(2),
      dailyLimit: i(20),
      tier: s('premium'),
      smarterAi: b(true),
      isUnlimited: b(false),
    }),
    dmUsage: map({
      month: s(new Date().toISOString().slice(0, 7)),
      count: i(2),
      limit: i(5),
    }),
    subscription: map({
      planKey: s('premium'),
      status: s('active'),
      currentPeriodEnd: ts(now + 30 * 86400000),
    }),
    pushTokens: arr([]),
    updatedAt: ts(now),
  });

  // --- the other people ----------------------------------------------------
  for (const person of DEMO_PEOPLE) {
    const avatar = `https://api.dicebear.com/7.x/notionists/svg?seed=${person.seed}&backgroundColor=f1e9df,f3d9a8,dce9dd`;
    await setDoc(`users/${person.id}`, {
      fullName: s(person.fullName),
      handle: s(person.id.replace('demo-', '')),
      // Chiara is the simulated partner: anything sent in her thread gets an AI
      // reply written as her, which is how the conversation mechanic is
      // exercised without a second person. This flag is exactly what the
      // simulatePartnerReply callable checks, so a real account can never be
      // impersonated - the server simply returns without writing.
      isSimulated: b(person.id === 'demo-chiara'),
      fullNameLower: s(person.fullName.toLowerCase()),
      age: i(person.age),
      onboarded: b(true),
      verificationTier: s(person.id === 'demo-layla' ? 'premium' : 'verified'),
      bio: s(person.bio),
      city: s(person.city),
      interests: arrStr(person.interests),
      conversationTopics: arrStr(person.topics),
      promptQuestion: s(person.promptQ),
      promptAnswer: s(person.promptA),
      photos: arrStr([avatar]),
      avatarUrl: s(avatar),
      lookingFor: arrStr(['everyone']),
      minAge: i(18),
      maxAge: i(99),
      maxDistanceKm: i(200),
      online: b(person.id !== 'demo-nora'),
      notifyMatches: b(true),
      notifyMessages: b(true),
      notifySuggestions: b(true),
      showDistance: b(true),
      showOnline: b(true),
      blockedUserIds: arr([]),
      postCount: i(1),
      connectionCount: i(3),
      friendCount: i(2),
      location: geo(51.5 + Math.random() * 0.4, -0.12 + Math.random() * 0.4),
      lastSeenAt: ts(now),
      createdAt: ts(now - 40 * 86400000),
      updatedAt: ts(now),
    });
  }

  console.log(`Created ${DEMO_PEOPLE.length} demo profiles.`);

  // --- connections, messages, coach cards, meetings ------------------------
  let messageCount = 0;

  for (const convo of CONVERSATIONS) {
    const person = DEMO_PEOPLE.find((p) => p.id === convo.person);
    const connectionId = [uid, person.id].sort().join('__');
    const startedAt = now - (CONVERSATIONS.indexOf(convo) + 1) * 3600000;

    const summarize = (p, id) => ({
      fullName: s(p ? p.fullName : 'You'),
      handle: s(p ? p.id.replace('demo-', '') : 'you'),
      avatarUrl: s(
        p
          ? `https://api.dicebear.com/7.x/notionists/svg?seed=${p.seed}&backgroundColor=f1e9df,f3d9a8,dce9dd`
          : `https://api.dicebear.com/7.x/notionists/svg?seed=${uid}&backgroundColor=f1e9df`,
      ),
      verificationTier: s(p ? 'verified' : 'premium'),
    });

    const lastIndex = convo.messages.length - 1;
    const lastAt = startedAt + lastIndex * 300000;

    await setDoc(`connections/${connectionId}`, {
      members: arrStr([uid, person.id].sort()),
      memberSummaries: map({
        [uid]: map(summarize(null, uid)),
        [person.id]: map(summarize(person, person.id)),
      }),
      kind: s(convo.kind),
      aiEnabled: b(true),
      lastMessage: s(convo.messages[lastIndex][1]),
      lastMessageAt: ts(lastAt),
      lastMessageSenderId: s(
        convo.messages[lastIndex][0] === 'me' ? uid : person.id,
      ),
      unread: map({ [uid]: i(convo === CONVERSATIONS[0] ? 2 : 0), [person.id]: i(0) }),
      muted: b(false),
      createdFrom: s('seed'),
      createdAt: ts(startedAt),
    });

    // Mutual coach consent, so the AI zone is live rather than showing the
    // opt-in prompt.
    for (const memberId of [uid, person.id]) {
      await setDoc(`connections/${connectionId}/optIns/${memberId}`, {
        userId: s(memberId),
        optedIn: b(true),
        updatedAt: ts(now),
      });
    }

    for (let index = 0; index < convo.messages.length; index++) {
      const [who, body] = convo.messages[index];
      const senderId = who === 'me' ? uid : person.id;
      await setDoc(
        `connections/${connectionId}/messages/msg-${String(index).padStart(2, '0')}`,
        {
          senderId: s(senderId),
          body: s(body),
          readBy: arrStr([senderId]),
          sentFromSuggestion: b(false),
          createdAt: ts(startedAt + index * 300000),
        },
      );
      messageCount++;
    }

    // A shared opener on the newest thread: the app's signature card.
    if (convo.opener) {
      await setDoc(`connections/${connectionId}/suggestions/sug-opener`, {
        content: s(convo.opener),
        reason: s('You just matched, so here is something to open with.'),
        status: s('active'),
        suggestionType: s('opener'),
        visibility: s('shared'),
        triggeredBy: s('match_created'),
        requestedBy: nul(),
        basedOn: arrStr(['profile', 'shared_interests']),
        createdAt: ts(now - 1800000),
      });
    }

    // A PRIVATE reciprocity nudge aimed at the signed-in user.
    //
    // This is the product's differentiator and the reason the security rules
    // exist: the other person must never be able to read this document. Seeding
    // it lets the private treatment be seen without waiting for the message
    // trigger to fire.
    if (convo.person === 'demo-chiara') {
      await setDoc(`connections/${connectionId}/suggestions/sug-nudge`, {
        content: s(
          'Ask her the same question back — she has been carrying the thread for a while.',
        ),
        reason: s('You answered without asking anything back.'),
        status: s('active'),
        suggestionType: s('reciprocity_nudge'),
        visibility: s('private'),
        targetUserId: s(uid),
        triggeredBy: s('one_sided_answer'),
        requestedBy: nul(),
        basedOn: arrStr(['recent_messages']),
        createdAt: ts(now - 600000),
      });
    }
  }

  console.log(`Created ${CONVERSATIONS.length} connections, ${messageCount} messages, 2 coach cards.`);

  // --- meetings ------------------------------------------------------------
  const laylaConnection = [uid, 'demo-layla'].sort().join('__');

  await setDoc('meetings/seed-meeting-1', {
    connectionId: s(laylaConnection),
    members: arrStr([uid, 'demo-layla'].sort()),
    proposedBy: s('demo-layla'),
    scheduledAt: ts(now + 2 * 86400000 + 18.5 * 3600000),
    note: s('Coffee somewhere near the river? I know a place that does not rush you.'),
    status: s('proposed'),
    otherUserId: s('demo-layla'),
    otherUser: map({
      fullName: s('Layla Adeyemi'),
      handle: s('layla'),
      avatarUrl: s('https://api.dicebear.com/7.x/notionists/svg?seed=layla&backgroundColor=f1e9df,f3d9a8,dce9dd'),
      verificationTier: s('verified'),
    }),
    createdAt: ts(now - 3600000),
  });

  await setDoc('meetings/seed-meeting-2', {
    connectionId: s([uid, 'demo-tomas'].sort().join('__')),
    members: arrStr([uid, 'demo-tomas'].sort()),
    proposedBy: s(uid),
    scheduledAt: ts(now + 5 * 86400000 + 19 * 3600000),
    note: s('That record shop you mentioned. Bring the album.'),
    status: s('accepted'),
    otherUserId: s('demo-tomas'),
    otherUser: map({
      fullName: s('Tomás Rivera'),
      handle: s('tomas'),
      avatarUrl: s('https://api.dicebear.com/7.x/notionists/svg?seed=tomas&backgroundColor=f1e9df,f3d9a8,dce9dd'),
      verificationTier: s('verified'),
    }),
    createdAt: ts(now - 4 * 3600000),
  });

  // --- posts ---------------------------------------------------------------
  for (let index = 0; index < POSTS.length; index++) {
    const [personId, body] = POSTS[index];
    const person = DEMO_PEOPLE.find((p) => p.id === personId);
    await setDoc(`posts/seed-post-${index}`, {
      authorId: s(personId),
      author: map({
        fullName: s(person.fullName),
        handle: s(personId.replace('demo-', '')),
        avatarUrl: s(`https://api.dicebear.com/7.x/notionists/svg?seed=${person.seed}&backgroundColor=f1e9df,f3d9a8,dce9dd`),
        verificationTier: s('verified'),
      }),
      body: s(body),
      imageUrls: arr([]),
      audience: s('everyone'),
      tags: arr([]),
      likeCount: i(Math.floor(Math.random() * 40) + 3),
      commentCount: i(Math.floor(Math.random() * 8)),
      createdAt: ts(now - (index + 1) * 5400000),
    });
  }

  console.log('Created 2 meetings and 4 posts.\n');

  console.log('Done. Open the app and sign in — Discover, Home, Chats and the');
  console.log('chat with the AI coach are all populated for this account.');
  console.log(`\nIf the app was already open, hard-refresh the page.`);
}

main().catch((error) => {
  console.error(`\nSeeding failed: ${error.message}`);
  process.exit(1);
});
