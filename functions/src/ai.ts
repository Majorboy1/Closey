import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { db, Col, Quota } from './config';

/**
 * The AI conversation coach.
 *
 * DeepSeek is called **only** from here. The key lives in a Firebase secret, so
 * it never reaches a client — the same guarantee the Supabase edge functions
 * provided, and the reason `analyze-conversation` existed server-side.
 */

export const deepseekKey = defineSecret('DEEPSEEK_API_KEY');

const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';

/** Free tier uses the cheaper model; Premium gets the reasoner. */
const MODEL_CHEAP = 'deepseek-chat';
const MODEL_SMART = 'deepseek-reasoner';

export type SuggestionType =
  | 'opener'
  | 'reciprocity_nudge'
  | 'topic_continuation'
  | 'new_topic'
  | 'deepening_question'
  | 'icebreaker_game';

export type TriggerKind =
  | 'match_created'
  | 'one_sided_answer'
  | 'silence_timeout'
  | 'user_requested'
  | 'deepening';

export interface CoachContext {
  myName: string;
  theirName: string;
  myBio?: string;
  theirBio?: string;
  myInterests: string[];
  theirInterests: string[];
  myTopics: string[];
  theirTopics: string[];
  myPrompt?: string;
  theirPrompt?: string;
  transcript: { who: 'me' | 'them'; text: string }[];
}

export interface CoachOutput {
  content: string;
  reason: string;
  type: SuggestionType;
  visibility: 'shared' | 'private';
  targetUserId?: string;
}

/**
 * System prompt.
 *
 * Three constraints are load-bearing and come straight from the spec:
 *
 *  - It must output something the USER could say, not advice *about* the user.
 *    "Ask them what they studied too" is right; "You should be more curious" is
 *    wrong.
 *  - It must never pretend to be the other person. The coach offers, the human
 *    sends.
 *  - It must build on things already said in the thread rather than jumping to
 *    a random topic, which is what makes it feel like it is paying attention.
 */
const SYSTEM_PROMPT = `You are the conversation coach inside Closey, a dating app.

Your job is to keep a real conversation between two people moving and gradually
deepening, the way a thoughtful mutual friend would nudge two people along on a
first date.

RULES YOU MUST FOLLOW:
1. Output ONE suggestion, written as the actual words the user could send.
   Never output advice about the user, and never describe what you are doing.
2. Never write as if you were the other person. You suggest; they send.
3. Build on what has already been said. Do not jump to an unrelated topic.
4. Aim for warm, specific and genuinely curious. No generic small talk, no
   "How was your day?", no emoji spam, no corporate tone.
5. Keep it under 30 words. Shorter is better.
6. Prefer moving small talk toward something real over time.

Return STRICT JSON only, no markdown fences:
{"content": "...", "reason": "...", "visibility": "shared" | "private"}

"reason" is a short sentence shown to the user explaining why this appeared.
It must describe the conversational situation, not flatter the user.`;

/** Builds the human-readable context block sent alongside the system prompt. */
function buildContext(c: CoachContext): string {
  const shared = c.myInterests.filter((i) => c.theirInterests.includes(i));

  const transcript =
    c.transcript.length === 0
      ? '(no messages yet — this conversation has just started)'
      : c.transcript
          .map((t) => `${t.who === 'me' ? c.myName : c.theirName}: ${t.text}`)
          .join('\n');

  return [
    '--- PROFILES ---',
    `${c.myName}: ${c.myBio ?? '(no bio)'}`,
    `  interests: ${c.myInterests.join(', ') || '(none)'}`,
    `  loves talking about: ${c.myTopics.join(', ') || '(none)'}`,
    `  prompt answer: ${c.myPrompt ?? '(none)'}`,
    `${c.theirName}: ${c.theirBio ?? '(no bio)'}`,
    `  interests: ${c.theirInterests.join(', ') || '(none)'}`,
    `  loves talking about: ${c.theirTopics.join(', ') || '(none)'}`,
    `  prompt answer: ${c.theirPrompt ?? '(none)'}`,
    '',
    `SHARED INTERESTS: ${shared.join(', ') || '(none yet)'}`,
    '',
    '--- RECENT CONVERSATION (oldest first) ---',
    transcript,
    '',
    '--- TASK ---',
    `The user is ${c.myName}. They are addressed as "me". Write the suggestion in the first person, as something ${c.myName} could send.`,
  ].join('\n');
}

/** Type-specific instruction appended to the task block. */
function typeInstruction(type: SuggestionType, trigger: TriggerKind): string {
  switch (type) {
    case 'opener':
      return 'This is the very first message between them. Use the shared interests or the most distinctive thing in their profile.';
    case 'reciprocity_nudge':
      return (
        'The other person asked a question and the user answered without asking anything back. ' +
        'Set visibility to "private". Give the user the question to ask back, phrased so that when they send it, it will look perfectly natural.'
      );
    case 'topic_continuation':
      return 'The thread has gone quiet. Re-open something specific that was mentioned earlier.';
    case 'new_topic':
      return 'The thread has gone quiet and everything so far has been covered. Introduce a fresh topic from their shared interests.';
    case 'deepening_question':
      return 'This thread has stayed surface-level for a while. Ask something more personal but still easy to answer, and not intrusive.';
    case 'icebreaker_game':
      return 'Offer a small playful game or prompt they can play together.';
  }
  return trigger === 'one_sided_answer'
    ? 'Focus on restoring balance to the exchange.'
    : 'Keep the conversation moving.';
}

/**
 * Calls DeepSeek and parses the JSON response.
 *
 * Falls back to a locally-composed suggestion if the model returns something
 * unparseable or the API errors, so the user never sees a dead end — and so the
 * product still behaves sensibly if the key is missing in a dev environment.
 */
export async function generateSuggestion(args: {
  context: CoachContext;
  type: SuggestionType;
  trigger: TriggerKind;
  smarterAi: boolean;
  targetUserId?: string;
}): Promise<CoachOutput> {
  const { context, type, trigger, smarterAi, targetUserId } = args;

  const wantsPrivate = type === 'reciprocity_nudge';

  const body = {
    model: smarterAi ? MODEL_SMART : MODEL_CHEAP,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      {
        role: 'user',
        content: `${buildContext(context)}\n\n${typeInstruction(type, trigger)}`,
      },
    ],
    temperature: 0.85,
    max_tokens: 220,
    response_format: { type: 'json_object' as const },
  };

  // Two guards, and both were missing. `deepseekKey.value()` returns an empty
  // string rather than throwing when the emulator cannot reach Secret Manager,
  // and `fetch` has no default timeout. Together that meant a real request to
  // DeepSeek carrying a blank bearer token, followed by an indefinite wait for a
  // reply that never arrived.
  //
  // The symptom was the worst possible one: the client sat on "Reading the
  // conversation..." forever, because a promise that never settles never
  // rejects either - so `fallback()` below was unreachable, and a missing
  // developer key looked like a broken feature rather than a missing key.
  let apiKey = '';
  try {
    apiKey = deepseekKey.value() ?? '';
  } catch {
    apiKey = '';
  }

  if (!apiKey.trim()) {
    logger.warn('DEEPSEEK_API_KEY is not set; composing locally instead.');
    return fallback(context, type, trigger, targetUserId);
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 9000);

  try {
    const response = await fetch(DEEPSEEK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    if (!response.ok) {
      logger.warn('DeepSeek returned an error', {
        status: response.status,
        body: await response.text().catch(() => ''),
      });
      return fallback(context, type, trigger, targetUserId);
    }

    const json = (await response.json()) as {
      choices?: { message?: { content?: string } }[];
    };
    const raw = json.choices?.[0]?.message?.content?.trim();
    if (!raw) return fallback(context, type, trigger, targetUserId);

    const parsed = JSON.parse(raw) as Partial<CoachOutput>;

    return {
      content: (parsed.content ?? '').trim() || fallback(context, type, trigger, targetUserId).content,
      reason: (parsed.reason ?? '').trim() || 'A prompt to keep things moving.',
      type,
      // The model is allowed to choose private, but only for a nudge — and we
      // force `private` for nudges regardless of what it returns, because a
      // public nudge would expose the user.
      visibility: wantsPrivate ? 'private' : (parsed.visibility === 'private' ? 'private' : 'shared'),
      targetUserId: wantsPrivate ? targetUserId : undefined,
    };
  } catch (error) {
    logger.error('Coach generation failed', error);
    return fallback(context, type, trigger, targetUserId);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * A reply written **as the other person**, for the simulated partner.
 *
 * This deliberately violates the coach's first rule - the coach must never
 * speak as anyone - so it keeps its own prompt and its own function, and the
 * callable that exposes it refuses to run unless the other member is flagged
 * `isSimulated`. A real account can never be impersonated, which is the only
 * reason this is safe to have in the codebase at all.
 *
 * It exists so the conversation mechanic can be exercised end to end without a
 * second person, including the coach's own cards, which need a real thread to
 * read.
 */
export async function generatePartnerReply(context: CoachContext): Promise<string> {
  const transcript =
    context.transcript.length === 0
      ? '(no messages yet)'
      : context.transcript
          .map((t) => `${t.who === 'me' ? context.myName : context.theirName}: ${t.text}`)
          .join('\n');

  const prompt = `You are ${context.theirName}, a person on a dating app, chatting with ${context.myName}.

Your profile:
  bio: ${context.theirBio ?? '(none)'}
  interests: ${context.theirInterests.join(', ') || '(none)'}
  loves talking about: ${context.theirTopics.join(', ') || '(none)'}
  prompt answer: ${context.theirPrompt ?? '(none)'}

Their profile:
  bio: ${context.myBio ?? '(none)'}
  interests: ${context.myInterests.join(', ') || '(none)'}
  loves talking about: ${context.myTopics.join(', ') || '(none)'}

Conversation so far:
${transcript}

Write your next message as ${context.theirName}, replying to their last message.

RULES:
1. Sound like a real person texting, not an assistant. No customer-service tone.
2. One to three sentences. Do not write an essay.
3. Refer to something specific that was actually said, or to a shared interest.
4. Ask something back sometimes, but not every single time - that reads as an interview.
5. Never mention being an AI, a model, a simulation or a test.
6. No emoji spam. At most one.

Return STRICT JSON only, no markdown fences: {"message": "..."}`;

  let apiKey = '';
  try {
    apiKey = deepseekKey.value() ?? '';
  } catch {
    apiKey = '';
  }

  if (!apiKey.trim()) return fallbackReply(context);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 9000);

  try {
    const response = await fetch(DEEPSEEK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL_CHEAP,
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.95,
        max_tokens: 160,
        response_format: { type: 'json_object' as const },
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      logger.warn('Partner reply failed', { status: response.status });
      return fallbackReply(context);
    }

    const json = (await response.json()) as {
      choices?: { message?: { content?: string } }[];
    };
    const raw = json.choices?.[0]?.message?.content?.trim();
    if (!raw) return fallbackReply(context);

    const parsed = JSON.parse(raw) as { message?: string };
    return (parsed.message ?? '').trim() || fallbackReply(context);
  } catch (error) {
    logger.error('Partner reply failed', error);
    return fallbackReply(context);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Local reply, used when no key is configured.
 *
 * Deliberately bland rather than pretending to be clever: a canned reply that
 * reads as obviously scripted is a far better signal that the model is not
 * wired up than a plausible one that hides it.
 */
function fallbackReply(context: CoachContext): string {
  const shared = context.myInterests.filter((i) =>
    context.theirInterests.includes(i),
  );
  const hook = shared[0] ?? context.theirInterests[0] ?? 'that';

  const myLast = [...context.transcript].reverse().find((t) => t.who === 'me');
  if (!myLast) {
    return `Hey. Your profile made me smile - ${hook}, right? What got you into it?`;
  }

  return (
    `That is a good point about ${hook}. ` +
    'I have not thought about it that way before - what made you land on it?'
  );
}

/**
 * Deterministic fallback. Composed from the shared-interest overlap so it is
 * still specific to the pair rather than a canned line.
 */
function fallback(
  context: CoachContext,
  type: SuggestionType,
  trigger: TriggerKind,
  targetUserId?: string,
): CoachOutput {
  const shared = context.myInterests.filter((i) =>
    context.theirInterests.includes(i),
  );
  const topic = shared[0] ?? context.theirInterests[0];

  const content = (() => {
    switch (type) {
      case 'opener':
        return topic
          ? `We matched on ${topic} — what got you into it?`
          : `What is something you could talk about for an hour with no preparation?`;
      case 'reciprocity_nudge':
        return `Ask them the same question back — it keeps things even.`;
      case 'topic_continuation':
        return `Let's go back to something you mentioned earlier — what is the story behind it?`;
      case 'new_topic':
        return topic
          ? `Neither of us has brought up ${topic} yet. What is your take on it?`
          : `What is something you have changed your mind about this year?`;
      case 'deepening_question':
        return `What is something you are working on that nobody would guess from your profile?`;
      case 'icebreaker_game':
        return `Two truths and a lie — you go first.`;
    }
  })();

  return {
    content,
    reason: trigger === 'match_created'
      ? 'You just matched, so here is something to open with.'
      : 'A prompt to keep the conversation moving.',
    type,
    visibility: type === 'reciprocity_nudge' ? 'private' : 'shared',
    targetUserId: type === 'reciprocity_nudge' ? targetUserId : undefined,
  };
}

// ---------------------------------------------------------------------------
// Conversation analysis
// ---------------------------------------------------------------------------

export interface AnalysisResult {
  trigger: TriggerKind;
  type: SuggestionType;
  /** The user who should be nudged, for a private reciprocity nudge. */
  targetUserId?: string;
}

/**
 * Decides whether the coach should speak, and why.
 *
 * This is the heart of the differentiator, and the port of
 * `analyze-conversation`. Four detectors, in priority order:
 *
 *  1. **Reciprocity gap** (private) — one person asked a question, the other
 *     answered it and did not ask anything back. This is the "civil
 *     engineering" case from the spec.
 *  2. **Stall** (shared) — nothing said for a while.
 *  3. **Deepening** (shared) — many turns, still surface level.
 *  4. Nothing.
 *
 * Deliberately rule-based rather than model-based: it runs on every message, so
 * it must be cheap, deterministic and explainable.
 */
export function analyzeConversation(
  messages: { senderId: string; body: string; createdAt: Date }[],
  members: string[],
): AnalysisResult | null {
  if (messages.length === 0) {
    return { trigger: 'match_created', type: 'opener' };
  }

  const recipient = members[0];
  const last = messages[messages.length - 1];
  const previous = messages[messages.length - 2];

  // ---- 1. Reciprocity gap ------------------------------------------------
  if (previous && previous.senderId !== last.senderId) {
    const askedQuestion = previous.body.includes('?');
    const answered = last.body.trim().length <= 160;
    const askedBack = last.body.includes('?');

    if (askedQuestion && answered && !askedBack) {
      return {
        trigger: 'one_sided_answer',
        type: 'reciprocity_nudge',
        // Nudge the person who answered without reciprocating.
        targetUserId: last.senderId === recipient ? recipient : last.senderId,
      };
    }
  }

  // ---- 2. Stall ----------------------------------------------------------
  const silentMinutes =
    (Date.now() - last.createdAt.getTime()) / (1000 * 60 * 60);
  if (silentMinutes >= Quota.stallHours) {
    const hasEarlierContent = messages.length >= 3;
    return {
      trigger: 'silence_timeout',
      type: hasEarlierContent ? 'topic_continuation' : 'new_topic',
    };
  }

  // ---- 3. Deepening ------------------------------------------------------
  // Many turns, still short-form. Deliberately high thresholds so this fires
  // rarely — an over-eager coach is worse than a quiet one.
  if (messages.length >= 12) {
    const recent = messages.slice(-10);
    const averageLength =
      recent.reduce((total, m) => total + m.body.length, 0) / recent.length;
    const askedSomethingReal = recent.filter((m) => m.body.includes('?')).length;

    if (averageLength < 60 && askedSomethingReal <= 3) {
      return { trigger: 'deepening', type: 'deepening_question' };
    }
  }

  return null;
}

/** Loads the profile fields the coach actually uses. */
export async function loadCoachContext(
  connectionId: string,
  meId: string,
  themId: string,
): Promise<CoachContext> {
  const [meSnap, themSnap, messagesSnap] = await Promise.all([
    db.collection(Col.users).doc(meId).get(),
    db.collection(Col.users).doc(themId).get(),
    db
      .collection(Col.connections)
      .doc(connectionId)
      .collection(Col.messages)
      .orderBy('createdAt', 'desc')
      .limit(Quota.contextWindow)
      .get(),
  ]);

  const me = meSnap.data() ?? {};
  const them = themSnap.data() ?? {};

  // Reverse because the query was descending — the model reads chronologically.
  const transcript = messagesSnap.docs.reverse().map((doc) => {
    const data = doc.data();
    return {
      who: (data.senderId === meId ? 'me' : 'them') as 'me' | 'them',
      text: String(data.body ?? ''),
    };
  });

  return {
    myName: String(me.fullName ?? 'You'),
    theirName: String(them.fullName ?? 'Them'),
    myBio: me.bio,
    theirBio: them.bio,
    myInterests: me.interests ?? [],
    theirInterests: them.interests ?? [],
    myTopics: me.conversationTopics ?? [],
    theirTopics: them.conversationTopics ?? [],
    myPrompt: me.promptAnswer,
    theirPrompt: them.promptAnswer,
    transcript,
  };
}
