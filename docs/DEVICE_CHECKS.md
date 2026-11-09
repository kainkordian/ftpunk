# Device and account checks (owner)

Everything that needs real hardware, a real account or a human eye. Agents can't do these. Tick them off
here with the date and versions used.

## Queue

| When | Check | From |
|------|-------|------|
| Before/after step 2 | **Reference ride** (protocol in archive/2026-11-04-roadmap/2-power-matching.md): matching off, cold trainer, Z2 then 60–120 % FTP steps. If convenient, once more at a different room temperature or after a spin-down. Run `FTPUNK_REPLAY_CSV=<file> swift test --filter replay` and send the output. | archive/2026-11-04-roadmap/2 |
| After step 2 | Ramp test with Assioma + matching **on**, and one with matching **off**. Compare `power_watts` and `trainer_watts` in the CSV export, especially the last minute. | archive/2026-11-04-roadmap/2 |
| After step 3 | Upload one ramp-test FIT and one workout FIT to COROS Training Hub (Activity List → Import Data). Check power, cadence, HR, laps, sport "Indoor Bike". Check the Training Hub link. Upload the same FIT to Intervals.icu. | archive/2026-11-04-roadmap/3 |
| After step 1 | Two riders with different Intervals.icu accounts: each ride is offered for upload to its own rider's account only. The consent screen lists the settings read permission. | next/1 |
| Any time | Approve one finished ride for upload to Intervals.icu: it arrives as a FIT with distance, speed, calories, work, balance, normalized power, TSS and IF; a ride with an HR strap shows RR/HRV data. | archive/fit-upload-and-load-fields.md |
| Any time | Low-load trainer command/release on the Suito-T, Bluetooth loss, app quit during a ride. | reference/architecture.md |
| Checkpoint B | Run the XCUITests once. VoiceOver, Increase Contrast and Mac keyboard pass on the cockpit. | ROADMAP |

## Safety checks on the real trainer (when convenient)

Target devices: **iPhone 15 Pro / iOS 26.6.2**, a Mac, an Elite Suito-T, Assioma pedals and an
optional HR strap. Record OS and firmware versions, the power/cadence source and the matching
setting with each run. Start at a low load.

| Scenario | Required observation |
|---|---|
| Full-length steady ride and structured target transitions | No unexplained gap, no missing measurements, no replayed target. Note the target-to-acknowledgement latency. |
| Stop with a target command outstanding | No later target increase. Note the stop-to-acknowledgement latency. Failures are reported honestly. |
| Missing optional HR | The ride continues, with HR marked unavailable |
| Missing power or trainer control | The ride is interrupted and released per session policy. The recording is kept. |
| iPhone screen locked | The ride is interrupted and the recording kept. Continued trainer control isn't required. |
| App quit during a ride | The recording is recovered as interrupted. The app never claims a stop acknowledgement it didn't receive. |

The Miyoo companion and the background/browser host were scratched on 2026-11-04. Their earlier
checks are in `archive/evolution-plan.md`.
