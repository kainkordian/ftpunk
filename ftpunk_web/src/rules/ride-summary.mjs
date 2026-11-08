import { rampPower, PRESETS } from '../domain.mjs';
import { trainingTarget } from '../training.mjs';
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
export function oneHertzPower(samples) {
  const result = []; let held = null, heldAt = -Infinity, bucket = [], bucketSecond = null, lastSecond = null;
  const flush = () => { if (bucketSecond != null && bucket.length) { held = bucket.reduce((a, b) => a + b, 0) / bucket.length; heldAt = bucketSecond; result.push(held); } bucket = []; bucketSecond = null; };
  for (const s of samples) {
    if (!Number.isFinite(s.power) || !Number.isFinite(s.time) || s.time < 0) continue;
    const second = Math.floor(s.time);
    if (second !== bucketSecond) {
      flush();
      if (lastSecond != null && held != null && second > lastSecond + 1 && second - heldAt <= 2) for (let i = 0; i < second - lastSecond - 1; i++) result.push(held);
      bucketSecond = second; lastSecond = second;
    }
    bucket.push(s.power);
  }
  flush();
  return result;
}
/** A 30-second rolling mean of one-second power, to the fourth power, averaged, and rooted. Needs 30 seconds of riding. */
export function normalizedPower(samples) {
  const p = oneHertzPower(samples); if (p.length < 30) return null;
  let window = p.slice(0, 30).reduce((a, b) => a + b, 0), fourth = 0, count = 0;
  for (let end = 29; end < p.length; end++) { if (end > 29) window += p[end] - p[end - 30]; const mean = window / 30; fourth += mean ** 4; count++; }
  return count ? (fourth / count) ** 0.25 : null;
}
export function rideSummary(session) {
  const samples = session.samples ?? [], powers = samples.map(s => s.power).filter(Number.isFinite), beats = samples.map(s => s.heartRate).filter(Number.isFinite);
  return {
    duration: session.endedAtOffset ?? samples.at(-1)?.time ?? 0,
    averagePower: weighted(series(samples, s => s.power)), normalizedPower: normalizedPower(samples), maximumPower: powers.length ? Math.max(...powers) : null,
    averageHeartRate: weighted(series(samples, s => s.heartRate), false), maximumHeartRate: beats.length ? Math.max(...beats) : null,
    averageCadence: weighted(series(samples, s => s.cadence), false),
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
  const begin = timeOf('Training'); if (plan.resistance != null || begin == null) return null;
  const pauses = []; let requested = null;
  for (const e of events) { if (e.message === 'Training paused; trainer release requested') requested = e.time; else if (e.message === 'Training resumed' && requested != null) { pauses.push([requested, e.time]); requested = null; } }
  if (requested != null) pauses.push([requested, Infinity]);
  const intensities = events.flatMap(e => { const v = intValue(e.message, 'Workout intensity changed to ', '%'); return v == null ? [] : [[e.time, v]]; });
  const erg = events.flatMap(e => { const v = intValue(e.message, 'ERG target changed to ', ' W'); return v == null ? [] : [[e.time, v]]; });
  const last = (list, t) => list.filter(x => x[0] <= t).at(-1)?.[1];
  return t => {
    if (t < begin) return null; let paused = 0;
    for (const [start, end] of pauses) { if (t >= start && t < end) return null; if (t >= end) paused += end - start; }
    if (plan.kind === 'freeRide') return last(erg, t) ?? plan.steps[0]?.watts ?? null;
    return trainingTarget(plan, t - begin - paused, last(intensities, t) ?? 100);
  };
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
