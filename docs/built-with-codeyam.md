# Built with CodeYam — how Otterpace was developed

Otterpace was built feature-by-feature in the **CodeYam editor**, a scenario-driven
workflow for native apps: you describe a feature, build it against **seeded states**
that render in a live simulator preview, **capture** those states as verified
screenshots, and commit — so the app always has a gallery of real, reproducible
UI states alongside its tests. This doc is a reference for anyone building a
mobile app the same way.

## The model: one state, many seeded scenarios

The whole UI is driven by a single value type, `TodayState`
(`Sources/AppCore/Model.swift`). Nothing in the views reaches for global state —
they render `TodayState`. That makes the app trivially seedable.

Each **scenario** lives in `.codeyam/scenarios/<slug>.json` and seeds the app at
launch via a `deviceState.preferences` map — UserDefaults keys (`rb*` for the
dashboard, `otterpace*` for settings/reminders) injected into the simulator
before the app boots. For example, `today-goal-crushed.json` seeds `rbSteps:
11240`, `rbBuddyMood: "celebrating"`, `rbStartTab: "today"`; `today-day-one-connect`
seeds `rbConnected: false`. Same screens, different seeds, each captured to
`.codeyam/scenarios/screenshots/`.

`codeyam-editor editor scenario-explain <slug>` prints exactly what a scenario
injects and where its capture lands.

## The key pattern: mock seam vs. real implementation

Every integration is split behind a protocol with **two** implementations: a
deterministic mock used by scenarios/previews, and the real one used in
production. This is what lets the preview loop stay fast, offline, and
permission-free while the shipping app does the real thing.

| Seam (protocol) | Seeded / mock | Production |
|---|---|---|
| `HealthDataSource` | `SeededHealthDataSource` (reads `rb*` keys) | `HealthKitDataSource` (HKHealthStore) |
| Ask Coach | `CoachEngine` (deterministic, intent-classified) | `RemoteCoach` (Claude via a Vercel proxy) |
| Reminders | `MovementReminderScheduler` no-op (`#else`) | `UNUserNotificationCenter` (`#if os(iOS)`) |
| Token storage | in-memory `TokenStoring` (tests) | `KeychainTokenStore` |

Rule of thumb: **scenarios never hit the network or device permissions.** The
mock always answers in a scenario; the real path only runs in the production app
(gated on `previewMode.isEmpty`, a connected key, etc.). That's why a "real AI
coach" feature still has perfectly reproducible chat captures — the seed path uses
`CoachEngine`.

## The build loop (per feature)

1. **Plan** the feature; identify the `TodayState` fields / new seam it needs.
2. **Build** the SwiftUI views + the mock implementation first.
3. **Register scenarios** (`editor register @scenario.json`) that seed the new
   states; each `register` does a clean simulator boot, injects the seed, and
   captures a screenshot.
4. **Verify** the capture shows the intended state (`seeded-capture-check`
   confirms distinct seeds produced distinct frames).
5. **Add XCTest** for the pure logic; `reconcile-registry --auto-apply` syncs the
   editor's test registry.
6. **Commit.** The screenshots + scenarios are part of the repo — the app's
   living UI gallery.
7. Later, swap in the **real** implementation behind the same seam; previews are
   unaffected.

## Gotchas worth knowing (learned building this)

- **The simulator is shared, so seeds bleed.** A flag a prior scenario set
  persists into the next capture. Fix: every scenario explicitly sets the *off*
  value for flags it doesn't use (`rbShowSettings: false`, `rbShowHistory:
  false`, `otterpaceRemind*: false`). Without this, e.g. the "Settings open"
  scenario bleeds into the next dashboard capture.
- **Recapture via `register`, not the bulk tool on native.** On this
  iOS/simulator stack, `recapture-stale` does a web-proxy follow-up that 502s;
  re-`register`ing a scenario (clean seeded boot) is the reliable path.
- **The first capture after an app rebuild can catch the launch screen.** If a
  screenshot shows the launch image, recapture once the app is warm.
- **Overlays must render on the first frame.** State that drives a full-screen
  overlay (Settings, Weekly Review) is initialized from the seed in `init()`,
  not `.onAppear`, so a launch-time capture lands on the finished screen.

## Tests

Plain **XCTest** in `Tests/AppCoreTests/` (the editor's runner parses the
`--xunit-output`; swift-testing isn't reliably captured under `--parallel`). Each
test has a `//` comment above it describing what it verifies — the editor uses
that as the test's description. Run:

```
swift test --parallel --disable-swift-testing --xunit-output .codeyam/swift-tests.xml
```

## Where to look

- `.codeyam/scenarios/` — the scenario definitions (+ `screenshots/` captures)
- `Sources/AppCore/Model.swift` — `TodayState`, the single source of truth
- The seam files above — each shows the mock/real split
- `Tests/AppCoreTests/` — the pure-logic coverage
