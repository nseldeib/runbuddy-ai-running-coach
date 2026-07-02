# Otterpace 🐾

An open-source, AI running coach for iOS — built in the open as a CodeYam showcase.

Otterpace is a friendly running coach in your pocket: it pulls your activity from
Apple HealthKit (or, optionally, Strava), keeps you moving toward your daily 10,000
steps, and gives injury-aware, never-shame-based coaching through **Buddy**, a
mood-reactive otter mascot.

## Launch

Otterpace is code-complete; going live is account/config work (Vercel deploy, DNS,
API keys, Xcode capabilities, TestFlight). Follow the ordered checklist:

**▶ [docs/go-live-runbook.md](docs/go-live-runbook.md)** — the end-to-end launch sequence, with a verification check at each phase.

Area deep-dives: [site + DNS](docs/site-and-dns.md) · [AI coach](docs/ai-coach.md) · [Strava + analytics](docs/strava-and-analytics.md) · [TestFlight prep](docs/testflight-prep.md).

## What's here today

The **Today dashboard**, a native SwiftUI screen that shows:

- A **step-goal ring** toward your daily 10K, plus active minutes, distance, and
  time since you last moved
- **Buddy**, whose mood (resting → ready → jogging → cheering → concerned →
  celebrating → recovery) reflects how the day is going
- An **AI coach card** with one clear, practical recommendation — conservative and
  injury-aware, flipping to an amber caution when your training load spikes
- Your **latest run/walk** and a **weekly training-load** snapshot
- A friendly **day-one "Connect Apple Health"** hero for first launch

The **Ask Coach** chat, reached from a Today/Coach tab bar or the
"Ask Buddy" button on the coach card:

- Ask Buddy a fitness question and get a practical, **injury-aware** reply —
  "Can I run or should I rest?", "How do I hit 10K without overdoing it?",
  "Am I increasing mileage too fast?", or "my knee hurts after my run"
- Replies are **classified by intent** and built from your own activity context,
  so they feel personal — a recent hard run or spiking load steers Buddy toward
  recovery, and pain questions return a non-diagnostic, see-a-clinician answer
  behind an amber **"safety first"** shield
- A **real AI coach** is available when you connect your own Anthropic key
  (Settings → AI Coach): questions go to a Vercel backend that calls Claude with
  the injury-aware coach prompt. Without a key — and offline, or in scenario
  previews — the deterministic `CoachEngine`
  (`Sources/AppCore/CoachEngine.swift`) answers, so the coach always works and
  captures stay reproducible

The **Weekly Review**, opened from the Coach tab — a read-only recap the coach
generates from your weekly training load: what went well, what changed, training
risk, suggested next week, and one focus area, with Buddy's mood and an amber
safety callout when load spikes. Built by the deterministic `WeeklyReviewEngine`.

The **Activity History**, opened from the Today dashboard — recent
workouts grouped by week, each week fronted by its mileage / run-count / rest-day
rollup, with a friendly empty state for day one. Grouping is the testable
`ActivityHistory.groupByWeek`.

**Settings**, reached from the gear on the dashboard, gathers the account and
integration controls:

- **Sign in with Apple** (optional) — no account is required to use Otterpace; if
  you sign in, only an anonymous identifier is kept in the Keychain. **Sign out**
  and **delete account** both live here (the App Store account-deletion requirement).
- **Apple Health** — connect / disconnect with a live status row.
- **Strava** (optional) — connect to import your runs and rides as an alternative
  to Apple Health. OAuth runs through a small backend so the client secret stays
  server-side; the Strava tokens never touch the device.
- **AI Coach** — paste your own Anthropic key to upgrade Buddy from the built-in
  coach to a real model (see Ask Coach above).
- **Movement reminders** — optional on-device notifications: a daily nudge at a
  time you choose, an evening goal nudge, and an inactivity nudge.
- Your editable **daily step goal** and a short privacy explainer.

The whole UI scales with **Dynamic Type** and meets WCAG AA contrast, and the app
ships a code-generated **app icon** (see below).

The Today screen is driven by a single `TodayState` (see `Sources/AppCore/Model.swift`),
populated from HealthKit (or imported Strava activity) in the real app and from
each CodeYam scenario's `deviceState` preferences in the simulator preview.
Production starts empty; each scenario carries its own seeded state.

## Built with CodeYam

Otterpace is a worked example of building a native iOS app with the **CodeYam
editor** — a scenario-driven loop where every feature is developed against
seeded, captured states that render in a live simulator preview.

The core idea: a single `TodayState` (`Sources/AppCore/Model.swift`) drives the
UI, and each **scenario** (`.codeyam/scenarios/*.json`) seeds that state at launch
through a `deviceState.preferences` map (the `rb*` / `otterpace*` UserDefaults
keys) injected into the simulator. "Goal Crushed", "Recovery Caution", and
"Day One — Connect" are the *same* screens rendered from different seeds, each
captured as a screenshot the editor verifies.

Two patterns keep that loop reliable:

- **Mock seams keep previews deterministic while production stays real.** Each
  integration sits behind a protocol with a seeded mock *and* a real
  implementation — `HealthDataSource` (seeded vs. `HealthKitDataSource`),
  `CoachEngine` (deterministic mock) vs. `RemoteCoach` (real Claude),
  `MovementReminderScheduler` (no-op vs. `UNUserNotificationCenter`). Scenarios
  always use the mock, so captures never touch the network or device permissions;
  production uses the real source.
- **Scenarios are bleed-proofed.** Because seeds are shared simulator state, each
  scenario explicitly sets the "off" value for flags it doesn't use
  (e.g. `rbShowSettings: false`) so a prior capture can't bleed into the next.

Tests are plain **XCTest** over the pure logic (coach intent classification,
weekly-review generation, activity-history grouping, formatters), captured by the
editor's runner. Full walkthrough: **[docs/built-with-codeyam.md](docs/built-with-codeyam.md)**.

## Architecture

- `App/` — the iOS app entry point (`@main`) and `Info.plist`
- `Sources/AppCore/` — the SwiftUI views and model, as a shared SwiftPM library:
  `OtterpaceModel` + `TodayState` (data + derived logic), `PuffyBuddy` (the otter
  mascot) + `PuffyBuddyLoader` (its loading state), one file per dashboard
  component (`StepRing`, `CoachCard`, `WeeklyLoadCard`, …), and the Ask Coach
  surface (`AskCoachView` + `CoachEngine` and its `ChatBubble` / `ChatThread` /
  `AskCoachInputBar` parts), plus the integration modules — `Auth/` (Sign in with
  Apple + Keychain), `Health/` (HealthKit data source), `Strava/`,
  `Notifications/` (movement reminders), `Analytics/`, and `SettingsView`
- `api/` — the Vercel serverless backend: the AI coach proxy (`coach.ts`) and the
  Strava OAuth + import functions (`strava/`)
- `site/` — the marketing landing page + privacy policy, deployed with `api/` on Vercel
- `Tests/AppCoreTests/` — XCTest coverage of the model, pure formatters, and the
  coach engine's intent classification and safety branches

## Running

Requires Xcode (16+) with an iOS simulator runtime installed. No private tooling
is needed to build, run, or test the app.

    # Open in Xcode, then pick an iPhone simulator and press ⌘R
    open App.xcodeproj

    # Run the unit test suite from the command line (no simulator needed)
    swift test

The app runs fully on a simulator with no backend: HealthKit returns no data in
the simulator, so you'll see the day-one "Connect Apple Health" state. For live
steps/workouts, run on a real device and grant Health access. The AI coach,
Strava, and account sync are all optional and only activate once you configure
their keys (see `docs/`).

### Optional: CodeYam scenario previews (maintainers)

This repo is also built with [CodeYam](https://codeyam.com). With the CodeYam
editor installed you can render the dashboard in seeded states without a device:

    codeyam-editor editor preview '{"dimension":"iPhone 16","path":"/","scenarioSlug":"today-goal-crushed"}'

Scenarios live in `.codeyam/scenarios/` and seed the dashboard's state at launch —
e.g. `today-day-one-connect`, `today-fresh-start`, `today-midday-nudge`,
`today-almost-there`, `today-recovery-caution`, `today-goal-crushed`.

## App icon & launch screen

The app icon and launch screen are generated from code, not hand-painted PNGs, so
they stay consistent with the in-app mascot. Regenerate both whenever the art
changes:

    swift run GenerateAppIcon

This rasterizes the `AppIconArtwork` SwiftUI view
(`Sources/AppCore/AppIconArtwork.swift`) to two sets of assets:

- **App icon** — `App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, the
  1024×1024 marketing icon. App Store constraints it satisfies: exactly
  **1024×1024**, sRGB, **opaque (no alpha)**, no rounded corners (iOS applies the
  superellipse mask). Xcode derives every home-screen / Spotlight / Settings size
  from that single source.
- **Launch screen** — a transparent Buddy (`LaunchBuddy`, 1x/2x/3x) shown over the
  coral `LaunchBackground` color via the `UILaunchScreen` keys in `App/Info.plist`,
  so first launch is branded rather than blank.

## Testing

Write tests with **XCTest** (`import XCTest`, `final class …: XCTestCase`,
`func testName()`). XCTest is the framework the editor's runner captures: the
editor parses the XCTest `--xunit-output` file, and **swift-testing** (`import
Testing`, `@Test func`) results do **not** reliably land there on Xcode 16.x /
Swift 6.x — under `--parallel`, the swift-testing run can overwrite the xunit
with `tests="0"`, so the editor sees no tests. Put your tests in
`Tests/AppCoreTests/` with a `//` comment directly above each `func testX()`
describing what it verifies (the editor parses that comment as the test's
description).

Tests run via:

    swift test --parallel --disable-swift-testing --xunit-output .codeyam/swift-tests.xml

- `--parallel` is required: modern SwiftPM only writes the XCTest xunit to
  `--xunit-output` when run in parallel, so without it the project reports
  zero tests.
- `--disable-swift-testing` makes the xunit deterministic: it stops the
  swift-testing harness from also claiming `--xunit-output` and racing the
  XCTest writer, which otherwise nondeterministically truncates the file to
  `tests="0"`.

To register your tests with the editor after writing them, run:

    codeyam-editor editor reconcile-registry --auto-apply

This diffs the runner output against the registry and auto-adds new tests —
line numbers and descriptions are resolved automatically, so you do not need
to pass `--line` by hand.

<!-- codeyam:run-and-edit:start -->
## Develop this project with codeyam-editor

This project is built with [codeyam-editor](https://codeyam.com) — code and runnable data scenarios are authored side by side against a live preview.

```bash
# Launch the editor (split-screen terminal + live preview)
codeyam-editor editor

# Run the tests
swift test --parallel --disable-swift-testing --xunit-output .codeyam/swift-tests.xml
```
<!-- codeyam:run-and-edit:end -->

<!-- codeyam:scenario-gallery:start -->
## Scenario gallery

States captured as runnable scenarios with codeyam-editor:

### Accessibility — Large Text Today

![Accessibility — Large Text Today](.codeyam/scenarios/screenshots/accessibility-large-text-today--iphone-16.png)

### Activity History — Empty

![Activity History — Empty](.codeyam/scenarios/screenshots/activity-history-empty--iphone-16.png)

### Activity History — Long Values

![Activity History — Long Values](.codeyam/scenarios/screenshots/activity-history-long-values--iphone-16.png)

### Activity History — Rich Multi-Week

![Activity History — Rich Multi-Week](.codeyam/scenarios/screenshots/activity-history-rich-multi-week--iphone-16.png)

### Activity History — Sparse

![Activity History — Sparse](.codeyam/scenarios/screenshots/activity-history-sparse--iphone-16.png)

### App Icon — Showcase

![App Icon — Showcase](.codeyam/scenarios/screenshots/app-icon-showcase--iphone-16.png)

### AskCoachHeader - Connected

![AskCoachHeader - Connected](.codeyam/scenarios/screenshots/askcoachheader-connected--iphone-16.png)

### Buddy Puffy — Loader

![Buddy Puffy — Loader](.codeyam/scenarios/screenshots/buddy-puffy-loader--iphone-16.png)
<!-- codeyam:scenario-gallery:end -->
