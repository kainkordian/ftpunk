# FTPunk iOS development plan

Build a native iPhone app that controls an Elite Suito-T in ERG mode and uses Favero Assioma PRO MX-2 pedals as the source for power and cadence. Tests and history work offline. Store results locally, offer optional automatic activity upload to Intervals.icu, and keep explicit boundaries for adding account sync later.

The first deliverable should be a working connection and recording prototype on the actual trainer and pedals. Reliable Bluetooth decoding, control acknowledgements, and measurement timing determine whether the FTP estimate is useful.

## Product scope

### First release

| Feature | Behavior |
| --- | --- |
| Device setup | Assign separate roles for trainer control, pedal power, and optional Bluetooth heart rate. Remember selected devices and show connection and data freshness separately. |
| Readiness check | Require fresh pedal power and cadence, trainer target-power capability, and confirmed control permission before starting. Show battery where exposed and remind the rider to verify pedal activation, crank length, and calibration in the vendor apps. |
| FTP and rider weight | Select the current adopted FTP, a dated historical FTP, or a manually entered existing FTP. Enter rider weight in kg and remember it for the next test. Snapshot both inputs when the session starts. |
| Ramp configuration | Offer the reference project's two ramps, editable warm-up duration, warm-up power defaulting to 50% of the selected existing FTP, a manual wattage override, a preview, and an explicit upper power and duration limit. Name presets by ramp rate rather than “heavy” and “light.” |
| Guided test | Wait for pedaling, warm up, increase ERG targets on schedule, detect sustained cadence failure, then offer cooldown. Provide an always-visible finish/stop control. |
| Ride display | Show pedal watts, target watts, pedal cadence, elapsed time, next target countdown, and optional heart rate. Offer a readable landscape view, large controls, optional audio cues, and a target-versus-power chart. |
| Result | Show best continuous 60-second measured power, estimated FTP range, the chosen FTP factor, FTP in W/kg using the session's weight, data quality, and reason for ending. Compare with the selected existing FTP and let the rider explicitly adopt a new FTP value. |
| History | Store sessions, charts, protocol settings, FTP changes, notes, and optional body mass for W/kg. Snapshot mass and adopted FTP so old results stay reproducible. |
| Export and recovery | Export CSV samples, versioned JSON session data, and a TCX activity through the share sheet. Recover saved data after termination as an interrupted session. Support local deletion. |
| Intervals.icu | Optional account connection and an automatic-upload toggle. After the activity is finalized and saved, queue a TCX upload, report its status, and retry safely after network failure. |
| Connection failures | Distinguish lost power data, lost trainer control, stopped pedaling, and a missing optional heart-rate sensor. Preserve the recording and explain why a test is incomplete. |

Favero documents power, cadence, and dual-sided balance over ordinary Bluetooth. Include L/R balance only if exposed and decoded with a known reference side; advanced cycling dynamics are outside the first release. Initial activation, firmware updates, crank-length setup, and vendor-specific calibration stay in Favero/Elite apps. [Favero device guidance](https://cycling.favero.com/faq/)

### Later additions

- FIT export, HealthKit workout export, and optional Strava upload.
- More structured workouts using the same execution engine, including a separate 20-minute FTP protocol.
- Validated pedal-based power matching, trainer-versus-pedal comparison, and additional FTMS trainers.
- iPad layouts, Live Activity status, and a companion Apple Watch interface.
- Optional account backup, multi-device history, and remotely supplied workout definitions.

Keep subscriptions, social features, GPS routes, ANT+ accessories, and remote trainer control outside the initial scope. All test, result, history, and file-export workflows must work without internet access or an account. Intervals.icu upload is optional and requires a connection only when uploading or authorizing access.

### FTP selection and rider weight

On the setup screen, default to the current adopted FTP and offer a picker of previous FTP entries with their dates and wattages, plus a manual existing-FTP entry. Selecting an old value changes the setup input for this session; it does not replace the profile's current adopted FTP. New users can enter their existing FTP or choose a manual warm-up wattage without inventing an FTP history entry.

Default warm-up intensity to 50% of the selected FTP, following the reference's warm-up guidance. For example, selecting 250 W yields a 125 W warm-up. Show the calculated watts immediately, round to the trainer's supported increment, and disclose any range adjustment before starting. Preserve an explicit manual wattage override. With no FTP selected, offer the reference preset's 100 W or 75 W warm-up as a visible fallback. Changing the selected FTP updates derived warm-up watts only while automatic mode is active; switching back from manual mode recalculates them.

Keep the selected prior FTP separate from the new test estimate. Store its entry ID, value, date/source, the warm-up mode and fraction, and the final warm-up target in the session snapshot. The selected FTP sets warm-up power; the selected ramp preset still determines the ramp's starting watts and increments.

Accept positive, finite rider weight in kg with decimal input, prefilled from the profile and editable before each test. Store the measurement date and session weight snapshot. Calculate result W/kg as estimated FTP watts divided by that weight; calculate the displayed range endpoints the same way. For example, 240 W at 75 kg is 3.20 W/kg. Label best-minute power per kg separately if included, so it cannot be confused with FTP per kg. Use unrounded values for calculation and round only for display.

Without a valid weight, allow the test and report watts, but leave W/kg unavailable with an option to add weight. A later correction to a specific session explicitly revises its weight and derived W/kg; changing the profile alone never changes past results. Adopting the new FTP appends a dated history entry for future warm-ups.

## Hardware connections and power control

| Role | Connection | Purpose |
| --- | --- | --- |
| Elite Suito-T | Bluetooth FTMS service `0x1826` | Read trainer capabilities, set ERG targets, and monitor machine status. |
| Assioma PRO MX-2 | Bluetooth Cycling Power service `0x1818` | Receive measured power and derive cadence; inspect the actual advertised pedal configuration during the hardware prototype. |
| Optional HR strap | Bluetooth Heart Rate service `0x180D` | Record/display heart rate without making it a prerequisite for the test. |

Elite lists FTMS support for Suito-T. Favor service discovery and advertised capabilities over device-name matching. The exact firmware and exposed characteristics must be recorded during the prototype. [Elite Suito-T specification](https://www.elite-it.com/uploads/product/catalog_box_cta_file_en/188/SUITO-T_FU_2025_EN.pdf)

Pair the pedal power stream once and verify that it represents total dual-sided power. Do not double the reported value or sum two independently discovered pedal values without establishing their meaning. Confirm the expected master sensor and totals against the Favero app or a bike computer.

For the first release, send the prescribed target directly to the trainer's own ERG controller. Calculate FTP exclusively from pedal measurements. A trainer target of 250 W does not guarantee that the pedals report exactly 250 W; display sustained target deviation and preserve both streams.

Elite's Power Meter Link can use an external meter and can revert to trainer-estimated power when that meter is unavailable. Treat its configuration as a separate, hardware-validated operating mode, recorded as user-confirmed or unknown unless the device exposes trustworthy status. Continue reading the pedals directly. Configure PML in Elite's app; do not assume standard FTMS can configure it. [Elite Power Meter Link](https://elitesrl.zendesk.com/hc/en-us/articles/4403492516242-Power-Meter-Link-PML-function)

Introduce an app-based correction controller only if hardware tests demonstrate a need. It must have filtered input, limited correction, a deadband, anti-windup, and suspension during low cadence, stale readings, and target transitions. Never combine app correction with PML. Keep this behind a `PowerControlStrategy` boundary from the beginning without implementing the extra controller in version one.

## Reference functionality to preserve

The source is `reference_project/ftpunk`, inspected at commit `f8daa4e5da3e5f00f24fffae79ee514b8ac041ac`. The detailed findings and packet experiments are in [Reference project audit](REFERENCE_AUDIT.md).

| Setting | 25 W per minute preset | 15 W per minute preset |
| --- | --- | --- |
| Ramp starting target | 100 W | 50 W |
| Target increment | 5 W every 12 seconds | 5 W every 20 seconds |
| Reference default warm-up | 10 minutes at 100 W | 10 minutes at 75 W |
| Default cooldown | 75 W | 50 W |
| Start condition in reference | Cadence reaches 20 rpm | Cadence reaches 20 rpm |
| End condition in reference | Cadence falls below 45 rpm | Cadence falls below 45 rpm |

Use the two ramp profiles as named, versioned definitions. Let riders choose rather than inferring a protocol from weight or sex. In the iOS app, default warm-up watts to 50% of the selected existing FTP; the table's reference wattages are fallbacks and manual choices. Preserve configurable warm-up duration. Treat the 20 rpm and 45 rpm values as starting behavior for validation, adding sustained detection and freshness checks instead of triggering on a single reading.

The reference computes 72–77% of its best 60 stored power values. The iOS result should present the measured best 60-second power and this estimated range, with 72% as a conservative suggested training value and an explicit 75% alternative. Record the applied factor; never silently overwrite the rider's adopted FTP. The range is a training heuristic, not a statistical confidence interval. Ramp rate and protocol affect comparability. [Richard Stern on MAP protocols and FTP estimation](https://www.cyclecoach.com/blog/2020/2/2/is-the-map-ramp-test-a-valid-estimator-of-ftp)

## Technology choices

| Area | Decision | Reason |
| --- | --- | --- |
| Language and UI | Swift 6 with SwiftUI | Native device lifecycle, accessibility, and direct integration with Apple's Bluetooth APIs. |
| Minimum OS | iOS 18 initially | A practical baseline for a new personal app; revisit if the intended phone needs an older version. Use the current stable Xcode SDK when implementation begins. |
| Bluetooth | CoreBluetooth directly | The integration needs explicit subscription, command, reconnection, and indication handling. Keep vendor behavior visible. |
| Concurrency | Swift concurrency with an actor owning the workout; a serial CoreBluetooth delegate queue | Serialize state transitions and commands while keeping sensor processing off UI rendering. |
| Charts | Swift Charts | Native live and historical plots with no chart dependency. |
| Storage | Core Data with a local SQLite store and explicit model versions | Atomic checkpoints and append-only samples without third-party dependencies. Hide persistence behind repository protocols and pass domain values across boundaries. This replaces the initial SwiftData choice; the installed command-line SDK lacks its macro plugin. |
| Dependencies | Swift Package Manager; Apple frameworks first | Keep maintenance and Bluetooth troubleshooting manageable. Add a FIT library only when implementing FIT export. |
| Activity upload | URLSession, AuthenticationServices, and Keychain | Direct Intervals.icu uploads and native OAuth authorization without a custom server. TCX export initially avoids a FIT dependency. |
| Verification | Swift Testing for parsers/domain; XCTest for app UI | Exercise binary decoding and time-driven behavior with injected clocks and transport simulations. |

CoreBluetooth is Apple's supported framework for communicating with these BLE peripherals. [Apple CoreBluetooth documentation](https://developer.apple.com/documentation/corebluetooth?changes=_6)

## Architecture

Use a small modular native application with dependency injection at the app entry point. Start with four local Swift package targets and the application target:

```text
FTPunkApp
  Features: Devices, TestSetup, ActiveTest, Results, History, Settings, Connections
  Presentation: SwiftUI views and observable screen models

FTPunkDomain       Foundation models, protocols, ramp engine, FTP calculator
FTPunkDevices      CoreBluetooth transport, FTMS/CPS/HR decoders, device adapters
FTPunkStorage      Core Data repositories, migrations, CSV/JSON/TCX export, upload outbox
FTPunkIntegrations Intervals.icu client, authorization, upload worker
```

`FTPunkDevices`, `FTPunkStorage`, and `FTPunkIntegrations` depend on `FTPunkDomain`. The domain target does not import SwiftUI, CoreBluetooth, Core Data, or networking frameworks. The app composes implementations; a view never sends raw Bluetooth bytes. The upload worker receives saved activity files and an outbox repository, keeping networking outside the workout engine.

Expose a small set of interfaces: `TrainerController`, `PowerSensor`, `HeartRateSensor`, `SessionRepository`, `ProfileRepository`, `WorkoutClock`, `ActivityUploader`, and `UploadQueueRepository`. Device events carry source identity, connection generation, sequence, receipt time, and decoded optional fields. Retain field-specific measurement times so a cadence-only notification cannot refresh power freshness.

Send events from the serial Bluetooth queue through one ordered consumer into the workout actor. Avoid starting an independent unstructured task per notification. Keep CoreBluetooth objects within their transport boundary and pass immutable values onward. Persistence uses its own isolated context; UI updates run on the main actor.

The initial prototype serializes CoreBluetooth delegates and a pure value-type ramp engine on the main actor. The domain state machine takes explicit monotonic offsets and is tested without a UI. Moving orchestration/persistence to dedicated actors remains a performance and reliability task before the full release; the prototype already fails closed on a material scheduling delay.

The workout state machine is:

```text
Idle -> Preparing -> WaitingForPedaling -> WarmUp -> Ramp -> Cooldown -> Completed
                                  any active phase -> Interrupted or Aborted
```

Keep the test result outcome separate from cooldown execution: exhaustion can end a successful test while recovery continues; a technical interruption must not become a normal successful completion. Warm-up may be paused. Pausing or losing essential data during the measured ramp ends its validity; reconnection enables a new attempt rather than resuming the same scored test.

## Bluetooth protocol implementation

### Trainer decoder and commands

Implement a bounds-checked byte cursor with explicit little-endian integer reads. Preserve the reference's flag-driven field order, inverted instantaneous-speed presence condition, speed scaling, cadence scaling, and signed watts. Model absent fields as absent. Reject truncated packets before mutating current readings.

Resolve the reference's resistance-field width against captures before finalizing its adapter. The current GATT supplement specifies one byte; the reference advances two. Any required Suito firmware exception must be selected explicitly and backed by a recorded fixture. Do not guess between layouts from whether the resulting watts look plausible. [Bluetooth GATT supplement, Indoor Bike Data](https://btprodspecificationrefs.blob.core.windows.net/gatt-specification-supplement/GATT_Specification_Supplement.pdf)

Treat a notification as a characteristic value, not an arbitrary serial byte stream. For FTMS records spanning notifications, parse each notification's flags and assemble fields until the terminating More Data value. Bound assembly time and reject incomplete records. Never concatenate complete notification payloads as though their repeated flag bytes were data.

Read Fitness Machine Feature and Supported Power Range. Subscribe to Indoor Bike Data, Fitness Machine Status, and Control Point indications before requesting control. Serialize control procedures; match response opcode, request opcode, and result. A successful GATT write does not establish command success. Implement start/resume and stop/pause behavior as required by the discovered device and verify the sequence on Suito-T. [Bluetooth FTMS specification, sections 4.16–4.19](https://www.bluetooth.org/DocMan/handlers/DownloadDoc.ashx?doc_id=423422)

Clamp and quantize targets to the discovered range and increment. Track prescribed, sent, and acknowledged targets separately. On timeout, permission loss, or disconnect, discard queued targets and invalidate the current connection generation. Never replay a backlog of missed ramp increments after reconnecting.

### Pedal decoder

Implement Cycling Power Measurement `0x2A63` independently of FTMS. Decode mandatory signed watts and optional fields using its own flags. Derive cadence from crank revolution and event-time deltas, accounting for counter rollover, unchanged events, reconnects, and resets. For crank event ticks, cadence is `60 * deltaRevolutions * 1024 / deltaTicks`; reject zero or implausible deltas. Capture actual Assioma payloads as fixtures. [Bluetooth GATT supplement, Cycling Power Measurement](https://btprodspecificationrefs.blob.core.windows.net/gatt-specification-supplement/GATT_Specification_Supplement.pdf)

Keep trainer cadence and power as separate diagnostic values. Optional cadence fallback must be visible and recorded, and must not silently change the FTP power source. If the pedal power stream becomes unavailable, end the scored test as interrupted.

## Timing and FTP calculation

Compute phase and target from elapsed monotonic time and the immutable protocol definition. UI timers only repaint. Scheduling delays or wall-clock changes must not alter ramp rate. Record intended and acknowledged command times; sustained control delay makes the test incomplete rather than silently extending an interval.

Store decoded sensor events at their incoming rate. For analysis, construct a time-weighted power signal with an explicitly versioned sample-hold policy and freshness limit. Compute the highest integral over a continuous, valid 60-second window within the measured ramp, divided by 60. Do not average “the last 60 notifications,” use smoothed display power, substitute trainer targets, or bridge a dropout.

Use a provisional maximum power-sample age of 2 seconds for analysis, to be validated against observed pedal notification cadence. Mark longer gaps missing. Preserve valid measured zeros as zeros; missing data must remain distinct. Display smoothing, such as a 3-second average, does not change the recorded signal or result.

Require at least one complete valid 60-second ramp window. A test with a material sensor/control interruption remains interrupted even if an earlier window exists; show that earlier power as diagnostic data without presenting an adopted FTP recommendation. A rider who manually finishes early receives an explicitly marked early-ended estimate when data allow, rather than a claim of reaching exhaustion.

For automatic exhaustion, begin validation with pedal cadence below 45 rpm for 5 continuous seconds after a 10-second ramp grace period. Both power-stream freshness and cadence-event interpretation must be valid. Timestamp the onset of the sustained failure and exclude the confirmation delay from the scored endpoint. Tune these proposed values on hardware; missing packets never count as physiological failure.

## Lifecycle and resistance handling

Keep the display awake during the active test and include `NSBluetoothAlwaysUsageDescription`. Design for CoreBluetooth state restoration and `bluetooth-central` background handling, but ship a foreground test policy first. If backgrounding, locking, suspension, or a long scheduling gap compromises control timing, end the scored ramp and save an interruption. Background Bluetooth events do not guarantee continuous workout scheduling. [Apple background Bluetooth guidance](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)

On finish or interruption with a live trainer link, cancel future ramp commands, attempt the validated low-load/stop sequence, and record acknowledgements. A normal cooldown uses its configured low power target. On exhausted or stalled pedaling, use the validated release-from-ERG behavior rather than assuming a zero-watt target removes braking. Stop is always immediately available without a confirmation dialog.

An app cannot guarantee resistance release after losing its connection. Verify Suito-T behavior on Bluetooth loss, app termination, and control takeover before first release, and make failure status visible. On reconnection, reacquire control at a low load after an explicit rider action; never restore the previous high target automatically.

## Intervals.icu activity upload

Include optional Intervals.icu upload in the first release, after the core local recording works. Generate a TCX activity containing timestamps, measured pedal power through the cycling power extension, cadence, optional heart rate, and lap/phase boundaries for warm-up, ramp, and cooldown. Export no fabricated GPS track or missing measurements as zeros. Validate the indoor cycling classification, stream import, elapsed time, and lap boundaries against an actual Intervals.icu import before release. FIT export remains a later addition.

Upload completed activity files with multipart `POST https://intervals.icu/api/v1/athlete/0/activities`, supplying the file and a stable `external_id` derived from the session UUID. Intervals.icu accepts TCX and supports this authenticated-athlete alias. Use a descriptive name and include protocol, selected prior FTP, session weight, and test outcome in the description; keep the app's FTP estimate clearly identified. [Intervals.icu integration cookbook](https://forum.intervals.icu/t/intervals-icu-api-integration-cookbook/80090)

Use OAuth authorization code flow with S256 PKCE through `ASWebAuthenticationSession`, registering the app as a public client and registering its exact redirect URI. Request `ACTIVITY:WRITE`, validate OAuth state, and store credentials in Keychain. Intervals.icu documents public-client PKCE without a client secret, so this integration needs no custom server. OAuth app approval is an implementation dependency. A personal API key stored in Keychain is a supported alternative for a private prototype using the owner's own data. [Intervals.icu OAuth documentation](https://forum.intervals.icu/t/intervals-icu-oauth-support/2759)

After connecting, the rider can enable automatic upload for future finalized activities. Save locally first, then enqueue after cooldown ends or the rider finishes the activity; do not upload at ramp exhaustion while cooldown is still recording. Interrupted or aborted sessions remain available for deliberate manual upload with their outcome in the title/description. History supports manual upload of older sessions. Never update Intervals.icu's FTP, weight, or wellness settings automatically as a side effect of uploading an activity.

Persist an upload job with destination account identity, session UUID, immutable export file, content hash, status, attempt count, last error, and returned activity IDs. Bind each job to the authorized account so signing into a different account cannot redirect queued uploads. Show queued, uploading, uploaded, and action-required states with manual retry. Retry transient errors with bounded backoff, respect rate-limit retry guidance, and pause for reauthorization on authentication failure. Reuse exactly the same file bytes after a timeout: Intervals.icu documents deduplication by file hash, with 201 for new activities and 200 for duplicates. Treat `external_id` as correlation, not an assumed idempotency guarantee. [Intervals.icu upload API](https://intervals.icu/api/v1/docs)

Attempt upload after saving while foregrounded, resume pending jobs on app launch and network recovery, and use iOS background transfer opportunities where appropriate. Automatic upload is eventual; offline use and force-quitting cannot guarantee immediate delivery. Disabling automatic upload cancels pending automatic jobs; disconnecting also clears credentials and stops that account's jobs, revoking OAuth access when reachable. Explain that already uploaded activities remain on Intervals.icu. Delete local credentials/files according to their own lifecycles, and keep secrets out of session exports and logs.

## Local data and future server support

Persist these domain records with app-generated UUIDs and versioned representations:

| Record | Important fields |
| --- | --- |
| RiderProfile | UUID, optional weight in kg and measurement date, current adopted FTP entry ID, preferences. No account required. |
| FTPEntry | UUID, FTP watts, effective date, source/manual origin, optional originating result ID. Preserve history when a new FTP is adopted. |
| DeviceBinding | Role, local peripheral identifier, optional model/serial/firmware, last capability snapshot. Bluetooth identifiers are local pairing hints, not global server identities. |
| TestProtocol | ID and version, warm-up/ramp/cooldown settings, limits, analysis factor and failure policy. Each session stores a snapshot. |
| TestSession | UUID, UTC start, monotonic offsets, protocol snapshot, selected prior FTP snapshot, session weight/date, warm-up mode/fraction/final watts, device/source snapshots, control strategy, outcome, interruption/end reason. |
| SensorSample | Session and source IDs, sequence, receipt offset, optional device event counters, optional measurements, field freshness/quality. |
| SessionEvent | Phase changes, sent/acknowledged targets, sensor loss, user actions, and errors. |
| FTPResult | Best-window bounds and coverage, measured power, coefficient/range, algorithm version, quality, session weight revision, derived W/kg, and explicitly adopted FTP. |
| ActivityUploadJob | Destination/account identity, session and export revision, file path/hash, status/attempts/errors, returned remote activity IDs. Credentials live only in Keychain. |

Use explicit batched saves at most one second apart during a test and flush on phase changes and completion. Verify recovery under forced termination; disclose the possible unsaved final batch. Avoid a single growing JSON array as primary storage. Keep raw packet capture in a bounded, opt-in diagnostic file, separate from normal samples and excluded from future sync by default.

Introduce server support through a separate `SyncService` and remote DTOs later. The local repository remains the read source. Reuse the durable outbox pattern introduced for Intervals.icu, but keep future account sync separate from third-party activity uploads. Reserve stable record IDs, schema versions, modification revisions, and explicit deletion semantics now. Workout execution never waits for a network call.

A future API should support idempotent session upload keyed by UUID, paginated incremental download, schema negotiation, and deletion tombstones. Treat original samples/protocol snapshots as immutable; version edited notes, session weight corrections, and adopted FTP separately. Use revision checks for mutable conflicts and ensure deletes cannot be undone by an old upload retry. Add the app's own account authentication with the server feature; Intervals.icu authorization remains independent.

Defer backend vendor selection until the server requirements exist. A small versioned HTTP API with PostgreSQL and object storage for sample chunks is a reasonable later shape; it does not require sharing Swift code or exposing managed persistence objects over the wire.

## Development sequence and acceptance gates

The estimates below are planning ranges for one experienced iOS developer with regular access to both devices. Hardware discoveries can change them. A practical MVP including optional Intervals.icu upload is approximately 7–10 weeks; OAuth app approval can add external waiting time.

| Phase | Estimate | Deliverables and acceptance gate |
| --- | --- | --- |
| 0 Reference and protocol baseline | 2–3 days | Preserve the reference commit/license, finalize parser findings, define protocol versions and fixtures. Resolve the resistance-width question with real packets. |
| 1 Hardware prototype | 4–6 days | Connect trainer and pedals simultaneously on an iPhone, record both streams, request control, change targets, and validate stop/control-loss behavior. Record firmware and total pedal-power semantics. Gate all further control work on this. |
| 2 Device and domain foundation | 5–7 days | Swift package boundaries, robust decoders, command queue, simulator/replay transport, deterministic clock and state machine. Parser/control failure cases pass. |
| 3 Guided test | 5–7 days | Device setup, readiness, current/historical/manual FTP selection, weight input, derived/manual warm-up, both ramp presets, ride display, end detection, stop and cooldown. Complete an entire simulated and real test without duplicate starts or target backlog. |
| 4 Results and local storage | 4–6 days | Time-weighted analysis, provenance/quality, FTP W/kg, session input snapshots, FTP history, charts, CSV/JSON/TCX export, schema migration, and interrupted-session recovery. Export/replay reproduces the stored result. |
| 4a Intervals.icu integration | 3–5 days | Approved OAuth public client with PKCE, Keychain credentials, validated TCX import, durable upload queue, status/retry/disconnect. Verify one remote activity after repeated identical retries and no upload before recording is finalized. |
| 5 Device reliability and release | 5–8 days | Real Suito-T/Assioma validation, lifecycle/error matrix, accessibility, long-run recording, offline use, signing, and TestFlight packaging. Close all critical control/data-loss failures. |

### Required verification

- Binary fixtures cover both FTMS More Data states, optional fields before power, signed values, short packets, resistance layout, and multi-notification records. CPS fixtures cover balance/torque/wheel fields before crank data, counter rollover, resets, and stale cadence.
- Transport simulations cover successful writes followed by failed indications, unexpected opcodes, missing responses, permission loss, disconnects, and callbacks from an old connection.
- A fake clock proves exact 12/20-second ramp boundaries, delayed callbacks, command lateness handling, single completion, and exclusion of warm-up/cooldown and failure-confirmation delay.
- Analysis cases distinguish real zeros from missing samples, reject incomplete windows, and reproduce 60-second integrals with irregular sample timing and partial final ramp intervals.
- Setup checks cover current/historical/manual FTP selection, 50% warm-up calculation, manual override behavior, missing FTP fallback, decimal weight entry, invalid values, and trainer target rounding. A 250 W FTP produces a 125 W warm-up when supported; a 240 W result at 75 kg reports 3.20 W/kg. Profile edits leave existing session snapshots unchanged.
- Persistence checks cover restart after termination, interrupted sessions, migrations, export round-trip, and deletion. No result depends on a view remaining alive.
- Integration checks cover OAuth state/PKCE, denial/revocation, offline queuing, restart/retry, 200/201 duplicate responses, ambiguous timeouts, rate limits, account changes, and disconnect. Validate TCX power/cadence/HR/laps on Intervals.icu and verify that uploads do not change remote FTP or wellness settings.
- Hardware runs cover both presets, low cadence, low/high target transitions within validated limits, trainer/pedal disconnects independently, Bluetooth off/on, incoming calls, screen lock, backgrounding, and another app taking trainer control.
- Verify complete setup, test, result, history, export, and deletion with network access disabled. Compare decoded pedal values with a trusted display and validate command application against observed trainer response.

The release gate is a complete offline ramp test with the selected FTP driving warm-up power, traceable pedal measurements, acknowledged trainer commands, reproducible FTP and W/kg analysis, saved history, and understood failure behavior on the actual Suito-T/Assioma setup. With Intervals.icu connected and automatic upload enabled, the finalized activity must eventually upload once connectivity permits without creating duplicates on retry.
