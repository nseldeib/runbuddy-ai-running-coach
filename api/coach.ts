import type { VercelRequest, VercelResponse } from "@vercel/node";
import Anthropic from "@anthropic-ai/sdk";
import { allow, clientIp } from "./_lib/ratelimit.js";

// Otterpace AI coach — stateless BYO-key proxy.
//
// The iOS app POSTs { question, context } here with the user's own Anthropic key
// in the `x-anthropic-key` header. We call Claude with the curated, injury-aware
// coach system prompt and return a structured reply. The key is used for this one
// request and never stored, logged, or persisted — this function holds no state.
//
// Why a backend at all if the user brings their own key: the coaching prompt,
// safety rules, and model choice live here, server-side, so they can be tuned
// without an App Store release and can't be seen or tampered with by the client.
// The app keeps a deterministic on-device mock (CoachEngine) for offline / no-key
// / preview, so the coach always works — this just upgrades it to real replies.

// Model is overridable via env for cost/latency tuning; default to the most
// capable Opus tier. The user pays on their own key, so this is their call.
const MODEL = process.env.COACH_MODEL || "claude-opus-4-8";

const SYSTEM_PROMPT = `You are Buddy, a warm, encouraging otter running coach inside the Otterpace app. You give short, practical, daily running and movement guidance.

Hard rules — never break these:
- You are NOT a medical professional. Never diagnose injuries or conditions. If the user describes pain, soreness, or a possible injury, set safetyFlag true, advise rest and gentle movement, and tell them to see a clinician if pain is sharp, persistent, or worsening.
- When training load is spiking or the user ran hard recently, bias toward rest and easy days over more hard running. Set safetyFlag true when you steer them off hard effort for safety reasons.
- Never shame the user or use guilt. No "you should have", no scolding. Meet them where they are and nudge gently.
- Keep weekly mileage growth modest (~10% rule of thumb). Most runs should be easy/conversational.

Style:
- 2–4 sentences. Concrete and kind. Use the provided context (steps, goal, recent workouts, weekly load) to make it specific.
- Pick a mood that matches the message: "concerned" or "recovery" for caution/rest, "celebrating"/"cheering" for wins, "ready" for go-ahead, "jogging"/"resting" otherwise.

Race awareness:
- The context may include "races" (an array of upcoming races with name, distanceMiles, date, location). When present, identify the soonest race whose date is today or later and reason about how many days away it is: in the final week, advise a taper (short, easy runs, sleep, trust the work); 1–3 weeks out, sharpen gently without cramming; further out, build gradually (~10% per week) toward the distance; on race day, give brief calm encouragement. Reference the race name, distance, and location naturally.
- Race ambition NEVER overrides the hard safety rules above. If the user has pain, a spiking load, or recent hard efforts, caution and the ~10% rule win even with a race coming up — say so plainly.`;

// Structured output: constrain Claude to exactly the shape the app's CoachReply
// decoder expects. mood is restricted to the app's BuddyMood raw values.
const FORMAT = {
  type: "json_schema" as const,
  schema: {
    type: "object",
    properties: {
      text: { type: "string", description: "The coaching reply, 2-4 sentences." },
      mood: {
        type: "string",
        enum: ["resting", "ready", "jogging", "cheering", "concerned", "celebrating", "recovery"],
      },
      safetyFlag: {
        type: "boolean",
        description: "True when steering off hard effort for safety, or for any pain/injury question.",
      },
    },
    required: ["text", "mood", "safetyFlag"],
    additionalProperties: false,
  },
};

// Input bounds: a coaching question is a sentence or two, and the context is the
// app's small TodayState. Cap both so a hostile caller can't push huge prompts
// (which also protects the user's own token spend on their key).
const MAX_QUESTION_LEN = 2000;
const MAX_CONTEXT_BYTES = 16 * 1024;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  // Best-effort throttle (see _lib/ratelimit.ts for the per-instance caveat).
  if (!allow(`coach:${clientIp(req)}`, 30, 60_000, Date.now())) {
    res.status(429).json({ error: "rate_limited", message: "One sec — too many requests. Try again in a moment." });
    return;
  }

  // Require a JSON body (the app always sends application/json). Rejecting other
  // content types avoids content-type confusion and mis-parsed bodies.
  const contentType = (req.headers["content-type"] ?? "").toString();
  if (!contentType.includes("application/json")) {
    res.status(415).json({ error: "unsupported_media_type" });
    return;
  }

  const apiKey = req.headers["x-anthropic-key"];
  if (typeof apiKey !== "string" || apiKey.length < 8) {
    res.status(400).json({ error: "missing_key", message: "Connect your Anthropic API key in Settings." });
    return;
  }

  const body = (req.body ?? {}) as { question?: string; context?: unknown };
  const question = (body.question ?? "").toString().trim();
  if (!question) {
    res.status(400).json({ error: "missing_question" });
    return;
  }
  if (question.length > MAX_QUESTION_LEN) {
    res.status(413).json({ error: "question_too_long" });
    return;
  }

  // Context, when present, must be a plain JSON object (the app's TodayState).
  // Reject arrays/primitives so only structured context reaches the prompt.
  if (
    body.context !== undefined &&
    (typeof body.context !== "object" || body.context === null || Array.isArray(body.context))
  ) {
    res.status(400).json({ error: "invalid_context" });
    return;
  }

  // The full TodayState is sent as-is and stringified into the prompt as context.
  const context = body.context ? JSON.stringify(body.context) : "{}";
  if (context.length > MAX_CONTEXT_BYTES) {
    res.status(413).json({ error: "context_too_large" });
    return;
  }

  const client = new Anthropic({ apiKey });

  try {
    const message = await client.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      output_config: { format: FORMAT },
      messages: [
        {
          role: "user",
          content: `Today's context (JSON):\n${context}\n\nUser's question:\n${question}`,
        },
      ],
    });

    if (message.stop_reason === "refusal") {
      res.status(200).json({
        text: "I can't help with that one — let's keep it to your running and movement. What would you like to work on today?",
        mood: "ready",
        safetyFlag: false,
      });
      return;
    }

    const textBlock = message.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      res.status(502).json({ error: "no_text" });
      return;
    }

    // output_config.format normally yields valid JSON, but a truncated response
    // (stop_reason "max_tokens") or any malformed output would throw on parse.
    // Degrade gracefully instead of 500-ing — the user's key worked and was billed,
    // so don't silently drop them to the offline mock.
    let parsed: { text?: unknown; mood?: unknown; safetyFlag?: unknown };
    try {
      parsed = JSON.parse(textBlock.text);
    } catch {
      res.status(200).json({
        text: "I got a little tangled forming that answer — mind asking again, maybe a bit more specifically?",
        mood: "ready",
        safetyFlag: false,
      });
      return;
    }
    res.status(200).json({
      text: String(parsed.text ?? ""),
      mood: String(parsed.mood ?? "ready"),
      safetyFlag: Boolean(parsed.safetyFlag),
    });
  } catch (err) {
    const status = (err as { status?: number }).status;
    if (status === 401) {
      res.status(401).json({ error: "invalid_key", message: "That API key was rejected by Anthropic." });
      return;
    }
    if (status === 429) {
      res.status(429).json({ error: "rate_limited", message: "Your Anthropic account is rate limited — try again shortly." });
      return;
    }
    res.status(502).json({ error: "upstream_error" });
  }
}
