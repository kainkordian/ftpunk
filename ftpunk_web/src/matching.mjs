// Power matching, a line-by-line port of Sources/FTPunkDevices/PowerMatcher.swift (same constants, order of operations, gates and caps).
// The estimator relates the two readings, not the target:  meter ≈ gain × trainerReported + offset  (a two-state Kalman filter, live, per ride).
// A fading rider does not change that relationship; the trainer falling below its own command is the fade signal. Samples are { time, watts }.
// Swift rounds halves away from zero and truncates integer division; `roundAway` and Math.trunc keep that.
const roundAway = v => Math.sign(v) * Math.round(Math.abs(v));
const clamp = (v, low, high) => Math.min(high, Math.max(low, v));

/** Work the trainer has done since the app connected to it, in kJ. A cold trainer misreports; warmth lives outside `PowerMatcher` so a second
 *  ride on the same connection starts warm. Only a new trainer connection resets it (the controller keeps one per Bluetooth trainer object). */
export class TrainerWarmth {
  static warmKilojoules = 60;
  static relaxedKilojoules = 120;
  constructor(kilojoules = 0) { this.kilojoules = kilojoules; this.lastTime = null; }
  /** A new ride's clock starts at zero again; the energy stays. */
  beginSession() { this.lastTime = null; }
  /** Feed every new trainer-reported sample once. Gaps longer than 3 s count as 3 s. */
  add(sample) {
    if (!Number.isFinite(sample.time) || !Number.isFinite(sample.watts)) return;
    const last = this.lastTime; this.lastTime = sample.time;
    if (last == null || !(sample.time > last) || !(sample.watts > 0)) return;
    this.kilojoules += sample.watts * Math.min(3, sample.time - last) / 1000;
  }
  /** 1 while cold, falling linearly to 0 between 60 and 120 kJ. Scales the estimator's process noise. */
  get coldness() {
    const { warmKilojoules: warm, relaxedKilojoules: relaxed } = TrainerWarmth;
    return this.kilojoules <= warm ? 1 : Math.max(0, 1 - (this.kilojoules - warm) / (relaxed - warm));
  }
  get isWarming() { return this.kilojoules < TrainerWarmth.warmKilojoules; }
  get percentOfWarmup() { return Math.trunc(Math.min(100, this.kilojoules / TrainerWarmth.warmKilojoules * 100)); }
}

// Measurement
const smoothingSeconds = 2, settleSeconds = 4, minimumCadence = 45, outlierFraction = 0.2;
/** A cold trainer can read 20 % low or more, so until it has warmed the surprise allowed per measurement is larger. */
const coldOutlierFraction = 0.45, measurementSigma = 4;
// Prior and process noise (variance per second).
const priorGainSigma = 0.05, priorOffsetSigma = 5;
const baseGainNoise = 1.7e-7, baseOffsetNoise = 2e-3, warmGainNoise = 2e-5, warmOffsetNoise = 0.05, boostFactor = 4, boostSeconds = 60;
// Controller
const correctionLimit = 0.2, coldCorrectionLimit = 0.35, moveInterval = 3, stepWatts = 3, warmingStepWatts = 6;
// Fade guard
const fadeShortfall = 0.03, fadeAfter = 3, fadeRelease = 5;

/** Status: { kind: 'off' } | { kind: 'warming', percent } | { kind: 'matching', gain, offset } | { kind: 'fadeHold' }. One instance per ride. */
export class PowerMatcher {
  constructor() {
    this.gain = 1; this.offset = 0; this.correction = 0; this.isFading = false; this.fadeSeconds = 0; this.measurementCount = 0; this.lastInnovation = null; this.status = { kind: 'off' };
    this.pGain = priorGainSigma * priorGainSigma; this.pCross = 0; this.pOffset = priorOffsetSigma * priorOffsetSigma;
    this.noiseTime = null; this.meterAverage = null; this.trainerAverage = null; this.averageTime = null; this.lastMeterTime = -Infinity;
    this.target = null; this.settledAt = 0; this.commanded = null; this.lastMove = -Infinity; this.fadeSince = null; this.holdSince = null; this.fadeTick = null;
    this.innovations = []; this.boostUntil = -Infinity; this.lastIssued = null;
  }
  get covariance() { return { gain: this.pGain, cross: this.pCross, offset: this.pOffset }; }
  /** The meter reading to expect for a trainer-reported value. */
  meterEstimate(reported) { return this.gain * reported + this.offset; }
  /** How far the trainer's own reading is from the meter at `watts` reported, as a signed share (+0.04 reads 4 % high). */
  trainerError(reported) { const meter = this.meterEstimate(reported); return reported > 0 && meter > 0 ? (reported - meter) / meter : null; }

  /** The pedals stopped, or the target changed in a way that stops the load (pause, resume, intensity or free-ride change): forget the smoothed
   *  readings and wait for the trainer to settle. The gain and offset estimate is kept. */
  restartSettle(time) {
    this.meterAverage = null; this.trainerAverage = null; this.averageTime = null; this.noiseTime = null;
    this.fadeSince = null; this.holdSince = null; this.fadeTick = null; this.isFading = false;
    this.commanded = null; this.target = null;
    this.settledAt = time + settleSeconds;
  }

  /** Feeds one meter/trainer pair to the estimator. `command` calls this; tests call it directly. */
  observe(meterIn, trainerIn, cadence, time, warmth) {
    if (!Number.isFinite(time)) return;
    const fresh = s => (s && Number.isFinite(s.time) && Number.isFinite(s.watts) && time >= s.time && time - s.time <= 2 ? s : null);
    const meter = fresh(meterIn);
    if (!meter || !(meter.time > this.lastMeterTime)) return;
    this.lastMeterTime = meter.time;
    const trainer = fresh(trainerIn);
    if (!trainer) return;
    if (meter.watts <= 0 || trainer.watts <= 0 || (cadence != null && (!Number.isFinite(cadence) || cadence < minimumCadence))) {
      // Stopped or approaching exhaustion: nothing to learn, and the smoothing is stale afterwards.
      this.meterAverage = null; this.trainerAverage = null; this.averageTime = null; this.settledAt = Math.max(this.settledAt, time + settleSeconds);
      return;
    }
    // Both readings get the same smoothing so the meter's and the trainer's lags line up.
    const alpha = this.averageTime != null ? 1 - Math.exp(-Math.min(5, Math.max(0, meter.time - this.averageTime)) / smoothingSeconds) : 1;
    this.averageTime = meter.time;
    this.meterAverage = this.meterAverage != null ? this.meterAverage + (meter.watts - this.meterAverage) * alpha : meter.watts;
    this.trainerAverage = this.trainerAverage != null ? this.trainerAverage + (trainer.watts - this.trainerAverage) * alpha : trainer.watts;
    if (!(time >= this.settledAt) || this.isFading || this.meterAverage == null || this.trainerAverage == null) return;
    const observed = this.meterAverage, regressor = this.trainerAverage;
    this.spreadNoise(meter.time, warmth);
    const predicted = this.gain * regressor + this.offset;
    const allowed = warmth.isWarming ? coldOutlierFraction : outlierFraction;
    if (!(Math.abs(observed - predicted) <= allowed * observed)) return; // sprints, coasting, dropouts
    const innovation = observed - predicted;
    // P·Hᵀ for H = [regressor, 1].
    const pgx = this.pGain * regressor + this.pCross, pox = this.pCross * regressor + this.pOffset;
    const variance = regressor * pgx + pox + measurementSigma * measurementSigma;
    const kGain = pgx / variance, kOffset = pox / variance;
    this.gain = Math.min(1.6, Math.max(0.6, this.gain + kGain * innovation));
    this.offset = Math.min(50, Math.max(-50, this.offset + kOffset * innovation));
    this.pGain = Math.max(1e-12, this.pGain - kGain * pgx);
    this.pCross -= kGain * pox;
    this.pOffset = Math.max(1e-9, this.pOffset - kOffset * pox);
    this.measurementCount += 1; this.lastInnovation = innovation;
    this.trackInnovation(innovation / Math.sqrt(variance), meter.time);
  }

  spreadNoise(time, warmth) {
    const last = this.noiseTime; this.noiseTime = time;
    if (last == null || !(time > last)) return;
    const seconds = Math.min(10, time - last), cold = warmth.coldness;
    const boost = time < this.boostUntil ? boostFactor : 1;
    this.pGain += (baseGainNoise + cold * (warmGainNoise - baseGainNoise)) * seconds * boost;
    this.pOffset += (baseOffsetNoise + cold * (warmOffsetNoise - baseOffsetNoise)) * seconds * boost;
  }

  /** When the last minute of residuals leans consistently to one side, the error is moves faster than the noise allows for (a cold room, a fan,
   *  a skipped calibration): let the estimate move 4 times faster for a minute. */
  trackInnovation(z, time) {
    this.innovations.push({ time, z });
    this.innovations = this.innovations.filter(i => !(time - i.time > 60));
    const count = this.innovations.length;
    if (count < 15) return;
    let sum = 0; for (const i of this.innovations) sum += i.z;
    const mean = sum / count;
    // Smoothed samples are correlated: count only a quarter of them as independent.
    if (Math.abs(mean) * Math.sqrt(count / 4) > 2) { this.boostUntil = time + boostSeconds; this.innovations = []; }
  }

  /** The ERG command for `watts`: feed-forward on a new target, then at most 3 W (6 W while warming) every 3 s towards the corrected value.
   *  `range` has `minimum`, `maximum` and `quantized(watts)`. */
  command(watts, meter, trainer, cadence, time, range, warmth) {
    if (!Number.isFinite(time)) return range.quantized(watts);
    const newTarget = this.target !== watts;
    if (newTarget) { this.target = watts; this.settledAt = time + settleSeconds; }
    this.updateFadeGuard(trainer, time);
    this.observe(meter, trainer, cadence, time, warmth);

    const goal = watts;
    const limit = warmth.isWarming ? coldCorrectionLimit : correctionLimit;
    const low = Math.max(goal * (1 - limit), range.minimum), high = Math.min(goal * (1 + limit), range.maximum);
    let wanted = Math.min(high, Math.max(low, (goal - this.offset) / this.gain));
    // A fading rider never makes the load harder: the correction may shrink, not grow.
    if (this.isFading && this.commanded != null) wanted = Math.min(wanted, goal + this.correction);
    if (newTarget || this.commanded == null) {
      this.commanded = wanted; this.lastMove = time;        // feed-forward: a new step gets its corrected command at once
    } else if (time - this.lastMove >= moveInterval && Math.abs(wanted - this.commanded) >= 1) {
      const step = warmth.isWarming ? warmingStepWatts : stepWatts;
      this.commanded = this.commanded + Math.min(step, Math.max(-step, wanted - this.commanded)); this.lastMove = time;
    }
    const value = this.commanded ?? goal;
    this.correction = value - goal;
    const issued = range.quantized(roundAway(value));
    this.lastIssued = issued;
    this.status = this.isFading ? { kind: 'fadeHold' } : warmth.isWarming ? { kind: 'warming', percent: warmth.percentOfWarmup } : { kind: 'matching', gain: this.gain, offset: this.offset };
    return issued;
  }

  /** The trainer falling below its own command is the fade signal: it cannot hold the load it was asked for. Judged only once the trainer has
   *  had time to settle after a target change. */
  updateFadeGuard(trainer, time) {
    if (this.fadeTick != null && this.isFading && time > this.fadeTick) this.fadeSeconds += Math.min(2, time - this.fadeTick);
    this.fadeTick = time;
    if (!trainer || this.lastIssued == null || !(time >= this.settledAt) || !(time >= trainer.time) || !(time - trainer.time <= 2)) return;
    if (trainer.watts < this.lastIssued * (1 - fadeShortfall)) {
      this.holdSince = null;
      this.fadeSince ??= time;
      if (this.fadeSince != null && time - this.fadeSince >= fadeAfter) this.isFading = true;
    } else {
      this.fadeSince = null;
      if (this.isFading) {
        this.holdSince ??= time;
        if (this.holdSince != null && time - this.holdSince >= fadeRelease) { this.isFading = false; this.holdSince = null; }
      }
    }
  }
}

/** Cockpit text for a matcher status, as native FTPCockpitView / WorkoutCockpitView show it. */
export function matchingStatusText(status) {
  switch (status?.kind) {
    case 'warming': return `Warming up the trainer · ${status.percent} %`;
    case 'matching': return `Matching · gain ${status.gain.toFixed(3)} · offset ${status.offset >= 0 ? '+' : '−'}${Math.abs(status.offset).toFixed(1)} W`;
    case 'fadeHold': return 'Fade hold · the target will not rise';
    default: return '';
  }
}
