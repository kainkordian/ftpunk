# FTPunk

A native iOS ramp-test prototype for an Elite Suito-T and Favero Assioma PRO MX-2 pedals. The trainer controls resistance; the pedals supply the power used for the result. Testing, analysis, and history work locally. Optional Intervals.icu upload uses a durable queue.

## Run on iPhone

1. Install full Xcode with the iOS SDK. Swift command-line tools alone cannot build an iPhone application.
2. Open `FTPunk.xcodeproj` and select the **FTPunk** scheme.
3. In Signing & Capabilities, choose your development team and, if necessary, a unique bundle identifier.
4. Run on an iPhone running iOS 18 or later. Use **Demo mode** first to explore setup, recording, results, and history. Demo rides use synthetic data, run at 12× speed, and cannot upload or become your adopted FTP.
5. For the hardware prototype, switch Demo mode off, connect the Suito-T and the Assioma master sensor separately, and enable trainer control. Optional heart rate can be connected independently.

The initial hardware path needs validation against your actual firmware. Check acknowledged target changes and stop behavior at a low load before a maximal test. Keep other trainer-control apps closed. Activate/configure/calibrate the pedals in Favero's app, and verify total pedal power and crank length there or with a bike computer.

The setup screen lets you select a current/historical FTP or enter one manually, enter weight in kg, choose either reference ramp, and set warm-up duration. Automatic warm-up uses 50% of the selected FTP. With no existing FTP, the preset's 100 W or 75 W fallback is shown. A manual wattage override is available. Results retain the session's input values and report FTP in W/kg when weight was provided.

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

The optional Mac preview is for inspecting the shared UI. Run it with `swift run FTPunkPreview` on a Mac with compatible developer tools. Use an iPhone for Bluetooth validation.

`Tools/generate_project.py` regenerates the committed Xcode project without XcodeGen or Ruby dependencies. Run it after adding/removing top-level Swift files in `App`. Swift package sources are discovered automatically. GitHub Actions is configured to run package tests and an unsigned iOS Simulator build when the repository is hosted there.

## Modules

| Location | Responsibility |
| --- | --- |
| `App` | SwiftUI screens and application orchestration, with explicit demo/real-device modes. |
| `Sources/FTPunkDomain` | Immutable setup snapshots, ramp definitions, deterministic state machine, time-weighted analysis, repository interfaces. |
| `Sources/FTPunkDevices` | Bounded FTMS/Cycling Power/HR decoding, cadence rollover handling, CoreBluetooth discovery and acknowledged trainer commands. |
| `Sources/FTPunkStorage` | Versioned Core Data SQLite model, atomic session checkpoints, append-only samples, CSV/JSON/TCX export. |
| `Sources/FTPunkIntegrations` | Keychain credentials, Intervals.icu HTTP adapter, immutable upload payloads, and persistent retry queue. |

Storage uses Core Data instead of the original plan's SwiftData choice. It gives this prototype explicit transactions and a versioned model, and compiles with the installed command-line tools, which lack SwiftData macro plugins. Domain types and repository interfaces remain independent of persistence and network services.

## Intervals.icu

The private prototype connects with **your own personal API key** from Intervals.icu's developer settings. The app verifies the athlete identity, stores the credential in Keychain, and keeps it out of activity exports. Enable automatic upload after connecting. Activities queue only after recording, including cooldown, has ended and been saved locally. Retries reuse the same TCX bytes for file-hash deduplication. You can also upload a saved non-demo activity manually.

Pending uploads resume on launch, network recovery, and foreground retry scheduling. This version does not guarantee background delivery after suspension/force-quit. Upload status appears in activity history. Automatic upload excludes interrupted/aborted tests; manual upload remains available. Uploading does not update the athlete's remote FTP or wellness settings.

Public distribution needs a registered and approved Intervals.icu OAuth public client, PKCE login, and a tested redirect URI. That authorization screen is not implemented in this private prototype. No custom server is required by the planned OAuth flow. See the [official integration cookbook](https://forum.intervals.icu/t/intervals-icu-api-integration-cookbook/80090) and [OAuth documentation](https://forum.intervals.icu/t/intervals-icu-oauth-support/2759).

## Current validation boundary

The app is a first implementation, not a hardware-certified release. Remaining validation includes:

- iOS Simulator/device build and visual checks with full Xcode.
- Actual Suito-T GATT capabilities, control/start/stop sequences, and behavior after connection loss.
- Actual Assioma total-power semantics, cadence notification timing, and comparison with a trusted display.
- Resistance-field layout: standard one-byte decoding is the default; the explicit two-byte reference layout is available under Bluetooth diagnostics. No automatic layout guessing is used.
- End-to-end TCX import and account upload with an authorized Intervals.icu account.
- Public OAuth registration/login, device binding persistence/reconnect, and broader lifecycle/release polish.

The foreground-only test policy interrupts an active test on backgrounding or stale essential data. Trainer stop acknowledgement is checked; if communication is lost, software cannot guarantee that braking is released. Exhaustion ends the scored window before its confirmation delay; the first hardware version releases ERG at exhaustion rather than imposing a cooldown target on stalled pedaling. A manually finished ramp can continue through cooldown.

## Repository and reference

`reference_project/` is ignored by Git and is not needed to build or test this repository. It stays on disk for local inspection. The [reference audit](docs/REFERENCE_AUDIT.md) records the inspected source commit and the findings carried into this implementation. The [development plan](docs/DEVELOPMENT_PLAN.md) describes the full intended release and future server boundaries.

The repository is initialized locally on `main`. No remote hosting or publication is required for development.
