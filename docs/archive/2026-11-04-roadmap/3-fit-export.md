# 3 — Export finished activities as FIT (for COROS and others)

The owner wants to download finished activities as `.fit` files and upload them by hand
to COROS. Today an activity exports as TCX, CSV or JSON
(`Sources/FTPunkStorage/ActivityExport.swift`, buttons in
`App/Features/Progress/ActivityDetailView.swift`). There is no FIT.

## Why manual, and what to tell the rider

- COROS has no public way for a third-party app to push activities. Its API is for
  approved partners only. The "unofficial" Training Hub API needs the rider's COROS
  password, can break at any time and is against the spirit of their terms. **Don't
  build it.**
- Intervals.icu imports *from* COROS and sends *planned workouts* to COROS. It does not
  send finished activities to COROS. So there's no automatic route through Intervals.
- COROS Training Hub (web) → Activity List → **Import Data** accepts `.fit` and `.tcx`.
  Per COROS support, files must be **20 KB – 200 MB**.

## A. FIT encoder (`Sources/FTPunkStorage/FITEncoder.swift`, pure, no dependencies)

Write a minimal FIT *activity* file encoder. Don't add a package dependency.

- Little-endian architecture, normal record headers, one local message type per global
  message (redefine when needed). 14-byte file header (protocol 2.0 `0x20`, profile
  version e.g. 21.xx, data size, `".FIT"`, header CRC) and a trailing file CRC-16. Use the
  CRC algorithm from the FIT SDK (nibble table).
- FIT timestamps are seconds since 1989-12-31 00:00:00 UTC (Unix − 631 065 600).
- Messages, in this order:

| Message (global #) | Fields |
|---|---|
| `file_id` (0) | type = 4 (activity), manufacturer = 255 (development), product = 1, serial_number, time_created |
| `event` (21) | timer start at the first sample |
| `record` (20) | one per sample: timestamp (253), heart_rate (3, u8), cadence (4, u8), power (7, u16). Omit a field (use the FIT invalid value) when the sample has no value; never write 0 for "missing". |
| `event` (21) | timer stop/start at each pause and resume (see below) |
| `lap` (19) | one per phase, using the same boundaries as `ActivityExport.tcx` (warm-up / ramp / cool-down for tests; one per training step for workouts if the plan has ≤ 100 steps, otherwise one lap) |
| `session` (18) | sport = 2 (cycling), sub_sport = 6 (indoor_cycling), start_time, total_elapsed_time, total_timer_time, avg/max power, avg/max heart rate, avg/max cadence, num_laps, threshold_power = the session's prior FTP if known |
| `activity` (34) | total_timer_time, num_sessions = 1, type = 0 (manual), event = 26, event_type = 1, local_timestamp |

- **Check every field number and base type against the FIT SDK profile** (Profile.xlsx
  from developer.garmin.com/fit). The numbers above are from memory. If you can't reach
  the SDK, keep them and list them as unverified in your report.
- Pauses: the session events record pause requests, confirmed release and resume
  (`contracts/README.md`, "Pause/resume"). Find how they're stored. Write timer stop
  at the confirmed release and timer start at resume, and exclude paused time from
  `total_timer_time`. If the events can't be mapped reliably, use elapsed time for both
  and say so.
- Same preconditions as TCX: `ExportError.notFinalized` / `.emptyActivity`.
- **Don't change scoring, and don't invent data.** Indoor distance and speed are
  unmeasured. Leave them out. Don't pad files to reach a size.
- Demo sessions export too, but the file name starts with `DEMO-`.

### Tests (`Tests/FTPunkTests/FITExportTests.swift`)

Write a small FIT *decoder* in the test target, just enough to read headers, definitions
and data messages. Then:

- Header size 14, `".FIT"`, data size matches, header CRC and file CRC are valid.
- Round trip: record count = sample count, timestamps, power/cadence/HR values, missing
  values decode as invalid.
- Lap count and boundaries match the TCX laps for a ramp test session fixture.
- Session totals: elapsed vs timer time with a paused workout fixture.
- Sport/sub-sport are cycling/indoor_cycling, and threshold_power is the prior FTP.
- Not finalized / empty → throws.
- If `python3 -c "import fitdecode"` or `fitparse` happens to be available on the
  machine, also decode one generated file with it **in the scratchpad**, as an extra
  check. Don't add it as a project dependency, and don't install packages globally.

## B. Export UI

`ActivityDetailView` "Export" section:

- Primary row: **"Export FIT file"** with the caption "For COROS, Garmin, Strava and
  TrainingPeaks". Below it, a secondary `Menu("Other formats")` with TCX, CSV and JSON.
  Remove the three separate "Prepare … file" buttons.
- Saving: use `.fileExporter` (a small `FileDocument` wrapper around `Data`) on **both**
  platforms. On macOS that's the native Save panel, and on iOS it's Files. Keep
  `ShareLink` as well on iOS (AirDrop, Mail). File name:
  `FTPunk-yyyy-MM-dd-<activity title>.fit` (sanitise to `[A-Za-z0-9-]`).
- After a FIT export, show a footer: "COROS: open Training Hub → Activity List → Import
  Data and choose this file." and a `Link("Open COROS Training Hub", destination:
  URL(string: "https://t.coros.com")!)`. **Flag the URL for the owner to verify.**
- If the generated FIT is smaller than 20 KB, add one line: "COROS may reject files
  under 20 KB. If it does, export TCX instead." (TCX is larger for the same ride.)
- Also offer "Export FIT file" on the post-ride result screen (find it under
  `App/Features/`). It uses the same code path.
- `AppModel.export(_:kind:)`: add `"fit"`. Better: replace the string `kind` with an
  `enum ActivityFileFormat: String, CaseIterable { case fit, tcx, csv, json }` and
  update the callers.

## Not in this plan

- The Intervals.icu upload stays TCX. Switching it to FIT is a separate decision.
- No COROS account connection.

## Owner checks (deferred)

Upload one ramp test FIT and one workout FIT to COROS Training Hub by hand. Check
power, cadence, HR, laps and "Indoor Bike" as the sport. Then check that the same FIT
uploads to Intervals.icu.
