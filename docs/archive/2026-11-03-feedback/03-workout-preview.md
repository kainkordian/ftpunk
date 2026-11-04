# 03 — Workout preview: show % FTP and watts per step

## Problem

`App/Features/Home/WorkoutDetailSheet.swift` shows a 120 pt profile chart without
values, and a step list that only shows `duration · watts`. The rider can't see the
intensity (% FTP) of an interval, and can't tell which bar is which step.

## Goal

Every step's **name, duration, % FTP and watts** is readable without interaction, and
the chart can be inspected by hover (macOS), by tap/drag (iOS) and by VoiceOver.

## Domain (testable, `Sources/FTPunkDomain/WorkoutProfile.swift` or a new `WorkoutPreview.swift`)

Add a pure model the sheet and chart both use:

```swift
public struct WorkoutStepSummary: Equatable, Sendable {
    public let index: Int
    public let name: String
    public let start: Double, seconds: Double
    public let watts: Int, endWatts: Int?
    public let percent: Int?, endPercent: Int?      // nil without FTP
    public let zone: IntensityZone?
    public var valueText: String                    // "10:00 · 50 % · 125 W", "5:00 · 60→40 % · 150→100 W", "10:00" when hidden
}
public enum WorkoutPreview {
    public static func steps(for plan: TrainingPlan, intensity: Int = 100) -> [WorkoutStepSummary]
    public static func step(atFraction x: Double, in plan: TrainingPlan) -> Int?   // for hover/drag hit-testing
    /// Consecutive identical repeat blocks, e.g. 5 × (3:00 @ 115 %, 3:00 @ 50 %), for the compact list.
    public static func groups(for plan: TrainingPlan) -> [StepGroup]
}
```

- Percent = `round(watts / ftp * 100)` with `plan.ftpWatts`; nil when there's no FTP.
  Imported workouts have fixed watts, so % is shown against the FTP saved with them
  (`plan.ftpWatts`), matching the existing "saved at X W FTP" note.
- `groups` collapses repeats: a run of the same (seconds, watts) pattern repeated ≥ 2×
  becomes one group "5× · VO2max 3:00 @ 115 % 288 W / Recovery 3:00 @ 50 % 125 W".
  It's used for the summary only; the full list stays available.

## Chart (`App/DesignSystem/WorkoutProfileChart.swift`)

Add optional parameters (defaults keep every current call site unchanged, including the
ride cockpit):

- `selectedStep: Binding<Int?>?`: when set, the selected bar gets a highlight outline
  and the rest dim to 60 %.
- `showsAxis: Bool = false`: draws labels "50 %", "100 %" on the left edge (only when the
  plan has an FTP).
- Interaction, only when `selectedStep` is non-nil:
  - macOS: `.onContinuousHover { phase in … }` → `WorkoutPreview.step(atFraction:)`.
  - iOS: `DragGesture(minimumDistance: 0)` for the same; clear the selection on end.
  - Tooltip: a small overlay callout above the selected bar with the step's
    `name` and `valueText`. Keep it inside the chart bounds.
- Accessibility: when interactive, expose each step as an accessibility child
  (`accessibilityChildren` or `AccessibilityChartDescriptor` via `.accessibilityChartDescriptor`)
  so VoiceOver can swipe through the steps with their value text.

## Sheet (`WorkoutDetailSheet.swift`)

- Chart height 160, `showsAxis: true`, bound to `@State var selectedStep`.
- A **summary line** under the title: total time, "Main set: 5 × 3:00 @ 115 % (288 W)",
  intensity label (existing `IntensityLabel`).
- **Step list**: each row shows a zone-colour swatch (`ZonePalette.color(for:)`), the
  name, then right-aligned `duration`, `% FTP` and `W` in three fixed-width monospaced
  columns. On macOS use a `Grid` so the columns line up. Hovering or tapping a row sets
  `selectedStep`, which highlights the chart bar (two-way link).
- When `detail.needsFTP`: show durations only and keep the existing warning (no %
  without an FTP, as today).

## Tests

- `WorkoutPreview.steps`: % and W for a library workout at 250 W FTP; ramp step text
  (imported plan with `endWatts`); no FTP → percent nil and value text = duration only;
  intensity 90 % scales the watts.
- `step(atFraction:)` hits the right step at the boundaries, 0 and 1.
- `groups` collapses `vo2max-5x3` into one 5× group and leaves `endurance-60` as three
  single steps.

## Out of scope

Editing steps (plan 07).
