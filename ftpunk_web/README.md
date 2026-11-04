# FTPunk Web

Chrome browser port of FTPunk, currently nested in the Apple app repository. This directory is self-contained: copy it into a separate repository later without changing runtime paths. The web app has no runtime packages, external scripts, fonts, or image services.

## Training and Cyclepunk

Train offers free ERG with ±10 W controls and offline Easy spin (20 min), Endurance
(30 min), and Tempo intervals (30 min) workouts. Set current FTP to resolve workout
targets. Trainer increments are applied to each outgoing command; out-of-range plans are
rejected. Workout and free ERG rides can pause: the trainer is released, step time
and XP freeze, and fresh pedaling is required to resume at the saved target.
Stop & save remains available while releasing or restarting. FTP ramp tests do
not pause and training rides do not produce FTP estimates.

Enable adventure progress in Train or City. Last Light restores the Lowline radio
and awards a patch after 20 cumulative riding minutes. Fresh, positive power earns
10 XP/minute regardless of intensity; zeros, gaps, waiting and mock rides earn no
credit. Fractional XP survives between rides. Progress and recordings commit in
one IndexedDB transaction, and progress survives recording deletion. Portable v3
backups transfer the library, recordings and progress to the native app; v1/v2 still import.

The library imports FTPunk workout JSON or Intervals cycling event JSON, with timed
ramps and nested repeats. Download an example from Train. Connected Intervals
accounts can download the next 14 days for offline use; unsupported workouts are
listed in the report. Targets resolve once and never follow later FTP/calendar edits.
Workout intensity adjusts ±5 points within 50–150% and trainer capability bounds.
ZWO/FIT/MRC/ERG import is not implemented.

Resistance rides require the advertised FTMS capability plus a valid six-byte
level range. Unsupported/ambiguous ranges disable this option. Levels are trainer
specific, not watts or percentages; matching is off. The City now has original
vector artwork, 0/5/10/20-minute story beats and post-ride unlock receipts.

Hidden-tab hosting remains planned. The standalone browser requires a visible tab
during real rides. Physical trainer behavior, live Intervals CORS and visual review
remain unverified.

## Run locally

From this repository’s root:

```sh
cd ftpunk_web
python3 tools/serve.py
```

Open **http://localhost:8080** in Chrome. Python 3 is the only development-server requirement. No `npm install` is needed. Use `--port 8081` if port 8080 is occupied; browser storage belongs to the origin, so keep the same port to retain access to the same history.

For a device-free walkthrough, choose **No trainer nearby? Try a mock ride** on FTP Test, then Start ramp test. Quick mock mode uses ten-second warm-up and cooldown periods. Choose 60× speed for a short walkthrough. Mock recordings are clearly marked, excluded from real FTP progress, cannot become your current FTP, and cannot upload.

For a live test:

1. Close other applications controlling the trainer. Connect the smart trainer; FTPunk checks ERG support, subscribes to measurements and control indications, reads supported power limits, and requests control.
2. Optionally connect an external Cycling Power meter and heart-rate sensor. For dual-sided pedals, choose the master sensor reporting total power. Once the meter’s notifications are ready, choose **Use power matching** or **Recording only**. The preference defaults to matching on and is also available in Settings.
3. Choose the power source and pedal until fresh readings appear. Cadence comes from the external meter when available, then the trainer. With no fresh cadence, use Finish ramp manually.
4. Select the rider, protocol, warm-up, cooldown, and estimate factor. Start the test. These settings and measurement sources are snapshotted for the recording.
5. Keep the app visible. A live test interrupts and attempts to stop the trainer if the tab becomes hidden; it does not promise background or screen-locked trainer control. Large scheduling gaps and stale essential signals also interrupt the test.
6. Review the saved recording in History. Download JSON, CSV, or TCX; optionally adopt a real result as that rider’s current FTP.

Before a maximal test, validate pairing, target changes, meter matching, and stop behavior at a low load with your actual trainer. Browser/process termination can prevent a final Bluetooth stop command from being delivered.

## What is implemented

- Responsive Train, FTP Test, City, History, and Settings screens with a persistent live-ride link; light, dark, and system appearances; larger ride numbers; keyboard and screen-reader labels; reduced-motion support.
- Standard +5 W / 12 seconds, gentle +5 W / 20 seconds, and Zwift-style +20 W / minute protocols.
- The native app’s deterministic workout state machine, time-weighted best complete 60-second ramp window, 72%/75% estimate, and 72–77% reference range. Zeros count; missing measurements do not fill themselves.
- Sustained fresh low-cadence exhaustion detection, optional cadence, manual finish, target/cadence/power freshness policies, and free-spin recovery after automatic exhaustion.
- FTMS ERG, Cycling Power meters, and Heart Rate sensors through Web Bluetooth. Packet validation, explicit resistance-field layouts, and bounded packet capture.
- Serialized FTMS control commands that wait for matching Control Point indications. A successful GATT write alone is insufficient.
- Power matching: five-second settling after target changes; correction updates at most every three seconds; at most 3 W of correction per update before trainer quantization; maximum correction ±20% or ±60 W, whichever is smaller; clamped to the trainer range without integrator windup. Zero watts and low cadence suspend correction.
- Fixed per-session measurement sources, independent freshness timestamps, and no silent fallback from a lost external meter to trainer watts.
- IndexedDB rider profiles, current FTP and FTP history, per-second session checkpoints, interruption recovery, JSON backups, and recording deletion. Web Locks prevent two tabs owning workouts simultaneously.
- Optional Intervals.icu API-key connection and explicit per-recording upload consent naming the rider and destination. Only approved, account-bound queued jobs retry; a stable external ID supports duplicate detection. Credentials exist in memory for the current tab and are never stored in IndexedDB, preferences, or backups.
- Offline app-shell caching and an install manifest. A service-worker update does not forcibly replace an active ride.
- Procedural pixel cycling scene and a measured-power chart, with numeric equivalents on the dashboard.

## Browser and integration boundaries

Use current Chrome on a supported platform, over HTTPS or localhost. Opening `index.html` through `file://` does not work. Web Bluetooth requires a user-initiated device chooser. On Linux, Chrome’s Web Bluetooth support may require its experimental web-platform feature flag; the exact Linux Bluetooth stack must be tested.

The web app does not synchronize history with the Mac/iPhone apps. Browser-local data is tied to the scheme, host, and port; clearing site data removes it. Settings offers portable backup export/import shared with Mac and iPhone. Import previews the riders, replaces matching identities (not matching names), preserves unrelated riders, and atomically stores a rollback backup before replacing data. Download the latest rollback through **Download pre-import backup**; the browser retains three. Importing does not recreate upload approvals or include credentials. Archives are limited to 64 MiB and finalized ramp tests, training activities, cached workouts and Cyclepunk progress. Older `ftpunk-web` backups also import through the browser adapter. Individual raw session JSON exports are not portable profile archives.

Intervals.icu uses the API-key option in this version. Registered browser OAuth redirects and production OAuth setup are not included. API requests go directly to Intervals.icu, so the service must permit the web origin through CORS. Live API access has not been exercised with user credentials. Reconnect after refreshing or closing the tab to retry approved uploads. Disconnecting does not delete remote activities or pending local approvals.

## Tests and build

With Node 22 or later:

```sh
npm test
```

There are no dependencies to install. This checks syntax, self-contained import paths, and asset references, then runs the domain/protocol/controller/archive/integration suite using simulated devices and HTTP responses. The packet and workout fixtures are ported from the Swift tests. The shared portable v1/v2/v3 and ramp/repeat import fixtures are also read directly by Swift tests. Coverage includes control acknowledgements and timeouts, connection setup, malformed data, meter dropouts, source isolation, scoring boundaries, delayed trainer response, power matching, session recovery, persistence failure, tab ownership, and upload consent/account isolation.

Alternatively, with the development server running, open **http://localhost:8080/tests/**. It runs the same suite plus isolated real-IndexedDB round-trip, restore, rollback-backup and duplicate-import checks. Test storage uses a unique database, not your real recordings.

Create a static deployable directory:

```sh
python3 tools/build.py
python3 tools/serve.py --dist
```

Deploy the contents of `dist/` to an HTTPS static host. There is no backend. Generated output is ignored by Git. The app is designed for a subdirectory as well as a domain root; all runtime assets and service-worker paths are relative.

## Structure

| Path | Purpose |
| --- | --- |
| `src/domain.mjs` | Configuration, ramp engine, FTP analysis, matching, synthetic ride input |
| `src/protocol.mjs` | Packet decoders, command encoding, source routing, freshness |
| `src/bluetooth.mjs` | Browser pairing, GATT notifications, acknowledged FTMS commands |
| `src/controller.mjs` | Workout ownership, scheduling, trainer commands, checkpoints, stopping |
| `src/storage.mjs` | IndexedDB, preferences, cross-tab ride lease, recovery and atomic archive restore |
| `src/archive.mjs` | Portable archive validation and native/browser adapters |
| `src/export.mjs` | JSON download, CSV, TCX |
| `src/intervals.mjs` | Memory-only credentials, explicit approvals, queued upload retries |
| `src/app.mjs`, `src/style.css` | Browser interface |
| `src/scene.mjs` | Pixel cycling scene and measured-power chart |
| `tests/` | Portable test suite and browser test page |
| `tools/` | Local server, static export, syntax/asset checks |

Modern ES modules keep this initial port runnable without a frontend toolchain. Pure workout logic and device adapters are separate so a future TypeScript migration or native adapter can be introduced independently.

## Verification status

The automated 58-test suite, JavaScript syntax/import/asset checks, static export, and local HTTP content-type checks pass. Chrome/Brave UI automation was blocked by the development environment’s organization policy, and its in-app browser was unavailable. Visual layout, actual browser IndexedDB execution, offline installation, real Bluetooth hardware, and live Intervals.icu access still need browser/device acceptance testing. These are not claimed as verified by the simulated tests. The separate `tests/storage-suite.mjs` passed under a temporary `fake-indexeddb` 6.2.7 implementation, exercising the v1 database upgrade, repeated imports, unrelated rider preservation, rollback retention, transaction abort after scheduled writes, and reopen. This adds no runtime dependency and does not replace the real-Chrome storage check.

References: [Chrome Web Bluetooth](https://developer.chrome.com/docs/capabilities/bluetooth), [page lifecycle](https://developer.chrome.com/docs/web-platform/page-lifecycle-api), [Screen Wake Lock](https://www.w3.org/TR/screen-wake-lock/), [Intervals.icu API](https://www.intervals.icu/features/open-api/).
