# FTPunk roadmap

The single source of truth for what FTPunk is, where it stands and what comes next.
Updated 2026-11-09. If this file and an archived plan disagree, this file wins.

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

## Where it stands (2026-11-11)

Built and covered by tests (365 Swift tests, 300 web tests, iOS + Mac builds pass):

- **Web ride port (2026-11-11):** the web app now matches the three native commits: FIT holds cadence/power for 3 s (same numbers as native tests), Skip step (engine, controller, exact event text, summary target honours skips; Cmd/Ctrl+Right), the Chaindance-style dashboard for workout, free and resistance rides (the FTP cockpit is unchanged), and on the ride overview trainer power, hover readings on every chart, HRV (RMSSD, beat-artifact share) and a DFA α1 chart. Unverified: no visual check of the dashboard CSS or hover, no real strap/trainer/pointer on a device. The web ↑/↓ keys are new (the old cockpit had none).- **Workout dashboard rework (2026-11-11, native only):** the workout / free-ride cockpit follows the Chaindance (RG/SP) mockups without the rider scene: square boxes, much bigger numbers with the step's time left as the biggest, TARGET with its −/+ inside the box (↑/↓ keys too), ACTUAL with the trainer's watts bottom-left, a red heart-rate line over the workout profile, Skip step (not the last step; recorded as an event, so the summary's target follows), and all ride figures always shown. Bluetooth connect failures now time out and show a re-pair hint. The iOS and Mac CI builds pass (2026-11-11); the new screen has not been looked at.
- **Ride overview additions (2026-11-11, native only):** trainer average power and NP while a meter is the source; hover/tap readings on the result charts; HRV from the strap's RR intervals (RMSSD figure, DFA α1 chart in two-minute windows, artifacts filtered). The FIT export holds a missing cadence/power for up to 3 s (Intervals.icu drew the Assioma's repeated crank events as cadence spikes). Unverified: the new charts have not been looked at, and α1 on the first ride (1.2–1.6 at 84 % FTP) is higher than typical; it has not been cross-checked against another DFA tool.
- **FIT uploads and training-load fields (2026-11-09, native + web):** Intervals.icu now receives the FIT file, so simulated distance, speed, calories, work and balance reach it. Jobs queued earlier as TCX still upload as TCX (the file name and type are read from the bytes). The FIT session gains normalized power, TSS and IF, laps gain normalized power (no FTP or under 30 s leaves them invalid), paused samples no longer count towards NP (also on the ride card), and heart-strap RR intervals are recorded and written as `hrv` messages. Both encoders stay byte-identical. Not exercised: a real upload to Intervals.icu, RR from a real strap.

- Simulated gravel-bike speed and distance from power (FIT records, laps, session), work in kJ, estimated kcal, left/right balance from a meter or trainer with an end-of-ride graph, and a main/additional readings switch in the cockpit. Not yet seen in a running app or on a real meter.
- FTP test (three ramp presets, warm-up/cool-down, scoring, adopt result), workouts (classic
  library with flat warm-ups, Intervals.icu calendar, JSON and ZWO import, ZWO export, % FTP / W preview), free ERG,
  resistance, pause/resume.
- Home / pre-flight / cockpit / result / Progress / Settings layout (UX rework, 2026-11-02).
- Devices: trainer required, power meter and HRM optional; power matching estimates the trainer's error live
  (gain + offset against its reported power, warmth in kJ, fade guard); replay test for real CSVs.
- Intervals.icu: API key and OAuth (asks for `SETTINGS:READ`; confirm on the next real sign-in), one
  connection per rider, a consent sheet after every finished ride (per-rider toggle, never silent),
  confirmed FIT upload queue, calendar download, FTP and weight sync (field names verified against a
  live account), explicit User-Agent on every request.
- **Chaindance** (the ride visual): standing sprint; strip and Large modes. Large is a taller raster (96 rows: extra
  sky with stars, moon and tower tips, the readout in the sky band, a two-column layout on wide windows). The strip is
  pixel-identical to before (fingerprint test). Not looked at on a screen yet.
- Activity export: FIT (own encoder, field numbers checked against FIT profile 21.221; decoded with fitdecode/fitparse),
  TCX, CSV, JSON from the activity detail and the result screen; save panel / Files plus Share on iOS.
- **Workout builder:** the riders' own workouts as blocks or text (a documented subset of the Intervals.icu syntax), % FTP and
  watts, ramps, one level of repeats; local per rider, in backups as an optional `customWorkouts` key (the web app keeps it too).
- Portable archives v1–v3, shared with the web app.

- **Web app foundation (plan 8, 2026-11-05):** `ftpunk_web/` now has the native structure: Home, pre-flight, cockpit, result, Progress and
  Settings (sidebar or tab bar), onboarding, the 14 classic workouts with flat warm-ups, the workout detail sheet and preview texts (both equal to
  Swift-written fixtures in `contracts/fixtures/`), retest advice and start blockers ported from `Sources/FTPunkDomain`, IndexedDB version 4
  (`customWorkouts`, `credentials`, `riderSettings` for the next plans), preview scenarios (`?scenario=`) and a capture tool (built, never run). The story is
  gone from the UI; its fields are preserved in archives. New FTP tests always use 72 %. Tests run in real headless Chrome with
  `python3 ftpunk_web/tools/test.py` (no Node; CI runs it before the Pages deploy).
- **Web app parity (plans 9a–9c, 2026-11-06):** the native power matcher (3,300 per-second commands equal to native) and Chaindance (60+ frames
  pixel-identical) with the cockpit's placement menu, matching status and two-column Large view; Intervals.icu per rider with an opt-in encrypted key
  (AES-GCM, non-extractable WebCrypto key), the upload prompt, FTP/weight sync, a strict CSP; FIT export byte-identical to native plus TCX/CSV/JSON
  and Share; ZWO import/export, the workout text syntax, custom workouts and the builder, `customWorkouts` in archives. 255 web tests.
  Not exercised: a real trainer, a real key from Chrome, a FIT file in COROS, clipboard/file pickers/downloads/Share in a real browser.
- **Ride summary, auto-pause, space bar (2026-11-08, native + web):** the result and activity detail show average and normalized power, average/max heart rate and
  average cadence, and a power chart with the target line plus a heart-rate chart (target rebuilt from the session, nothing new stored). Workouts and free rides pause
  after 3 s without power and resume after 2 s of pedalling (a manual pause is never auto-resumed; a Settings switch turns it off; never in the FTP test); Space
  pauses and resumes. 8 new Swift tests, 6 new web tests. Not exercised: a real trainer, a screen (the charts and the Space key were not looked at).
- **Sprite rider + live power chart (2026-11-08, native + web):** the Chaindance scene now draws the RG SP rider (rider A's build in rider D's violet/yellow colours; `RideVisualSprite.swift`, `chaindance/rider-sprite.mjs`), opt-in per scene so the pixel fixtures keep the original rider; the sprite has one fixed pose (no posture or road tilt). Mac/iOS cockpits show the live "Power over time" chart (last 10 min, target dashed) like the web. Checked: swift test, both CI builds, web tests, rendered frames; not checked on a real ride or the sprite on a downhill.
- **Web visual review (2026-11-06, headless Chrome, all 34 scenarios at 390 and 1280 px):** layouts hold at both sizes. Fixed: the app could hang on
  "Loading…" when Chrome never answered the Web Locks request (now a 5 s timeout, and previews use their own lease; this was also the flaky test);
  the CSP blocked Chaindance's inline readout height; a global `details` rule hid the "How this is calculated" arrow; the theme switch stretched
  full width; the ride header's minimise glyph; the remember-key note's wording for other users.
  Polish done the same day: tab-style switches use the lime accent, one "Share…" button (FIT) instead of four, custom-workout cards show only Edit (the detail
  sheet has Duplicate, Export ZWO and Delete), dialogs no longer open with a focus ring on ✕, the sidebar logo is a rounded tile, chart axis text is larger on phones.

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

The seven plans of milestones A–C were implemented on 2026-11-04 and archived in [`archive/2026-11-04-roadmap/`](archive/2026-11-04-roadmap/). Milestone D (web parity) was done on 2026-11-05/06 and archived in [`archive/2026-11-05-web/`](archive/2026-11-05-web/). `next/` is empty.

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

Bring `ftpunk_web/` to the native app. All four plans are done (2026-11-06); 9a, 9b and 9c ran in parallel (separate
worktrees, each owns its files, merged in the order 9a, 9b, 9c). Parity is checked with golden fixtures written by
Swift tests in `contracts/fixtures/`.

| # | Plan | Size | Runs |
|---|------|------|------|
| 8 | [Web foundation](archive/2026-11-05-web/8-web-foundation.md) (done 2026-11-05): story out, native screens, library + preview, storage, scenarios | L | first, alone |
| 9a | [Ride](archive/2026-11-05-web/9a-web-ride.md) (done): live power matching, Chaindance, cockpit | M–L | parallel |
| 9b | [Intervals.icu per rider + upload prompt + sync, FIT export](archive/2026-11-05-web/9b-web-intervals-and-files.md) (done) | M | parallel |
| 9c | [My workouts](archive/2026-11-05-web/9c-web-your-workouts.md) (done): ZWO, builder, `customWorkouts` in archives | L | parallel |

Checkpoint D: `python3 ftpunk_web/tools/test.py`, native tests and builds, then a visual review of the web scenarios (headless Chrome
capture, with the owner's permission), then the owner's checks in Chrome with a real trainer and a real key.

## Parked (deliberately not now)

Each item needs a decision from the owner before a plan is written.

- Web: Intervals.icu OAuth in the browser (needs a client secret, so a server; conflicts with local only). An own
  domain for the web app, so its storage isn't shared with the owner's other `github.io` sites.
- Web: Chaindance hashes scenery with 64-bit BigInt per pixel; measure on a slow device and switch to 32-bit arithmetic if needed (the fingerprint
  fixture guards the pixels). The backup import sheet lists cached workouts but not custom workouts that it will replace. Leaving a changed builder
  through the tab bar doesn't ask to discard (Cancel and closing the tab do).
- Send *planned* workouts or custom workouts to the Intervals.icu calendar or library.
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
| 2026-11-09 | Intervals.icu uploads are FIT instead of TCX (supersedes 2026-11-04); TCX stays an export. |

## Where the docs are

| Path | What it is |
|------|------------|
| `docs/ROADMAP.md` | This file: state, order, parked items, decisions |
| `docs/next/` | Ready-to-run plans, numbered in run order. Move each to `archive/` when done. |
| `docs/DEVICE_CHECKS.md` | Everything that needs real hardware or a real account, for the owner |
| `docs/reference/` | Still-valid background: architecture/BLE/upload design, reference project audit |
| `docs/archive/` | Finished or superseded plans. Historical, not instructions. |
| `contracts/` | Archive formats and fixtures shared with the web app |
