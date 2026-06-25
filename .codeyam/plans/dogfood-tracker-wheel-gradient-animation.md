---
title: "dogfood: Tracker Wheel — Seamless Gradient & Entrance Animation"
mode: ui
createdAt: "2026-06-25T16:01:45Z"
prefix: "dogfood"
source: manual
---

## Summary

The daily step-goal ring (`StepRing`) draws its progress arc with a full-circle
`AngularGradient` of `[Palette.brand, Palette.gold, Palette.go]` rotated by
`-90°`. Because an angular gradient wraps the entire circle, the green end color
(`Palette.go`) butts directly against the coral start color (`Palette.brand`) at
12 o'clock — producing the abrupt green/orange split the user noticed at the top
of the wheel. The ring is also fully static: it snaps to its final value with no
motion. This plan removes the seam by mapping the gradient onto the *filled arc*
instead of the whole circle, and adds a smooth entrance animation (the arc sweeps
up to the current progress on appear) plus animated transitions when the step
count changes — while respecting Reduce Motion.

## Key Decisions

- **Map the gradient to the progress arc, don't wrap it** — switch the trimmed
  `Circle` to an `AngularGradient(gradient:center:startAngle:endAngle:)` whose
  angular span equals the filled portion (`startAngle = -90°`,
  `endAngle = -90° + 360° * progress`). Coral→gold→green then flows along the
  actual progress and the leading rounded cap is green, with no color seam at the
  top regardless of progress. Chosen over the alternative of duplicating
  `Palette.brand` as the gradient's end color (which only hides the seam and
  muddies the coral→green story).
- **Entrance animation via an animatable progress state** — animate a
  `@State private var animatedProgress` from `0` to `progress` on appear so the
  arc sweeps in; the gradient `endAngle` is derived from the same value so color
  and length stay in sync. Use a gentle ease-out / spring.
- **Honor Reduce Motion** — read `@Environment(\.accessibilityReduceMotion)` and
  skip the sweep (snap to final value) when it's on, consistent with the
  completed `accessible-responsive-design` work.
- **Animate updates too** — when `progress`/`steps` change (e.g. new HealthKit
  read), animate the arc to the new value rather than snapping, with a subtle
  emphasis when the goal is first reached/exceeded.

## Implementation

### 1. Seamless gradient + animated arc

**File**: `Sources/AppCore/StepRing.swift`

- Replace the full-circle `AngularGradient(gradient:center:)` on the trimmed
  progress `Circle` with the start/end-angle form so the gradient spans only the
  filled arc (`startAngle: .degrees(-90)`,
  `endAngle: .degrees(-90 + 360 * animatedProgress)`). Keep the faint background
  track ring (`Palette.brand.opacity(0.14)`) and the `.round` line cap.
- Introduce `@State private var animatedProgress: Double` (init `0`). Drive both
  the `trim(from:to:)` and the gradient `endAngle` from `animatedProgress` so
  length and color move together.
- On `.onAppear`, set `animatedProgress` to `progress` inside
  `withAnimation(...)` (ease-out or a soft spring, ~0.6–0.9s). On
  `.onChange(of: progress)`, animate to the new value. When
  `accessibilityReduceMotion` is true, assign without animation.
- Optional flourish when `reached`/`exceeded` flips true: a brief scale/opacity
  pulse on the center count or a one-shot glow on the cap — kept subtle and also
  gated by Reduce Motion.
- Leave the center `VStack` (count, caption, "to go") and all accessibility
  wiring (`accessibilityLabel`/`accessibilityValue`, `@ScaledMetric diameter`)
  unchanged — this is a visual/motion change only.

### 2. Verify exceeded (>100%) rendering

**File**: `Sources/AppCore/StepRing.swift`

`progress` can exceed `1.0` when the goal is beaten. Clamp the *trim* to `1.0`
(a circle can't draw more than full) while still letting the caption reflect the
`exceeded` state, and make sure the gradient `endAngle` clamps at `-90 + 360` so
the wheel reads as a complete, seam-free ring when the goal is crushed.

## Reused existing code

- `Palette.brand` / `Palette.gold` / `Palette.go` from
  `Sources/AppCore/Theme.swift` — the existing progress gradient stops.
- `stepGoalCaption` / `stepGoalAccessibilityValue` (Formatters) and `formatted(_:)`
  — the center text + accessibility value, unchanged.
- `Typography` and the `@ScaledMetric` diameter pattern already in `StepRing`.
- `@Environment(\.accessibilityReduceMotion)` — same Reduce-Motion approach used
  by the completed `accessible-responsive-design` plan.

## Scenarios to Demonstrate

- **Mid-progress (no seam)**: `today-midday-nudge` / `today-almost-there` — the
  arc shows coral→gold→green flowing along the filled portion with the top of the
  ring clean (no green/orange split).
- **Entrance animation**: any Today scenario on first appear — the arc sweeps
  from empty up to its value.
- **Goal crushed / exceeded**: `today-goal-crushed` — full, seam-free ring plus
  the reached/exceeded emphasis.
- **Fresh start (0%)**: `today-fresh-start` — near-empty ring still renders the
  rounded cap cleanly.
- **Reduce Motion on**: the ring snaps to its final value with no sweep.
