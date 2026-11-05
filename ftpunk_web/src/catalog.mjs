import { validatePlan } from './training.mjs';
// The built-in classic workouts. Port of Sources/FTPunkDomain/WorkoutLibrary.swift; tests/fixtures/workout-library-250w.json
// (written by a Swift test) is the truth. Every step is constant power: warm-ups, cool-downs and recoveries are flat 50 %
// (the three original starters keep their own steps). Imported and Intervals.icu workouts can still contain ramps.
export const CATEGORIES = Object.freeze([
  { id: 'endurance', title: 'Endurance' }, { id: 'tempo', title: 'Tempo' }, { id: 'sweetSpot', title: 'Sweet spot' },
  { id: 'overUnders', title: 'Over-unders' }, { id: 'threshold', title: 'Threshold' }, { id: 'vo2max', title: 'VO2max' },
]);
export const categoryTitle = id => CATEGORIES.find(c => c.id === id)?.title ?? id;
const step = (name, minutes, from, to = null) => Object.freeze({ name, minutes, from, to });
const warmup = step('Warm-up', 10, 0.50), cooldown = step('Cool-down', 5, 0.50), recovery = minutes => step('Recovery', minutes, 0.50);
/** `count` efforts with recoveries between them (none after the last). */
const repeats = (label, count, minutes, fraction, rest) => Array.from({ length: count }, (_, i) => [step(`${label} ${i + 1} of ${count}`, minutes, fraction), ...(i + 1 < count ? [recovery(rest)] : [])]).flat();
function overUnderSets(sets, under, over, underFraction, overFraction, rest) {
  return Array.from({ length: sets }, (_, s) => [...[1, 2, 3].flatMap(rep => [step(`Set ${s + 1} · under ${rep}`, under, underFraction), step(`Set ${s + 1} · over ${rep}`, over, overFraction)]), ...(s + 1 < sets ? [recovery(rest)] : [])]).flat();
}
const define = (id, name, category, steps) => Object.freeze({ id, name, category, steps: Object.freeze(steps), duration: steps.reduce((n, s) => n + s.minutes * 60, 0) });
export const CATALOG = Object.freeze([
  define('easy-spin', 'Easy spin', 'endurance', [step('Warm-up', 3, 0.50), step('Easy spin', 14, 0.55), step('Cooldown', 3, 0.40)]),
  define('endurance-30', 'Endurance 30', 'endurance', [step('Warm-up', 5, 0.50), step('Endurance', 20, 0.65), step('Cooldown', 5, 0.40)]),
  define('endurance-60', 'Endurance 60', 'endurance', [warmup, step('Endurance', 45, 0.68), cooldown]),
  define('tempo-3x5', 'Tempo 3×5', 'tempo', [step('Warm-up', 5, 0.50), ...[1, 2, 3].flatMap(n => [step(`Tempo ${n} of 3`, 5, 0.80), step('Recovery', 2, 0.45)]), step('Cooldown', 4, 0.40)]),
  define('tempo-3x10', 'Tempo 3×10', 'tempo', [warmup, ...repeats('Tempo', 3, 10, 0.83, 3), cooldown]),
  define('tempo-2x20', 'Tempo 2×20', 'tempo', [warmup, ...repeats('Tempo', 2, 20, 0.82, 5), cooldown]),
  define('sweet-spot-3x10', 'Sweet spot 3×10', 'sweetSpot', [warmup, ...repeats('Sweet spot', 3, 10, 0.90, 5), cooldown]),
  define('sweet-spot-2x20', 'Sweet spot 2×20', 'sweetSpot', [warmup, ...repeats('Sweet spot', 2, 20, 0.90, 5), cooldown]),
  define('over-unders-3x9', 'Over-unders 3×9', 'overUnders', [warmup, ...overUnderSets(3, 2, 1, 0.95, 1.05, 5), cooldown]),
  define('over-unders-4x6', 'Over-unders 4×6', 'overUnders', [warmup, ...overUnderSets(4, 1, 1, 0.90, 1.10, 4), cooldown]),
  define('threshold-2x20', 'Threshold 2×20', 'threshold', [warmup, ...repeats('Threshold', 2, 20, 0.97, 5), cooldown]),
  define('threshold-3x12', 'Threshold 3×12', 'threshold', [warmup, ...repeats('Threshold', 3, 12, 1.00, 6), cooldown]),
  define('vo2max-5x3', 'VO2max 5×3', 'vo2max', [warmup, ...repeats('VO2max', 5, 3, 1.15, 3), cooldown]),
  define('vo2max-4x4', 'VO2max 4×4', 'vo2max', [warmup, ...repeats('VO2max', 4, 4, 1.10, 4), cooldown]),
]);
export const definition = id => CATALOG.find(d => d.id === id) ?? null;
export const definitionsIn = category => category ? CATALOG.filter(d => d.category === category) : [...CATALOG];
/** Whole-watt targets at the rider's FTP. Resolved again each time the workout is shown and snapshotted when a ride starts. */
export function planFor(def, ftp) {
  if (!Number.isFinite(ftp) || ftp <= 0 || ftp > 32767) throw Error('Set your FTP before choosing a workout.');
  const watts = fraction => Math.max(1, Math.round(ftp * fraction));
  return validatePlan({ version: def.steps.some(s => s.to != null) ? 2 : 1, kind: 'workout', name: def.name, ftpWatts: ftp, steps: def.steps.map(s => ({ name: s.name, seconds: s.minutes * 60, watts: watts(s.from), ...(s.to == null ? {} : { endWatts: watts(s.to) }) })) });
}
export const classics = ftp => CATALOG.map(def => ({ definition: def, id: def.id, category: def.category, plan: planFor(def, ftp) }));

/** "Sweet spot 3×10: 225 → 188 W": how a new FTP changes one library workout's main set. */
export function retargetExample(oldFTP, newFTP, workoutID = 'sweet-spot-3x10') {
  const def = definition(workoutID), ok = n => Number.isFinite(n) && n > 0;
  if (!def || !ok(oldFTP) || !ok(newFTP)) return null;
  const old = planFor(def, oldFTP), next = planFor(def, newFTP);
  // The hardest step is the main set; built-in warm-ups and cool-downs are flat at 50 %.
  let best = -1;
  old.steps.forEach((s, i) => { if (s.endWatts == null && (best < 0 || s.watts > old.steps[best].watts)) best = i; });
  return best < 0 ? null : { workoutName: def.name, oldWatts: old.steps[best].watts, newWatts: next.steps[best].watts, text: `${def.name}: ${old.steps[best].watts} → ${next.steps[best].watts} W` };
}
/** Plain-words intensity for workouts that are not in the built-in catalog. */
export function intensityLabel(plan) {
  const ftp = plan.ftpWatts, constant = plan.steps.filter(s => s.endWatts == null).map(s => s.watts);
  if (!(ftp > 0) || !constant.length) return 'Custom power targets';
  const f = Math.max(...constant) / ftp;
  return f < 0.56 ? 'Easy · active recovery' : f < 0.76 ? 'Endurance' : f < 0.91 ? 'Tempo' : f < 1.06 ? 'Threshold' : 'VO2max and above';
}
export const mainSetWatts = plan => { const c = plan.steps.filter(s => s.endWatts == null).map(s => s.watts); return c.length ? Math.max(...c) : null; };
