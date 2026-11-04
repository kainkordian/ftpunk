# 06 — Power matching during the ramp test

The owner asked: will power matching work with the ramp test, where the target rises
every 12 s? This plan records the analysis and the work to verify and harden it.
**Do phase 1 first and report the numbers to the owner before starting phase 2.**

## How the matcher behaves today (`Sources/FTPunkDevices/PowerMatcher.swift`)

- Outer loop on top of the trainer's own ERG loop. Commanded watts = target + `correction`.
- On every target change: 5 s settle, smoothing (EMA α = 0.3) reset.
- After settling: at most one adjustment every 3 s, step = clamp(0.25 × error, ±3 W),
  dead band 2 W. Correction limited to ±min(60 W, 20 % of target) and to the trainer's range.
- Cadence < 45 rpm or 0 W: correction frozen and settle restarted.
- **`correction` carries over across target changes.** That's what makes it usable in a ramp.

### Standard ramp (+5 W every 12 s)

Each 12 s step: settle 0–5 s, then adjustments at about 5, 8 and 11 s → up to 3
adjustments, ≤ 9 W of correction change per step.

- **Calibration offset (the normal case): works.** A meter that reads e.g. 5 % lower
  than the trainer needs a correction that grows by only ~0.25 W per step (5 % of 5 W).
  Most of the offset is learned during the 10-minute constant warm-up and carries into
  the ramp.
- **Gentle (20 s) and Zwift-style (60 s) presets:** more settled time per step, even better.
- **Warm-up skipped (`warmupSeconds == 0`):** the offset is learned during the first
  ramp steps, at ≤ 9 W per 12 s. A 15 W offset is gone in about 2 steps. Acceptable.
- Scoring is unaffected: the result uses the samples from the selected source (the
  external meter), which is exactly the stream the matcher aims at.

### Where it can go wrong: the last minute

As the rider fades, cadence falls (e.g. 90 → 55 rpm). Many ERG trainers then fall short of
the target (flywheel inertia, torque limit). The meter reads below target. **The matcher
reads this as a calibration error and adds up to +3 W every 3 s**, on top of the
+5 W/12 s ramp. In the final 30–60 s the effective ramp rate can more than double. That
makes the end of the test harder than the protocol intends, and the rider may fail earlier.
The 45 rpm freeze is below the cadence range where this happens.

The same thing happens on short, very hard workout intervals, but only the ramp affects
the FTP result.

### Smaller issues

- The correction is additive. Meter/trainer differences are mostly proportional
  (calibration slope), so an offset learned at 100 W warm-up is too small at 400 W. The
  loop catches up (see above), but a ratio would be right from the first second of each step.
- The first value after each settle is used unsmoothed (EMA restarts from one sample),
  so one noisy sample can cause a 3 W step. Minor.

## Phase 1: simulation tests (no behaviour change)

Add `Tests/FTPunkTests/PowerMatchingRampSimulationTests.swift` with a small simulated
trainer + meter:

- Trainer: first-order lag towards the commanded watts (τ = 1.5 s), quantised by
  `SupportedPowerRange`, plus a "torque limit" option: when cadence < c₀, delivered
  power = commanded × (cadence / c₀).
- Meter: `delivered × scale + offset + noise` (seeded deterministic noise, ±4 W).
- Drive it through a real `RideEngine` (`SessionConfiguration(preset: .standard,
  powerSource: .externalPowerMeter, powerMatchingEnabled: true)`) at 1 Hz ticks, calling
  `PowerMatcher.command` like `AppModel.update()` does (`AppModel.swift` around line 427).

Scenarios. For each, record the mean |meter − target| over the last 5 s of each ramp step,
and the maximum correction change per 12 s:

1. scale 0.95, offset 0, warm-up 600 s, rider never fades.
2. scale 1.05, offset +10 W.
3. Warm-up 0 s, scale 0.93.
4. Gentle and Zwift-style presets with scenario 1.
5. Fading rider: cadence drops linearly 90 → 50 rpm over the last 60 s before the
   ramp ends, torque limit c₀ = 70 rpm.

Expected assertions for 1–4 (write them; if they fail, report the measured values and
don't change thresholds to make them pass): after the first 3 ramp steps, the step-end
error is ≤ 3 % of target.

For 5, record how much extra load the matcher added in the final 60 s compared with
matching off. Put the numbers in your report to the owner.

## Phase 2: hardening — superseded by [next/2-power-matching.md](../../next/2-power-matching.md)

Phase 1 is done. The design below was the first draft; implement next/2-power-matching.md instead.

Proposed changes, each with a test from the phase 1 harness:

1. **Ramp-aware mode.** Add `mode: PowerMatcher.Mode` (`.steady` default, `.ramp`) to
   `command(...)`. `AppModel.update()` passes `.ramp` while `engine.phase == .ramp`. In
   `.ramp`:
   - The correction may move **towards zero freely but away from zero by at most 1 W per
     adjustment** (calibration drift is slow; fading is fast).
   - Freeze when cadence < 65 rpm (instead of 45), or when the error is > 8 % of target
     (a shortfall that large is the rider fading, not calibration).
2. **Proportional correction.** Store `ratio` (commanded / target, init 1.0, limited
   to 0.8…1.2) instead of an additive offset, and update it with the same rate limits
   expressed in watts at the current target. The warm-up calibration then scales
   correctly to ramp powers. Keep the public `correction` property (derived) for the
   existing tests, or update those tests deliberately.
3. Seed the EMA with the mean of the samples in the first second after settling
   instead of a single sample.
4. Update the Learn-more text (`SettingsTopic.powerMatching`) to say what happens in
   the ramp.

Must not change: scoring, cadence-based exhaustion detection (`RideEngine`, < 45 rpm for
5 s), the freewheel cooldown, the trainer-range clamping.

## Owner checks (deferred, physical)

Per `AGENTS.md`, physical trainer checks are deferred. When the owner tests: a ramp
with a power meter and matching on, and the same with matching off. Compare the trainer's
power with the meter's power in the exported activity.
