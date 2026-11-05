# FTPunk roadmap

The single source of truth for what FTPunk is, where it stands and what comes next.
Updated 2026-11-05. If this file and an archived plan disagree, this file wins.

## What FTPunk is

A native iPhone and Mac app for **FTP ramp tests** on a smart trainer (Elite Suito-T, ERG),
with an optional external power meter (Favero Assioma) and heart-rate strap. Around the test:
structured workouts, free ERG / resistance rides, history and progress, optional Intervals.icu
upload and calendar download, and Chaindance, the night-city ride visual.

Fixed principles:

- **The FTP test is the core feature.** Everything else connects to it and must not weaken it.
  The estimate stays **72 % of the best minute**. Never change it to 75 %.
- Offline first. Data is local per device. Transfer is a manual portable backup
  (`contracts/`). Nothing goes to a server unless the rider confirms it.
- The trainer is only ever controlled by the ride engine. Visuals, imports and integrations
  never send trainer commands.

## Where it stands (2026-11-05)

Built and covered by tests (306 Swift tests, iOS + Mac builds pass):

- FTP test (three ramp presets, warm-up/cool-down, scoring, adopt result), workouts (classic
  library with flat warm-ups, Intervals.icu calendar, JSON and ZWO import, ZWO export, % FTP / W preview), free ERG,
  resistance, pause/resume.
- Home / pre-flight / cockpit / result / Progress / Settings layout (UX rework, 2026-11-02).
- Devices: trainer required, power meter and HRM optional; power matching estimates the trainer's error live
  (gain + offset against its reported power, warmth in kJ, fade guard); replay test for real CSVs.
- Intervals.icu: API key and OAuth (asks for `SETTINGS:READ`; confirm on the next real sign-in), one
  connection per rider, a consent sheet after every finished ride (per-rider toggle, never silent),
  confirmed TCX upload queue, calendar download, FTP and weight sync (field names verified against a
  live account), explicit User-Agent on every request.
- **Chaindance** (the ride visual): standing sprint; strip and Large modes. Large is a taller raster (96 rows: extra
  sky with stars, moon and tower tips, the readout in the sky band, a two-column layout on wide windows). The strip is
  pixel-identical to before (fingerprint test). Not looked at on a screen yet.
- Activity export: FIT (own encoder, field numbers checked against FIT profile 21.221; decoded with fitdecode/fitparse),
  TCX, CSV, JSON from the activity detail and the result screen; save panel / Files plus Share on iOS.
- **Workout builder:** the riders' own workouts as blocks or text (a documented subset of the Intervals.icu syntax), % FTP and
  watts, ramps, one level of repeats; local per rider, in backups as an optional `customWorkouts` key (web app ignores it).
- Portable archives v1–v3, shared with the web app.

- **Web app foundation (plan 8, 2026-11-05):** `ftpunk_web/` now has the native structure: Home, pre-flight, cockpit, result, Progress and
  Settings (sidebar or tab bar), onboarding, the 14 classic workouts with flat warm-ups, the workout detail sheet and preview texts (both equal to
  Swift-written fixtures in `contracts/fixtures/`), retest advice and start blockers ported from `Sources/FTPunkDomain`, IndexedDB version 4
  (`customWorkouts`, `credentials`, `riderSettings` for the next plans), preview scenarios (`?scenario=`) and a capture tool (built, never run). The story is
  gone from the UI; its fields are preserved in archives. New FTP tests always use 72 %. Tests run in real headless Chrome with
  `python3 ftpunk_web/tools/test.py` (158 tests, no Node; CI runs it before the Pages deploy). Still old on the web: the power matcher, the ride visual,
  Intervals.icu per rider, FIT export, ZWO and the workout builder (plans 9a-9c).

**Not verified yet:** none of the seven roadmap plans has been looked at on a screen (Chaindance Large, the builder, the
Settings changes, the export controls), and the save panel / Files behaviour of `fileExporter` is untested. A FIT file has been decoded
with fitdecode and fitparse but not uploaded to COROS; the Intervals.icu `SETTINGS:READ` scope is unconfirmed on a real
consent screen. The XCUITests have never run. No VoiceOver, Increase Contrast or keyboard
pass has been done. Nothing has run on a real trainer, iPhone or meter (see
[DEVICE_CHECKS.md](DEVICE_CHECKS.md)). The iOS Simulator screenshot matrix hasn't been run for
the latest screens. The web app (`ftpunk_web/`) has the same caveat: its new screens have been checked only by DOM and layout-bound tests in headless Chrome, never looked at.

**Repository:** the whole working tree was committed as one baseline on 2026-11-04 and is published as
`kainkordian/ftpunk` (the earlier web-only app is kept at tag `web-v1`). GitHub Pages serves `ftpunk_web/` through `.github/workflows/pages.yml`.

## Next steps

The seven plans of milestones A–C were implemented on 2026-11-04 and archived in [`archive/2026-11-04-roadmap/`](archive/2026-11-04-roadmap/). Milestone D (web parity) is ready in `next/`.

### Step 0: baseline commit (done 2026-11-04)

Commit the current working tree as one baseline after the owner has looked at `git status`.
Every later step then gets its own reviewable commit, and only when the owner asks.

### Milestone A: a test you can trust and take with you

| # | Plan | Size | Why now |
|---|------|------|---------|
| 1 | Intervals.icu per rider + upload prompt after every ride (done, [archived](archive/2026-11-04-roadmap/1-intervals-per-rider.md)) | M | Today one account serves all riders, and upload is a button you have to find |
| 2 | Power matching: estimate the trainer's error live, never chase a fading rider (done, [archived](archive/2026-11-04-roadmap/2-power-matching.md)) | M | The trainer's error changes with calibration, temperature and load. Today's matcher also adds load when a rider fades. |
| 3 | FIT export (COROS, Garmin, Strava) (done, [archived](archive/2026-11-04-roadmap/3-fit-export.md)) | M | Owner needs rides in COROS. There's no automatic route. |

Checkpoint A: tests + both builds, owner commit. Then the owner's calibration ride (sets the matching
constants), a ramp with matching on/off and the COROS upload, all in DEVICE_CHECKS.

### Milestone B: the ride screen

| # | Plan | Size |
|---|------|------|
| 4 | Chaindance: rename, a real large view, coaching/labels polish (done, [archived](archive/2026-11-04-roadmap/4-chaindance.md)) | M |
| 5 | Preview scenarios in the iOS Simulator (done, [archived](archive/2026-11-04-roadmap/5-simulator-scenarios.md)) | S |

Checkpoint B: **visual review on the iOS Simulator matrix and the Mac walkthrough, after
asking the owner** (AGENTS.md). This review also covers the never-run XCUITests.

### Milestone C: your own workouts

| # | Plan | Size |
|---|------|------|
| 6 | ZWO import and export (done, [archived](archive/2026-11-04-roadmap/6-zwo-workouts.md)) | M |
| 7 | Workout builder: blocks + text, % FTP and watts, ramps (done, [archived](archive/2026-11-04-roadmap/7-workout-builder.md)) | L |

Checkpoint C: tests, builds, visual review (with permission). Plan 7 changes the archive
contract, so update `contracts/README.md` and note the web-port impact.

### Milestone D: the web app catches up (local only)

Bring `ftpunk_web/` to the native app. Plan 8 is done; 9a, 9b and 9c run in parallel (separate
worktrees, each owns its files, merged in the order 9a, 9b, 9c). Parity is checked with golden fixtures written by
Swift tests in `contracts/fixtures/`.

| # | Plan | Size | Runs |
|---|------|------|------|
| 8 | [Web foundation](archive/2026-11-05-web/8-web-foundation.md) (done 2026-11-05): story out, native screens, library + preview, storage, scenarios | L | first, alone |
| 9a | [Ride](next/9a-web-ride.md): live power matching, Chaindance, cockpit | M–L | parallel |
| 9b | [Intervals.icu per rider + upload prompt + sync, FIT export](next/9b-web-intervals-and-files.md) | M | parallel |
| 9c | [My workouts](next/9c-web-your-workouts.md): ZWO, builder, `customWorkouts` in archives | L | parallel |

Checkpoint D: `python3 ftpunk_web/tools/test.py`, native tests and builds, then a visual review of the web scenarios (headless Chrome
capture, with the owner's permission), then the owner's checks in Chrome with a real trainer and a real key.

## Parked (deliberately not now)

Each item needs a decision from the owner before a plan is written.

- Web: Intervals.icu OAuth in the browser (needs a client secret, so a server; conflicts with local only). An own
  domain for the web app, so its storage isn't shared with the owner's other `github.io` sites.
- Send *planned* workouts or custom workouts to the Intervals.icu calendar or library. Switch the
  activity upload from TCX to FIT.
- FIT *workout* files, cadence targets, free-ride segments in workouts.
- Release: Developer ID signing, notarization, App Store. Live OAuth approval.
- Trainer spin-down calibration from the app (FTMS Spin Down Control). Needs hardware testing.
- Builder: keep repeat-group labels ("Main set"), accept cadence targets and zones in the text editor, push custom workouts to Intervals.icu (needs a decision).
- Trainer warmth cools down when the trainer idles (today it only resets on a new Bluetooth connection).
- Account/server sync between devices (the original architecture keeps room for it).

## Decisions log

| Date | Decision |
|------|----------|
| 2026-11-02 | The story mode (Lowline/Cyclepunk) was removed from native. Its data fields are kept for archive compatibility. |
| 2026-11-02 | Locked-screen iOS riding isn't required. Physical checks are deferred. |
| 2026-11-03 | Built-in workouts use flat 50 % warm-ups, with no ramped warm-ups or cool-downs. |
| 2026-11-03 | The rider stands at 7 W/kg (1.6 × FTP without a weight), never in the FTP-test warm-up or ramp. |
| 2026-11-04 | The ride visual is named **Chaindance**. |
| 2026-11-04 | COROS: manual FIT upload. No unofficial COROS API. The Intervals upload stays TCX for now. |
| 2026-11-04 | Intervals.icu FTP/weight sync is editable locally. OAuth asks for `SETTINGS:READ`. |
| 2026-11-04 | **Scratched:** the Miyoo companion and the Mac background/browser host. No Apple Watch or Live Activity (never requested). |
| 2026-11-04 | Each rider has its own Intervals.icu connection. After every finished ride the app asks to upload (no silent uploads). |
| 2026-11-04 | Power matching: no learned profile across rides (calibration, temperature and load vary). Per ride it estimates meter vs. the trainer's *reported* power live (gain + offset), adapts faster while the trainer warms (by kJ done), and holds when the trainer can't hold its own target (fade). |
| 2026-11-04 | Builder: % FTP **and** watts, ramps allowed, local only, iPhone + Mac, block and text editors with a toggle. |
| 2026-11-05 | The web app follows the native app (milestone D). The story is scratched there too. Local only: no server or accounts. Intervals.icu answers CORS for localhost and github.io, so the browser talks to it directly. Pages serves the new web app (GitHub Actions), not `web-v1`. Web tests run in headless Chrome, no Node. The Intervals.icu key can be remembered per rider, opt-in, encrypted with a non-extractable WebCrypto key. |

## Where the docs are

| Path | What it is |
|------|------------|
| `docs/ROADMAP.md` | This file: state, order, parked items, decisions |
| `docs/next/` | Ready-to-run plans, numbered in run order. Move each to `archive/` when done. |
| `docs/DEVICE_CHECKS.md` | Everything that needs real hardware or a real account, for the owner |
| `docs/reference/` | Still-valid background: architecture/BLE/upload design, reference project audit |
| `docs/archive/` | Finished or superseded plans. Historical, not instructions. |
| `contracts/` | Archive formats and fixtures shared with the web app |
