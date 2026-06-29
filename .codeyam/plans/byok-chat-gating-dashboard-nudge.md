---
title: "BYOK Chat Gating + Real Dashboard Nudge"
mode: ui
createdAt: "2026-06-29T20:25:25Z"
source: manual
---

## Summary

Make Otterpace honest about what is AI and what is computed. Today the
open-ended "Ask Buddy" chat answers with a rule-based mock (labeled "mock
coach") when no Anthropic key is connected, and the Today dashboard's coach
nudge only appears when a scenario seeds it (`rbCoachHeadline`) — in
production it is `nil`, so real users see no nudge. This plan: (1) generates
the dashboard coach nudge deterministically from the day's data so the no-key
tier genuinely delivers computed insights + encouragement; (2) gates the
conversational chat behind bring-your-own-key — no key shows an "Add your AI
key to chat with Buddy" prompt instead of a fabricated answer; (3) removes the
"mock coach" label. The result: free tier = real insights + nudges; AI chat =
the reason to add a key. Everything stays reviewable by Apple with no setup.

## Key Decisions

- **Free tier is "insights + nudges," not a fake coach.** The deterministic
  `CoachEngine` stops impersonating a conversational coach in the chat and
  instead powers the honest, computed Today nudge. This kills the "mock coach"
  label problem at the root.
- **Dashboard nudge becomes a real production feature** (chosen over
  "gate chat only"). `TodayState.coach` is currently populated only from the
  `rbCoachHeadline` seed (`Model.swift:196`); in production it is `nil`. We
  generate it from `TodayState` via `CoachEngine` so no-key users get a real
  nudge, and so the App Store dashboard screenshot reflects real behavior.
- **Conversational chat is key-gated, not removed.** With a key: `RemoteCoach`
  exactly as today. Without a key: a clear CTA into Settings, not a mock reply.
- **On a keyed transient failure, show a retry/error, not a fabricated mock.**
  Today `submit` falls back to `CoachEngine` on network/server errors, which
  reintroduces fake answers. Replace that with an honest "couldn't reach Buddy,
  try again" state. Keep the existing invalid-key message (points to Settings).
- **Keep all coach SAFETY behavior on the keyed path** (backend `api/coach.ts`
  owns prompt + safety; unchanged).

## Implementation

### 1. Generate the Today coach nudge in production

**File**: `Sources/AppCore/Model.swift`

In `TodayState.readState` (and/or the production builder), when no
`rbCoachHeadline` seed is present, populate `coach: CoachRecommendation?` by
deriving it from the current `TodayState` (steps vs goal, load trend, latest
workout). Reuse `CoachEngine`'s deterministic logic (e.g. a new
`CoachEngine.dailyNudge(context:)` that returns a `CoachRecommendation` from
the same intent/branch helpers as `generalReply`/`stepsReply`/`runOrRestReply`)
so the nudge is computed, not seeded. Seeds still override for scenarios.

### 2. Add a dashboard-nudge generator to CoachEngine

**File**: `Sources/AppCore/CoachEngine.swift`

Add `static func dailyNudge(context: TodayState, asOf:) -> CoachRecommendation`
that maps the day's state to a short headline + body + `recommendationType` +
`safetyFlag` (celebrate / easy-day / nudge-to-move / recovery-caution). This is
the honest, computed encouragement — distinct from the chat. Keep the existing
`reply(to:context:)` (still used by scenario seeding for chat captures; see #6).

### 3. Gate the chat behind a connected key

**File**: `Sources/AppCore/AskCoachView.swift`

- In `submit(_:)`, when `keyStore.key == nil`, do NOT call `ask()` (the mock).
  Instead surface the no-key state: an "Add your AI key to chat with Buddy"
  message/CTA that routes to Settings → AI Coach (reuse the existing
  Settings/coach navigation; the chat already has `model`). Built-in insights
  are free; conversational chat needs a key.
- Keyed path unchanged (`RemoteCoach`), except: on `CoachError.network`/
  `.server`, replace `offlineFallback(...)` (mock) with a retry/error coach
  bubble. Keep the `.invalidKey` message.
- Remove `offlineFallback` and the no-key branch's `ask(...)` mock call.
  `ask(...)` itself stays only if still needed by scenario seeding (#6);
  otherwise inline/remove.

### 4. Empty / CTA state for the no-key chat

**File**: `Sources/AppCore/AskCoachEmptyState.swift` (and/or a small new
subview)

When no key is connected, the empty chat should present the "Add your AI key"
explainer + button rather than the "ask me anything" prompt. When a key is
connected, keep today's empty prompt. Drive this off `CoachKeyStore.isConnected`.

### 5. Remove the "mock coach" label

**File**: `Sources/AppCore/AskCoachHeader.swift`

Replace `Text("Buddy • mock coach")` (line 16). When a key is connected, show
`Buddy • AI coach` (or just `Buddy`); with no key, the header pairs with the
CTA empty state, so show `Buddy` with no "mock" wording. Update the file's
header comment that describes the "mock coach" subtitle.

### 6. Keep scenarios capturable offline

**Files**: affected scenario JSON under `.codeyam/scenarios/` + any new seed
key handling in `AskCoachView` / `Model`.

The ask-coach scenarios (`ask-coach-knee-pain`, `ask-coach-hit-10k`,
`ask-coach-mileage-spike`, `ask-coach-race-taper`, `ask-coach-run-or-rest`)
currently render a mock reply via `rbAskSeedQuestion` → `CoachEngine`. After
gating, the no-key path won't render a reply. Preserve deterministic, offline
captures by treating a seeded conversation as a "connected" preview: e.g. when
`rbAskSeedQuestion` is present, seed the chat as if a key is connected and
render the reply directly from `CoachEngine` (no live network). Add a new
no-key CTA scenario (e.g. `ask-coach-no-key`) to demonstrate the gated state.
Re-capture the App Store screenshot `02-ask-coach-knee-pain.png` from the
keyed-seed state afterward.

### 7. Tests

**File**: `Tests/AppCoreTests/CoachEngineTests.swift` (+ new cases)

- Add tests for `CoachEngine.dailyNudge(context:)` across states (goal hit,
  load spike, fresh start, recovery caution).
- Add tests that `requireUser`-style gating holds: no key → chat produces the
  CTA path and makes no network call; key present → routes to `RemoteCoach`.
- Keep existing `CoachEngine.reply` intent tests (still used by seeded chat
  captures).

## Reused existing code

- `CoachEngine` / `CoachIntent` / `CoachReply` from
  `Sources/AppCore/CoachEngine.swift` (glossary: `CoachEngine`, `CoachIntent`) —
  source of the deterministic nudge + seeded-chat replies.
- `CoachKeyStore` / `RemoteCoach` / `CoachConfig` from
  `Sources/AppCore/Coach/RemoteCoach.swift` — `isConnected` is the gate signal;
  `RemoteCoach.reply` is the keyed path (unchanged).
- `CoachRecommendation` + `TodayState` from `Sources/AppCore/Model.swift`
  (glossary: `OtterpaceModel`/model types) — the nudge shape the dashboard
  `CoachCard` already renders.
- `CoachCard` from `Sources/AppCore/CoachCard.swift` (glossary: `CoachCard`) —
  renders the dashboard nudge as-is; no change needed beyond it now having data
  in production.
- Settings AI Coach card / key entry in `Sources/AppCore/SettingsView.swift`
  (`coachCard`, line ~349) — the CTA destination.

## Scenarios to Demonstrate

- Today dashboard with a real computed nudge, no key (goal crushed → celebrate).
- Today dashboard nudge in a recovery-caution state (load spiking).
- Ask Buddy, no key: the "Add your AI key to chat with Buddy" CTA empty state.
- Ask Buddy, key connected: a populated conversation (seeded reply, offline).
- Ask Buddy, key connected, transient failure: honest retry/error bubble.
- Settings AI Coach card: not connected vs connected.
