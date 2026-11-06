import { validatePlan } from './training.mjs';
import { LIMITS, normalized, isPlainName, duration as parseShort } from './workout-text.mjs';
// A workout the rider built in the app: blocks of steps with targets in % FTP or watts, ramps and one level of repeats. Port of
// Sources/FTPunkDomain/CustomWorkout.swift; tests/fixtures/custom-workouts-250w.json (written by a Swift test) is the truth.
// It is resolved into a plan when shown or started, so later edits never change a recording. Custom workouts never leave the device
// except in a backup the rider exports. Shape (identical to the portable archive's `customWorkouts`):
//   { id, riderID, name, category?, updatedAt (ISO), blocks: [{ kind: 'step', step } | { kind: 'repeats', count, steps }] }
//   step = { name, seconds, start, end? }, target = { unit: 'percentFTP' | 'watts', value }
export { LIMITS, normalized };
export const NEEDS_FTP = 'This workout has % FTP targets. Set an FTP first.';
const CATEGORY_IDS = ['endurance', 'tempo', 'sweetSpot', 'overUnders', 'threshold', 'vo2max'];
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const chars = text => [...text].length, finite = Number.isFinite;
const inRange = (value, [low, high]) => finite(value) && value >= low && value <= high;

export const percent = value => ({ unit: 'percentFTP', value });
export const watts = value => ({ unit: 'watts', value });
export const isPercent = target => target.unit === 'percentFTP';
export const step = (name, seconds, start, end = null) => ({ name, seconds, start, ...(end ? { end } : {}) });
export const stepBlock = s => ({ kind: 'step', step: s });
export const repeatBlock = (count, steps) => ({ kind: 'repeats', count, steps });
export const newWorkout = (riderID, { id = crypto.randomUUID(), name = '', blocks = [], category = null, date = new Date() } = {}) => ({ id, riderID, name, ...(category ? { category } : {}), updatedAt: date.toISOString(), blocks });

/** Every step in riding order, repeats expanded. */
export const flattened = workout => workout.blocks.flatMap(block => block.kind === 'step' ? [block.step] : Array.from({ length: Math.max(0, block.count) }, () => block.steps).flat());
export const needsFTP = workout => flattened(workout).some(s => isPercent(s.start) || (s.end && isPercent(s.end)));
export const totalSeconds = workout => flattened(workout).reduce((sum, s) => sum + s.seconds, 0);
/** The flat step index (repeats expanded) range of each block row: [first, past the last]. */
export function flatRanges(workout) {
  let next = 0;
  return workout.blocks.map(block => { const count = block.kind === 'step' ? 1 : block.count * block.steps.length, range = [next, next + count]; next += count; return range; });
}

/** A step name must survive the text editor unchanged: one line, no words that read as a duration, target or repeat count. */
export const nameIsPlain = name => name === normalized(name) && !name.includes('\n') && isPlainName(name);

/** Everything that is wrong, worded for the rider ("Step 3: ..."). Empty means the workout can be saved. */
export function issues(workout) {
  const found = [], name = typeof workout.name === 'string' ? workout.name : '';
  if (!name.trim()) found.push('Give the workout a name.'); else if (chars(name) > 100) found.push('The name can have at most 100 characters.');
  if (!workout.blocks.length) found.push('Add at least one step.');
  if (workout.blocks.length > LIMITS.maximumExpandedSteps) found.push(`A workout can have at most ${LIMITS.maximumExpandedSteps} blocks.`);
  let number = 0;
  const check = s => {
    number += 1; const label = `Step ${number}`;
    if (!inRange(s.seconds, LIMITS.stepSeconds)) found.push(`${label}: the duration must be between 5 seconds and 4 hours.`);
    if (chars(s.name) > 100) found.push(`${label}: the name can have at most 100 characters.`);
    if (!nameIsPlain(s.name)) found.push(`${label}: the name cannot contain line breaks, '@', or words such as 10m, 80%, 200w, ramp or 5x.`);
    for (const target of [s.start, ...(s.end ? [s.end] : [])]) {
      if (isPercent(target)) { if (!inRange(target.value, LIMITS.percent)) found.push(`${label}: % FTP must be between 30 and 250.`); }
      else if (!inRange(target.value, LIMITS.watts)) found.push(`${label}: watts must be between 20 and 1500.`);
    }
    if (s.end && isPercent(s.end) !== isPercent(s.start)) found.push(`${label}: a ramp uses one unit for both ends (% FTP or watts).`);
  };
  for (const block of workout.blocks) {
    if (block.kind === 'step') check(block.step);
    else {
      if (!Number.isInteger(block.count) || !inRange(block.count, LIMITS.repeats)) found.push('A repeat block needs 1 to 100 repeats.');
      if (!block.steps.length) found.push('A repeat block needs at least one step.');
      block.steps.forEach(check);
    }
  }
  const expanded = flattened(workout);
  if (expanded.length > LIMITS.maximumExpandedSteps) found.push(`The workout has ${expanded.length} steps once repeats are expanded; the limit is ${LIMITS.maximumExpandedSteps}.`);
  if (expanded.reduce((sum, s) => sum + s.seconds, 0) > LIMITS.maximumDuration) found.push('The workout is longer than 24 hours.');
  return found;
}
export function validate(workout) { const first = issues(workout)[0]; if (first) throw Error(first); }

/** The workout as fixed targets. % FTP steps resolve once with `ftp`; watt steps never change. */
export function planFor(workout, ftp) {
  validate(workout);
  const usable = finite(ftp) && ftp > 0 && ftp <= 32767 ? ftp : null;
  if (needsFTP(workout) && usable == null) throw Error(NEEDS_FTP);
  const toWatts = target => target.unit === 'watts' ? Math.max(1, Math.round(target.value)) : Math.max(1, Math.round((usable ?? 0) * target.value));
  const steps = flattened(workout).map((s, index) => {
    const start = toWatts(s.start), end = s.end ? toWatts(s.end) : null;
    return { name: s.name || `Step ${index + 1}`, seconds: s.seconds, watts: start, ...(end == null || end === start ? {} : { endWatts: end }) };
  });
  return validatePlan({ version: steps.some(s => s.endWatts != null) ? 2 : 1, kind: 'workout', name: workout.name.trim(), ftpWatts: usable, steps });
}
/** `planFor` or null (a workout that cannot be resolved right now, for example % FTP steps without an FTP). */
export function tryPlan(workout, ftp) { try { return planFor(workout, ftp); } catch { return null; } }

// ----- from other workouts ---------------------------------------------------------------------------------------------------------
const clean = workout => issues(workout).length ? null : workout;
/** A built-in workout as % FTP blocks. Building it back at the same FTP gives the identical plan. */
export function fromDefinition(def, riderID, { name = null, ...options } = {}) {
  const steps = def.steps.map(s => step(s.name, s.minutes * 60, percent(s.from), s.to == null ? null : percent(s.to)));
  return clean(newWorkout(riderID, { ...options, name: name ?? def.name, category: def.category, blocks: steps.map(stepBlock) }));
}
/** Any plan as watt blocks, for "Duplicate & edit" of an imported or calendar workout. Null when a step is outside the builder's limits. */
export function fromPlan(plan, riderID, { name = null, ...options } = {}) {
  const steps = plan.steps.map(s => step(normalized(s.name), s.seconds, watts(s.watts), s.endWatts == null ? null : watts(s.endWatts)));
  return clean(newWorkout(riderID, { ...options, name: name ?? plan.name, blocks: steps.map(stepBlock) }));
}
export const copyName = name => `Copy of ${name}`.slice(0, 100);

// ----- helpers for the editor ------------------------------------------------------------------------------------------------------
/** A duration typed into a field: m:ss, h:mm:ss, a plain number of minutes, or the text-editor forms (90s, 1m30, 1h). Null when it is not one. */
export function parseDuration(text) {
  const trimmed = text.replace(/^[ \t]+|[ \t]+$/g, '');
  if (trimmed.includes(':')) {
    const parts = trimmed.split(':').map(p => /^[0-9]+$/.test(p) ? Number(p) : null);
    if (parts.length < 2 || parts.length > 3 || parts.some(p => p == null)) return null;
    if (parts.length === 2) return parts[1] < 60 ? parts[0] * 60 + parts[1] : null;
    return parts[1] < 60 && parts[2] < 60 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : null;
  }
  if (/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(trimmed)) { const minutes = Number(trimmed); if (finite(minutes) && minutes > 0) return minutes * 60; }
  return parseShort(trimmed);
}
/** "m:ss", or "h:mm:ss" from an hour on. */
export function durationText(seconds) {
  const total = Math.round(Math.max(0, seconds)), two = n => String(n).padStart(2, '0');
  return total >= 3600 ? `${Math.floor(total / 3600)}:${two(Math.floor(total % 3600 / 60))}:${two(total % 60)}` : `${Math.floor(total / 60)}:${two(total % 60)}`;
}

/** Estimated intensity factor and training stress: power is averaged the way normalised power is (fourth-power mean), but over whole steps
    instead of rolling 30 s windows, so it is an estimate. Watt steps count against `ftp`. Null without an FTP or with problems. */
export function estimatedLoad(workout, ftp) {
  if (!(finite(ftp) && ftp > 0) || issues(workout).length) return null;
  const toWatts = target => isPercent(target) ? target.value * ftp : target.value;
  let weighted = 0, seconds = 0;
  for (const s of flattened(workout)) {
    const from = toWatts(s.start), to = s.end ? toWatts(s.end) : from, slices = Math.max(1, Math.round(s.seconds / 5));
    for (let slice = 0; slice < slices; slice++) { const power = from + (to - from) * (slice + 0.5) / slices; weighted += Math.pow(power, 4) * (s.seconds / slices); seconds += s.seconds / slices; }
  }
  if (!(seconds > 0)) return null;
  const factor = Math.pow(weighted / seconds, 0.25) / ftp;
  return { intensityFactor: factor, tss: seconds / 3600 * factor * factor * 100 };
}

/** Structural equality of workouts, blocks and steps (key order never matters). */
export function same(a, b) {
  if (a === b) return true;
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object' || Array.isArray(a) !== Array.isArray(b)) return false;
  const keys = Object.keys(a).filter(k => a[k] !== undefined), other = Object.keys(b).filter(k => b[k] !== undefined);
  return keys.length === other.length && keys.every(k => same(a[k], b[k]));
}

// ----- stored and archived records -------------------------------------------------------------------------------------------------
const object = value => value != null && typeof value === 'object' && !Array.isArray(value);
const validDate = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT/.test(value) && Number.isFinite(Date.parse(value));
function target(value) {
  if (!object(value) || !['percentFTP', 'watts'].includes(value.unit) || !finite(value.value)) throw Error('Invalid custom workout target.');
  return { unit: value.unit, value: value.value };
}
function stepOf(value) {
  if (!object(value) || typeof value.name !== 'string' || !finite(value.seconds)) throw Error('Invalid custom workout step.');
  return step(value.name, value.seconds, target(value.start), value.end == null ? null : target(value.end));
}
/** Validates a custom workout read from storage or an archive, and returns a clean copy with lowercase identities. Throws on anything the app would not save. */
export function validateCustomWorkout(record) {
  if (!object(record) || typeof record.id !== 'string' || !uuidPattern.test(record.id) || typeof record.riderID !== 'string' || !uuidPattern.test(record.riderID) || typeof record.name !== 'string'
    || !validDate(record.updatedAt) || !Array.isArray(record.blocks) || (record.category != null && !CATEGORY_IDS.includes(record.category))) throw Error('Invalid custom workout.');
  const blocks = record.blocks.map(block => {
    if (!object(block)) throw Error('Invalid custom workout block.');
    if (block.kind === 'step') return stepBlock(stepOf(block.step));
    if (block.kind === 'repeats' && Number.isInteger(block.count) && Array.isArray(block.steps)) return repeatBlock(block.count, block.steps.map(stepOf));
    throw Error('Invalid custom workout block.');
  });
  const workout = { id: record.id.toLowerCase(), riderID: record.riderID.toLowerCase(), name: record.name, ...(record.category == null ? {} : { category: record.category }), updatedAt: record.updatedAt, blocks };
  validate(workout);
  return workout;
}
/** The cap and identity rules for saving `workout` next to the `existing` records (all riders). Throws with the native wording. */
export function checkSave(existing, workout) {
  const current = existing.find(w => w.id === workout.id);
  if (current && current.riderID !== workout.riderID) throw Error('An imported activity belongs to a different local rider. Nothing was changed.');
  if (!current && existing.filter(w => w.riderID === workout.riderID).length >= LIMITS.maximumPerRider) throw Error(`Each rider can have up to ${LIMITS.maximumPerRider} of their own workouts.`);
}
