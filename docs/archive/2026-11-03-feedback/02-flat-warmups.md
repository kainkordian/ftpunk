# 02 — Flat warm-up and cool-down in built-in workouts

The owner doesn't want rising or falling steps in the default workouts. Every built-in
workout should start with a plain, constant warm-up at 50 % FTP.

## File

`Sources/FTPunkDomain/WorkoutLibrary.swift`

## Change

```swift
private static let warmup   = Step("Warm-up",   10, 0.50)   // was 0.50 → 0.70
private static let cooldown = Step("Cool-down",  5, 0.50)   // was 0.60 → 0.40
```

- The cool-down becomes flat too ("remove the rising and falling intervals"). Use 50 %;
  if the owner later wants a lower cool-down, it's a one-number change.
- Check that no other catalog entry uses `to:`. `grep -n "to:" WorkoutLibrary.swift` after
  the edit should only match the `Step` initialiser itself.
- The three starters (`easy-spin`, `endurance-30`, `tempo-3x5`) already have flat steps
  but warm up at 45–50 % and cool down at 40 %. Set their warm-ups to 0.50 for
  consistency. Leave their other steps alone.
- Update the doc comment above `WorkoutLibrary` (it describes the 50→70 / 60→40 ramps).
- `RetargetExample.make` filters `endWatts == nil` to skip ramps. After this change,
  warm-up and cool-down are also constant, so the filter is redundant but harmless. The
  max-watts selection still picks the main set. Fix the stale comment.

## Not in scope

- `TrainingPlan` must keep supporting ramps (`endWatts`): imported and Intervals.icu
  workouts can contain them, and old recordings use them.
- The FTP test's own warm-up is already constant (`SessionConfiguration.warmupPower`).
  Don't touch it.

## Tests

- `Tests/FTPunkTests/WorkoutLibraryTests.swift:27` expects
  `.init("Warm-up", seconds: 600, watts: 125, endWatts: 175)`. Change it to
  `.init("Warm-up", seconds: 600, watts: 125)`.
- Add a test: for every `WorkoutLibrary.catalog` definition, every step has `to == nil`,
  and the first step is named "Warm-up" at 0.50.
- `swift test` passes.
