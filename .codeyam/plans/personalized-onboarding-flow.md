---
title: "Personalized Onboarding Flow"
mode: ui
createdAt: "2026-07-01T17:00:00Z"
source: manual
---

## Summary

Turn the first-run welcome tour into a personalized setup flow. After the
existing three intro pages, add a short, movement-first sequence where the user
sets their daily step goal, tells Buddy about their walking habits (how much,
when) and any other training, and is prompted to connect an AI coaching key —
with **every one of these steps individually skippable**. The answers persist
on-device as a lightweight profile and are threaded into the coach context
(`TodayState`) so both the deterministic nudge and the real AI coach speak to
the person instead of a generic runner. Because the profile now leaves the
device on connected-coach requests, the privacy policy and marketing site copy
are updated to say so.

## Key Decisions

- **Extend the existing onboarding, don't build a parallel flow.** The new
  steps live inside `OnboardingFlowView` after the intro carousel and remain
  replayable from Settings via the existing `onReplayTour` path — one gated
  overlay, one "seen" flag, no second entry point.
- **Movement-first, nutrition dropped.** Steps cover daily step goal, walking
  habits, and other training only. No eating/nutrition questions, per scope.
- **Every step is skippable and leaves a safe default.** Skipping the goal keeps
  `UserPreferences.defaultGoal` (10k); skipping a profile question stores `nil`
  for that field; skipping the key prompt leaves the built-in coach in place.
  Nothing collected is required to finish onboarding.
- **Profile feeds the coach, stored locally, sent only when coach is connected.**
  A new `CoachProfile` (UserDefaults-backed, mirroring `UserPreferences` /
  `RaceStore`) is attached as an optional field on `TodayState`, so it flows
  through the existing `RemoteCoach` → `/api/coach` request with no new
  transport. It's optional/`nil`-defaulting so existing scenarios and the
  `TodayState` Codable shape are unaffected.
- **Privacy + site copy updated because behavior changed.** With a connected
  key, the request now includes a small personalization profile in addition to
  the day's activity summary. `site/privacy.html` and `docs/ai-coach.md` must
  reflect that; the profile itself is never sent to analytics and never leaves
  the device unless the AI coach is connected.
- **Reuse, don't reinvent, the goal picker and key entry.** The goal step reuses
  `UserPreferences` presets + `clampGoal`; the key step reuses `CoachKeyStore`
  and the exact "stored only on this device" framing from the Settings AI Coach
  card.

## Implementation

### 1. New on-device profile store

**New file**: `Sources/AppCore/Onboarding/CoachProfile.swift`

A `CoachProfile: Codable, Equatable` value plus a UserDefaults-backed store,
following the `RaceStore` pattern (single JSON key, injectable `defaults`,
`load` / `save` / `clear`). All fields optional so "skipped" is representable:

- `walkVolume` — enum (`rarely`, `someDays`, `mostDays`, `daily`), "how much do
  you usually walk?"
- `walkTime` — enum (`mornings`, `midday`, `evenings`, `varies`), "when do you
  usually walk?"
- `otherTraining` — set/array of enum (`running`, `strength`, `cycling`,
  `mobility`, `sports`; empty => none), "do you do any other training?"

Each enum carries a short human `label` for the coach payload. The daily step
goal is intentionally **not** duplicated here — it stays the single source of
truth in `UserPreferences`. Keep this file focused so it can register cleanly in
the glossary.

### 2. Attach the profile to the coach context

**File**: `Sources/AppCore/Model.swift`

Add an optional `profile: CoachProfile?` to `TodayState` (default `nil`, placed
next to `races`). In `OtterpaceModel` where `self.today.races = RaceStore.load(...)`
is set (around line 141), also load `CoachProfile` and assign it. Keeping it
optional means existing scenario JSON and the Codable contract are unchanged.

### 3. Extend the onboarding into a personalized flow

**File**: `Sources/AppCore/Onboarding/OnboardingFlowView.swift`

Keep the three intro pages, then continue into a small stepped sequence rather
than finishing at "Get started":

1. **Set your goal** — reuse `UserPreferences.goalOptions` + `clampGoal`; a
   preset chooser (optionally the custom stepper) that calls
   `UserPreferences.setGoalSteps` on selection. Skip keeps the default.
2. **Walking habits** — how much (`walkVolume`) and when (`walkTime`); tap-to-
   pick chips.
3. **Other training** — multi-select chips for `otherTraining`.
4. **Add AI coaching (optional)** — reuse the Settings AI Coach copy and
   `CoachKeyStore.save`; a `SecureField("sk-ant-…")` + Connect, a "Get an API
   key" link, and a prominent **Skip for now** that explains the built-in coach
   still works.

Every personalization step shows a clearly visible per-step **Skip** control
(distinct from finishing the tour). Persist collected values to `CoachProfile`
(and the goal to `UserPreferences`) as the user advances or on finish. The final
step's primary button is "Get started", which calls `onFinish`.

### 4. Track the flow's structure + step gating

**File**: `Sources/AppCore/Onboarding/OnboardingState.swift`

`pageCount` currently hardcodes `3` for the intro carousel and drives
`startPage` clamping + the scenario `rbOnboardingPage` hook. Update it to model
the full flow — keep an `introPageCount` (3) for the swipeable carousel and add
the personalization step indices — so `startPage` clamping and scenario seeding
can target any step (intro page or a specific personalization step) for capture.
Keep `hasSeen` / `markSeen` / `shouldShow` semantics unchanged.

### 5. Analytics for the new steps

**File**: `Sources/AppCore/ContentView.swift` (and/or `OnboardingFlowView`)

Keep the existing `onboarding_started` / `onboarding_completed` events. Add
lightweight step events via `Analytics.shared.capture` — e.g.
`onboarding_goal_set`, `onboarding_profile_saved`, `onboarding_key_connected`,
and `onboarding_step_skipped` (with a step name property) — so completion vs.
skip of each new step is visible. No PII in properties (enum labels only).

### 6. Teach the coach to use the profile

**File**: `api/coach.ts`

The profile now rides inside `context` (`TodayState.profile`). Add a
"Personalization" section to `SYSTEM_PROMPT` describing the optional profile
(usual walking volume + time of day, other training) and how to use it: tailor
tone and suggestions to their normal movement, respect that walking may be their
main activity, and fold other training into load reasoning. Reassert that the
existing hard safety rules and the ~10% guidance still win. Missing/`null`
fields mean "not shared — don't assume."

**File** (optional, deterministic parity): `Sources/AppCore/CoachEngine.swift` —
if low-effort, let `dailyNudge(for:)` lightly reference `profile` (e.g. a
walking-focused nudge when `otherTraining` is empty), so the no-key tier also
feels personalized. Keep it optional and safety-neutral.

### 7. Update privacy + marketing copy

**File**: `site/privacy.html`

Update the "AI coach (optional)" paragraph (line ~39) so it states that, when a
key is connected, the request includes **your question, a summary of the day's
activity, and the personalization profile you set in onboarding** (goal, walking
habits, other training) — sent to our backend and on to Anthropic, key stored
only in the Keychain, questions not retained. Reaffirm the profile is never sent
to analytics and never leaves the device unless the AI coach is connected.

**File**: `docs/ai-coach.md`

Note in the "How it connects" section that the coach context now carries the
optional onboarding profile alongside the activity summary.

**File** (light touch): `site/index.html` — if a feature bullet describes the
coach/onboarding, mention the quick personalized setup; no privacy claim changes
needed beyond the health-data language already present.

### 8. Tests

**Files**: `Tests/AppCoreTests/` (Swift) and `test/` (vitest, `npm test`)

- Swift: `CoachProfile` round-trip (save/load/clear, all-nil default, partial
  fill), and `OnboardingState` step-count / `startPage` clamping across the new
  step range.
- Swift: `TodayState` still decodes legacy scenario JSON with no `profile` field
  (optional-field back-compat).
- Swift (if #6 done): a `CoachEngine.dailyNudge` case exercising a profile with
  empty `otherTraining`.
- Vitest: `api/coach.ts` builds the prompt/request including the profile when
  `context.profile` is present and behaves unchanged when it's absent.

## Reused existing code

- `UserPreferences` (goal presets, `clampGoal`, `setGoalSteps`,
  `defaultGoal`) from `Sources/AppCore/Preferences.swift` (glossary:
  `UserPreferences`, `clampGoal`) — the goal step's source of truth.
- `RaceStore` UserDefaults-JSON pattern from `Sources/AppCore/RaceGoals.swift` —
  the template for `CoachProfile` persistence.
- `CoachKeyStore` (`save` / `isConnected`) from
  `Sources/AppCore/Coach/RemoteCoach.swift` — the onboarding key step reuses it,
  same as Settings.
- `TodayState` / `CoachRecommendation` from `Sources/AppCore/Model.swift` — add
  the optional `profile` field alongside `races`; `RemoteCoach` already ships
  `context: TodayState` to the backend, so no transport change.
- `OnboardingFlowView` / `OnboardingState` from `Sources/AppCore/Onboarding/` —
  extended in place; `ContentView`'s `showOnboarding` overlay + `onReplayTour`
  wiring is reused unchanged.
- Settings AI Coach card copy + `SecureField("sk-ant-…")` pattern from
  `Sources/AppCore/SettingsView.swift` (`coachCard`, line ~349) — reused for the
  onboarding key step.
- `CoachEngine.dailyNudge(for:)` / `reply(to:context:)` from
  `Sources/AppCore/CoachEngine.swift` (glossary: `CoachEngine`) — the deterministic
  tier that can optionally read `profile`.

## Scenarios to Demonstrate

- Onboarding — goal step: choosing an 8k preset (goal reflected on entry).
- Onboarding — walking-habits step: "most days / mornings" selected.
- Onboarding — other-training step: multi-select with running + strength picked.
- Onboarding — AI-key prompt step, not connected: the Skip-for-now / built-in
  coach explainer.
- Onboarding — AI-key prompt step, key entered: connected confirmation.
- Skip-everything fast path: user skips each step and lands in the app with
  defaults (10k goal, no profile, built-in coach).
- Replay from Settings: re-entering the full personalized flow via the tour.
- Ask Buddy with a profile set (seeded, offline): reply that reflects walking-
  focused personalization.
