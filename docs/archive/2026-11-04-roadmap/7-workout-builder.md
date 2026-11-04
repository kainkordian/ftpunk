# 7 — Workout builder (decided, ready to implement)

The owner's decisions (2026-11-04):

1. Targets in **% FTP and in absolute watts**, per step.
2. **Ramps are allowed** (the owner dislikes them in the built-in warm-ups, but wants the option).
3. Custom workouts **stay local** (plus backup). No Intervals.icu push in this plan.
4. **iPhone and Mac** both get the editor.
5. **Both editors**: a block editor and a text editor in Intervals.icu workout syntax, with a
   **toggle to switch between them** at any time.

Prerequisites already done: the `WorkoutPreview` model and interactive chart (archived plan 03). next/6 (ZWO export)
is optional, but custom workouts should plug into it if it exists.

## What it is

Riders create their own structured workouts in the app. They appear in the library next to the
classics and imported/Intervals.icu workouts and start like any other workout.

## Model (`Sources/FTPunkDomain/CustomWorkout.swift`)

```swift
public struct CustomWorkout: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var riderID: UUID
    public var name: String
    public var category: WorkoutCategory?
    public var blocks: [Block]
    public var updatedAt: Date
    public enum Block: Codable, Equatable, Sendable {
        case step(Step)
        case repeats(count: Int, steps: [Step])   // one level of nesting only
    }
    public struct Step: Codable, Equatable, Sendable {
        public var name: String
        public var seconds: Double                // 5 s … 4 h
        public var start: Target
        public var end: Target?                   // nil = constant; non-nil = linear ramp
    }
    public enum Target: Codable, Equatable, Sendable {
        case percentFTP(Double)                   // 0.30 … 2.50
        case watts(Double)                        // 20 … 1500
    }
    public func plan(ftp: Double?) throws -> TrainingPlan
}
```

- `start` and `end` of one step must use the **same unit** (no ramp from 150 W to 80 %).
  Enforce in validation and in the editor.
- `plan(ftp:)` flattens repeats and resolves `.percentFTP` with the FTP passed in
  (throws `needsFTP` if a % step exists and `ftp` is nil). `.watts` steps never rescale.
  Ramps become `watts`/`endWatts` steps (plan version 2 already supports `endWatts`).
- Validation limits match `TrainingPlan`'s (500 expanded steps, 24 h, 100 repeats).
- A workout with only watt targets starts without an FTP. One with % steps needs the rider's
  FTP, and the library card says "Needs FTP" otherwise.

## Intervals.icu text syntax (`Sources/FTPunkDomain/WorkoutText.swift`)

Pure parser and printer, no UI. Support a **documented subset** and nothing guessed:

```
Warm-up
- 10m 50%
Main set 5x
- 3m 115%
- 3m 55%
Ramp down
- 5m ramp 60-40%
Sprint
- 20s 650w
```

- A line starting with `- ` is a step: `<duration> <target>`. Duration `h`, `m`, `s`
  (combinable, `1m30s`). Target `NN%` (% FTP), `NNw` (watts), `ramp A-B%` / `ramp A-Bw`.
  An optional text before the duration or after the target is the step name is **not**
  supported; the name is the preceding header line. Unsupported tokens (cadence, HR, `%HR`,
  `pace`, zones like `Z2`, distance, `ftp` keywords) produce an error that names the line.
- A non-step line is a header. Header + `Nx` ("Main set 5x") starts a repeat group of the
  following steps up to the next blank line or header. A header without `Nx` names
  the single step below it. Blank line ends a group.
- Printer output must parse back to an equal `[Block]` (`parse(print(blocks)) == blocks`),
  for every valid workout, including steps with `name` equal to the default.
- Before implementing, **check Intervals.icu's documented syntax** (the owner's account is
  connected: read `https://forum.intervals.icu/t/workout-builder/1163` or the in-app syntax
  help) and adjust the grammar above to match where it differs. List differences in
  your report. Import of text pasted from Intervals.icu workouts should work for this subset.

## Editor UI (`App/Features/Builder/`)

One screen, two modes, switched by a **segmented control "Blocks | Text"** at the top.

- **Blocks mode**:
  - live profile chart (`WorkoutPreview`) on top, block list below;
  - step row: name, duration (m:ss field + stepper), target (unit toggle **% FTP | W**, value
    field with a 5-unit stepper), optional ramp (toggle "Ramp", second value), read-only
    equivalent (watts at current FTP, or % of FTP), zone colour;
  - repeat block: "× N" stepper containing step rows;
  - add step / repeat, duplicate, delete, drag to reorder;
  - quick-add presets: "Warm-up 10 min @ 50 %", "Cool-down 5 min @ 50 %", "Recovery".
- **Text mode**: monospaced editor, no autocorrect/autocapitalise, live parse. Errors appear
  inline under the editor with the line number, and the chart shows the last valid parse
  (greyed) so the rider sees what they have.
- **Switching**: Blocks → Text prints the blocks (always works). Text → Blocks parses. If there
  are errors, **stay in Text mode** and show "Fix line 4 first: …", never discard text.
  The text is the editor state while in Text mode and blocks are the state in Blocks mode, so
  neither converts lossily. Remember the last-used mode per device (`@AppStorage`).
- Selecting a row highlights its chart bar and the other way round (same binding as the workout detail chart).
  Not available in Text mode (highlight the line instead if simple, otherwise skip).
- Summary: total time, estimated IF/TSS (needs FTP; for watt steps use FTP, say "estimated"),
  main set line.
- Save is disabled until valid. Reasons are shown inline. Unsaved changes ask before closing.
- **Layout**: iPhone = one column (chart on top, editor below, collapsible chart in the
  keyboard-open state). Mac and iPad ≥ 900 pt = two columns (editor | chart + summary).
  Dynamic Type and VoiceOver: every control labelled, the segmented control and the step
  fields reachable, text mode must be usable with large text.
- Entry points: "New workout" in the library, "Duplicate & edit" in `WorkoutDetailSheet`
  (any workout whose plan can be expressed in blocks; imported ones become watt steps),
  "Edit" and "Delete" for custom workouts. Pasting text on the library screen offers
  "Create workout from text".

## Storage and backup

- `LocalStore`: per-rider custom workouts, stored like `CachedWorkout` (look at how it's
  done and mirror it). Max 200 per rider.
- `PortableArchive`: add as an **optional** `customWorkouts` field, so old archives load. Check
  whether an older build's decoder ignores the unknown key, and if not bump the archive
  version following the rules in `contracts/README.md` (lowest compatible version rule), update
  the schema and fixture notes. Add an archive round-trip test and update `contracts/README.md`
  ("Custom workouts: native only for now; the web app preserves/ignores them").
  Never send custom workouts to Intervals.icu or any server.

## Library integration

- `WorkoutRef` gets `.custom(UUID)`. `model.workoutDetail(for:)` handles it.
- Library gets a "My workouts" section/filter. Cards show % or W targets, total time and a flat/ramp preview.
- Starting one snapshots `plan(ftp:)` into the session, like classics. Later edits never
  change recordings.
- Chaindance, the preview scenarios and `ShellAndScenarioTests` need no change, but add
  scenarios `builder-blocks` and `builder-text` to `PreviewScenarios` (and the simulator matrix list).

## Tests

- `CustomWorkout`: flattening, `plan(ftp:)` for % and watts, ramps, mixed units rejected, `needsFTP`,
  limits, Codable round trip.
- `WorkoutText`: every syntax form above, error lines for each unsupported token, print/parse
  round trip over a generated set (property-style loop with a seeded generator), pasted
  Intervals sample.
- Conversion of every `WorkoutLibrary.catalog` definition to blocks and back → identical
  `TrainingPlan`, and to text and back.
- Archive round trip and an old-archive load. Store tests for add/edit/delete per rider.
- Mode switching as a pure view-model test (`BuilderState`): errors keep Text mode, success switches,
  nothing lost.

## Rules

Follow `AGENTS.md`. Don't open the app or take screenshots without asking the owner.
Don't change scoring or the 72 % factor. Report anything unverified (especially the syntax check).

## Later (not in this plan)

Push to Intervals.icu, cadence targets, free-ride segments, sharing files between riders (ZWO
export from next/6 already covers that).
