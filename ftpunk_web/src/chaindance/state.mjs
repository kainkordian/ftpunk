import { PRESETS } from '../domain.mjs';
// Chaindance state: a port of Sources/FTPunkDomain/RideVisual.swift and RideVisualMotion.swift. Pure: no DOM, no clock.
// The visual only reads a ride; nothing here ever reaches the trainer.
// Swift rounds halves away from zero and truncates integer division; `roundAway` and Math.trunc keep that.
export const roundAway = v => Math.sign(v) * Math.round(Math.abs(v));

export const BRAND_NAME = 'Chaindance';
export const HeroLayout = Object.freeze({ stripRows: 60, heroRows: 96, skyRows: 36, readoutFraction: 36 / 96 });

/** Intensity zones of the workout profile charts, by raw value 0...5. */
export const ZONES = Object.freeze(['recovery', 'endurance', 'tempo', 'sweetSpot', 'threshold', 'vo2max']);
export const ZONE_TITLES = Object.freeze(['Recovery', 'Endurance', 'Tempo', 'Sweet spot', 'Threshold', 'VO2max']);
export const zoneForFraction = fraction => {
  if (!Number.isFinite(fraction)) return fraction > 0 ? 5 : 0;
  const percent = roundAway(fraction * 100);
  return percent < 56 ? 0 : percent <= 75 ? 1 : percent <= 87 ? 2 : percent <= 94 ? 3 : percent <= 105 ? 4 : 5;
};
/** The zone of a power against an FTP; null without an FTP or a usable power. */
export const zoneOf = (power, ftp) => (power == null || !Number.isFinite(power) || power < 0 || ftp == null || !Number.isFinite(ftp) || ftp <= 0 ? null : zoneForFraction(power / ftp));

/** Rider postures, in order of how low they sit. */
export const Posture = Object.freeze({ upright: 0, hoods: 1, low: 2, drops: 3, standing: 4 });

export const NOMINAL_CADENCE = 85, PEDALLING_CADENCE = 10, MAXIMUM_ANIMATION_RATE = 4, LEVEL_PREVIEW_SECONDS = 6, STEP_PREVIEW_SECONDS = 10;
/** The rider stands from 7 W/kg; without a weight, from 1.6 × FTP (above the end of a ramp test); never without either. */
export const STANDING_WATTS_PER_KG = 7, STANDING_FTP_FACTOR = 1.6, STANDING_HOLD_FRACTION = 0.85;
export const standingThreshold = (weightKG, ftp) => (Number.isFinite(weightKG) && weightKG > 0 ? STANDING_WATTS_PER_KG * weightKG : Number.isFinite(ftp) && ftp > 0 ? STANDING_FTP_FACTOR * ftp : null);

export const postureForZone = zone => (zone == null || zone === 1 ? Posture.hoods : zone === 0 ? Posture.upright : zone <= 3 ? Posture.low : Posture.drops);
export const districtFor = zone => ({ kind: zone === 0 ? 'residential' : 'market', zone });
export const sameDistrict = (a, b) => a?.kind === b?.kind && a?.zone === b?.zone;
const clock = seconds => { const whole = roundAway(seconds); return `${Math.trunc(whole / 60)}:${String(whole % 60).padStart(2, '0')}`; };

/** The trail behind the bike: its length in pixels and whether it is dim. */
export function trailOf(state) {
  if (state.posture === Posture.standing) return { length: 36, dim: false };
  switch (state.zone) { case 0: return { length: 6, dim: true }; case 1: return { length: 9, dim: false }; case 2: return { length: 15, dim: false }; case 3: return { length: 24, dim: false }; case 4: return { length: 30, dim: false }; case 5: return { length: 36, dim: false }; default: return { length: 9, dim: false }; }
}
export const showsSweat = s => s.zone === 4 || s.zone === 5 || s.posture === Posture.standing;
export const showsSpeedLines = showsSweat;
export const showsSparks = s => s.zone === 5 || s.posture === Posture.standing;

/**
 * Derives the visual state from a ride. `input`:
 * { mode: 'ftpTest'|'workout'|'freeERG'|'resistance', phase, power, cadence, cadenceAvailable = true, ftp, playbackSpeed = 1,
 *   ramp: { phaseSeconds, warmupSeconds, cooldownSeconds, stepSeconds, rampSeconds, bestMinuteWatts }, step: { index, count, startWatts, endWatts, seconds, remaining, next: { seconds, startWatts, endWatts } },
 *   target, weightKG, sprintPower, sprintPeak }.
 * Only the FTP test leaves the flat boulevard: it climbs the Spire during the ramp. Nothing predicts where a ramp will end.
 */
export function rideVisualState(input) {
  const { mode, phase } = input, cadenceAvailable = input.cadenceAvailable ?? true;
  const rate = Number.isFinite(input.playbackSpeed ?? 1) ? Math.min(MAXIMUM_ANIMATION_RATE, Math.max(1, input.playbackSpeed ?? 1)) : 1;
  const power = Number.isFinite(input.power) && input.power >= 0 ? input.power : null;
  const zone = zoneOf(power, input.ftp);
  const cadence = input.cadence ?? null;
  let motion;
  if (phase === 'paused') motion = 'footDown';
  else if (cadenceAvailable) motion = (cadence ?? 0) >= PEDALLING_CADENCE ? 'pedalling' : 'coasting';
  else motion = (power ?? 0) > 5 ? 'pedalling' : 'coasting';

  // Standing: a sprint at the threshold, or smoothed power still near it right after a one-second window reached it.
  // The FTP test's warm-up and ramp say "stay seated", so the rider never stands there.
  const seatedPhase = mode === 'ftpTest' && ['waiting', 'warmup', 'ramp'].includes(phase);
  let standing = false;
  const threshold = standingThreshold(input.weightKG, input.ftp);
  if (motion === 'pedalling' && !seatedPhase && threshold != null) {
    const sprint = Number.isFinite(input.sprintPower) ? input.sprintPower : null, peak = Number.isFinite(input.sprintPeak) ? input.sprintPeak : null;
    standing = (sprint ?? 0) >= threshold || ((power ?? 0) >= STANDING_HOLD_FRACTION * threshold && Math.max(peak ?? 0, sprint ?? 0) >= threshold);
  }

  let pedalPeriod = null;
  if (motion === 'pedalling') {
    const rpm = cadenceAvailable ? (cadence ?? NOMINAL_CADENCE) : NOMINAL_CADENCE;
    pedalPeriod = 60 / Math.min(150, Math.max(20, rpm * rate));
  }
  let worldSpeed;
  if (motion === 'footDown') worldSpeed = 0;
  else if (motion === 'coasting') worldSpeed = 6 * rate;
  else worldSpeed = Math.min(90, (14 + 28 * Math.min(500, Math.max(0, power ?? 120)) / 500) * rate);

  let world = 'boulevard', district = { kind: 'market', zone: null }, glow = 0.85, level = null, sign = null, upcoming = null, spire = 0, climb = 0, descent = 0, summary = '';
  switch (mode) {
    case 'ftpTest': {
      const ramp = input.ramp; if (!ramp) break;
      const stepSeconds = Math.max(1, ramp.stepSeconds), levelNumber = seconds => Math.trunc(Math.max(0, seconds) / stepSeconds) + 1;
      if (['waiting', 'warmup', 'riding', 'paused'].includes(phase)) {
        const progress = phase === 'warmup' && ramp.warmupSeconds > 0 ? Math.min(1, Math.max(0, ramp.phaseSeconds / ramp.warmupSeconds)) : 0;
        spire = 0.2 + 0.8 * progress;
        const remaining = ramp.warmupSeconds - ramp.phaseSeconds;
        if (phase === 'warmup' && remaining <= LEVEL_PREVIEW_SECONDS) upcoming = { key: 1, kind: 'level', text: 'LVL 1', secondsUntil: Math.max(0, remaining), district: null };
        summary = phase === 'warmup' ? 'warming up' : '';
      } else if (phase === 'ramp') {
        world = 'skyway'; spire = 1; climb = Math.max(0, ramp.rampSeconds);
        const current = levelNumber(ramp.rampSeconds);
        level = current; sign = { kind: 'level', text: `LVL ${current}` };
        const untilNext = stepSeconds - ramp.rampSeconds % stepSeconds;
        if (untilNext <= LEVEL_PREVIEW_SECONDS) upcoming = { key: current + 1, kind: 'level', text: `LVL ${current + 1}`, secondsUntil: untilNext, district: null };
        summary = `level ${current}`;
      } else if (['cooldown', 'completed', 'interrupted'].includes(phase)) {
        spire = 1; climb = Math.max(0, ramp.rampSeconds);
        const reached = ramp.rampSeconds > 0 ? levelNumber(ramp.rampSeconds) : null;
        const finish = Math.min(6, ramp.cooldownSeconds * 0.3);
        const atSummit = phase === 'completed' || phase === 'interrupted' || ramp.phaseSeconds < finish;
        if (reached == null) { world = 'boulevard'; spire = 0.2; }
        else if (atSummit) {
          world = 'rooftop'; level = reached;
          const best = Number.isFinite(ramp.bestMinuteWatts) && ramp.bestMinuteWatts > 0 ? roundAway(ramp.bestMinuteWatts) : null;
          sign = { kind: 'finish', text: best != null ? `LVL ${reached} · ${best} W` : `LVL ${reached}` };
          summary = `ramp finished at level ${reached}`;
        } else {
          world = 'descent'; level = reached;
          const span = Math.max(1, ramp.cooldownSeconds - finish);
          descent = Math.min(1, Math.max(0, (ramp.phaseSeconds - finish) / span));
          summary = 'cooling down';
        }
      }
      break;
    }
    case 'workout': {
      const step = input.step; if (!step) break;
      level = step.index + 1;
      district = districtFor(zoneOf((step.startWatts + step.endWatts) / 2, input.ftp));
      const ramped = step.endWatts !== step.startWatts, progress = step.seconds > 0 ? Math.min(1, Math.max(0, 1 - step.remaining / step.seconds)) : 1;
      if (ramped) glow = 0.4 + 0.6 * (step.endWatts > step.startWatts ? progress : 1 - progress);
      else glow = district.kind === 'residential' ? 0.6 : 1;
      sign = { kind: 'step', text: `STEP ${step.index + 1}/${step.count}` };
      if (step.next && step.remaining <= STEP_PREVIEW_SECONDS) {
        const nextZone = zoneOf((step.next.startWatts + step.next.endWatts) / 2, input.ftp);
        upcoming = { key: step.index + 1, kind: 'step', text: `NEXT ${clock(step.next.seconds)} · ${roundAway(step.next.startWatts)} W`, secondsUntil: Math.max(0, step.remaining), district: districtFor(nextZone) };
      }
      summary = `step ${step.index + 1} of ${step.count}`;
      break;
    }
    case 'freeERG': if (input.target != null) sign = { kind: 'gate', text: `${input.target} W` }; break;
    case 'resistance': if (input.target != null) sign = { kind: 'gate', text: `RES ${(input.target / 10).toFixed(1)}` }; break;
  }
  if (phase === 'paused') sign = { kind: 'paused', text: 'PAUSED' };

  const effort = standing ? 'sprinting out of the saddle' : zone != null ? `${ZONE_TITLES[zone].toLowerCase()} effort` : 'steady effort';
  let accessibilitySummary;
  if (phase === 'paused') accessibilitySummary = `${BRAND_NAME}: paused`;
  else if (world === 'rooftop') accessibilitySummary = `${BRAND_NAME}: ${summary}`;
  else if (world === 'descent') accessibilitySummary = `${BRAND_NAME}: cooling down`;
  else if (mode === 'ftpTest' && summary === 'warming up') accessibilitySummary = `${BRAND_NAME}: warming up, ${effort}`;
  else if (summary === '') accessibilitySummary = `${BRAND_NAME}: ${effort}`;
  else accessibilitySummary = `${BRAND_NAME}: ${effort}, ${summary}`;

  return { mode, world, zone, posture: standing ? Posture.standing : postureForZone(zone), motion, pedalPeriod, worldSpeed, animationRate: rate, rainSlant: 0.1 + 0.9 * Math.min(1, worldSpeed / 60),
    district, glow, level, sign, upcoming, spire, climbSeconds: climb, descent, accessibilitySummary };
}

// ---- smoothing of live power (RideVisualSmoothing) ---------------------------------------------------------------------------------
/** Mean of the power readings in the last `window` seconds; null when the newest reading is older than `staleAfter` seconds. `samples` are { time, power }. */
export function smoothedPower(samples, now, window = 3, staleAfter = 2) {
  let sum = 0, count = 0, newest = null;
  for (let i = samples.length - 1; i >= 0; i--) {
    const s = samples[i];
    if (s.time > now + 0.001) continue;
    if (s.time < now - window) break;
    if (!Number.isFinite(s.power)) continue;
    newest ??= s.time; sum += s.power; count += 1;
  }
  return count > 0 && newest != null && now - newest <= staleAfter ? sum / count : null;
}
/** Power averaged over the last second (null when stale), for sprint detection. */
export const sprintPower = (samples, now) => smoothedPower(samples, now, 1);
/** The highest one-second average ending within the last `lookback` seconds. */
export function sprintPeak(samples, now, lookback = 3) {
  let best = null;
  for (let i = samples.length - 1; i >= 0; i--) {
    const s = samples[i];
    if (s.time > now + 0.001) continue;
    if (s.time < now - lookback) break;
    const value = smoothedPower(samples, s.time, 1, 0);
    if (value != null) best = Math.max(best ?? value, value);
  }
  return best;
}

// ---- motion: what the visual has accumulated while it animates ---------------------------------------------------------------
/** The scenery repeats exactly after this many road pixels and seconds, so it never counts towards a finish. */
export const LOOP_DISTANCE = 1536, LOOP_TIME = 3, VIEW_DISTANCE = 128;

export class RideVisualMotion {
  constructor(distance = 0, time = 0, crankTurns = 0) { this.distance = distance; this.time = time; this.crankTurns = crankTurns; this.markers = []; this.segments = []; this.lastUpcoming = null; this.lastGate = null; this.lastDistrict = null; }
  advance(seconds, state) {
    const dt = Number.isFinite(seconds) ? Math.min(0.25, Math.max(0, seconds)) : 0;
    this.time += dt * state.animationRate;
    this.distance += state.worldSpeed * dt;
    if (state.pedalPeriod != null) this.crankTurns += dt / state.pedalPeriod;
    this.observe(state);
    this.markers = this.markers.filter(m => !(m.worldX < this.distance - 90));
    while (this.segments.length > 1 && this.segments[1].startX < this.distance - 220) this.segments.shift();
  }
  /** The district at a road coordinate, as the scenery sees it. */
  districtAt(x) { for (let i = this.segments.length - 1; i >= 0; i--) if (this.segments[i].startX <= x) return this.segments[i].district; return this.segments[0]?.district ?? null; }
  observe(state) {
    if (!this.segments.length) this.segments = [{ startX: -1e12, district: state.district }];
    const upcoming = state.upcoming;
    if (upcoming && upcoming.key !== this.lastUpcoming) {
      this.lastUpcoming = upcoming.key;
      const x = this.distance + Math.max(24, upcoming.secondsUntil * Math.max(state.worldSpeed, 18));
      if (upcoming.kind === 'level') this.markers.push({ kind: 'level', text: upcoming.text, worldX: x });
      else {
        this.markers.push({ kind: 'billboard', text: upcoming.text, worldX: x - 30 });
        this.markers.push({ kind: 'gantry', text: '', worldX: x });
        if (upcoming.district && !sameDistrict(this.segments.at(-1)?.district, upcoming.district)) this.segments.push({ startX: x, district: upcoming.district });
      }
    }
    const sign = state.sign;
    if (sign && sign.kind === 'gate') {
      if (this.lastGate != null && this.lastGate !== sign.text) this.markers.push({ kind: 'gate', text: sign.text, worldX: this.distance + VIEW_DISTANCE + 10 });
      this.lastGate = sign.text;
    }
    // A district change nobody announced (a different intensity moved the next step across a zone boundary).
    if (this.lastDistrict && !sameDistrict(this.lastDistrict, state.district) && !sameDistrict(this.segments.at(-1)?.district, state.district)) this.segments.push({ startX: this.distance + 40, district: state.district });
    this.lastDistrict = state.district;
  }
}

// ---- placement preference -----------------------------------------------------------------------------------------------------
/** How the visual is shown in the cockpits: not at all, a strip between the readings, or a hero scene filling the top. */
export const PLACEMENTS = Object.freeze([['off', 'Off'], ['strip', 'Strip'], ['hero', 'Large']]);
export const PLACEMENT_KEY = 'rideVisualPlacement';
export const placementTitle = placement => PLACEMENTS.find(([id]) => id === placement)?.[1] ?? 'Strip';
export const nextPlacement = placement => ({ off: 'strip', strip: 'hero', hero: 'off' }[placement] ?? 'strip');
/** A stored placement wins; anything else is the strip. */
export const resolvePlacement = stored => (PLACEMENTS.some(([id]) => id === stored) ? stored : 'strip');

// ---- reading a ride ------------------------------------------------------------------------------------------------------------
/**
 * Builds the input for `rideVisualState` from a live ride (RideVisualInput(model:engine:)): the engine, the ride clock `elapsed`, and the debug playback speed.
 * Targets in workouts are scaled by the ride's intensity.
 */
export function rideVisualInput(engine, elapsed, { playbackSpeed = 1 } = {}) {
  const session = engine.session, c = session.configuration, training = session.training;
  const mode = training == null ? 'ftpTest' : training.kind === 'workout' ? 'workout' : engine.resistanceLevel != null ? 'resistance' : 'freeERG';
  const phaseSeconds = Math.max(0, elapsed - engine.phaseStartedAt);
  let ramp = null, step = null, target = null;
  if (training == null) {
    let rampSeconds = 0;
    if (engine.phase === 'ramp') rampSeconds = phaseSeconds;
    else if (session.rampStart != null && session.rampEnd != null) rampSeconds = Math.max(0, session.rampEnd - session.rampStart);
    ramp = { phaseSeconds, warmupSeconds: c.warmupSeconds, cooldownSeconds: c.cooldownSeconds, stepSeconds: stepSecondsOf(c), rampSeconds, bestMinuteWatts: session.result?.bestMinutePower ?? null };
  } else if (engine.currentStep) {
    const current = engine.currentStep, scale = engine.intensity / 100, scaled = w => w * scale, steps = training.steps;
    const next = current.index + 1 < steps.length ? steps[current.index + 1] : null;
    step = { index: current.index, count: steps.length, startWatts: scaled(current.step.watts), endWatts: scaled(current.step.endWatts ?? current.step.watts), seconds: current.step.seconds, remaining: current.remaining,
      next: next ? { seconds: next.seconds, startWatts: scaled(next.watts), endWatts: scaled(next.endWatts ?? next.watts) } : null };
  }
  if (mode === 'freeERG') target = engine.target ?? engine.resumeTarget;
  if (mode === 'resistance') target = engine.resistanceLevel;
  const samples = session.samples, lastCadence = engine.lastCadence;
  return { mode, phase: engine.phase, power: smoothedPower(samples, elapsed), cadence: lastCadence && elapsed - lastCadence.time <= 2 ? lastCadence.rpm : null,
    cadenceAvailable: c.cadenceSource !== 'unavailable', ftp: training?.ftpWatts ?? c.priorFTP ?? null, playbackSpeed, ramp, step, target, weightKG: c.weightKG ?? null,
    sprintPower: sprintPower(samples, elapsed), sprintPeak: sprintPeak(samples, elapsed) };
}
const stepSecondsOf = c => PRESETS[c.preset]?.seconds ?? 12;
