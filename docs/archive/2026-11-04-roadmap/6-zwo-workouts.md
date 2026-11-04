# 6 — ZWO workout import and export

The owner asked why workouts are JSON and not FIT or ZWO. The answer:

- The built-in workouts are **Swift code** (`Sources/FTPunkDomain/WorkoutLibrary.swift`),
  not files.
- `contracts/fixtures/workout-library-250w.json` is a **test fixture**. It lets the
  web port prove it builds exactly the same workouts. It's not a workout file format.
- `ftpunk-workout` JSON exists only as a minimal import format next to Intervals.icu
  events. ZWO, FIT, MRC and ERG are explicitly "not supported in this increment"
  (`contracts/README.md`).

ZWO (Zwift's XML) is the de-facto exchange format for structured indoor workouts. Most
sites and coaches offer it, and Intervals.icu imports and exports it. FIT *workout*
files are mainly for head units and watches, and they're binary. Do ZWO now and leave
FIT workouts for later.

## A. Import (`Sources/FTPunkDomain/ZWOImport.swift`)

- Parse with Foundation `XMLParser`, which works on iOS and macOS. Same limits as
  `WorkoutImport`: 2 MiB, 500 expanded steps, 24 h, 100 repeats.
- `<workout_file>`: `name`, optional `description`, `sportType` must be `bike` or
  absent. `<workout>` children, in order:

| Element | Becomes |
|---|---|
| `SteadyState Duration Power` | one step, `watts = Power × FTP` |
| `Warmup` / `Cooldown` / `Ramp Duration PowerLow PowerHigh` | one step with `watts`/`endWatts` (linear) |
| `IntervalsT Repeat OnDuration OffDuration OnPower OffPower` (also `PowerOnLow/High`, `PowerOffLow/High` → ramps) | expanded on/off pairs, named "On"/"Off" |
| `FreeRide`, `MaxEffort`, `SolidState` without power | **reject** with a clear message (same rule as Intervals: no guessed watts) |
| `textevent`, `Cadence*`, `pace`, `tags`, `author` | ignored |

- Powers are fractions of FTP, so import needs the selected rider's FTP. Without an
  FTP, show an error ("Set an FTP first"). Store the resolved plan with the FTP
  snapshot (`TrainingPlan` already has one). Same rules as Intervals `%ftp`.
- Hook it into the existing import path in `WorkoutLibrarySection`. Pick the parser by
  extension or root element. `fileImporter` allowed types: add
  `UTType(filenameExtension: "zwo", conformingTo: .xml)` and keep JSON.

## B. Export (`Sources/FTPunkDomain/ZWOExport.swift`)

- Any classic, cached or imported workout → `.zwo`: a step with `endWatts` becomes
  `Ramp`, otherwise `SteadyState`. Power = watts ÷ FTP, using the plan's FTP snapshot
  if it has one, otherwise the rider's FTP, rounded to 3 decimals. Don't try to fold
  steps back into `IntervalsT`.
- Escape XML. `sportType` = `bike`. Put `author` = "FTPunk".
- UI: "Export as ZWO" in `WorkoutDetailSheet` (`fileExporter`, as in next/3-fit-export.md).

## C. Contracts

Update `contracts/README.md` ("ZWO, FIT, MRC and ERG files are not supported"): ZWO is now
supported natively, and the web port should follow. Add `contracts/workout-example.zwo`
covering every supported element.

## Tests

- Parse the example: expanded steps, watts at FTP 250, ramps.
- Reject FreeRide/MaxEffort, a non-bike `sportType`, malformed XML, and files over the limits.
- Round trip: every `WorkoutLibrary.catalog` workout → ZWO → import at the same FTP gives
  the identical `TrainingPlan` (to ±1 W from rounding).

Relationship to next/7 (builder): custom workouts export through the same code.
