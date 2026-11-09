# FIT uploads, training-load fields and RR intervals

Owner asked for this on 2026-11-09. Native app and web app change together, and the two FIT encoders must stay byte-identical.

Goal: Intervals.icu receives the FIT file, so simulated distance, speed, calories, work and pedal balance reach it. The FIT file also gains
normalized power, TSS, IF and heart-strap RR intervals.

Out of scope: the ramp protocol, ramp scoring and the 72 % factor; TCX, CSV and JSON exports (they stay as they are); new charts or dashboard tiles;
live uploads to a real account.

## 1. Upload FIT instead of TCX

Today: `UploadWorker.enqueue` stores `ActivityExport.tcx(session)` in the job, `IntervalsClient` hard-codes a `.tcx` filename and the TCX media type.
On web, `intervals.mjs` stores `tcx(session)` in `job.file` and names the part `${sessionID}.tcx`.

- New jobs carry `FITEncoder.fileData(session)` / `fitFile(session)`.
- Jobs already queued hold TCX. They must still upload correctly, so name the upload from its content, not from a new stored field. Add one pure,
  tested function on each platform: bytes with `.FIT` at offset 8 are `<id>.fit` with `application/octet-stream`, anything else is `<id>.tcx` with the
  existing TCX type. Web: `job.file` is a `Uint8Array` for FIT and a string for old jobs; IndexedDB stores both. Check the job survives the store
  round trip and any code that assumes a string (sizes, backup, rendering).
- `external_id`, `name`, `description` and `device_name` stay the same, so an activity already uploaded is not duplicated by a retry.
- `description` already carries what TCX notes carried; check nothing in the upload path relied on TCX-only content.
- Rides the FIT encoder refuses (`notFinalized`, `emptyActivity`) must fail the same way the TCX path did: a visible error, no queued broken job.
- Update user-visible copy that says uploads are TCX, if any (`grep -i tcx App ftpunk_web/src`). Export buttons keep offering TCX.

## 2. Normalized power, TSS and IF in the FIT file

Field numbers confirmed against FIT profile 21.221:

| Message | Field | Type | Scale |
| --- | --- | --- | --- |
| session (18) | 34 normalized_power | uint16 | 1 |
| session (18) | 35 training_stress_score | uint16 | 10 |
| session (18) | 36 intensity_factor | uint16 | 1000 |
| lap (19) | 33 normalized_power | uint16 | 1 |

- Add a pure function next to `RideSummary.normalizedPower` (web twin in `rules/ride-summary.mjs`) that returns NP, IF and TSS for a session.
  FTP is `configuration.priorFTP`. No FTP means IF and TSS are invalid, not 0. Under 30 seconds of riding means NP is invalid.
  `IF = NP / FTP`, `TSS = seconds × NP × IF / (FTP × 3600) × 100`, where `seconds` is ridden seconds (`RideTrack.points.count` / `track.seconds`).
- Paused samples must not count. Samples keep arriving during a pause, so filter them with `RidePause` first. Apply the same filter to the NP shown in
  `RideSummary` so the card and the file agree (the current card includes paused samples: a small existing bug).
- `pow(x, 0.25)` is not guaranteed identical across platforms. Use `sqrt(sqrt(x))` in both NP implementations.
- Lap NP: only the lap's own unpaused samples; invalid under 30 seconds.

## 3. RR intervals

FIT message `hrv` (78), field 0 `time`: uint16 **array**, scale 1000, seconds.

- Decode RR in the Heart Rate Measurement (flag 16, little-endian uint16 values in 1/1024 s) on both platforms. Native `HeartRateMeasurement.decode` and web
  `heartRate` currently skip them. Keep the existing heart-rate result and its tests working; malformed packets are still rejected.
- Add `RideSample.rrIntervals: [Double]?` in seconds (web `rrIntervals`), set only when the packet has any. Route through `DeviceReading` / `route()`.
  Add it to `contracts/portable-archive-v3.schema.json`. Old sessions decode unchanged.
- Add array support to both FIT writers. A local message's definition is fixed, so write `hrv` with a fixed 5-element array (2 bytes each, size 10),
  padding with the uint16 invalid value, and split longer lists over several messages.
- Each `hrv` message goes right after the record for that sample's second, in time order. Paused samples are left out. A second with RR but no record
  has no `hrv` either. Values round to milliseconds and are capped at 65534.
- `MockRideStream` and `mockSample` provide one RR value from the heart rate, so demo rides exercise it.

## Tests and fixtures

- Swift Testing and web tests for: content-based naming (FIT, TCX); upload body or form carrying a `.fit` part; a queued TCX job still uploading as TCX;
  NP, IF and TSS including no-FTP, under-30-seconds and paused samples; RR decoding including several values and malformed packets; `hrv` array padding
  and splitting; decoded FIT fields (session 34, 35, 36; lap 33; message 78).
- Add RR values to the FTP-test fixture in `FITFixtureTests`, regenerate with `FTPUNK_WRITE_FIXTURES=1 swift test --filter fitFilesMatchTheSharedFixtures`,
  then copy the `fit-*` files from `contracts/fixtures/` to `ftpunk_web/tests/fixtures/`.

## Done

- `swift test`, both `xcodebuild` CI builds from AGENTS.md, and `CI=true python3 ftpunk_web/tools/test.py` pass.
- `ftpunk_web/sw.js` cache version bumped; any new runtime web file added to `ASSETS`.
- `docs/ROADMAP.md`: "Where it stands" updated, and the two Parked items covered here removed ("Switch the activity upload from TCX to FIT" and the
  RR/NP/TSS/IF line). This plan moved to `docs/archive/`.

Stays unverified after this plan: a real upload to Intervals.icu, and RR from a real strap.
