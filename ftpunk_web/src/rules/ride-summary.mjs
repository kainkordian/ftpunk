import { rampPower, PRESETS } from '../domain.mjs';
import { trainingTarget, SKIP_PREFIX } from '../training.mjs';
import { rideTrack, rideBalance, ridePauses } from './virtual-ride.mjs';
// Ride figures, the target line and automatic pausing. Mirrors Sources/FTPunkDomain/RideSummary.swift.

function weighted(points, includeZero = true) {
  let total = 0, seconds = 0;
  for (let i = 0; i + 1 < points.length; i++) {
    if (!includeZero && points[i].value <= 0) continue;
    const span = Math.min(2, Math.max(0, points[i + 1].time - points[i].time)); total += points[i].value * span; seconds += span;
  }
  return seconds > 0 ? total / seconds : null;
}
const series = (samples, pick) => samples.flatMap(s => { const v = pick(s); return Number.isFinite(v) ? [{ time: s.time, value: v }] : []; });

/** One value per second of riding: the mean of that second's samples, held across gaps of up to two seconds; longer gaps (pauses) leave no entries. */
export function oneHertzPower(samples, pauses = []) {
  const result = [], paused = t => pauses.some(p => t >= p.stop && t < (p.resume ?? Infinity)); let held = null, heldAt = -Infinity, bucket = [], bucketSecond = null, lastSecond = null;
  const flush = () => { if (bucketSecond != null && bucket.length) { held = bucket.reduce((a, b) => a + b, 0) / bucket.length; heldAt = bucketSecond; result.push(held); } bucket = []; bucketSecond = null; };
  for (const s of samples) {
    if (!Number.isFinite(s.power) || !Number.isFinite(s.time) || s.time < 0 || paused(s.time)) continue;
    const second = Math.floor(s.time);
    if (second !== bucketSecond) {
      flush();
      if (lastSecond != null && held != null && second > lastSecond + 1 && second - heldAt <= 2) for (let gap = lastSecond + 1; gap < second; gap++) if (!paused(gap)) result.push(held);
      bucketSecond = second; lastSecond = second;
    }
    bucket.push(s.power);
  }
  flush();
  return result;
}
/** A 30-second rolling mean of one-second power, to the fourth power, averaged, and rooted. Needs 30 seconds of riding. Samples inside `pauses` don't count.
    Plain multiplication and two square roots, because `**` can differ between platforms and the FIT files must match the native app's byte for byte. */
export function normalizedPower(samples, pauses = []) {
  const p = oneHertzPower(samples, pauses); if (p.length < 30) return null;
  let window = p.slice(0, 30).reduce((a, b) => a + b, 0), fourth = 0, count = 0;
  for (let end = 29; end < p.length; end++) { if (end > 29) window += p[end] - p[end - 30]; const mean = window / 30; fourth += mean * mean * mean * mean; count++; }
  if (!count) return null;
  const root = Math.sqrt(Math.sqrt(fourth / count));
  return Number.isFinite(root) ? root : null;
}
export const priorFTPWatts = session => { const p = session.configuration?.priorFTP; return typeof p === 'number' ? p : p?.watts ?? null; };
/** Normalized power, intensity factor and training stress score. Paused samples don't count. NP needs 30 seconds of riding; IF and TSS also need a known FTP (null, never 0). */
export function trainingLoad(session, { track = null, pauses = ridePauses(session), end = session.endedAtOffset ?? session.samples?.at(-1)?.time ?? 0 } = {}) {
  const power = normalizedPower((session.samples ?? []).filter(s => s.time <= end), pauses), ftp = priorFTPWatts(session);
  if (power == null || !Number.isFinite(ftp) || ftp <= 0) return { normalizedPower: power, intensityFactor: null, trainingStressScore: null };
  const seconds = (track ?? rideTrack(session, { pauses, end })).seconds, intensity = power / ftp;
  return { normalizedPower: power, intensityFactor: intensity, trainingStressScore: seconds * power * intensity / (ftp * 3600) * 100 };
}
/** The trainer's own average power and NP, only while a power meter is the source (otherwise it is the same number as the main one). Null when the trainer reported nothing. */
function trainerFigures(session, samples, pauses) {
  const none = { trainerAveragePower: null, trainerNormalizedPower: null };
  if (session.configuration?.powerSource !== 'externalPowerMeter') return none;
  const trainer = samples.flatMap(s => Number.isFinite(s.trainerPower) ? [{ time: s.time, power: s.trainerPower }] : []);
  if (!trainer.length) return none;
  return { trainerAveragePower: weighted(series(trainer, s => s.power)), trainerNormalizedPower: normalizedPower(trainer, pauses) };
}
export function rideSummary(session, { track = rideTrack(session) } = {}) {
  // Samples that arrive during a pause don't count; `duration` is the elapsed time including pauses.
  const pauses = ridePauses(session), samples = (session.samples ?? []).filter(s => !pauses.some(p => s.time >= p.stop && s.time < (p.resume ?? Infinity)));
  const powers = samples.map(s => s.power).filter(Number.isFinite), beats = samples.map(s => s.heartRate).filter(Number.isFinite), ridden = track.seconds > 0;
  return {
    duration: session.endedAtOffset ?? session.samples?.at(-1)?.time ?? 0,
    averagePower: weighted(series(samples, s => s.power)), normalizedPower: trainingLoad(session, { track }).normalizedPower, maximumPower: powers.length ? Math.max(...powers) : null,
    averageHeartRate: weighted(series(samples, s => s.heartRate), false), maximumHeartRate: beats.length ? Math.max(...beats) : null,
    averageCadence: weighted(series(samples, s => s.cadence), false),
    ...trainerFigures(session, samples, pauses),
    kilojoules: ridden ? track.kilojoules : null, kilocalories: ridden ? track.kilocalories : null, distance: ridden ? track.distance : null, leftBalance: rideBalance(session, track)?.left ?? null,
  };
}

const intValue = (message, prefix, suffix) => message.startsWith(prefix) && message.endsWith(suffix) && /^\d+$/.test(message.slice(prefix.length, message.length - suffix.length)) ? Number(message.slice(prefix.length, message.length - suffix.length)) : null;
function targetFunction(session) {
  const events = [...session.events].sort((a, b) => a.time - b.time), timeOf = message => events.find(e => e.message === message)?.time ?? null, c = session.configuration, plan = session.training;
  if (plan == null) {
    const warm = timeOf('Warm-up'), rampStart = session.rampStart ?? null, rampEnd = session.cooldownStart ?? session.rampEnd ?? null, cooldown = rampEnd;
    return t => {
      if (rampStart != null && t >= rampStart && (rampEnd == null || t < rampEnd)) return rampPower(c, t - rampStart);
      if (warm != null && t >= warm && (rampStart == null || t < rampStart)) return c.warmupPower;
      if (cooldown != null && t >= cooldown && session.outcome !== 'exhaustion') return PRESETS[c.preset].cooldown;
      return null;
    };
  }
  const clock = WorkoutClock.of(session); if (plan.resistance != null || clock == null) return null;
  const intensities = events.flatMap(e => { const v = intValue(e.message, 'Workout intensity changed to ', '%'); return v == null ? [] : [[e.time, v]]; });
  const erg = events.flatMap(e => { const v = intValue(e.message, 'ERG target changed to ', ' W'); return v == null ? [] : [[e.time, v]]; });
  const last = (list, t) => list.filter(x => x[0] <= t).at(-1)?.[1];
  return t => {
    const training = clock.trainingTime(t); if (training == null) return null;
    if (plan.kind === 'freeRide') return last(erg, t) ?? plan.steps[0]?.watts ?? null;
    return trainingTarget(plan, training, last(intensities, t) ?? 100);
  };
}
/** Training seconds at a moment of a workout recording: the riding start, minus pauses, plus skipped steps. Mirrors native WorkoutClock. */
export class WorkoutClock {
  /** @returns {WorkoutClock|null} null without a plan or a riding start. */
  static of(session) {
    const events = [...(session.events ?? [])].sort((a, b) => a.time - b.time), begin = events.find(e => e.message === 'Training')?.time;
    if (session.training == null || begin == null) return null;
    const pauses = [], skips = []; let requested = null;
    for (const e of events) {
      if (e.message === 'Training paused; trainer release requested') requested = e.time;
      else if (e.message === 'Training resumed' && requested != null) { pauses.push([requested, e.time]); requested = null; }
      else if (e.message.startsWith(SKIP_PREFIX)) { const seconds = Number(e.message.slice(SKIP_PREFIX.length).split(' ')[0]); if (Number.isFinite(seconds) && seconds > 0) skips.push([e.time, seconds]); }
    }
    if (requested != null) pauses.push([requested, Infinity]);
    return new WorkoutClock(begin, pauses, skips);
  }
  constructor(begin, pauses, skips) { this.begin = begin; this.pauses = pauses; this.skips = skips; }
  /** Null before riding started and while paused. */
  trainingTime(t) {
    if (t < this.begin) return null; let paused = 0;
    for (const [start, end] of this.pauses) { if (t >= start && t < end) return null; if (t >= end) paused += end - start; }
    return t - this.begin - paused + this.skips.reduce((sum, [time, seconds]) => time <= t ? sum + seconds : sum, 0);
  }
  /** Heart rate on the training clock, for the workout profile: at most one point per second, paused samples left out. */
  heartRate(session) {
    const result = [];
    for (const s of session.samples ?? []) {
      if (!(s.heartRate > 0)) continue; const time = this.trainingTime(s.time); if (time == null) continue;
      const last = result.at(-1); if (last && time >= last.time && time - last.time < 1) continue;
      result.push({ time, bpm: s.heartRate });
    }
    return result;
  }
}
/** The target the ride asked for, as step-shaped line points; a pause starts a new segment. Rebuilt from the session, so older rides have it too. */
export function targetSeries(session) {
  const end = session.endedAtOffset ?? session.samples?.at(-1)?.time ?? 0, target = targetFunction(session); if (!(end > 0) || !target) return [];
  const points = []; let segment = 0, run = null, runStart = 0;
  const close = at => { if (run != null && at > runStart) points.push({ time: runStart, watts: run, segment }, { time: at, watts: run, segment }); };
  for (let second = 0; second < end; second++) { const value = target(second) ?? null; if (value !== run) { close(second); if (value == null) segment++; run = value; runStart = second; } }
  close(end);
  return points;
}

/** Pauses a workout after 3 s of no power and resumes after 2 s of pedalling again; a pause the rider made is never resumed by this. */
export class AutoPause {
  static stopSeconds = 3; static startSeconds = 2;
  constructor() { this.reset(); }
  reset() { this.stoppedSince = null; this.pedallingSince = null; this.automatic = false; }
  /** @returns {'pause'|'resume'|null} */
  update({ time, phase, power, canResume }) {
    if (phase === 'riding') {
      this.pedallingSince = null;
      if (!(power != null && power < 1)) { this.stoppedSince = null; this.automatic = false; return null; }
      this.stoppedSince ??= time;
      if (time - this.stoppedSince >= AutoPause.stopSeconds) { this.automatic = true; return 'pause'; }
      return null;
    }
    if (phase === 'paused') {
      this.stoppedSince = null;
      if (!this.automatic || !canResume) { this.pedallingSince = null; return null; }
      this.pedallingSince ??= time;
      if (time - this.pedallingSince >= AutoPause.startSeconds) { this.automatic = false; this.pedallingSince = null; return 'resume'; }
      return null;
    }
    this.reset(); return null;
  }
}

/** The target at one moment of the recording; null when there was none (e.g. while paused). */
export const targetValue = (session, time) => targetFunction(session)?.(time) ?? null;
/** Every reading at one moment, for the charts' hover card: the latest value in the two seconds up to `time`, so a gap or a pause shows as null. */
export function rideMoment(session, time) {
  const window = (session.samples ?? []).filter(s => s.time <= time && time - s.time <= 2), latest = key => window.findLast(s => Number.isFinite(s[key]))?.[key] ?? null;
  return { time, power: latest('power'), target: targetValue(session, time), trainerPower: session.configuration?.powerSource === 'externalPowerMeter' ? latest('trainerPower') : null,
    heartRate: latest('heartRate'), cadence: latest('cadence'), leftBalance: latest('leftBalance') };
}
