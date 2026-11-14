# FTPunk contracts

`portable-archive-v1.schema.json` defines manual transfer between the native and web applications. It is not either application's database schema. The fixture at `../ftpunk_web/tests/fixtures/portable-v1.json` is consumed by both Swift and JavaScript tests; it stays inside the web directory so that directory's test suite remains self-contained.

## Portable archive v1

- Envelope: `format: "ftpunk-portable"`, `version: 1`, ISO-8601 `exportedAt`, `profiles`, `activities`.
- Each activity has `schemaVersion: 1`, `kind: "rampTest"` and the existing native `TestSession` payload. Other kinds and newer versions are rejected until implemented, rather than silently dropped.
- UUIDs are case-insensitive. Browser storage normalizes imported IDs to lowercase. Timestamps carry a timezone; exports use UTC with milliseconds. Measurement offsets and durations are seconds, power is watts, cadence rpm and weight kg.
- `configuration.priorFTP` is an FTP entry object, even though the browser's internal configuration uses numeric watts. The browser adapter resolves the object on import and emits a session-snapshot entry on export. Original target watts and measurement sources remain unchanged.
- Computed FTP values are derived from the stored result, not accepted as independent values. The result's algorithm/version and measurement history remain intact. Importing is not adopting a result as a rider's current FTP.
- Legacy absent measurement metadata follows the existing native defaults. Absent matching metadata means matching off.
- Identity uniqueness, rider references, current FTP references, phase/sample bounds, finite measurements and eligibility of results are additional semantic checks beyond JSON Schema.
- Only ended activities may transfer. Maximum file size is 64 MiB. Input is validated completely before replacement. Archives do not contain credentials, remote pairing secrets or upload jobs.

## Replacement semantics

The review names incoming riders and explains that matching **IDs**, not names, are replaced. All local activities for those identities are replaced with the incoming snapshot, including when the archive contains fewer activities. Unrelated riders remain. An activity ID colliding with a different unrelated local rider rejects the import. Repeated import is idempotent.

Before replacement, native writes a complete portable backup under Application Support/FTPunk/Backups. Browser stores its rollback backup in the same IndexedDB transaction as replacement and retains the latest three. A failed validation, backup write or database transaction must leave the previous history intact. Upload approvals for replaced activities are removed; remote activities are untouched. Rollback is an explicit review/import of the saved file and does not recreate upload approvals.

The first version does not merge divergent profiles or synchronize devices. A later game/workout archive revision must include its durable progress records before those features are advertised as transferable.

## Portable archive v2

`portable-archive-v2.schema.json` adds `workout` and `freeRide` activity kinds,
resolved `training` plans, per-activity `adventureEnabled`/`eligibleMilliseconds`,
and rider-owned `cycleProgress`. Both apps still import v1; exports use v2 when
training or progression is present. Older apps reject v2 explicitly.

Plans contain version 1, kind, name, optional FTP snapshot, and ordered timed
steps (`name`, `seconds`, `watts`). Targets are resolved once using the saved FTP snapshot. The original targets
remain in the plan; individual trainer commands are rounded to its increment.
Intensity scales from those original targets, never from an already scaled value. Free
ERG has one initial target; subsequent target changes are recorded in events.
There is a 24-hour activity cap, 500-step limit, and no FTP result on training
activities. `completed` is the new non-test completion outcome.

Progress version 1 (legacy; see "Story fields are legacy" below) is a map from lowercase activity UUID to its largest credited
millisecond count. Each checkpoint atomically writes the recording and the rider's
credit. Ten XP per minute means one XP per 6,000 ms; remainder survives between
rides. Credits require two consecutive positive selected-power readings no more
than two seconds apart, after pedaling begins. Magnitude does not affect credit;
zeros, gaps, waiting, and mock rides earn none. The Last Light radio and patch
unlock at 1,200,000 ms. Their state is derived from the durable total, so repeated
checkpoints or imports cannot grant them twice. Deleting recordings retains the
ledger. Explicit archive replacement replaces the ledger too; it is not a merge.

`../ftpunk_web/tests/fixtures/portable-v2.json` is consumed by both apps' tests and
includes a deleted activity's retained credit. No credentials or upload approvals
travel in either archive version.


Pause/resume does not add an archive version: timestamped session events record
pause requests, confirmed release, and resume. The recording's elapsed duration
includes paused time. Playback's active clock excludes it. Paused measurements
remain recorded, earn no progress, and cannot bridge credit across resume. After
an application restart, unfinished recordings recover as interrupted; an imported
archive never restarts trainer control.

## Portable archive v3 and workout imports

`portable-archive-v3.schema.json` adds the per-rider offline `workouts` library,
training-plan version 2, and `adventureStartMilliseconds` for stable post-ride
receipts. Both apps import versions 1–3 and export the lowest compatible version.
Old apps reject new archives rather than interpret a resistance ride as ERG.
The shared `portable-v3.json` fixture lives beside the earlier fixtures.

Plan v2 adds optional `endWatts` for linear interpolation over a timed step, and
optional `resistance` for a free ride. Resistance is integer tenths of a unitless
trainer level. Its single step's `watts: 1` is a structural placeholder that must
never be sent as a power command or displayed as a prescribed watt target.
Intensity is 50–150%, adjusted in five-point increments, with timestamped events.
It is not applied to FTP tests or resistance rides. Pauses freeze ramp time.
Training activity snapshots retain the original plan, not a modified library item.

The library holds at most 2,000 normalized workouts, each with a string ID, rider
UUID, source label, save timestamp and immutable plan. IDs from calendar downloads
include account, rider and event identity; downloading again updates that cache
entry. Deleting a cache entry does not change recordings. Archive replacement also
replaces the matching riders' libraries, preserving unrelated riders and rejecting
cross-rider ID collisions. Rollback backups include the library. No credentials,
remote authorization or upload jobs travel in these records.

`workout-example.json` documents the supported import envelope: format
`ftpunk-workout`, version 1, name, optional `ftpWatts`, and steps. A leaf has seconds,
watts, optional endWatts and optional name; a repeat has `repeat` plus nested steps.
Targets are absolute watts; ftpWatts is provenance, not a scaling multiplier.
Files are limited to 2 MiB, 500 expanded steps, four nested repeat levels, 100 repeats
per group and 24 hours total. Imports also accept an Intervals cycling WORKOUT event
with `workout_doc`, timed power steps, ramps and `reps`. Resolved `_power` watts take
precedence; unresolved `%ftp` uses the document FTP or selected rider FTP once.
Unsupported distance, lap-triggered, free/maximal effort and non-power steps reject
the workout. FIT, MRC and ERG files are not supported in this increment.

Zwift `.zwo` files are supported natively (4 November 2026) and in the web app (`ftpunk_web/src/zwo.mjs`, parsed with `DOMParser`; `fixtures/zwo-cases.json` is the shared test).
`workout-example.zwo` shows every supported element. Powers are fractions of FTP and need the
selected rider's FTP (an import without one fails with "Set an FTP first"); watts are rounded
once and stored with that FTP as the plan's `ftpWatts`. `SteadyState` is one step.
`Warmup`, `Cooldown` and `Ramp` are one linear step from `PowerLow` to `PowerHigh` (`PowerLow`
is the start even when a cool-down falls). `IntervalsT` expands to `Repeat` pairs named On and
Off, with `OnPower`/`OffPower` or the ramp forms `PowerOnLow`/`PowerOnHigh` and
`PowerOffLow`/`PowerOffHigh`. `SolidState` is read like a steady or ramp step when it has power.
`FreeRide`, `MaxEffort`, a `SolidState` without power, a `sportType` other than `bike`,
a DTD and malformed XML reject the file; `textevent`, `Cadence` and other metadata are ignored.
Step names are not part of the format: imports name steps Warm-up, Cool-down, Ramp, Steady,
On and Off. Limits are the same as for JSON (2 MiB, 500 expanded steps, 100 repeats, 24 hours).
Export writes `SteadyState` and `Ramp` only (never `IntervalsT`), with powers rounded to three
decimals of the plan's FTP snapshot, or of the rider's FTP when the plan has none.

## Custom workouts (native and web)

Riders can build their own workouts in the native apps (4 November 2026) and in the web app (5 November 2026). Archives
carry them in an optional `customWorkouts` array next to `workouts`, in the same version 3 (a decoder that does not know
the key ignores it). The web app validates the array exactly as native does, keeps every field, stores it in its
`customWorkouts` store, exports it, includes it in the rollback backup and replaces the incoming riders' workouts by
identity on import (unrelated riders keep theirs), so a backup passes native -> web -> native unchanged (the web writes
`null` for an absent rider weight or current-FTP reference where native omits the key; both mean the same). Archives with
custom workouts export as version 3. The shared fixtures are `fixtures/portable-v3-custom.json` (an archive),
`fixtures/custom-workouts-250w.json` (workouts, their validation messages and resolved plans at 250 W, with and without
an FTP) and `fixtures/workout-text-cases.json` (text to blocks or errors, blocks to text); each is written by
`Tests/FTPunkTests/WebWorkoutFixturesTests.swift` and read by the web suite (`ftpunk_web/tests/my-workouts.test.mjs`).

A custom workout has `id`, `riderID`, `name` (1-100 characters), optional `category`, `updatedAt` and `blocks`. A block is
`{"kind":"step","step":{...}}` or `{"kind":"repeats","count":1-100,"steps":[...]}` (one level only). A step has `name`
(empty means unnamed; the plan calls it "Step N"), `seconds` (5 to 14 400), `start` and an optional `end`
(`{"unit":"percentFTP"|"watts","value":n}`; percent is a fraction, 0.30 to 2.50; watts 20 to 1500; a ramp's two ends use
one unit). At most 500 expanded steps, 24 hours and 200 workouts per rider. Percent targets resolve to whole watts with
the rider's FTP when the workout is shown or started, and the resolved plan is what a recording stores. Watt targets
never rescale. Custom workouts never go to Intervals.icu or any server. The text editor reads and writes a documented
subset of the Intervals.icu workout syntax (see `WorkoutText.swift`): steps `- 10m 50%`, `- 3m 200w`, `- 5m ramp 60-40%`,
headers ending in `5x` for repeats, text before the duration as the step name; cadence, heart rate, pace, zones,
distance, ranges and free-ride steps are rejected.

## Story fields are legacy

Neither app has the Lowline story any more (native 2 November 2026, web 5 November 2026). The
story's data stays in the contract so backups round-trip without losing progress:

- `cycleProgress` on a profile (version 1, a map of lowercase activity UUID to credited milliseconds), and the activity
  fields `adventureEnabled`, `adventureStartMilliseconds` and `eligibleMilliseconds`, remain optional, validated exactly as
  described above and **preserved unchanged** through native storage, export and re-import. Native reads them and never
  edits them.
- New native recordings omit all three activity fields and never add credits. A legacy recording that carries them (from
  an older build or the web app) still credits its rider's ledger idempotently when saved or imported, and deleting a
  recording keeps the ledger.
- Archive version selection is unchanged: `cycleProgress` or `adventureEnabled` makes an export at least v2, and
  `adventureStartMilliseconds` makes it v3. A native export with none of them stays at the lowest compatible version.
- The Swift tests `StoryCompatibilityTests` import the shared v2 and v3 fixtures, export, re-import and compare the
  ledger and the session fields.

The earlier text above about beats at 0, 5, 10 and 20 minutes, receipts and ten XP per minute describes the removed
web story and is kept only to explain the data. The web app preserves the same fields: it validates, stores and exports
`cycleProgress` and the three activity fields unchanged, never writes them for new recordings, and still credits the
ledger once for a legacy recording it saves or imports (`ftpunk_web/tests/suite.mjs`, "legacy ledger").

## Scheduled dates and the workout library fixture

`scheduledDate` is an optional field of a cached workout: the local calendar day,
`yyyy-MM-dd`, taken from an Intervals.icu event's `start_date_local`. It is text, not an
instant, so a workout planned for Tuesday stays on Tuesday in any time zone. Archives
and caches written before it existed omit the key and remain valid; those workouts are
listed under Upcoming without a date until the next calendar download updates the same
cache entry. No archive version bump is needed, because the field is optional and
readers that do not know it ignore it. Imported files never have one. Native validation
rejects a present value that is not a real calendar day.

`fixtures/workout-library-250w.json` lists every classic workout of the built-in
library (UX plan §5) resolved at an FTP of 250 W: id, name, category
(`endurance`, `tempo`, `sweetSpot`, `overUnders`, `threshold`, `vo2max`), total
`durationSeconds` and the ordered steps (`name`, `seconds`, `watts`, optional `endWatts`).
Targets are percentages of FTP rounded to whole watts, before any trainer increment is
applied. Every workout except the three original starters (Easy spin, Endurance 30,
Tempo 3×5, which keep their exact steps) has a flat 10 minute warm-up at 50 % and a flat
5 minute cool-down at 50 % (no ramps, decision of 3 November 2026); recoveries are at 50 % and sit between
efforts. The Swift test `workoutLibraryMatchesTheSharedFixtureAt250Watts` fails if the
catalog and the file drift apart; regenerate with
`FTPUNK_WRITE_FIXTURES=1 swift test --filter workoutLibraryMatchesTheSharedFixtureAt250Watts`.
The web port should copy the file next to its other fixtures so its suite stays
self-contained, and compare its own catalog against it (done: `ftpunk_web/tests/library.test.mjs`).

`fixtures/workout-preview-250w.json` is what the workout preview shows for each of those workouts at 250 W: total
duration text, intensity label, `mainSetText` (values on, off and at 110 %), the step texts (`valueText`, spoken text, zone)
with values on, off and at 110 %, the repeat groups of the compact list and the profile bars (fractions rounded to six
decimals). The Swift test `workoutPreviewMatchesTheSharedFixtureAt250Watts` fails on drift; regenerate with
`FTPUNK_WRITE_FIXTURES=1 swift test --filter workoutPreviewMatchesTheSharedFixtureAt250Watts`. The web copies both fixtures to
`ftpunk_web/tests/fixtures/`; `python3 ftpunk_web/tools/test.py` fails if a copy differs from `contracts/fixtures/`.

Free rides can change mode without replacing the original plan. Timestamped events
`Free ride mode: resistance <tenths-level>` and `Free ride mode: ERG <watts> W` record
acknowledged transitions; target reconstruction suppresses ERG targets during resistance
spans and preserves earlier targets. Existing pause/resume and ERG target events still apply.
