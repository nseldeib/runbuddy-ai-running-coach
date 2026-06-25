---
title: "dogfood: Overall UI/UX Polish & Navigation"
mode: ui
createdAt: "2026-06-25T16:01:46Z"
prefix: "dogfood"
source: manual
---

## Summary

Dogfooding surfaced that, while individual screens work, the app doesn't yet
feel like one cohesive, polished product: spacing, typography, card chrome, and
motion vary screen-to-screen, and the navigation between Today, Ask Coach,
Settings, sign-in, history, and the weekly review is functional but not
deliberate. This plan is a broad UI/UX pass — both a visual-consistency /
micro-interaction polish across every existing screen *and* a navigation/flow
cleanup — building on the completed `polish-today-states` and
`accessible-responsive-design` plans. It adds no new product features; it makes
what's there feel intentional and connected.

## Key Decisions

- **Consolidate the design language in `Theme.swift` / `ViewStyles.swift`** —
  the app already centralizes color (`Palette`), type (`Typography`), and the
  `cardStyle()` chrome. Rather than tweak views ad hoc, codify a spacing scale
  and any missing shared modifiers there, then apply them consistently. This
  keeps the polish DRY and reviewable.
- **Polish + navigation together** — per the dogfooding ask, cover both the
  surface (spacing, motion, states) and the structure (how screens connect: tab
  bar, settings access, sign-in entry, transitions).
- **No new features, preserve behavior & accessibility** — every change is
  presentational or navigational; keep the existing `TodayState`/`SessionStore`
  data flow, Dynamic Type support, and Reduce-Motion handling intact.

## Implementation

### 1. Shared design tokens & chrome

**File**: `Sources/AppCore/Theme.swift`, `Sources/AppCore/ViewStyles.swift`

- Define a small, named spacing scale (e.g. `Layout.gutter`, section spacing) and
  any shared modifiers missing today (section header style, consistent card
  padding, pill/button styles used across screens), so screens stop hardcoding
  one-off paddings.
- Audit `Typography` usage for consistent hierarchy (titles, section headers,
  body, captions) and fill gaps.

### 2. Per-screen visual polish

**Files**: `Sources/AppCore/TodayView.swift`, `AskCoachView.swift`,
`SettingsView.swift`, `Auth/SignInView.swift`, `ConnectHero.swift`, and the
dashboard component views (`StatsRow`/`StatTile`, `WeeklyLoadCard`, `CoachCard`,
`BuddySummaryCard`, plus the Activity History and Weekly Review surfaces).

Apply the shared tokens for consistent rhythm; tighten alignment and card
spacing; unify empty/loading states (reuse `PuffyBuddyLoader`); make sure Buddy,
cards, and CTAs feel like one family across screens.

### 3. Motion & micro-interactions

**Files**: the same view files, plus any shared transition helpers.

- Add tasteful, consistent transitions for screen/tab changes, card appearance,
  and button presses, all gated by `@Environment(\.accessibilityReduceMotion)`.
- Coordinate with the separate `dogfood-tracker-wheel-gradient-animation` plan so
  the ring's motion language matches the rest of the app (shared easing/spring).

### 4. Navigation & flow

**File**: `Sources/AppCore/ContentView.swift` (+ `TodayView`/`AskCoachView`
headers and `SettingsView` entry points)

- Review the Today/Coach tab bar and the paths into Settings, sign-in, history,
  and the weekly review; make entry points consistent (e.g. a single, predictable
  way to reach Settings and to start a coach chat) and the transitions between
  them smooth.
- Ensure the production sign-in → dashboard flow and the scenario-seeded fast
  paths (`rbStartTab`, `rbStartScreen`, `rbShowSettings`, …) still behave.

## Reused existing code

- `Palette` / `Typography` from `Sources/AppCore/Theme.swift` and `cardStyle()`
  from `Sources/AppCore/ViewStyles.swift` — the design-token home this pass
  extends.
- `PuffyBuddy` / `PuffyBuddyLoader` — the mascot + loading states reused for
  consistent empty/loading treatment.
- `ContentView`'s existing tab + scenario-seed wiring
  (`rbStartTab`/`rbStartScreen`/`rbShowSettings`/`rbPreviewMode`) — navigation
  changes must keep these preview hooks working.
- Prior art: the completed `polish-today-states` and
  `accessible-responsive-design` plans set the bar this pass extends app-wide.

## Scenarios to Demonstrate

- **Screen-by-screen consistency**: Today, Ask Coach, Settings, Sign-in,
  Activity History, Weekly Review — each shown with the unified spacing/type/chrome.
- **Empty & loading states**: day-one `today-day-one-connect`, empty chat
  (`ask-coach-empty-chat`), and a loading state via `PuffyBuddyLoader`.
- **Navigation flow**: Today ⇄ Coach tab switch, opening Settings, and the
  sign-in → dashboard transition.
- **Dynamic Type + Reduce Motion**: largest text size and Reduce-Motion on, to
  confirm polish doesn't regress accessibility.
