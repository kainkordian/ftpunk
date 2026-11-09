import { validateCachedWorkout } from './workouts.mjs';
import { validatePlan, validateProgress } from './training.mjs';
import { validateCustomWorkout, LIMITS as CUSTOM_LIMITS } from './custom-workouts.mjs';
// Portable v1 uses the native ramp payload with ISO-8601 dates. Internal browser
// configuration remains unchanged; adapters preserve its numeric prior FTP.
import { PRESETS } from './domain.mjs';
export const MAX_ARCHIVE_BYTES = 64 * 1024 * 1024;
export const LEGACY_RIDER = '00000000-0000-0000-0000-000000000001';
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const validDate = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT/.test(value) && Number.isFinite(Date.parse(value));
const finite = Number.isFinite;
const positive = value => finite(value) && value > 0;
const optional = (value, predicate) => value == null || predicate(value);
const pick = (value, keys) => Object.fromEntries(keys.filter(k => value[k] !== undefined).map(k => [k, value[k]]));
function require(condition, message) { if (!condition) throw Error(message); }
function id(value) { require(typeof value === 'string' && uuidPattern.test(value), 'Invalid archive identity.'); return value.toLowerCase(); }
function entry(value) {
  require(value && positive(value.watts) && value.watts <= 32767 && validDate(value.date) && typeof value.source === 'string', 'Invalid FTP history entry.');
  return { id: id(value.id), watts: value.watts, date: value.date, source: value.source };
}
function profile(value) {
  require(value && typeof value.name === 'string' && value.name.trim() && [...value.name].length <= 80 && optional(value.weightKG, positive) && Array.isArray(value.ftpHistory), 'Invalid rider profile.');
  const history = value.ftpHistory.map(entry), current = value.currentFTPID == null ? null : id(value.currentFTPID);
  require(new Set(history.map(e => e.id)).size === history.length, 'Duplicate FTP history identities.');
  require(current == null || history.some(e => e.id === current), 'The current FTP entry is missing.');
  return { ...(value.cycleProgress == null ? {} : { cycleProgress: validateProgress(value.cycleProgress) }), id: id(value.id), name: value.name, weightKG: value.weightKG ?? null, ftpHistory: history, currentFTPID: current };
}
export function validateArchive(input) {
  require(input?.format === 'ftpunk-portable' && [1, 2, 3].includes(input.version), 'This archive format or version is not supported.');
  require(validDate(input.exportedAt), 'Invalid archive date.');
  require(Array.isArray(input.profiles) && input.profiles.length > 0 && input.profiles.length <= 1000 && Array.isArray(input.activities) && input.activities.length <= 100000, 'Invalid archive contents.');
  require(input.version >= 2 || input.profiles.every(p => p.cycleProgress == null), 'Legacy progress records require archive version 2.');
  const profiles = input.profiles.map(profile), riders = new Set(profiles.map(p => p.id)), activities = [];
  const workouts = (input.workouts ?? []).map(validateCachedWorkout);
  require(workouts.length <= 2000 && (input.version >= 3 || !workouts.length) && new Set(workouts.map(w => w.id)).size === workouts.length && workouts.every(w => riders.has(w.riderID)), 'Invalid workout library identities or version.');
  require(riders.size === profiles.length, 'Duplicate rider identities in archive.');
  // The riders' own workouts (portable v3, optional key): validated like the native decoder, kept in full, never sent anywhere.
  require(input.customWorkouts == null || Array.isArray(input.customWorkouts), 'Invalid custom workout list.');
  const custom = (input.customWorkouts ?? []).map(validateCustomWorkout);
  require(input.version >= 3 || !custom.length, 'Custom workouts require archive version 3.');
  require(custom.length <= 2000 && new Set(custom.map(w => w.id)).size === custom.length, 'Invalid custom workout identities.');
  require(custom.every(w => riders.has(w.riderID)), 'A custom workout references a missing rider.');
  const perRider = new Map(); for (const w of custom) perRider.set(w.riderID, (perRider.get(w.riderID) ?? 0) + 1);
  require([...perRider.values()].every(n => n <= CUSTOM_LIMITS.maximumPerRider), 'Too many custom workouts for one rider.');
  for (const record of input.activities) {
    require(record?.schemaVersion === 1 && ['rampTest', 'workout', 'freeRide'].includes(record.kind), 'This activity kind or version is not supported.');
    const s = structuredClone(record.session), c = s?.configuration;
    require(s && c && PRESETS[c.preset] && Number.isInteger(c.protocolVersion) && c.protocolVersion >= 1 && c.protocolVersion <= 3, 'Invalid ramp configuration.');
    if (s.training != null) s.training = validatePlan(s.training);
    require(input.version >= 3 || (s.training?.version ?? 1) === 1, "Ramp and resistance plans require archive version 3.");
    require(s.adventureStartMilliseconds == null || input.version >= 3 && Number.isSafeInteger(s.adventureStartMilliseconds) && s.adventureStartMilliseconds >= 0 && s.adventureStartMilliseconds <= 8640000000000, 'Invalid legacy progress starting point.');
    require(record.kind === (s.training?.kind ?? 'rampTest'), 'Activity kind does not match its plan.');
    require(input.version >= 2 || (!s.training && s.adventureEnabled !== true), 'Training activities and legacy progress fields require archive version 2.');
    require(!s.training || s.result == null, 'Training activities cannot contain FTP estimates.');
    require(optional(s.adventureEnabled, v => typeof v === 'boolean') && optional(s.eligibleMilliseconds, v => Number.isSafeInteger(v) && v >= 0 && v <= Math.min(86400000, (s.endedAtOffset + .001) * 1000)), 'Invalid legacy progress time.');
    s.id = id(s.id); c.riderID = id(c.riderID ?? LEGACY_RIDER);
    require(riders.has(c.riderID), 'An activity references a missing rider.');
    require(validDate(s.startedAt) && typeof s.isDemo === 'boolean', 'Invalid activity metadata.');
    require(finite(s.endedAtOffset) && s.endedAtOffset >= 0 && ['exhaustion', 'finishedEarly', 'limitReached', 'interrupted', 'aborted', 'completed'].includes(s.outcome), 'Finish or recover all activities before transferring them.');
    require(Number.isInteger(c.warmupPower) && c.warmupPower > 0 && c.warmupPower <= 32767 && Number.isInteger(c.maximumPower) && c.maximumPower >= PRESETS[c.preset].start && c.maximumPower <= 32767, 'Invalid power targets.');
    require([c.warmupSeconds, c.cooldownSeconds].every(n => finite(n) && n >= 0 && n <= 3600) && finite(c.maximumRampSeconds) && c.maximumRampSeconds >= 60 && [0.72, 0.75].includes(c.ftpFactor) && typeof c.usesAutomaticWarmup === 'boolean', 'Invalid phase configuration.');
    require(optional(c.weightKG, positive) && optional(c.riderName, n => typeof n === 'string'), 'Invalid rider snapshot.');
    c.priorFTP = c.priorFTP == null ? null : entry(c.priorFTP);
    c.powerSource ??= 'externalPowerMeter'; c.cadenceSource ??= c.powerSource; c.powerMatchingEnabled ??= false;
    require(['trainer', 'externalPowerMeter'].includes(c.powerSource) && ['trainer', 'externalPowerMeter', 'unavailable'].includes(c.cadenceSource) && typeof c.powerMatchingEnabled === 'boolean', 'Invalid measurement source.');
    require([s.rampStart, s.rampEnd, s.cooldownStart].every(n => optional(n, n => finite(n) && n >= 0 && n <= s.endedAtOffset)), 'Invalid phase timestamps.');
    require(optional(s.endReason, n => typeof n === 'string'), 'Invalid activity end reason.');
    require(Array.isArray(s.devices) && s.devices.every(d => d && ['role', 'name', 'localIdentifier'].every(k => typeof d[k] === 'string') && d.capabilities && typeof d.capabilities === 'object' && !Array.isArray(d.capabilities) && Object.values(d.capabilities).every(v => typeof v === 'string')), 'Invalid device snapshots.');
    require(Array.isArray(s.samples) && s.samples.length <= 2000000 && s.samples.every(m => m && finite(m.time) && m.time >= 0 && m.time <= s.endedAtOffset + 2 && ['power', 'trainerPower', 'cadence'].every(k => optional(m[k], finite)) && optional(m.heartRate, n => Number.isInteger(n) && n >= 0 && n <= 65535) && optional(m.leftBalance, n => finite(n) && n >= 0 && n <= 100) && optional(m.rrIntervals, list => Array.isArray(list) && list.every(n => finite(n) && n >= 0))), 'Invalid activity samples.');
    require(Array.isArray(s.events) && s.events.every(e => e && finite(e.time) && e.time >= 0 && e.time <= s.endedAtOffset + 2 && typeof e.message === 'string'), 'Invalid activity events.');
    if (s.result != null) {
      const r = s.result;
      require(['exhaustion', 'finishedEarly'].includes(s.outcome) && r.algorithmVersion === 1 && positive(r.bestMinutePower) && finite(r.windowStart) && r.windowStart >= 0 && finite(r.windowEnd) && r.windowEnd <= s.endedAtOffset && Math.abs(r.windowEnd - r.windowStart - 60) < 0.001 && [0.72, 0.75].includes(r.factor) && optional(r.weightKG, positive), 'Invalid FTP result.');
    }
    const clean = pick(s, ['id', 'startedAt', 'isDemo', 'outcome', 'endReason', 'rampStart', 'rampEnd', 'cooldownStart', 'endedAtOffset', 'training', 'adventureEnabled', 'eligibleMilliseconds', 'adventureStartMilliseconds']);
    clean.configuration = pick(c, ['protocolVersion', 'preset', 'priorFTP', 'weightKG', 'warmupSeconds', 'warmupPower', 'usesAutomaticWarmup', 'maximumPower', 'maximumRampSeconds', 'cooldownSeconds', 'ftpFactor', 'riderID', 'riderName', 'powerSource', 'cadenceSource', 'powerMatchingEnabled']);
    clean.devices = s.devices.map(d => pick(d, ['role', 'name', 'localIdentifier', 'capabilities']));
    clean.samples = s.samples.map(m => pick(m, ['time', 'power', 'trainerPower', 'cadence', 'heartRate', 'rrIntervals', 'leftBalance']));
    clean.events = s.events.map(e => pick(e, ['time', 'message']));
    clean.result = s.result == null ? null : pick(s.result, ['bestMinutePower', 'windowStart', 'windowEnd', 'factor', 'weightKG', 'algorithmVersion']);
    activities.push({ schemaVersion: 1, kind: record.kind, session: clean });
  }
  require(new Set(activities.map(a => a.session.id)).size === activities.length, 'Duplicate activity identities in archive.');
  return { format: 'ftpunk-portable', version: input.version, exportedAt: input.exportedAt, profiles, activities, ...(workouts.length ? { workouts } : {}), ...(custom.length ? { customWorkouts: custom } : {}) };
}
export function makeArchive(profiles, sessions, exportedAt = new Date().toISOString(), workouts = [], customWorkouts = []) {
  const riders = structuredClone(profiles);
  const activities = sessions.map(source => {
    const s = structuredClone(source), c = s.configuration;
    c.riderID ??= LEGACY_RIDER;
    if (!riders.some(p => p.id.toLowerCase() === c.riderID.toLowerCase())) riders.push({ id: c.riderID, name: c.riderName ?? 'You', weightKG: null, ftpHistory: [], currentFTPID: null });
    if (typeof c.priorFTP === 'number') c.priorFTP = { id: s.id, watts: c.priorFTP, date: s.startedAt, source: 'Session snapshot' };
    delete c.manualWarmupPower;
    s.devices = s.devices.map(d => ({ ...d, capabilities: Object.fromEntries(Object.entries(d.capabilities ?? {}).map(([k, v]) => [k, String(v)])) }));
    if (s.result) {
      const { bestMinutePower, windowStart, windowEnd, factor, weightKG, algorithmVersion } = s.result;
      s.result = { bestMinutePower, windowStart, windowEnd, factor, weightKG, algorithmVersion };
    }
    return { schemaVersion: 1, kind: s.training?.kind ?? 'rampTest', session: s };
  });
  if (!riders.length) riders.push({ id: LEGACY_RIDER, name: 'You', weightKG: null, ftpHistory: [], currentFTPID: null });
  return validateArchive({ format: 'ftpunk-portable', version: workouts.length || customWorkouts.length || sessions.some(s => s.training?.version >= 2 || s.adventureStartMilliseconds != null) ? 3 : sessions.some(s => s.training || s.adventureEnabled) || riders.some(p => p.cycleProgress) ? 2 : 1, exportedAt, profiles: riders, activities, workouts, ...(customWorkouts.length ? { customWorkouts } : {}) });
}
export function archiveText(archive) {
  const text = JSON.stringify(validateArchive(archive), null, 2);
  require(new TextEncoder().encode(text).length <= MAX_ARCHIVE_BYTES, 'The archive exceeds the 64 MB limit.');
  return text;
}
export function parseArchive(text) {
  require(new TextEncoder().encode(text).length <= MAX_ARCHIVE_BYTES, 'The archive exceeds the 64 MB import limit.');
  const input = JSON.parse(text);
  // Preserve files exported by the original browser port as well as the shared format.
  if (input?.format === 'ftpunk-web' && input.version === 1) return makeArchive(input.profiles, input.sessions, input.exportedAt);
  return validateArchive(input);
}
export function archiveSessions(archive) {
  return validateArchive(archive).activities.map(({ session }) => {
    const c = session.configuration;
    c.priorFTP = c.priorFTP?.watts ?? null;
    c.manualWarmupPower = c.usesAutomaticWarmup ? null : c.warmupPower;
    c.riderName ??= archive.profiles.find(p => p.id.toLowerCase() === c.riderID)?.name ?? 'You';
    if (session.result) {
      const r = session.result;
      Object.assign(r, { estimatedFTP: r.bestMinutePower * r.factor, lowerFTP: r.bestMinutePower * 0.72, upperFTP: r.bestMinutePower * 0.77, wattsPerKG: r.weightKG ? r.bestMinutePower * r.factor / r.weightKG : null });
    }
    return session;
  });
}
