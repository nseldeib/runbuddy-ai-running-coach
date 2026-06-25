# Otterpace v1 polish plan — on-device TestFlight feedback

First on-device test of build 1.0/1 surfaced a batch of UI/UX issues. This is the
**robust, sequenced fix plan** — every workstream below has concrete file targets,
an approach, and acceptance criteria so each can be picked up and verified
independently. **Headline decision: force a clean, light theme app-wide — no dark
mode.** That's the root cause of most of these.

> **Functional check:** ✅ Confirmed working on device — real step count loaded
> (HealthKit) and the real AI coach reply came back. So this whole plan is
> **visual/UX + a coach-prompt tweak + ops (email)** — there are no functional
> bugs to chase.

## Root cause (the visual cluster)
Otterpace is a **light-only design** (cream/coral `Palette`), but it never forces
a color scheme. The app entry point (`App/App.swift`) is a bare
`WindowGroup { ContentView() }` with **no `.preferredColorScheme`**. On a device
in **Dark Mode**, SwiftUI's *system* colors flip dark (default text, `SecureField`,
system backgrounds, some SF Symbols) while the custom-painted `Palette` areas stay
light → **light-text-on-light** and **dark-where-it-should-be-light**. The captures
never showed this because the simulator ran in light mode.

---

## Sequencing (robust plan for everything, in order)

The work splits into **quick wins → ship build 2 → larger nav rework → ops**, so
the dark-mode fixes get on-device feedback fast before the riskier navigation
rework. Each phase is independently shippable.

| Phase | Workstream | Risk | Gate before next |
|------|------------|------|------------------|
| 1 | **WS1** Force light theme | Tiny (1 line) | — |
| 1 | **WS2** Theme / contrast audit | Low | visual AA pass |
| 1 | **WS3** Ask Coach input + back-to-Today | Low | on-device dismiss works |
| 1 | **WS4** Coach asks clarifying Q first | Low | prompt + mock agree |
| 1→ship | **WS7a** Re-verify + cut **build 2** | Low | swift test green, scenarios recaptured |
| 2 | **WS5** Today ↔ Weekly ↔ History nav rework | **Med-High** | its own design pass + build 3 |
| ops | **WS6** Email / contact reconciliation | Low (decision pending) | tracked todo — decide later |

---

## WS1 — Force light theme (do FIRST; likely clears bugs 1,2,3,7)
**Bugs:** 1 coach text light-on-light · 2 Today renders dark / other tabs light ·
3 API-key `SecureField` renders dark · 7 light icon on light background.

**Change:** force `.preferredColorScheme(.light)` at the root.
- Target: `App/App.swift` — `WindowGroup { ContentView().preferredColorScheme(.light) }`
  (apply at the scene root so it covers every overlay/sheet too).
- Belt-and-suspenders: also set it on `ContentView`'s top container so SwiftUI
  previews and isolated-component scenarios render light.

**Acceptance:** with the **device in Dark Mode**, every screen (Today, Coach,
Settings, the API-key field, all overlays) renders in the light `Palette`. Re-test
bugs 1/2/3/7 on device — most should be gone before WS2.

## WS2 — Theme / contrast audit pass
After forcing light, sweep for anything still leaning on system colors and pin
explicit `Palette` values; re-check WCAG AA on text + icons.

**Targets to audit:**
- `ChatBubble` / `AskCoachView` — coach reply text color (bug 1). Pin to a dark
  ink `Palette` color on the bubble fill; verify AA contrast.
- `SettingsView` — the AI Coach `SecureField` ("sk-ant-…"): give it an explicit
  light field background + dark text (bug 3).
- The **light-on-light icon** (bug 7) — identify which SF Symbol/screen and pin a
  contrasting tint.
- Grep for `Color.primary`, `Color.secondary`, default `.background`, system
  `Material`, and any unpinned `TextField`/`SecureField` styling across
  `Sources/AppCore/**`; replace with `Palette` equivalents.

**Acceptance:** no light-on-light or dark-on-dark anywhere; all body text and
interactive icons pass AA in light.

## WS3 — Ask Coach input & back-to-Today
**Bugs:** 4 hard to get back to Today from Coach · 5 keyboard hard to dismiss.

**Changes (Ask Coach view):**
- `.scrollDismissesKeyboard(.interactively)` on the chat scroll view.
- Tap-anywhere-to-dismiss + a **Done**/Return that resigns first responder.
- Make the bottom tab bar reliably reachable (not hidden behind the keyboard);
  add a clear affordance back to Today if the tab bar isn't obvious.

**Acceptance:** on device, the keyboard dismisses by scroll, tap, and Return; you
can always get back to Today in one tap.

## WS4 — Coach asks a clarifying question FIRST
**Bug:** 6 "coach jumps to feedback and doesn't ask questions."
**Decision (resolved):** Buddy opens conversationally and asks **~one** clarifying
question when the user's intent/context is thin, *then* advises — not an
interrogation.

**Changes:**
- `api/coach.ts` — update the system prompt: instruct it to ask a single
  clarifying question before advising when context is thin.
- `Sources/AppCore/Coach/CoachEngine.swift` (the deterministic mock) — mirror the
  intent so previews/offline mode match the real coach.

**Acceptance:** a cold "what should I do today?" returns one friendly clarifying
question, not immediate prescriptive feedback; the mock behaves the same offline.

## WS5 — Navigation rework (Today ↔ Weekly Review ↔ Activity History) — Phase 2
**Bug:** 8 navigation between Today, Weekly Review, and Activity History is hard.
Today these open as full-cover **overlays** driven by `showReview` / `showHistory`
booleans, with no consistent back/close or way to move between them.

**This is the biggest UX rework — give it its own design pass before coding.**
- Spans `ContentView`, `WeeklyReviewView`, `ActivityHistoryView`, `TodayDashboard`.
- Options to weigh in the design pass: a proper `NavigationStack` with visible back
  buttons vs. keeping overlays but adding consistent close + cross-navigation
  affordances. Decide the model first, then implement.

**Acceptance:** from Today you can reliably reach Weekly Review and Activity
History and get back, with consistent, visible affordances on every screen.
**Ships as build 3** (after build 2's dark-mode fixes are validated on device).

## WS6 — Email / contact reconciliation — OPS (track as todos, decide later)
**Decision pending (user: "just track as todos, decide later").** The contact
addresses published in shipped artifacts don't resolve to a real mailbox, and they
**disagree with each other**:

| Where | Address | Problem |
|-------|---------|---------|
| `site/privacy.html:53` (LIVE) | `hello@otterpace.com` | no mailbox behind it |
| `CODE_OF_CONDUCT.md:48` | `conduct@otterpace.app` | **wrong TLD** (`.app` ≠ owned `.com`) + different local-part |
| `docs/go-live-runbook.md:135`, `docs/site-and-dns.md:46`, `docs/testflight-prep.md:57` | `hello@otterpace.com` | already flagged "set up later" |

**Todos (do NOT implement yet — these are tracked decisions):**
1. **Decide the canonical address(es):** one shared `hello@otterpace.com`, or split
   `hello@` + `conduct@`. Whatever we pick, the domain must be `otterpace.com`
   (the one we own) — `otterpace.app` in the CoC is a typo to fix regardless.
2. **Decide the inbox strategy:** (a) Namecheap email **forwarding** → an inbox you
   already read (cheapest, no mailbox); (b) a real **mailbox** (Namecheap Private
   Email / Google Workspace); or (c) repoint references to an existing inbox
   (e.g. `hello@codeyam.com`) and drop the otterpace address entirely.
3. **If forwarding/mailbox:** add the **MX records** at Namecheap (separate from the
   site's A records) + verify deliverability. Capture steps in `docs/site-and-dns.md`.
4. **Reconcile references** once decided: `site/privacy.html`, `CODE_OF_CONDUCT.md`
   (fix `.app`→`.com`), and the 3 docs — all point to the same real address.

**Acceptance:** every published contact address resolves to an inbox we read, on a
domain we own, and the CoC TLD typo is gone. (Deferred until the user decides.)

## WS7 — Re-verify & ship
**WS7a (gates build 2, after Phase 1):**
- `swift test` (the 95-test suite incl. `IntegrationModuleTests`) green.
- `seeded-capture-check`; recapture any scenario whose look changed (captures are
  already light, so likely minimal — but the forced-light change touches every screen).
- **Bump `CFBundleVersion` 1 → 2** in `App/Info.plist`.
- Rebuild via the recorded CLI pipeline (team `4D67UCFK3J`,
  `TARGETED_DEVICE_FAMILY=1`, `CODE_SIGN_STYLE=Automatic`,
  `-allowProvisioningUpdates`) → `-exportArchive` → `altool --upload-app`. Full
  recipe in `docs/testflight-prep.md` + `memory/otterpace-launch-state.md`.
- Re-test the 8 bugs on device.

**WS7b (gates build 3):** same verify/ship loop after WS5 lands; bump
`CFBundleVersion` → 3.

---

## Reminders / housekeeping
- **Revoke the app-specific password** `favo-…` (it was pasted in chat during the
  build-1 upload). `account.apple.com → Sign-In and Security → App-Specific Passwords`.
- Build pipeline + team ID + gotchas live in `memory/otterpace-launch-state.md` and
  `docs/testflight-prep.md`.
- Forced-light is the theme decision; **no dark mode is supported by design.**

## Context for resuming (after /clear)
- TestFlight build 1.0/1 is delivered & installed; this plan is the v1 polish round.
- Phase 1 → build 2 (dark-mode + coach quick wins). Phase 2 → build 3 (nav rework).
  WS6 (email) is a tracked ops decision, independent of the builds.
