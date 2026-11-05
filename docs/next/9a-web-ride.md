# Plan 9a: web ride screen (power matching and Chaindance)

**Runs after plan 8 is merged, in parallel with 9b and 9c.** Size: M–L.
Read "The web parity project" in [8-web-foundation.md](../archive/2026-11-05-web/8-web-foundation.md) first; its rules apply here.

## Files this plan owns

May edit: `src/domain.mjs` (only the matcher), new `src/matching.mjs`, `src/controller.mjs`, `src/scene.mjs`,
new `src/chaindance/`, `src/ui/ride.mjs`, `src/ui/ride.css`, this plan's block in `src/ui/scenarios.mjs`, its own
tests and fixtures. Native side: new Swift test files only.
Don't edit files owned by 9b or 9c. If you need a change in `shell.mjs`, `components.mjs` or `storage.mjs`, make
the smallest possible change and list it in the report (the merge resolves it).

## 1. Power matching: port the native estimator

Today's web matcher (`PowerMatcher` in `domain.mjs`) is the old one: it integrates the meter error against the
target, 3 W per step, ±20 % / ±60 W. The native one (`Sources/FTPunkDevices/PowerMatcher.swift`, decision of
2026-11-04 in the roadmap) instead:

- estimates `meter ≈ gain × trainerReported + offset` live with a two-state Kalman filter, per ride, nothing learned
  across rides;
- tracks `TrainerWarmth` in kJ since the Bluetooth connection (cold model error until 60 kJ, relaxed by 120 kJ),
  which scales process noise; warmth survives a second ride on the same connection and resets on reconnect;
- applies feed-forward on each target change;
- holds (fade guard) when the trainer's *reported* power is more than 3 % below its own command;
- reports a status: off, warming (percent), matching (gain, offset), fade hold.

Port it to `src/matching.mjs` as a line-by-line translation (same constants, same order of operations, same
outlier gate and caps, including the wider gate while warming). Remove the old class.

**Parity fixture:** add a Swift test `PowerMatchingFixtureTests.swift` that runs the native matcher over the
synthetic rides used in `PowerMatchingReplayTests.swift` and `PowerMatchingRampSimulationTests.swift` (cold start,
warm start, fading rider, meter dropout, ramp) and writes, per second, the inputs and the matcher's command and
status to `contracts/fixtures/power-matching-replay.json` (`FTPUNK_WRITE_FIXTURES=1`, else compare). The JS test
feeds the same inputs and must match every command within 0.01 W and every status exactly.
Also port the behavioural tests (converges with ±offset, gain error, never chases a fading rider, clamps to range
without windup, respects freshness and low cadence).

**Controller:** feed the matcher the trainer-reported power (the web's equivalent of
`RideEngine.lastTrainerPower`), keep `TrainerWarmth` on the Bluetooth trainer object so a reconnect resets it,
show the status in the cockpit like native (`FTPCockpitView.swift`, `WorkoutCockpitView.swift`). Recording-only
mode still sends unmodified targets. Keep every existing controller test green (pause/resume resets matching
state but not warmth).

## 2. Chaindance

Port the ride visual. Native sources: `Sources/FTPunkDomain/RideVisual.swift` and `RideVisualMotion.swift`
(state: zones, poses, standing at 7 W/kg or 1.6 × FTP without weight, never during the FTP-test warm-up or ramp),
`App/Features/Ride/RideVisualRaster.swift`, `RideVisualRider.swift`, `PixelCanvas.swift` (the pixel renderer),
`RideVisualStrip.swift` (placement menu Off / Strip / Large, branding name **Chaindance**).

- `src/chaindance/state.mjs` (pure state), `src/chaindance/raster.mjs` (renders into a `Uint8ClampedArray`
  RGBA buffer, no DOM), `src/chaindance/view.mjs` (draws the buffer to a `<canvas>` with
  `image-rendering: pixelated`, at most 12 fps, paused when the tab is hidden).
- Strip: the same raster size and look as native; Large: the 96-row raster with sky, stars, moon, readout in the sky band
  and the two-column layout on wide windows (`CockpitLayout`).
- Reduce motion and increase contrast behave as native (`prefers-reduced-motion`, `prefers-contrast: more`).
- **Pixel parity:** add a Swift test `ChaindanceFixtureTests.swift` that renders a fixed set of states (each
  zone, both modes, standing, coasting, reduce motion, contrast, a few distances/times) and writes their FNV-1a
  fingerprints (the function in `RideVisualRasterTests.swift`) to `contracts/fixtures/chaindance-fingerprints.json`.
  The JS raster must produce identical bytes. If exact parity proves impossible for a specific reason (e.g. a
  Core Graphics colour conversion), stop that part and report the reason with the first differing pixel.
- The placement choice is a preference; the menu must not re-render on every telemetry tick (the native
  flicker bug of 2026-11-04: keep the menu outside the per-tick update path).
- The visual never sends trainer commands.

## 3. Cockpit polish

Bring `src/ui/ride.mjs` to the native cockpits: header (title, clock; compact on narrow screens), target and
power tiles, step countdown ring, phase timeline, coaching text (`CoachingText`), live best minute in the FTP
test, the "…" menu with debug controls when debug mode is on, pause/resume and hold-to-stop as native.

## 4. Scenarios

Add `ride-ftp-cold` (matching warming), `ride-ftp-fade` (fade hold), `ride-workout-large` (Chaindance Large),
`ride-workout-strip` to `src/ui/scenarios.mjs`.

## Acceptance

- `python3 tools/test.py` (with the new fixture tests) and the native `swift test` plus both builds pass.
- Matching fixture and Chaindance fingerprints match, or the report explains exactly where and why not.
- No old matcher code remains.

## Report

Test counts, fixture results, any deviation from native, and what wasn't looked at on a screen.
