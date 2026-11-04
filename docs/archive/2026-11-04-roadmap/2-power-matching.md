# 2 — Power matching: estimate the trainer's error live, never chase a fading rider

This replaces phase 2 of `archive/2026-11-03-feedback/06-power-matching-ramp.md` and both earlier
drafts ("calibrate, then hold" and "learned power profile"). The phase-1 harness
(`Tests/FTPunkTests/PowerMatchingRampSimulationTests.swift`) stays and becomes the acceptance test.

## What we know about the Suito-T's error (owner, 2026-11-04)

- When cold (about the first 5 min) it **underreports heavily**. Once warm, it usually
  **overreports** a little around Z2 and keeps **drifting** slowly.
- The gap **grows with power**.
- The size and the timing depend on **when it was last calibrated** (spin-down), **room
  temperature** and **the ride's load**. A hard ride heats the unit faster than an easy one.

### Why no learned mapping across rides

Every one of those factors changes between rides, and the app can't measure two of them
(calibration state, room temperature). A curve learned last week encodes last week's
conditions. So the design has **no persisted trainer profile**. Each ride estimates the error
from scratch, from the one thing that is always right: the pedals, every second.

The factors don't need to be modelled. They decide **how fast the error can change**, and that
sets how fast the estimator must adapt:

| Factor | Effect on the error | How the design handles it |
|---|---|---|
| Calibration | a constant offset/gain for the whole ride | estimated in the first minutes, then tracked |
| Room temperature | how big the cold error is and how long it lasts | adaptation speed follows the residuals (below), not a fixed 5 min |
| Load | heating speed: higher watts warm the unit faster | the "warming" phase is measured in **work done (kJ)**, not minutes |
| Power level | the gap grows with watts | a gain **and** offset model, so the correction scales with the target |

## The key idea: compare the meter with the trainer's *reported* power, not with the target

The trainer reports its own measured power (Indoor Bike Data; recorded as `trainerPower` in each
sample, `trainer_watts` in the CSV). Estimate the relationship **meter vs. trainer-reported**:

    meter ≈ gain × trainerReported + offset

- **Calibration and thermal errors** change this relationship. That's what we want to correct.
- **A fading rider doesn't change it.** When the rider can't hold the load, the trainer's own
  reading drops too, because it measures the same flywheel. The relationship stays put, and the
  estimator isn't fooled.
- A fade is visible on its own terms: the **trainer is below its own command**
  (`trainerReported < commanded − 3 %`). That's the fade guard, and it doesn't need cadence
  thresholds.

Check that `trainerPower` is present on samples whenever the external meter is the source. If it
isn't on every sample, find out why in `RideEngine` / `BluetoothDevices` and report it before
building on it.

## Design (`Sources/FTPunkDevices/PowerMatcher.swift`, pure)

### Estimator: a small two-state Kalman filter

- State `[gain, offset]`, prior `[1.0, 0 W]`. Offset prior variance is small (≈ 5 W)², gain
  variance (0.05)².
- Measurement: once per fresh sample pair, both EMA-smoothed with the **same** time constant (2 s)
  so the meter and trainer lags line up. Regressor = smoothed trainer-reported power. Use only when:
  - ≥ 4 s after a target change;
  - both readings are fresh (≤ 2 s old) and > 0 W;
  - cadence ≥ 45 rpm;
  - |observed − predicted| ≤ 20 % (outliers such as sprints and coasting are skipped).
- Process noise (random walk) **adapts**:
  - **Warming**: high Q until the trainer has done ~60 kJ of work since this app connected to it
    (≈ 5 min at 200 W, ≈ 8 min at 125 W). Decay Q linearly towards the base value up to 120 kJ.
    The energy is counted from trainer-reported power, for the whole connection, not per ride.
    A second ride right after the first starts warm.
  - **Innovation-adaptive**: if the last 60 s of residuals are consistently on one side
    (|mean| > 2 σ), raise Q ×4 for 60 s. This covers whatever the kJ rule misses: a cold room,
    a fan, a skipped calibration.
  - Base Q: drift of ~1 % per 10 min.
- Without power variation (a constant warm-up), gain and offset can't both be identified. The
  priors keep the offset small, so a constant-power period mostly moves the gain. Once the
  power varies (the ramp, any workout), the offset becomes identifiable.

### Controller

- `command = (target − offset) ÷ gain`, quantized and clamped to the trainer range, and also to
  ±20 % of the target as a sanity cap.
- **Feed-forward on every target change**: a new ramp step gets the corrected command in the same
  tick.
- Between target changes, the command changes by at most ±3 W per 3 s (±6 W while warming), so
  it never fights the trainer's own ERG loop.
- **Fade guard**: when `trainerReported < commanded − 3 %` for ≥ 3 s (the trainer can't hold
  its own target):
  - freeze the estimator;
  - never **raise** the command;
  - lowering stays allowed.

  The guard also covers torque limits at low cadence. It lifts after 5 s of the trainer holding
  again.
- When the rider stops pedalling (power 0, cadence < 45), freeze and restart the settle, as today.

### State across interruptions

Only a new trainer connection resets the warming energy. Only a new session resets the
estimator. Pause/resume (`App/AppModel.swift:548`), free-ride target changes (`:741`) and the
other `PowerMatcher()` resets (`:355`, `:499`, `:530`, `:706`) call `restartSettle(at:)` instead.
Read each call site and keep its intent.

### What the rider sees

- `PowerMatcher.status`: `.off / .warming(percentOfWarmup) / .matching(gain, offset) / .fadeHold`.
- FTP warm-up coaching line while warming: "Trainer warming up — power matching is settling."
- DevicesSheet: "Trainer reads 4 % high at 200 W" (from gain/offset at the current target).
- Ride events (`engine.recordEvent`, no schema change), at ramp start, every 2 min of ramp and at
  ramp end: gain, offset, warming energy, fade-guard time. The owner can see what the matcher did.
- Learn-more text (`SettingsTopic.powerMatching`):
  - the trainer's accuracy depends on calibration, room temperature and how warm it is;
  - the app measures the error against your pedals all ride long;
  - it never makes the ramp harder when you fade;
  - **calibrate the trainer (spin-down in Elite's app) after ~10 min of riding** for the best
    starting point;
  - turn **off** Elite's Power Meter Link while matching is on.

Not in scope: running a spin-down from the app (FTMS Spin Down Control). It needs hardware
testing. Add it as one line under "Parked" in the roadmap.

## Validation

### 1. Simulation (extend the phase-1 harness; don't relax thresholds to pass)

Trainer error model in the harness, with the parameters **varied per scenario** to stand in for
the real factors:

    meterTruth = delivered
    trainerReported = delivered × g(t) + o(t)
    g(t) = gWarm + gCold × exp(−E(t) / E₀)     (E = kJ done, E₀ varies: 40–120 kJ)
    o(t) = calibration offset (−10…+10 W)
    gWarm: 1.00…1.04 plus a 1 %/10 min drift; gCold: −0.10…−0.20 (underreporting when cold)

Run a grid: 3 calibration offsets × 3 warm-up speeds (E₀) × 2 gWarm values, for each:

| Scenario | Must hold |
|---|---|
| Standard ramp, 10 min warm-up | from step 4 on, mean step-end meter error ≤ 3 % in every grid cell |
| Warm-up 0 s (cold ramp start) | ≤ 6 % in steps 1–20, ≤ 3 % after |
| Gentle / Zwift-style presets | ≤ 3 % from step 4 |
| Fading rider (cadence 90 → 50 over the last 60 s, torque limit 70 rpm) | extra commanded load vs matching off in the final 60 s: mean ≤ 3 W, max ≤ 6 W (today 21 / 38 W) |
| Sprint spike in warm-up (5 s at 2 × target) | gain moves < 0.5 % |
| Second ride 5 min after the first | starts in the warm state (no high Q) |
| Pause/resume in a workout | estimator state identical before and after |

Print a table of every grid cell, old matcher vs new, in the report.

### 2. Replay on real rides

Write a Swift test helper (no Python script) that reads a
FTPunk CSV export (`seconds, power_watts, cadence_rpm, trainer_watts`). It runs the estimator over
it and reports the prediction error |meter − (gain × trainer + offset)| per minute. Ship it
as a test that is **skipped** unless `FTPUNK_REPLAY_CSV=<path>` is set, so it runs on the owner's
files without committing them.

## Must not change

Scoring, the 72 % factor, the ramp protocol, exhaustion detection (`RideEngine`, < 45 rpm for 5 s),
the freewheel cool-down, trainer-range clamping. Matching stays off unless the rider turns it on.

## Owner: rides that validate it (physical, when convenient)

1. **Reference ride, matching off**, cold trainer, Assioma as source: 10 min Z2, then 3 min each at
   60, 75, 90, 105 and 120 % FTP, 5 min easy. Export the CSV. Repeat it once in a different room
   temperature, or right after a spin-down, if convenient.
2. Run the replay test on those files:
   `FTPUNK_REPLAY_CSV=<file> swift test --filter replay`. Send the output.
3. Then a ramp test with matching **on**, and compare the meter and the trainer in its CSV.
