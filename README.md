# FTPunk

Home is a ride picker: today’s Intervals.icu workout, your FTP card (with the FTP test button), quick
rides (free ERG, resistance) and a library of classic workouts grouped by type. The FTP test stays the
key feature, with a permanent place on Home. Pause releases the trainer and freezes workout progress. A pixel
ride (a short rainy-night city strip whose rider shows your effort) can sit in every cockpit. Mac, iPhone and
web transfer history and workouts through portable backups. See the [roadmap](docs/ROADMAP.md) for status and next steps, and the
[workout example](contracts/workout-example.json).

Native iPhone and Mac apps for FTP ramp tests with a smart trainer, including the Elite Suito-T. The trainer controls resistance and supplies measured power by default. An external Bluetooth power meter, such as Favero Assioma PRO MX-2 pedals, is optional. Riders, recordings and progress work locally. Intervals.icu upload is optional and asks for confirmation.

Power matching is enabled by default for external meters. Once a meter’s measurement connection is ready, FTPunk asks whether to use it to control trainer power or only to record power. Change this in **Settings → Devices & trainer control → Power matching** before a test. The choice is fixed in each recording; older recordings retain their original behavior. Corrections settle for five seconds after target changes, update at most every three seconds, and are limited to 3 W per update and ±20% (at most 60 W), within the trainer’s supported range. Zero power or low cadence suspends correction; loss of the selected meter still interrupts the test. Validate response with your trainer at low load before a maximal test.

The selected app icon is the 8-bit cyclist wearing a magenta helmet. Source artwork, the edit prompt and export instructions are in [design/app-icon](design/app-icon/README.md); both iPhone and Mac builds use it.

## Chrome web app

The self-contained Chrome port lives in [`ftpunk_web/`](ftpunk_web/README.md). It follows the native app's screens (Home, pre-flight, cockpit, result, Progress, Settings) and workout library, with Web Bluetooth trainer control, external power matching, debug mock rides, local browser history, exports, and optional approved Intervals.icu uploads. Its tests run in headless Chrome with `python3 ftpunk_web/tools/test.py` (no Node).

```sh
cd ftpunk_web
python3 tools/serve.py
```

Open **http://localhost:8080** in Chrome. See the web README for tests, deployment, and browser/hardware verification limits.

## Use the Mac app

The local build produces `dist/FTPunk.app` and `dist/FTPunk-Mac.zip`. Open the app directly or copy it to Applications. It has persistent local profiles and history, Bluetooth support, account connections, and the same test engine as the iPhone app. It is not restricted to mock input.

```sh
sh Tools/build_mac.sh
open dist/FTPunk.app
```

This packages a release executable for the build Mac's architecture (Apple silicon in this workspace), with an ad-hoc local signature. A Developer ID signature and notarization remain necessary for normal public distribution to other Macs. The full Xcode project also includes a **FTPunkMac** scheme, with Bluetooth/network sandbox entitlements for signed builds. Minimum macOS: 14.

Mac, iPhone and web stores remain independent. Use **Settings → Backup & transfer** to export a portable JSON archive and import it on another device. Imports preview the riders, replace matching identities, preserve unrelated riders and save a rollback backup first. Accounts and upload approvals are not transferred. This is manual transfer, not automatic sync; see the [archive contract](contracts/README.md).

The [roadmap](docs/ROADMAP.md) lists what is built, the next steps in order and what is parked. [Device and account checks](docs/DEVICE_CHECKS.md) are deferred to the owner. iOS may remain foreground-only; locked-screen operation is out of scope.

## Run on iPhone

1. Install full Xcode and an iOS Simulator runtime. Command-line tools alone are insufficient.
2. Open `FTPunk.xcodeproj`, select **FTPunk**, and choose an iPhone simulator or an iOS 18+ device.
3. For a physical iPhone, choose your signing team and, if needed, a unique bundle identifier.
4. To try mock input first, open **Settings → About FTPunk**, activate the version/info bubble ten times, then enable **Mock sensors** under Debug tools. For hardware, turn mock sensors off in Settings, then tap the **Devices** pill on Home to connect the trainer and enable trainer control. Trainer power is the default. Trainer, External power meter and Heart rate each have a separate row in the Devices sheet. Connecting an external meter selects it for power; Measure power with lets you choose the source explicitly. Heart rate is optional.

UI optimization targets **iPhone 15 Pro** first, in portrait, with both light and dark appearance. To build and open that exact simulator model with an isolated mock profile:

```sh
sh Tools/run_simulator.sh
```

The launcher selects an installed runtime that explicitly supports iPhone 15 Pro and never falls back to another model. Only one compatible runtime is needed; the Duo-only iOS 27.1 runtime is unnecessary. Add `--autostart-debug` to open a mock ride directly.

If using an external meter, configure/calibrate it in its vendor app. For dual-sided Assioma pedals, verify total power and crank length in Favero's app or with a bike computer. Before a maximal test, validate acknowledged target changes and stopping at a low load on your actual trainer firmware. Keep other trainer-control apps closed.

## Workflow and features

**Stop & save** requests release immediately, without a confirmation dialog. A new session remains unavailable until cleanup finishes; an unconfirmed stop requires reconnecting trainer control.

**Home → pre-flight → cockpit → result.** Every ride passes through one pre-flight checklist with Start always visible; when Start is disabled, the reason sits directly above it. The cockpit fills the screen during a ride (minimise it to get the live-ride bar above the tabs), and the result shows the training result first, then what it means for training, then sharing.

- **Navigation:** Home, Progress and Settings, as tabs on iPhone and a sidebar on Mac. The rider chip and the Devices pill sit on Home’s toolbar; the rider chip is the only place the rider is chosen, and Devices is one shared sheet.
- **Named riders:** choose or add a local person in the rider sheet. Each has separate FTP history and weight. Tests snapshot rider identity/name, FTP, weight, protocol, factor and measurement sources. Adopting a test’s FTP updates its owner, even when another rider is selected. A first launch with no rider data asks for a name, optional weight and FTP.
- **FTP card:** current FTP, W/kg, date and source; after eight weeks it suggests a retest. With no FTP it moves to the top as the main call to action and library workouts say “Needs FTP”.
- **FTP test pre-flight:** the protocol is recommended from your weight (below 60 kg: 15 W/min, otherwise 25 W/min) with its reason, and can be changed (the in-app guide attributes the original protocol reasoning to Richard Stern). Warm-up and cool-down default to 10 and 3 minutes, from 0 to 60 whole minutes each (zero skips the phase), with an optional manual warm-up target; the warm-up uses 50% of FTP, or 75 W (15 W/min) / 100 W (others) without one. Quick debug timing (10 s each) appears only with mock sensors.
- **Estimate:** always 72% of the best valid continuous 60-second ramp power; there is no factor picker. Recordings and archives made with 75% in earlier versions load unchanged and show their original factor. The result shows the 72–77% range under “How this is calculated”.
- **Three protocols:** 15 W/min (50 W start, +5 W/20 s), 25 W/min (100 W start, +5 W/12 s), and 20 W/min Zwift-style (100 W start, +20 W/60 s).
- **Power source:** Trainer is the default; no separate meter is required. Choose an optional external Bluetooth Cycling Power meter on pedals, a crank or a hub. Power and cadence sources are fixed when a ride starts. Cadence prefers the selected meter when available, then the trainer. If neither reports fresh cadence, the test uses manual ramp finishing and says so. A selected meter disconnect interrupts the ride; it never silently switches power sources.
- **Native ride dashboard:** window-scaled dark tiles without scrolling on Mac from 900×600; compact phones stack the tiles. Power is a display-only, time-weighted 3 / 10 / 30 / 60 s average (caption menu and Settings share the choice); scoring and recorded samples are unchanged. Tektur is bundled under the OFL license, with SF Rounded and System alternatives in Settings → Ride screen, plus Fit to screen / Compact numbers and step sound. FTP warm-up/cool-down share the grid; the ramp focuses on power and cadence, uses the engine’s existing below-45 rpm countdown, and retains the 72 % estimate. Sound cues cover workout countdowns and ramp cadence warnings; Reduce Motion suppresses target pulses.
- **Mac menus:** Settings… (⌘,), Go → Home / Progress / Settings (⌘1 / ⌘2 / ⌘3), and a Ride menu for the active ride. Space or ⌘⇧P pauses/resumes workouts and free rides; ⌘→ skips a workout step, ↑/↓ adjusts the workout intensity by 1 %, free ERG by 5 W or resistance by one level; ⇧↑/⇧↓ changes by 5 %, 25 W or five levels, ⌘⇧F finishes the ramp, and ⌘. stops and saves. M switches More metrics / Chart for workouts and free rides (also in the ⋯ menu). New Window and automatic window tabbing are disabled.
- **FTP test cockpit:** large target and actual watts, the ramp step and ramp time, a next-step countdown ring, heart rate, cadence and live **MAX 60 S**. Below 60 rpm the cadence tile turns amber with “Ramp ends below 45 rpm”; the automatic finish (cadence under 45 rpm for 5 s) is unchanged. **Hold to finish** needs a 1.5 s press (VoiceOver action and ⌘⇧F on Mac); **Stop & save** is a single tap. MAX 60 S is the best complete, valid 60-second ramp average so far, not FTP; it waits for coverage, counts zeros, and excludes warm-up/cool-down. The final score rechecks the exact ramp endpoint. The **Chaindance** (below) sits under the numbers. Debug controls live in a sheet.
- **Result:** the estimate with its change from your current FTP, the power chart with the best minute shaded, and a pinned “Use 209 W as Alex’s FTP” / “Keep 250 W” choice. After adopting, a hand-off card shows what changes in the library. Interrupted results explain what was saved; debug results cannot be adopted or uploaded.
- **Workouts:** 14 built-in classics (endurance, tempo, sweet spot, over-unders, threshold, VO2max) resolved at your FTP when shown and snapshotted when a ride starts, plus Intervals.icu workouts and imported JSON files. Intensity is 50–150% in 1-point steps. The shared dashboard shows power and step time in the hero row, then heart rate, cadence and the clickable Next tile (skip without confirmation). The profile includes heart rate and finished-step averages below the bars; elapsed ridden time never jumps on Skip. Free ERG changes by ±5 W and resistance rides by one level; the header switches between ERG and resistance during the ride after confirming trainer release/restart. Pause/Resume and Stop & save sit in the header.
- **Intervals.icu calendar:** when connected, Home refreshes the next 14 days on appear if the last download is over an hour old (never during a ride) and on pull-to-refresh. Cached workouts carry an optional `scheduledDate` (local `yyyy-MM-dd`); older caches show under Upcoming without a date until the next download.
- **Chaindance:** a short, full-width night-city strip (192 × 60 pixels, 16:5, enlarged crisply) in the dashboard strip slot, or as the existing Large scene. It is off by default; switch it on in the pre-flight (tests and workouts), live in the cockpit ⋯ menu, or in Settings → Ride screen (`rideVisualEnabled`, migrated from the old `showStelvioASCII`: absent means off, a stored choice is kept). The rider (magenta helmet, lime jacket, cyan-rimmed bike) shows the current intensity, from power smoothed over 3 s against the FTP of the ride, using the same zones and colours as the workout profile charts: upright and dim trail in recovery, hoods in endurance, lower in tempo and sweet spot with a growing trail in the zone colour, and in the drops with sweat and speed lines at threshold, plus sparks above it. Pedalling follows measured cadence in four frames a turn and coasts when cadence is stale or zero; the scenery scrolls faster with power. The FTP test rides a boulevard towards the Spire in warm-up, climbs its skyway during the ramp (a `LVL n` sign passes at every step; the climb is endless and never hints where the ramp will end), shows a rooftop sign such as `LVL 23 · 290 W` when the ramp ends and glides down in cool-down. Workouts ride the Neon Boulevard: a gantry at every step boundary, calm teal blocks for recoveries, a bright market district in the step's zone colour for work, and a `NEXT 5:00 · 225 W` billboard ten seconds ahead. Free ERG passes a gate at each target change; resistance shows the level. Paused rides stop with a foot down and a `PAUSED` sign. It is decorative (one summary label, no announcements), always night, animates at about 12 frames a second only while visible, and under Reduce Motion stops scrolling, rain and pedalling while pose, colour and signs keep following the ride. Increase Contrast adds a dark outline around the rider. It only reads the ride and never changes a trainer target.
- **No story:** the Lowline story was removed from the native app. Riders, recordings and backups still carry its old progress fields so web backups round-trip unchanged; nothing in the native app grants, shows or edits them.
- **Progress:** the FTP trend for the selected rider (real results by default, debug on request; one colour per rider, one shape for real/debug, one legend) above an activity list filtered by All / FTP tests / Workouts / Free rides. Deleting is by swipe, context menu or the detail menu, always with confirmation; it removes local samples and pending jobs, while adopted FTP values and activities already on Intervals.icu remain.
- **Appearance:** System, Light and Dark under Settings → Ride screen, remembered per device.
- **Readability:** primary actions use explicit text/fill colors tested above 4.5:1 contrast in light and dark mode. Larger ride numbers follow Dynamic Type, with an extra-large option in Settings. Accessibility text sizes stack metrics/actions vertically. Labels, units, icons, stronger text colors, optional increased-contrast borders, VoiceOver values/iPhone phase announcements, and Reduce Motion support the ride workflow. See the [accessibility review](docs/archive/ux-review.md#accessibility-and-readability-review).
- **About:** Settings shows the bundle’s version/build number and “Created by Kordian Gontarska · Developed with assistance from OpenAI Codex” credits. Ten button activations unlock persistent debug tools. Mock mode cannot be changed while a session is active; Hide debug tools locks it again. Normal launches default to real sensors, while explicit in-memory preview launches retain direct mock access.

Disclosure headers, toggles, selection rows, device connections and form actions respond across their full row, with 44-point targets. Numeric duration fields show units and validation; invalid entries block Start and say why, and the iPhone number pad has a Done button.

Design history: the [UX rework plan](docs/archive/ux-rework-plan.md) and the earlier [UI review](docs/archive/ux-review.md).

## Try without cycling devices

Unlock Debug tools with ten activations of **Settings → About FTPunk**, then enable mock sensors there. Mock input generates power, cadence and heart rate through the real ramp engine and FTP analysis. It offers 1×/4×/12×/60× playback, exact manual sliders, pause/resume, skip warm-up, advance 60 seconds, lost signals and simulated trainer disconnection. Quick tests use a 10-second warm-up/cooldown. The default mock rider exhausts when the ramp passes 300 W. Debug recordings never upload or become adopted FTP. The About button is accessible to VoiceOver, Switch Control and keyboard activation; it does not depend on a raw multi-tap gesture.

For an isolated in-memory Mac preview:

```sh
sh Tools/run_preview.sh
```

Preview scenarios open a seeded state in the in-memory store only; they never read or change real history. Names: `first-launch`, `home-today`, `home-not-connected`, `home-no-ftp`, `home-retest-due`, `library`, `preflight-blocked`, `ride-warmup`, `ride-ramp`, `ride-ramp-low-cadence`, `ride-cooldown`, `result-new-ftp`, `result-interrupted`, `result-upload-prompt`, `workout-running`, `workout-paused`, `free-ride`, `resistance`, `progress-two-riders`, and the Chaindance states `visual-ramp-threshold`, `visual-workout-vo2`, `visual-recovery`, `visual-summit`, `visual-paused`, `visual-off`, `visual-hero`, `visual-sprint`, plus `settings-devices`, `settings-intervals`, `settings-intervals-connected` (a fake connection and seeded sync state), `workout-detail`, and the workout builder in `builder-blocks` and `builder-text`. Dashboard previews: `dash-workout`, `dash-workout-recovery-next` (mockup 1b: recovery step, zone-coloured Next), `dash-workout-countdown`, `dash-workout-paused`, `dash-workout-scaled`, `dash-ftp-warmup`, `dash-ftp-ramp`, `dash-ftp-low-cadence`, `dash-ftp-ending`, `dash-ftp-cooldown`, `dash-free-ride`, `dash-free-ride-resistance`, `dash-more-metrics`, `dash-signal-lost`. Their Mac walkthrough size is 1470×923; they explicitly turn Chaindance off. Existing ride scenarios show Chaindance by default. A preview launched with `--debug-preview --mock-speed 4` runs its mock sensors at 4× instead of 12×.

```sh
sh Tools/run_preview.sh --scenario ride-ramp                   # one state on the Mac
sh Tools/run_preview.sh --preview-walkthrough                  # screenshot every scenario
sh Tools/run_simulator.sh --scenario result-new-ftp            # one state on the iPhone 15 Pro simulator
sh Tools/run_simulator.sh --matrix [directory] [scenario ...]  # simulator screenshots, light/dark x text size
```

The simulator matrix waits longer for the first launch after an appearance or text-size change and retakes any screenshot smaller than `FTPUNK_MIN_SCREENSHOT_BYTES` (default 150000; a blank frame is far smaller), up to three times, then warns.

The Mac walkthrough captures this app’s own views in `/tmp/ftpunk-preview` (or `--capture-dir`): each scenario in dark and light, at the default and an accessibility text size, in a 393 × 852 iPhone layout, plus the Mac window. The preview skips loading existing credentials. Normal app launches use persistent history.

## Intervals.icu

**Settings → Connect with an API key** is available in either real-device or debug mode. Copy your personal key from Intervals.icu Settings → Developer settings. The app verifies the athlete, stores the key in Keychain and excludes it from exports.

The future sign-in flow uses Apple's authentication browser with OAuth/S256 PKCE. Its implementation is retained but the sign-in UI is hidden for now. Live sign-in needs FTPunk's one-time public-client registration and approval. No server or embedded client secret is required. See [configuration](Configuration/IntervalsOAuth.md) and the [official OAuth documentation](https://forum.intervals.icu/t/intervals-icu-oauth-support/2759).

After a real test is finalized and saved, the app asks whether to upload it. The prompt identifies **the test's rider and the connected athlete account**, so guests' tests do not silently go to the app owner's account. Choose Upload or Keep local. An activity’s detail in Progress provides the same deliberate upload flow for older recordings. Connecting while a finalized real test is on the result screen also offers its upload. Debug tests are always excluded.

Only an approved upload enters the durable queue. Approved jobs retry on launch, network recovery and foreground scheduling, retaining the same file bytes for file-hash deduplication (FIT since 2026-11-09; jobs queued earlier stay TCX). Force-quitting/suspension cannot guarantee immediate delivery. Old pending automatic jobs from earlier prototypes are cancelled during migration; no new automatic uploads are created. Uploads never update remote FTP, weight or wellness settings. No COROS integration is included.

## Build and test

```sh
swift test
```

On a command-line-only Swift 6.4 installation whose default engine cannot load Swift Testing macros, use `sh Tools/test.sh`. The package has no external dependencies. Tests compile the full shared app and cover packets, timing/analysis, persistence/export, upload requests/queue, OAuth, legacy rider migration, multi-rider ownership, confirmation and deletion.

```sh
xcodebuild -project FTPunk.xcodeproj -scheme FTPunk \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project FTPunk.xcodeproj -scheme FTPunkMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

`python3 Tools/generate_project.py` regenerates both shared schemes/project without extra tooling. The iOS target is named `FTPunkiOS` (scheme `FTPunk`, product `FTPunk.app`, bundle id `com.kainkordian.ftpunk`): a target also called `FTPunk` collided with the Swift package's `FTPunk` executable product, and Xcode could not find the app under test for `FTPunkUITests`. Run it after adding, moving or removing Swift files anywhere under `App` or `UITests`. Package sources are discovered automatically. GitHub Actions checks tests, unsigned iOS/macOS builds and that the UI tests compile.

The `FTPunkUITests` target (`UITests/`) holds XCUITest smoke tests for the FTP test, workouts, free ERG, Progress, Chaindance and the absence of the story, using mock sensors and the preview scenarios. They drive the simulator UI, so compile them with `build-for-testing` and run them only when you want a visual run:

```sh
xcodebuild -project FTPunk.xcodeproj -scheme FTPunk -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```


## Architecture and validation boundary

| Location | Responsibility |
| --- | --- |
| `App` | Shared SwiftUI: `DesignSystem/` components, `Features/{Shell,Home,Preflight,Ride,Result,Progress,Settings}/`, preview scenarios, adaptive theme, native sign-in, rider orchestration, the workout catalog and upload consent. |
| `Sources/FTPunkDomain` | Immutable session snapshots, rider identity/grouping, ramp definitions/state machine, time-weighted analysis, the classic workout library, pure presentation rules (start blockers, retest age, cadence guard, result order), the pure `RideVisualState` behind Chaindance, and repository interfaces. |
| `Sources/FTPunkDevices` | Bounded FTMS/Cycling Power/HR parsing, cadence rollover, CoreBluetooth discovery and acknowledged commands. |
| `Sources/FTPunkStorage` | Versioned Core Data SQLite store, independent profiles, append-only samples, checkpoints and CSV/JSON/TCX export. |
| `Sources/FTPunkIntegrations` | Keychain credentials, Intervals.icu HTTP/OAuth adapters and account-bound retry queue. |

Core Data avoids third-party dependencies and keeps explicit transactions. Older recordings retain their original external-meter power/cadence provenance; new tests default to trainer power. Older single-rider JSON payloads decode into a stable default rider; the existing SQLite model needs no destructive migration. Future account sync remains a separate service with DTOs/outbox behavior; workouts never depend on network access.

This remains a hardware prototype. Validate actual Suito-T control/start/stop and capability ranges, Assioma total-power/cadence semantics, live FIT import and authorization, wider display/accessibility cases, reconnect/device bindings and lifecycle behavior before release. Standard one-byte FTMS resistance decoding is the default; use the explicit two-byte reference layout only when confirmed by packet capture.

The foreground-only test policy interrupts on backgrounding or stale essential data. Stop acknowledgements are checked, but software cannot release braking after communication is lost. Automatic exhaustion fixes the scored ramp window, releases ERG with an acknowledged stop, and records the chosen free-spin cool-down without issuing another power target. A manually finished ramp retains the preset gentle cool-down target. Zero recovery ends immediately. Fresh power is still required during recovery; losing it preserves the scored result and ends the recording. Actual Suito-T telemetry after an acknowledged stop remains a hardware-validation item.

The pixel scenery uses a deterministic 192 × 96 panorama scaled without interpolation, drawn locally at up to 12 frames per second. The 24-second procedural loop has no downloaded assets or game-engine dependency. It does not claim real GPS position, elevation or distance. Workout phase events, not predicted FTP or elapsed climb loops, control summit/descent transitions. Reduce Motion shows a static victory pose instead of an animated cheer.

CSV exports use `power_watts` for the selected measured stream (replacing the old `pedal_watts` header), retain `trainer_watts` diagnostics, and include `power_source`/`cadence_source` columns. JSON metadata and TCX notes record the source too. History and results label each test’s power source so comparisons stay traceable.

## Reference and repository

`reference_project/` stays ignored and is not included in the repository or Mac archive. See the [reference audit](docs/reference/reference-audit.md) and [architecture](docs/reference/architecture.md). Generated binaries/archives in `dist/` are also ignored. The repository is [github.com/kainkordian/ftpunk](https://github.com/kainkordian/ftpunk). GitHub Pages serves the web app in `ftpunk_web/` at [kainkordian.github.io/ftpunk](https://kainkordian.github.io/ftpunk/), deployed by `.github/workflows/pages.yml`. The earlier web-only FTPunk is kept at tag `web-v1`.
