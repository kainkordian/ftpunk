# FTPunk

Native iPhone and Mac apps for FTP ramp tests with a smart trainer, including the Elite Suito-T. The trainer controls resistance and supplies measured power by default. An external Bluetooth power meter, such as Favero Assioma PRO MX-2 pedals, is optional. Riders, recordings and progress work locally. Intervals.icu upload is optional and asks for confirmation.

## Use the Mac app

The local build produces `dist/FTPunk.app` and `dist/FTPunk-Mac.zip`. Open the app directly or copy it to Applications. It has persistent local profiles and history, Bluetooth support, account connections, and the same test engine as the iPhone app. It is not restricted to mock input.

```sh
sh Tools/build_mac.sh
open dist/FTPunk.app
```

This packages a release executable for the build Mac's architecture (Apple silicon in this workspace), with an ad-hoc local signature. A Developer ID signature and notarization remain necessary for normal public distribution to other Macs. The full Xcode project also includes a **FTPunkMac** scheme, with Bluetooth/network sandbox entitlements for signed builds. Minimum macOS: 14.

Mac and iPhone stores are independent. Future server sync can connect them without changing the workout engine or repository boundaries.

## Run on iPhone

1. Install full Xcode and an iOS Simulator runtime. Command-line tools alone are insufficient.
2. Open `FTPunk.xcodeproj`, select **FTPunk**, and choose an iPhone simulator or an iOS 18+ device.
3. For a physical iPhone, choose your signing team and, if needed, a unique bundle identifier.
4. Use **Debug mode · no devices** first. For hardware, turn it off on the Ready step, connect the trainer and enable trainer control. Trainer power is the default. Select External power meter only if you want to use a separate sensor. Heart rate is optional.

To build and open a dedicated virtual iPhone with an isolated mock profile:

```sh
sh Tools/run_simulator.sh
```

If using an external meter, configure/calibrate it in its vendor app. For dual-sided Assioma pedals, verify total power and crank length in Favero's app or with a bike computer. Before a maximal test, validate acknowledged target changes and stopping at a low load on your actual trainer firmware. Keep other trainer-control apps closed.

## Workflow and features

**New test → Rider → Protocol → Ready → Ride → Result** keeps preparation separate from the active effort. Back/Continue/Start controls stay visible below the scrollable setup form.

- **Named riders:** choose or add a local person. Each has separate FTP history and weight. Tests snapshot rider identity/name, selected FTP, weight, protocol, factor and measurement sources. Adopting an old test's FTP updates its owner, even when another rider is selected.
- **Starting FTP:** select a current or historical value, enter one manually, or leave it unspecified. Automatic warm-up uses 50% of the selected value. Without FTP, fallback power is 75 W for the 15 W/min protocol and 100 W for the others. A manual override is available.
- **Three protocols:** 15 W/min (50 W start, +5 W/20 s), 25 W/min (100 W start, +5 W/12 s), and 20 W/min Zwift-style (100 W start, +20 W/60 s). Choose manually. The in-app guide explains the reference's 60 kg guideline and attributes the original protocol reasoning to Richard Stern.
- **Power source:** Trainer is the default; no separate meter is required. Choose an optional external Bluetooth Cycling Power meter on pedals, a crank or a hub. Power and cadence sources are fixed when a test starts. Cadence prefers the selected meter when available, then the trainer. If neither reports fresh cadence, the test uses manual ramp finishing and says so. A selected meter disconnect interrupts the test; it never silently switches power sources.
- **Dashboard:** large target and actual watts, next-step countdown/progress, ramp/total time, cadence, optional heart rate, a power trace and clear finish/stop actions. Debug controls are collapsible.
- **Results:** best valid continuous 60-second ramp power, a selected 72% or 75% estimate, the 72–77% range, and W/kg from session weight. In-app information explains the range and its limitations.
- **Progress:** rider-grouped recordings, a rider filter and FTP/W/kg trend charts. Debug points are hidden by default and use diamond symbols when included. Compare matching protocols, factors and power sources.
- **Deletion:** visible trash buttons, swipe/context actions and a detail-screen action, all with confirmation. Deleting removes local samples and pending jobs; adopted FTP values and activities already on Intervals.icu remain.
- **Appearance:** System, Light and Dark under Settings, remembered per device. Native surfaces/text and adaptive accents support both themes.

The [UI review](docs/UX_REVIEW.md) explains the design decisions and remaining validation.

## Try without cycling devices

Debug mode generates power, cadence and heart rate through the real ramp engine and FTP analysis. It offers 1×/4×/12×/60× playback, exact manual sliders, pause/resume, skip warm-up, advance 60 seconds, lost power/cadence signals and simulated trainer disconnection. Quick tests use a 10-second warm-up/cooldown. The default mock rider exhausts when the ramp passes 300 W. Debug recordings never upload or become adopted FTP.

For an isolated in-memory Mac preview:

```sh
sh Tools/run_preview.sh
```

For a repeatable visual walkthrough with two synthetic riders and dated mock history:

```sh
sh Tools/run_preview.sh --preview-walkthrough
```

It captures this app's own views in `/tmp/ftpunk-preview`, including all setup stages, the ride dashboard, results, progress, settings and light-theme screens. The preview skips loading existing credentials. Normal app launches use persistent history.

## Intervals.icu

**Settings → Connect with an API key** is available in either real-device or debug mode. Copy your personal key from Intervals.icu Settings → Developer settings. The app verifies the athlete, stores the key in Keychain and excludes it from exports.

The alternative sign-in button uses Apple's authentication browser with OAuth/S256 PKCE. Its implementation is present, but live sign-in needs FTPunk's one-time public-client registration and approval. No server or embedded client secret is required. See [configuration](Configuration/IntervalsOAuth.md) and the [official OAuth documentation](https://forum.intervals.icu/t/intervals-icu-oauth-support/2759).

After a real test is finalized and saved, the app asks whether to upload it. The prompt identifies **the test's rider and the connected athlete account**, so guests' tests do not silently go to the app owner's account. Choose Upload or Keep local. History provides the same deliberate upload flow for older recordings. Connecting while a finalized real test is on the Ride screen also offers its upload. Debug tests are always excluded.

Only an approved upload enters the durable queue. Approved jobs retry on launch, network recovery and foreground scheduling, retaining the same TCX bytes for file-hash deduplication. Force-quitting/suspension cannot guarantee immediate delivery. Old pending automatic jobs from earlier prototypes are cancelled during migration; no new automatic uploads are created. Uploads never update remote FTP, weight or wellness settings. No COROS integration is included.

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

`python3 Tools/generate_project.py` regenerates both shared schemes/project without extra tooling. Run it after adding/removing top-level Swift files in `App`. Package sources are discovered automatically. GitHub Actions checks tests and unsigned iOS/macOS builds.

## Architecture and validation boundary

| Location | Responsibility |
| --- | --- |
| `App` | Shared SwiftUI workflow/dashboard, adaptive theme, native sign-in, rider orchestration and upload consent. |
| `Sources/FTPunkDomain` | Immutable session snapshots, rider identity/grouping, ramp definitions/state machine, time-weighted analysis and repository interfaces. |
| `Sources/FTPunkDevices` | Bounded FTMS/Cycling Power/HR parsing, cadence rollover, CoreBluetooth discovery and acknowledged commands. |
| `Sources/FTPunkStorage` | Versioned Core Data SQLite store, independent profiles, append-only samples, checkpoints and CSV/JSON/TCX export. |
| `Sources/FTPunkIntegrations` | Keychain credentials, Intervals.icu HTTP/OAuth adapters and account-bound retry queue. |

Core Data avoids third-party dependencies and keeps explicit transactions. Older recordings retain their original external-meter power/cadence provenance; new tests default to trainer power. Older single-rider JSON payloads decode into a stable default rider; the existing SQLite model needs no destructive migration. Future account sync remains a separate service with DTOs/outbox behavior; workouts never depend on network access.

This remains a hardware prototype. Validate actual Suito-T control/start/stop and capability ranges, Assioma total-power/cadence semantics, live TCX import and authorization, wider display/accessibility cases, reconnect/device bindings and lifecycle behavior before release. Standard one-byte FTMS resistance decoding is the default; use the explicit two-byte reference layout only when confirmed by packet capture.

The foreground-only test policy interrupts on backgrounding or stale essential data. Stop acknowledgements are checked, but software cannot release braking after communication is lost. At exhaustion the hardware path releases ERG; a manually finished ramp can include cooldown.

CSV exports use `power_watts` for the selected measured stream (replacing the old `pedal_watts` header), retain `trainer_watts` diagnostics, and include `power_source`/`cadence_source` columns. JSON metadata and TCX notes record the source too. History and results label each test’s power source so comparisons stay traceable.

## Reference and repository

`reference_project/` stays ignored and is not included in the repository or Mac archive. See the [reference audit](docs/REFERENCE_AUDIT.md) and [development plan](docs/DEVELOPMENT_PLAN.md). Generated binaries/archives in `dist/` are also ignored. The repository remains local on `main` with no remote publication.
