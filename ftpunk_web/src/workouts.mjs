import { validatePlan } from './training.mjs';
import { parseZWO, looksLikeZWO } from './zwo.mjs';
export const MAX_WORKOUT_BYTES = 2 * 1024 * 1024;
const number = n => typeof n === 'number' && Number.isFinite(n) ? n : null;
export function importWorkout(text, ftp = null) {
  if (new TextEncoder().encode(text).length > MAX_WORKOUT_BYTES) throw Error('Workout files must be under 2 MB.');
  const object = JSON.parse(text), native = object?.format === 'ftpunk-workout', doc = native ? object : object?.workout_doc;
  if (native ? object.version !== 1 : !doc || object.type !== 'Ride' || object.category !== 'WORKOUT') throw Error('Use FTPunk workout JSON or an Intervals.icu cycling workout event.');
  const declaredFTP = native ? object.ftpWatts : doc.ftp;
  if (declaredFTP != null && number(declaredFTP) == null) throw Error('Invalid workout FTP.');
  ftp = number(native ? object.ftpWatts : doc.ftp) ?? ftp;
  if (doc.target && !['POWER', 'W', 'AUTO', 'A'].includes(doc.target)) throw Error('Only timed power workouts are supported.');
  if (!Array.isArray(doc.steps) || !doc.steps.length) throw Error('The workout contains no steps.');
  const steps = [];
  function expand(list, depth) {
    if (depth > 4 || list.length > 500) throw Error('Workout repeats are too deeply nested or too large.');
    for (const item of list) {
      if (!item || typeof item !== 'object') throw Error('Invalid workout step.');
      if (Array.isArray(item.steps)) {
        const count = item[native ? 'repeat' : 'reps'];
        if (!Number.isInteger(count) || count < 1 || count > 100 || !item.steps.length) throw Error('Invalid repeat count.');
        for (let n = 0; n < count; n++) expand(item.steps, depth + 1);
        continue;
      }
      const seconds = number(item[native ? 'seconds' : 'duration']);
      if (steps.length >= 500 || ['freeride', 'maxeffort', 'until_lap_press'].some(k => item[k] === true) || item.distance != null || seconds == null || seconds <= 0 || seconds > 86400 || item.repeat != null || item.reps != null) throw Error('Every step must have a timed power target; free, distance and lap steps are unsupported.');
      let from, to;
      if (native) { from = number(item.watts); to = number(item.endWatts); }
      else {
        const resolved = item._power, power = resolved ?? item.power ?? {}, units = String(power.units ?? (resolved ? 'w' : '')).toLowerCase();
        let multiplier;
        if (resolved || ['w', 'watts'].includes(units)) multiplier = 1;
        else if (units === '%ftp' && number(ftp) != null && ftp > 0 && ftp <= 32767) multiplier = ftp / 100;
        else throw Error('This workout needs resolved watts or a valid FTP for percent targets.');
        if (item.ramp === true) { from = number(power.start) == null ? null : power.start * multiplier; to = number(power.end) == null ? null : power.end * multiplier; if (to == null) throw Error('A ramp needs both power endpoints.'); }
        else { from = number(power.value) == null ? null : power.value * multiplier; to = null; }
      }
      if (from == null || from <= 0 || from > 32767 || to != null && (to <= 0 || to > 32767) || native && Object.hasOwn(item, 'endWatts') && to == null) throw Error('Power targets must be positive watts within the supported file range.');
      const name = String(item[native ? 'name' : 'text'] ?? `Step ${steps.length + 1}`).slice(0, 100) || `Step ${steps.length + 1}`;
      steps.push({ name, seconds, watts: Math.max(1, Math.round(from)), ...(to == null ? {} : { endWatts: Math.max(1, Math.round(to)) }) });
    }
  }
  expand(doc.steps, 0);
  return validatePlan({ version: steps.some(s => s.endWatts != null) ? 2 : 1, kind: 'workout', name: object.name ?? 'Imported workout', ftpWatts: ftp, steps });
}
/** A picked file's text: a Zwift .zwo (it starts with "<"; powers need `ftp`) or FTPunk / Intervals.icu JSON. Returns { plan, source } with the library's source label. */
export function importWorkoutText(text, ftp = null) {
  return looksLikeZWO(text) ? { plan: parseZWO(text, ftp), source: 'Imported ZWO' } : { plan: importWorkout(text, ftp), source: 'Imported JSON' };
}
/** `scheduledDate` is a local calendar day, `yyyy-MM-dd`, text rather than an instant (a workout planned for Tuesday stays on Tuesday). */
export const ScheduledDate = Object.freeze({
  isValid(text) {
    if (typeof text !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(text)) return false;
    const [year, month, day] = text.split('-').map(Number), probe = new Date(Date.UTC(year, month - 1, day));
    return year >= 1970 && year <= 2200 && probe.getUTCFullYear() === year && probe.getUTCMonth() === month - 1 && probe.getUTCDate() === day;
  },
  /** "2026-11-02T06:30:00" (Intervals `start_date_local`) becomes "2026-11-02". */
  fromIntervalsLocal(text) { const day = typeof text === 'string' && text.length >= 10 ? text.slice(0, 10) : null; return day && this.isValid(day) ? day : null; },
  stringFor(date = new Date()) { return `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`; },
  dateFrom(text) { if (!this.isValid(text)) return null; const [y, m, d] = text.split('-').map(Number); return new Date(y, m - 1, d); },
});
export function validateCachedWorkout(record) {
  if (!record || typeof record.id !== 'string' || !record.id.length || record.id.length > 300 || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(record.riderID) || typeof record.source !== 'string' || !record.source.length || record.source.length > 300 || !Number.isFinite(Date.parse(record.savedAt))) throw Error('Invalid cached workout.');
  const plan = validatePlan(record.plan); if (plan.kind !== 'workout') throw Error('Only structured workouts belong in the library.');
  if (record.scheduledDate != null && !ScheduledDate.isValid(record.scheduledDate)) throw Error('Invalid cached workout.');
  return { id: record.id, riderID: record.riderID.toLowerCase(), source: record.source, savedAt: record.savedAt, plan, ...(record.scheduledDate == null ? {} : { scheduledDate: record.scheduledDate }) };
}
export const exampleWorkout = { format: 'ftpunk-workout', version: 1, name: 'Ramps and repeats · 12 min', ftpWatts: 200, steps: [{ name: 'Warm-up ramp', seconds: 180, watts: 80, endWatts: 120 }, { repeat: 3, steps: [{ name: 'Effort', seconds: 90, watts: 160 }, { name: 'Recover', seconds: 30, watts: 90 }] }, { name: 'Cooldown ramp', seconds: 180, watts: 100, endWatts: 60 }] };
