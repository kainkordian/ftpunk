# Plan 9c: web "My workouts" (ZWO import/export and the workout builder)

**Runs after plan 8 is merged, in parallel with 9a and 9b.** Size: L.
Read "The web parity project" in [8-web-foundation.md](../archive/2026-11-05-web/8-web-foundation.md) first; its rules apply here.

## Files this plan owns

May edit: `src/workouts.mjs`, new `src/zwo.mjs`, new `src/custom-workouts.mjs`, new `src/workout-text.mjs`,
new `src/builder-state.mjs`, `src/archive.mjs`, `src/ui/library.mjs`, the "My workouts" placeholder in
`src/ui/home.mjs`, new `src/ui/builder.mjs` (+ CSS), this plan's block in `src/ui/scenarios.mjs`, its own tests
and fixtures. Native side: new Swift test files only.
`storage.mjs`: add read/write functions for the `customWorkouts` store plan 8 created; don't change the schema.
Register the builder route with `registerRoute` from `shell.mjs`; don't edit the shell otherwise.

## 1. ZWO import and export

Port `ZWOImport.swift` and `ZWOExport.swift` to `src/zwo.mjs`; the rules are in `contracts/README.md` (ZWO paragraph).
Parse with `DOMParser` (`application/xml`); reject `parsererror`, any DOCTYPE, `sportType` other than bike, and the
unsupported elements as native. Copy `contracts/workout-example.zwo` to the web fixtures.

- Port every case in `ZWOTests.swift`. Add a Swift test that writes `contracts/fixtures/zwo-cases.json` (input file name
  or inline XML, FTP, expected resolved plan or error message, and the exported XML for a few plans) and compare in JS.
- Import from the library section (file picker accepts `.json` and `.zwo`); export from the workout detail
  ("Export as ZWO").

## 2. Custom workouts and the builder

Port, with their tests (`WorkoutBuilderTests.swift`):

- `CustomWorkout.swift` → `src/custom-workouts.mjs` (model, validation limits, resolve to a plan with the rider's FTP,
  % FTP and watts, ramps, one level of repeats, 200 per rider);
- `WorkoutText.swift` → `src/workout-text.mjs` (the documented Intervals.icu subset, parse and format, the same error
  messages);
- `BuilderState.swift` → `src/builder-state.mjs` (blocks ↔ text switching, undo-safe edits, dirty state).

**Parity fixture:** a Swift test writes `contracts/fixtures/workout-text-cases.json` (text → blocks or error, blocks → text)
and `contracts/fixtures/custom-workouts-250w.json` (custom workouts → resolved plans at 250 W). JS must match exactly.

**Builder screen** (native `App/Features/Builder/BuilderView.swift`): name, Blocks / Text toggle with the header staying
put when switching, block editor (add step, add repeats, reorder, duplicate, delete; duration, start/end target, unit
% FTP or W), text editor with inline error line, live profile chart and total duration, Save / Cancel with a
discard confirmation. Works with keyboard only and at 390 px wide.

**My workouts section** (native `MyWorkoutsSection` in `WorkoutLibrarySection.swift`): title plus the three actions
"New workout", "Paste as text", "Import file…" as buttons (not a menu; they wrap on narrow screens), the rider's
custom workouts as cards (edit, duplicate, export ZWO, delete with confirmation), and in the empty state a
"Get an example JSON file" link. Starting a custom workout goes through pre-flight like any workout.

## 3. Archive

`customWorkouts` in portable v3 exactly as `contracts/README.md` → "Custom workouts" describes: validate, store,
export (forces v3), import replacing by id and preserving unrelated riders, included in the rollback backup. Add a
shared fixture `contracts/fixtures/portable-v3-custom.json` written by a Swift test and read by both suites. Then
update the README sentence that says the web drops them.

## 4. Scenarios

Add `home-my-workouts`, `home-my-workouts-empty`, `builder-blocks`, `builder-text-error`.

## Acceptance

- `python3 tools/test.py` and the native `swift test` plus both builds pass.
- ZWO, workout-text and custom-workout fixtures match; a v3 archive with custom workouts round-trips
  native → web → native unchanged.
- Custom workouts never leave the device except in a backup the rider exports.

## Report

Test counts, fixture results, deviations from native, and what wasn't looked at on a screen.
