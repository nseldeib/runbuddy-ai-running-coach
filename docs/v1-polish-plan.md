# Otterpace v1 polish plan — on-device TestFlight feedback

First on-device test of build 1.0/1 surfaced a batch of UI/UX issues. This is the
fix plan. **Headline decision: force a clean, light theme app-wide — no dark
mode.** That's the root cause of most of these.

## Root cause (the visual cluster)
Otterpace is a **light-only design** (cream/coral `Palette`), but it never forces
a color scheme. On a device in **Dark Mode**, SwiftUI's *system* colors flip dark
(default text, `SecureField`, system backgrounds, some SF Symbols) while the
custom-painted `Palette` areas stay light → **light-text-on-light** and
**dark-where-it-should-be-light**. The captures never showed this because the
simulator ran in light mode.

**Primary fix:** force `.preferredColorScheme(.light)` at the root
(`ContentView` / the `@main` App scene), then audit every place that leans on
system colors and pin explicit `Palette` colors.

## Issues

### A. Theme / dark-mode → force light (do first; likely fixes 1,2,3,7)
1. **Coach reply text** is light-on-light, unreadable (Ask Coach chat bubbles).
2. **Today/Home renders dark**, the other tabs render light — all should be light.
3. **API-key entry** screen (the `SecureField` in Settings → AI Coach) renders dark.
7. **Light icon on a light background** — low contrast (identify which icon/screen).

Fix: force light scheme; replace any `Color.primary/.secondary`, default
`SecureField`/`TextField` styling, and system backgrounds with explicit `Palette`
colors; re-check WCAG AA contrast (icons + text) in light. Audit `ChatBubble`,
`AskCoachView`, `SettingsView` (SecureField), and the tab/background containers.

### B. Navigation & input
4. **Hard to get back to Today** from the Coach tab — verify the bottom tab bar is
   reachable / not hidden behind the keyboard; consider a clearer affordance.
5. **Keyboard hard to dismiss** in the chat input — add
   `.scrollDismissesKeyboard(.interactively)`, tap-to-dismiss, and/or a Return/Done
   submit that resigns first responder.
8. **Overall navigation is hard between Today ↔ Weekly Review ↔ Activity History.**
   Today these open as full-cover **overlays** (driven by `showReview` / `showHistory`
   booleans), with no consistent back/close or way to move between them. Rethink the
   navigation model so the user can reliably get from Today to Weekly Review, to
   History, and back — e.g. a proper navigation stack with visible back buttons, or
   clear entry/close affordances on each overlay. This is the biggest UX rework here;
   it spans `ContentView`, `WeeklyReviewView`, `ActivityHistoryView`, `TodayDashboard`.

### C. Coach behavior (needs clarification before building)
6. **"Coach jumps to feedback and doesn't ask questions."** Capture the intended
   behavior at kickoff: should Buddy ask a clarifying follow-up before advising,
   or open more conversationally rather than going straight to a recommendation?
   This touches the coach **system prompt** (`api/coach.ts`) and/or the
   `CoachEngine` mock. Decide the desired interaction, then adjust the prompt.

## Approach / order
1. **Force light theme** (one line at the root) — re-test on device; likely clears 1,2,3,7.
2. **Theme/contrast audit pass** — pin `Palette` colors, fix the SecureField, fix the light-on-light icon, re-check AA contrast.
3. **Ask Coach UX** — keyboard dismissal + back-to-Today (4,5).
4. **Coach behavior** (6) — per the clarified intent; tweak the prompt.
5. **Re-verify scenarios** — `swift test`, `seeded-capture-check`; recapture any screen whose look changed (captures are light already, so likely minimal).
6. **Rebuild → re-archive → upload build 2** to TestFlight for re-test (use the recorded CLI pipeline in `testflight-prep.md` / the build-fixes commit: team `4D67UCFK3J`, `TARGETED_DEVICE_FAMILY=1`, etc.). **Bump CFBundleVersion to 2.**

## Open questions to resolve at kickoff
- **Item 6:** what coach interaction do you want (ask clarifying Qs vs. direct advice)?
- **Functional check from the smoke test:** did your **real step count load** (HealthKit)? Did the **real AI coach reply** come back when you pasted your key? (Item 6 implies the coach *did* respond — confirm so we know the plan is visual/UX, not functional.)

## Context for resuming (after /clear)
- TestFlight build 1.0/1 is delivered & installed; this plan is the v1 polish round → build 2.
- Build pipeline + team ID + gotchas are in `memory/otterpace-launch-state.md` and `docs/testflight-prep.md`.
- Forced-light is the theme decision; no dark mode is supported by design.
