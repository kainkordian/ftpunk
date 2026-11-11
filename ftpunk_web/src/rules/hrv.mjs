import { ridePauses } from './virtual-ride.mjs';
// Heart-rate variability from the strap's RR intervals. Mirrors Sources/FTPunkDomain/HeartRateVariability.swift.
// RMSSD over the whole ride; DFA alpha1 (box sizes 4-16 beats) in two-minute windows every 30 s, windows with more than 5 % rejected beats left out.
export const WINDOW_SECONDS = 120, STEP_SECONDS = 30, MAXIMUM_ARTIFACT_SHARE = 0.05;
const sum = values => values.reduce((a, b) => a + b, 0);

/** Null when the ride has fewer than 30 RR intervals. `artifactShare` is 0-1. */
export function heartRateVariability(session) {
  const all = beats(session); if (all.length < 30) return null;
  const { kept, accepted } = filtered(all);
  return { rmssd: rmssd(kept.map(b => b.interval)), artifactShare: (all.length - kept.length) / all.length, alpha1: alpha1Series(all, accepted) };
}
/** Every RR interval outside pauses, timed by its beat: a notification carries the intervals that ended at or before it, so the last one is placed at the notification and the earlier ones before it. */
export function beats(session) {
  const pauses = ridePauses(session), result = [];
  for (const sample of session.samples ?? []) {
    if (pauses.some(p => sample.time >= p.stop && sample.time < (p.resume ?? Infinity))) continue;
    const intervals = sample.rrIntervals; if (!intervals?.length) continue;
    let time = sample.time; const placed = [];
    for (const interval of [...intervals].reverse()) if (Number.isFinite(interval) && interval > 0) { placed.push({ time, interval }); time -= interval; }
    result.push(...placed.reverse());
  }
  return result;
}
/** Drops intervals outside 0.25-2 s and those more than 20 % from the median of the last five accepted ones (a missed or an extra beat). */
export function filtered(list) {
  const kept = [], accepted = [];
  for (const beat of list) {
    let ok = beat.interval >= 0.25 && beat.interval <= 2;
    if (ok && kept.length >= 3) {
      const recent = kept.slice(-5).map(b => b.interval).sort((a, b) => a - b), median = recent[Math.floor(recent.length / 2)];
      ok = Math.abs(beat.interval - median) <= 0.2 * median;
    }
    if (ok) kept.push(beat);
    accepted.push(ok);
  }
  return { kept, accepted };
}
/** RMSSD in milliseconds; null with fewer than 30 intervals. */
export function rmssd(intervals) {
  if (intervals.length < 30) return null;
  let total = 0;
  for (let i = 1; i < intervals.length; i++) { const d = (intervals[i] - intervals[i - 1]) * 1000; total += d * d; }
  return Math.sqrt(total / (intervals.length - 1));
}
const slopeOf = (ys, xs) => {
  const meanX = sum(xs) / xs.length, meanY = sum(ys) / ys.length; let numerator = 0, denominator = 0;
  xs.forEach((x, i) => { numerator += (x - meanX) * (ys[i] - meanY); denominator += (x - meanX) * (x - meanX); });
  return denominator > 0 ? numerator / denominator : NaN;
};
function residualSquares(values) {
  const xs = values.map((_, i) => i), slope = slopeOf(values, xs), meanX = sum(xs) / xs.length, meanY = sum(values) / values.length, intercept = meanY - slope * meanX;
  return values.reduce((total, y, x) => { const r = y - (intercept + slope * x); return total + r * r; }, 0);
}
/** DFA alpha1 over box sizes 4-16; null with fewer than 50 intervals. */
export function alpha1(intervals) {
  if (intervals.length < 50) return null;
  const mean = sum(intervals) / intervals.length, profile = []; let running = 0;
  for (const value of intervals) { running += value - mean; profile.push(running); }
  const logN = [], logF = [];
  for (let size = 4; size <= 16; size++) {
    const boxes = Math.floor(profile.length / size); if (boxes < 1) continue;
    let squares = 0;
    for (let box = 0; box < boxes; box++) squares += residualSquares(profile.slice(box * size, (box + 1) * size));
    const fluctuation = Math.sqrt(squares / (boxes * size)); if (!(fluctuation > 0)) continue;
    logN.push(Math.log10(size)); logF.push(Math.log10(fluctuation));
  }
  if (logN.length < 3) return null;
  const slope = slopeOf(logF, logN); return Number.isFinite(slope) ? slope : null;
}
/** Alpha1 in two-minute windows every 30 s. A window counts when at most 5 % of its beats were rejected and no gap inside it is over 3 s. */
export function alpha1Series(list, accepted) {
  const first = list[0]?.time, last = list.at(-1)?.time; if (first == null || !(last - first >= WINDOW_SECONDS)) return [];
  const points = []; let end = first + WINDOW_SECONDS, lower = 0;
  while (end <= last + 0.001) {
    while (lower < list.length && list[lower].time < end - WINDOW_SECONDS) lower++;
    let upper = lower, total = 0, rejected = 0; const intervals = [];
    while (upper < list.length && list[upper].time <= end) { total++; if (accepted[upper]) intervals.push(list[upper].interval); else rejected++; upper++; }
    let continuous = true; for (let i = lower + 1; i < upper; i++) if (list[i].time - list[i - 1].time > 3) { continuous = false; break; }
    if (total > 0 && continuous && rejected / total <= MAXIMUM_ARTIFACT_SHARE) { const alpha = alpha1(intervals); if (alpha != null) points.push({ time: end, alpha1: alpha }); }
    end += STEP_SECONDS;
  }
  return points;
}
