import { validatePlan, stepAt, trainingTarget, supportsIntensity } from './training.mjs';
// Ported from FTPunkDomain. No browser APIs: the workout clock is supplied by its owner.
export const PRESETS = Object.freeze({
  standard: { title: '25 W / min', start: 100, step: 5, seconds: 12, cooldown: 75, warmup: 100, audience: 'Reference guideline · 60 kg and above' },
  gentle: { title: '15 W / min', start: 50, step: 5, seconds: 20, cooldown: 50, warmup: 75, audience: 'Reference guideline · below 60 kg' },
  zwift: { title: '20 W / min', start: 100, step: 20, seconds: 60, cooldown: 75, warmup: 100, audience: 'Zwift-style · one-minute steps' },
});
export const PHASES = { riding: 'Training', paused: 'Paused', waiting: 'Start pedaling', warmup: 'Warm-up', ramp: 'Ramp test', cooldown: 'Cooldown', completed: 'Activity saved', interrupted: 'Test interrupted' };
export const OUTCOMES = { completed: 'Ride complete', exhaustion: 'Ramp complete', finishedEarly: 'Finished early', limitReached: 'Test limit reached', interrupted: 'Test interrupted', aborted: 'Stopped' };
export const uuid = () => crypto.randomUUID();
export const clamp = (n, a, b) => Math.min(b, Math.max(a, n));
export function configuration(input = {}) {
  const c = { protocolVersion: 3, preset: 'standard', priorFTP: null, weightKG: null, warmupSeconds: 600, cooldownSeconds: 180, maximumPower: 600, maximumRampSeconds: 1800, ftpFactor: 0.72, riderID: null, riderName: 'You', powerSource: 'trainer', cadenceSource: 'trainer', powerMatchingEnabled: true, ...structuredClone(input) };
  if (!PRESETS[c.preset]) throw Error('Choose a valid ramp protocol.');
  if (typeof c.riderName !== 'string' || !c.riderName.trim() || c.riderName.trim().length > 80) throw Error('Enter a rider name (up to 80 characters).');
  if (c.priorFTP != null && (!Number.isFinite(c.priorFTP) || c.priorFTP <= 0 || c.priorFTP > 32767)) throw Error('FTP must be a positive number, up to 32767 W.');
  if (c.weightKG != null && (!Number.isFinite(c.weightKG) || c.weightKG <= 0)) throw Error('Weight must be a positive number in kg.');
  c.usesAutomaticWarmup = c.manualWarmupPower == null;
  c.warmupPower = c.manualWarmupPower ?? Math.round(c.priorFTP != null ? c.priorFTP * 0.5 : PRESETS[c.preset].warmup);
  if (![c.warmupSeconds, c.cooldownSeconds].every(n => Number.isFinite(n) && n >= 0 && n <= 3600) || !Number.isInteger(c.warmupPower) || c.warmupPower < 1 || c.warmupPower > 32767) throw Error('Enter valid warm-up and cooldown values.');
  if (!Number.isInteger(c.maximumPower) || c.maximumPower < PRESETS[c.preset].start || c.maximumPower > 32767 || !Number.isFinite(c.maximumRampSeconds) || c.maximumRampSeconds < 60 || ![0.72, 0.75].includes(c.ftpFactor)) throw Error('Enter valid test limits and FTP factor.');
  if (!['trainer', 'externalPowerMeter'].includes(c.powerSource) || !['trainer', 'externalPowerMeter', 'unavailable'].includes(c.cadenceSource)) throw Error('Choose valid measurement sources.');
  c.powerMatchingEnabled = c.powerSource === 'externalPowerMeter' && c.powerMatchingEnabled === true;
  c.riderName = c.riderName.trim();
  return Object.freeze(c);
}
export function rampPower(c, elapsed) { const p = PRESETS[c.preset]; return Math.min(c.maximumPower, p.start + Math.floor(clamp(elapsed, 0, c.maximumRampSeconds) / p.seconds) * p.step); }
export function analyze(samples, start, end, factor = 0.72, weightKG = null) {
  if (![start, end, factor].every(Number.isFinite) || end - start < 60 || factor <= 0 || (weightKG != null && (!Number.isFinite(weightKG) || weightKG <= 0))) throw Error('A complete, fresh 60-second power window is required.');
  if (!samples.every((s, i) => Number.isFinite(s.time) && Number.isFinite(s.watts) && (i === 0 || samples[i - 1].time < s.time))) throw Error('Power sample times or values are invalid.');
  const segments = samples.map((s, i) => ({ start: Math.max(start, s.time), end: Math.min(end, samples[i + 1]?.time ?? end, s.time + 2), watts: s.watts })).filter(s => s.end > s.start);
  const candidates = new Set([start, end - 60]);
  for (const s of segments) for (const t of [s.start, s.end, s.start - 60, s.end - 60]) if (t >= start && t + 60 <= end) candidates.add(t);
  let best = null;
  for (const window of [...candidates].sort((a, b) => a - b)) {
    let cursor = window, energy = 0;
    for (const s of segments) {
      if (s.end <= window || s.start >= window + 60) continue;
      const a = Math.max(window, s.start), b = Math.min(window + 60, s.end);
      if (a > cursor + 1e-6) break;
      energy += (b - a) * s.watts; cursor = b;
    }
    if (cursor >= window + 60 - 1e-6 && (!best || energy / 60 > best.bestMinutePower)) best = { bestMinutePower: energy / 60, windowStart: window, windowEnd: window + 60, factor, weightKG, algorithmVersion: 1, estimatedFTP: energy / 60 * factor, lowerFTP: energy / 60 * 0.72, upperFTP: energy / 60 * 0.77, wattsPerKG: weightKG ? energy / 60 * factor / weightKG : null };
  }
  if (!best || best.bestMinutePower <= 0) throw Error('A complete, fresh 60-second power window is required.');
  return best;
}
export class RampEngine {
  constructor(config, { demo = false, date = new Date().toISOString(), devices = [], training = null } = {}) {
    this.phase = 'waiting'; this.target = null; this.phaseStartedAt = 0; this.lastTick = 0; this.lastAnalysis = -Infinity; this.lowCadenceSince = null; this.lastPower = null; this.lastCadence = null; this.liveBest = null;
    if (training) training = validatePlan(training);
    this.trainingStartedAt = null; this.pausedAt = null; this.pausedSeconds = 0; this.freeRideTarget = training?.resistance == null ? training?.steps[0].watts : null; this.resistanceLevel = training?.resistance ?? null; this.intensity = 100;
    this.session = { training, id: uuid(), startedAt: date, configuration: structuredClone(config), isDemo: demo, devices, samples: [], events: [], outcome: null, result: null, endedAtOffset: null };
  }
  get active() { return !['completed', 'interrupted'].includes(this.phase); }
  get freewheel() { return this.phase === 'cooldown' && this.session.outcome === 'exhaustion'; }
  receive(s) {
    if (!this.active || !Number.isFinite(s.time) || s.time < 0) return;
    s = { ...s };
    if (Number.isFinite(s.power)) {
      if (!this.lastPower || s.time > this.lastPower.time) {
        this.lastPower = { time: s.time, watts: s.power };
      }
      else delete s.power;
    }
    if (Number.isFinite(s.cadence) && s.cadence >= 0 && (!this.lastCadence || s.time > this.lastCadence.time)) this.lastCadence = { time: s.time, rpm: s.cadence };
    this.session.samples.push({ ...s });
  }
  event(time, message) { this.session.events.push({ time, message }); }
  transition(phase, time) { this.phase = phase; this.phaseStartedAt = time; this.event(time, PHASES[phase]); }
  tick(time) {
    if (!this.active || !Number.isFinite(time) || time < this.lastTick) return;
    const delta = time - this.lastTick; this.lastTick = time;
    if (this.phase === 'paused') return;
    if (delta > 3 && this.phase !== 'waiting') return this.interrupt(time, 'Workout scheduling was interrupted.');
    const c = this.session.configuration, p = PRESETS[c.preset];
    const fresh = this.lastPower && time >= this.lastPower.time && time - this.lastPower.time <= 2;
    if (this.phase !== 'waiting' && !fresh) return this.interrupt(time, 'Power from the selected source is no longer fresh.');
    const cadenceFresh = this.lastCadence && time >= this.lastCadence.time && time - this.lastCadence.time <= 2;
    if (this.phase === 'waiting') {
      const moving = c.cadenceSource === 'unavailable' ? this.lastPower?.watts > 0 : cadenceFresh && this.lastCadence.rpm >= 20;
      if (fresh && moving) {
        if (this.session.training) { this.trainingStartedAt = time; this.transition('riding', time); this.target = this.session.training.kind === 'freeRide' ? this.freeRideTarget : trainingTarget(this.session.training, 0, this.intensity); return; }
        this.transition(c.warmupSeconds === 0 ? 'ramp' : 'warmup', time);
        if (this.phase === 'ramp') this.session.rampStart = time;
        this.target = this.phase === 'ramp' ? p.start : c.warmupPower;
      }
    } else if (this.phase === 'riding') {
      const current = stepAt(this.session.training, this.trainingTime(time));
      if (!current) { this.session.outcome = 'completed'; this.end(time); }
      else this.target = this.session.training.kind === 'freeRide' ? this.freeRideTarget : trainingTarget(this.session.training, this.trainingTime(time), this.intensity);
    } else if (this.phase === 'warmup' && time - this.phaseStartedAt >= c.warmupSeconds) {
      const boundary = this.phaseStartedAt + c.warmupSeconds;
      this.transition('ramp', boundary); this.session.rampStart = boundary; this.target = p.start;
    } else if (this.phase === 'ramp') {
      const elapsed = time - this.phaseStartedAt;
      if (time - this.session.rampStart >= 60 && time - this.lastAnalysis >= 1) {
        const start = Math.max(this.session.rampStart, time - 63);
        try { this.liveBest = Math.max(this.liveBest ?? 0, analyze(this.powerSamples().filter(s => s.time >= start - 2), start, time).bestMinutePower); } catch { /* Not enough fresh coverage yet. */ }
        this.lastAnalysis = time;
      }
      if (c.cadenceSource !== 'unavailable' && !cadenceFresh) return this.interrupt(time, 'Cadence from the selected source is no longer fresh.');
      if (elapsed >= c.maximumRampSeconds || p.start + Math.floor(elapsed / p.seconds) * p.step > c.maximumPower) return this.finishRamp(time, 'limitReached');
      this.target = rampPower(c, elapsed);
      if (c.cadenceSource !== 'unavailable' && elapsed >= 10 && this.lastCadence.rpm < 45) {
        this.lowCadenceSince ??= time;
        if (time - this.lowCadenceSince >= 5) this.finishRamp(this.lowCadenceSince, 'exhaustion', time);
      } else this.lowCadenceSince = null;
    } else if (this.phase === 'cooldown' && time - this.phaseStartedAt >= c.cooldownSeconds) this.end(time);
  }
  trainingTime(time) { return this.trainingStartedAt == null ? 0 : Math.max(0, (this.pausedAt ?? time) - this.trainingStartedAt - this.pausedSeconds); }
  get trainingElapsed() { return this.trainingTime(this.session.endedAtOffset ?? this.lastTick); }
  get resumeTarget() { return this.session.training?.kind === 'freeRide' ? this.freeRideTarget : this.session.training ? trainingTarget(this.session.training, this.trainingElapsed, this.intensity) : null; }
  canResume(time) {
    const power = this.lastPower, cadence = this.lastCadence;
    return this.phase === 'paused' && Number.isFinite(time) && time >= this.lastTick && power?.watts > 0 && time >= power.time && time - power.time <= 2 &&
      (this.session.configuration.cadenceSource === 'unavailable' || cadence && time >= cadence.time && time - cadence.time <= 2 && cadence.rpm >= 20);
  }
  pause(time) {
    if (!this.session.training || !['waiting', 'riding'].includes(this.phase) || !Number.isFinite(time) || time < this.lastTick) return false;
    this.tick(time); if (!['waiting', 'riding'].includes(this.phase)) return false;
    this.phaseBeforePause = this.phase; this.pausedAt = time; this.phase = 'paused'; this.target = null;
    this.event(time, 'Training paused; trainer release requested'); return true;
  }
  resume(time) {
    if (!this.canResume(time)) return false;
    if (this.trainingStartedAt != null) { this.pausedSeconds += time - this.pausedAt; this.phaseStartedAt += time - this.pausedAt; }
    this.pausedAt = null; this.phase = this.phaseBeforePause; this.phaseBeforePause = null; this.lastTick = time;
    this.target = this.phase === 'riding' ? this.resumeTarget : null;
    this.event(time, 'Training resumed'); return true;
  }
  get currentStep() { return this.session.training ? stepAt(this.session.training, this.trainingElapsed) : null; }
  get targetResistance() { return this.phase === 'riding' ? this.resistanceLevel : null; }
  setIntensity(percent, time, minimum = 1, maximum = 32767) {
    if (!this.active || this.session.training?.kind !== 'workout' || !supportsIntensity(this.session.training, percent, minimum, maximum)) return false;
    this.intensity = percent;
    if (this.phase === 'riding') this.target = trainingTarget(this.session.training, this.trainingElapsed, percent);
    this.event(time, `Workout intensity changed to ${percent}%`); return true;
  }
  adjustResistance(level, time) {
    if (!this.active || this.resistanceLevel == null || !Number.isInteger(level) || level < 0 || level > 32767) return;
    this.resistanceLevel = level; this.event(time, `Resistance target changed to ${level / 10}`);
  }
  adjustERG(watts, time) {
    if (!this.active || this.resistanceLevel != null || this.session.training?.kind !== 'freeRide' || !Number.isInteger(watts) || watts < 1 || watts > 32767) return;
    this.freeRideTarget = watts; if (this.phase === 'riding') this.target = watts;
    this.event(time, `ERG target changed to ${watts} W`);
  }
  powerSamples() {
    // Strictly increasing source samples, including zero watts; never fill gaps.
    return this.session.samples.filter(s => Number.isFinite(s.power)).map(s => ({ time: s.time, watts: s.power }));
  }
  finishRamp(time, outcome = 'finishedEarly', cooldownStart = time) {
    if (this.phase !== 'ramp') return;
    const s = this.session, c = s.configuration;
    s.outcome = outcome; s.rampEnd = time;
    if (['exhaustion', 'finishedEarly'].includes(outcome)) {
      try { s.result = analyze(this.powerSamples(), s.rampStart, time, c.ftpFactor, c.weightKG); } catch { s.result = null; }
      this.liveBest = s.result?.bestMinutePower ?? this.liveBest;
    }
    s.cooldownStart = cooldownStart; this.transition('cooldown', cooldownStart);
    this.target = outcome === 'exhaustion' ? null : PRESETS[c.preset].cooldown;
    if (c.cooldownSeconds === 0) this.end(cooldownStart);
  }
  end(time) {
    if (!this.active) return;
    if (this.phase === 'ramp') this.finishRamp(time);
    this.session.outcome ??= 'aborted'; this.session.endedAtOffset = time; this.transition('completed', time); this.target = null;
  }
  interrupt(time, reason) {
    if (!this.active) return;
    if (this.phase !== 'cooldown') { this.session.outcome = 'interrupted'; this.session.result = null; }
    this.session.endReason = reason; this.session.endedAtOffset = time; this.transition('interrupted', time); this.target = null;
  }
}
export class PowerMatcher {
  constructor() { this.correction = 0; this.target = null; this.settledAt = 0; this.lastAdjustment = -Infinity; this.lastSampleTime = -Infinity; this.smoothed = null; }
  command(watts, sample, cadence, time, range) {
    if (!Number.isFinite(time)) return range.quantized(watts);
    const limit = Math.min(60, watts * 0.2);
    if (this.target !== watts) { this.target = watts; this.settledAt = time + 5; this.smoothed = null; }
    const lower = Math.max(-limit, range.minimum - watts), upper = Math.min(limit, range.maximum - watts);
    this.correction = clamp(this.correction, lower, upper);
    if (sample && Number.isFinite(sample.time) && Number.isFinite(sample.watts) && time >= sample.time && time - sample.time <= 2 && sample.time > this.lastSampleTime) {
      this.lastSampleTime = sample.time;
      if (sample.watts <= 0 || (cadence != null && (!Number.isFinite(cadence) || cadence < 45))) { this.smoothed = null; this.settledAt = time + 5; }
      else if (time >= this.settledAt) {
        this.smoothed = this.smoothed == null ? sample.watts : this.smoothed * 0.7 + sample.watts * 0.3;
        if (time - this.lastAdjustment >= 3) {
          const error = watts - this.smoothed;
          if (Math.abs(error) > 2) this.correction = clamp(this.correction + clamp(error * 0.25, -3, 3), lower, upper);
          this.lastAdjustment = time;
        }
      }
    }
    return range.quantized(Math.round(watts + this.correction));
  }
}
export function mockSample(time, target, phase, scenario = 'exhaustion') {
  const exhausted = scenario === 'exhaustion' && phase === 'ramp' && target > 300;
  return { time, power: scenario === 'powerDropout' && time > 75 ? null : Math.max(0, target * (exhausted ? 0.4 : 1) + 2 * Math.sin(time / 3)), cadence: scenario === 'cadenceDropout' && time > 75 ? null : exhausted ? 28 : 88 + 3 * Math.sin(time / 7), heartRate: Math.round(Math.min(190, 100 + target * 0.2)), trainerPower: target };
}
