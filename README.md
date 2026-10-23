# FTPunk

A native iOS ramp-test prototype for an Elite Suito-T and Favero Assioma PRO MX-2 pedals. The trainer controls resistance; the pedals supply the power used for the result. Testing, analysis, and history work locally. Optional Intervals.icu upload uses a durable queue.

## Run on iPhone

1. Install full Xcode with the iOS SDK. Swift command-line tools alone cannot build an iPhone application.
2. Open `FTPunk.xcodeproj` and select the **FTPunk** scheme.
3. In Signing & Capabilities, choose your development team and, if necessary, a unique bundle identifier.
4. Run on an iPhone running iOS 18 or later. **Debug mode · no devices** is enabled initially so you can explore setup, recording, results, and history immediately.
5. For the hardware prototype, switch Debug mode off, connect the Suito-T and the Assioma master sensor separately, and enable trainer control. Optional heart rate can be connected independently.

The initial hardware path needs validation against your actual firmware. Check acknowledged target changes and stop behavior at a low load before a maximal test. Keep other trainer-control apps closed. Activate/configure/calibrate the pedals in Favero's app, and verify total pedal power and crank length there or with a bike computer.

The setup screen lets you select a current/historical FTP or enter one manually, enter weight in kg, choose either reference ramp, and set warm-up duration. Automatic warm-up uses 50% of the selected FTP. With no existing FTP, the preset's 100 W or 75 W fallback is shown. A manual wattage override is available. Results retain the session's input values and report FTP in W/kg when weight was provided.

## Try it without cycling devices

With full Xcode installed and its first-launch setup complete, start a dedicated virtual iPhone:

```sh
sh Tools/run_simulator.sh
```

The launcher builds, installs, and opens FTPunk with an isolated in-memory preview profile (250 W FTP, 75 kg). Select **Start debug test**. On the Ride screen you can:

- Play generated power, cadence, and heart rate at 1×, 4×, 12×, or 60× speed.
- Set exact values with sliders, including zero power or cadence.
- Pause/resume the stream, skip warm-up, or advance 60 seconds.
- Simulate power loss, cadence loss, or trainer disconnection.
- Complete a test and inspect its FTP estimate, W/kg, chart, and history.

The default mock rider eventually exhausts as the ramp passes 300 W. Quick debug tests use a 10-second warm-up and cooldown. Disable that option to exercise normal durations. The generated samples pass through the same ramp engine and analysis as real samples. Debug activities never upload or become an adopted FTP.

Until full Xcode and an iOS Simulator runtime are installed, the same SwiftUI screens can run as a native Mac app:

```sh
sh Tools/run_preview.sh
```

This preview is for UI and local behavior; it does not replace an iOS build or Bluetooth validation. Preview launches use in-memory history and skip loading existing account credentials. For a repeatable walkthrough that leaves a result on screen and captures this app's views in `/tmp/ftpunk-preview`, run `sh Tools/run_preview.sh --preview-walkthrough`.

## Build and test

```sh
swift test
```

For a command-line-only Swift installation whose default engine fails to load Swift Testing macros, use `sh Tools/test.sh` instead. This uses the installed macro plugin explicitly and does not download dependencies. That is the test path verified on this workspace's Swift 6.4 toolchain.

This compiles the four library modules and the shared SwiftUI screens through a native Mac preview target, and runs packet, ramp, analysis, storage, export, and upload-queue tests. The libraries have no external package dependencies. A full Xcode install is still needed for the iOS target and Simulator.

```sh
xcodebuild -project FTPunk.xcodeproj -scheme FTPunk \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Use an iPhone for Bluetooth validation.

`Tools/generate_project.py` regenerates the committed Xcode project without XcodeGen or Ruby dependencies. Run it after adding/removing top-level Swift files in `App`. Swift package sources are discovered automatically. GitHub Actions is configured to run package tests and an unsigned iOS Simulator build when the repository is hosted there.

## Modules

| Location | Responsibility |
| --- | --- |
| `App` | SwiftUI screens, native authentication browser, application orchestration, and explicit debug/real-device modes. |
| `Sources/FTPunkDomain` | Immutable setup snapshots, ramp definitions, deterministic state machine, time-weighted analysis, repository interfaces. |
| `Sources/FTPunkDevices` | Bounded FTMS/Cycling Power/HR decoding, cadence rollover handling, CoreBluetooth discovery and acknowledged trainer commands. |
| `Sources/FTPunkStorage` | Versioned Core Data SQLite model, atomic session checkpoints, append-only samples, CSV/JSON/TCX export. |
| `Sources/FTPunkIntegrations` | Keychain credentials, Intervals.icu HTTP adapter, immutable upload payloads, and persistent retry queue. |

Storage uses Core Data instead of the original plan's SwiftData choice. It gives this prototype explicit transactions and a versioned model, and compiles with the installed command-line tools, which lack SwiftData macro plugins. Domain types and repository interfaces remain independent of persistence and network services.

## Intervals.icu

The normal connection flow is **Connect Intervals.icu → sign in → approve activity uploads**, using Apple's authentication browser and OAuth with S256 PKCE. Users do not need an API key. Tokens are stored in Keychain and excluded from activity exports. No custom server or embedded client secret is needed for an approved public client.

**Live sign-in needs a one-time app registration and approval.** The repository contains the sign-in implementation but leaves the public client ID empty. Until configured, Connections explains that registration is pending. Follow [Intervals.icu configuration](Configuration/IntervalsOAuth.md) to register the app and set its client ID. A personal API-key fallback remains under advanced developer options in debug mode; existing private connections are migrated automatically.

Enable automatic upload after connecting. Activities queue only after recording, including cooldown, has ended and been saved locally. Retries reuse the same TCX bytes for file-hash deduplication. You can also upload a saved real-device activity manually.

Pending uploads resume on launch, network recovery, and foreground retry scheduling. This version does not guarantee background delivery after suspension/force-quit. Upload status appears in activity history. Automatic upload excludes interrupted/aborted tests; manual upload remains available. Uploading does not update the athlete's remote FTP or wellness settings.

See the [official integration cookbook](https://forum.intervals.icu/t/intervals-icu-api-integration-cookbook/80090) and [OAuth documentation](https://forum.intervals.icu/t/intervals-icu-oauth-support/2759).

## Current validation boundary

The app is a first implementation, not a hardware-certified release. Remaining validation includes:

- iOS Simulator/device build and visual checks with full Xcode.
- Actual Suito-T GATT capabilities, control/start/stop sequences, and behavior after connection loss.
- Actual Assioma total-power semantics, cadence notification timing, and comparison with a trusted display.
- Resistance-field layout: standard one-byte decoding is the default; the explicit two-byte reference layout is available under Bluetooth diagnostics. No automatic layout guessing is used.
- End-to-end TCX import and account upload with an authorized Intervals.icu account.
- OAuth registration and live authorization/denial/revocation, device binding persistence/reconnect, and broader lifecycle/release polish.

The foreground-only test policy interrupts an active test on backgrounding or stale essential data. Trainer stop acknowledgement is checked; if communication is lost, software cannot guarantee that braking is released. Exhaustion ends the scored window before its confirmation delay; the first hardware version releases ERG at exhaustion rather than imposing a cooldown target on stalled pedaling. A manually finished ramp can continue through cooldown.

## Repository and reference

`reference_project/` is ignored by Git and is not needed to build or test this repository. It stays on disk for local inspection. The [reference audit](docs/REFERENCE_AUDIT.md) records the inspected source commit and the findings carried into this implementation. The [development plan](docs/DEVELOPMENT_PLAN.md) describes the full intended release and future server boundaries.

The repository is initialized locally on `main`. No remote hosting or publication is required for development.
