// Immutable, resolved training plans. Only the ride engine ever supplies trainer targets.
export function validatePlan(plan) {
  if (!plan || ![1, 2].includes(plan.version) || !['workout', 'freeRide'].includes(plan.kind) || typeof plan.name !== 'string' || !plan.name.length || plan.name.length > 100 || plan.ftpWatts != null && (!Number.isFinite(plan.ftpWatts) || plan.ftpWatts <= 0 || plan.ftpWatts > 32767) || !Array.isArray(plan.steps) || !plan.steps.length || plan.steps.length > 500 || !plan.steps.every(s => typeof s.name === 'string' && s.name.length > 0 && s.name.length <= 100 && Number.isFinite(s.seconds) && s.seconds > 0 && Number.isInteger(s.watts) && s.watts > 0 && s.watts <= 32767 && (s.endWatts == null || Number.isInteger(s.endWatts) && s.endWatts >= 1 && s.endWatts <= 32767)) || duration(plan) > 86400 || plan.kind === 'freeRide' && plan.steps.length !== 1) throw Error('Invalid workout duration or power target.');
  if (plan.version === 1 && (plan.resistance != null || plan.steps.some(s => s.endWatts != null)) || plan.resistance != null && (plan.kind !== 'freeRide' || !Number.isInteger(plan.resistance) || plan.resistance < 0 || plan.resistance > 32767)) throw Error('Invalid training control mode or version.');
  return { version: plan.version, ...(plan.resistance == null ? {} : { resistance: plan.resistance }), kind: plan.kind, name: plan.name, ftpWatts: plan.ftpWatts ?? null, steps: plan.steps.map(s => ({ name: s.name, seconds: s.seconds, watts: s.watts, ...(s.endWatts == null ? {} : { endWatts: s.endWatts }) })) };
}
export const duration = plan => plan.steps.reduce((sum, s) => sum + s.seconds, 0);
export function stepAt(plan, elapsed) {
  let start = 0;
  for (const [index, step] of plan.steps.entries()) { if (elapsed < start + step.seconds) return { index, step, remaining: start + step.seconds - elapsed }; start += step.seconds; }
  return null;
}
export function freeRide(watts) { return validatePlan({ version: 1, kind: 'freeRide', name: 'Free ERG ride', ftpWatts: null, steps: [{ name: 'Ride at your own pace', seconds: 86400, watts }] }); }
// Legacy progress ledger: recordings made before the story was removed still carry credits. They are validated, stored and
// exported unchanged (contracts/README.md, "Story fields are legacy"). Nothing in the UI reads them and new recordings never add credits.
export function validateProgress(progress) {
  if (!progress || progress.version !== 1 || !progress.credits || typeof progress.credits !== 'object' || Array.isArray(progress.credits) || Object.keys(progress.credits).length > 100000 || !Object.entries(progress.credits).every(([id, ms]) => /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(id) && Number.isSafeInteger(ms) && ms >= 0 && ms <= 86400000)) throw Error('Invalid legacy progress record.');
  return { version: 1, credits: { ...progress.credits } };
}
export function creditSession(progress, session) {
  const next = validateProgress(progress ?? { version: 1, credits: {} });
  if (!session.isDemo && session.adventureEnabled === true && Number.isSafeInteger(session.eligibleMilliseconds) && session.eligibleMilliseconds >= 0) {
    const id = session.id.toLowerCase(); next.credits[id] = Math.max(next.credits[id] ?? 0, session.eligibleMilliseconds);
  }
  return validateProgress(next);
}
export const progressMilliseconds = progress => Object.values(progress?.credits ?? {}).reduce((a, b) => a + b, 0);

export function trainingTarget(plan, elapsed, intensity = 100) {
  const current = stepAt(plan, elapsed); if (!current || plan.resistance != null) return null;
  const { step, remaining } = current, fraction = Math.max(0, Math.min(1, 1 - remaining / step.seconds));
  return Math.round((step.watts + ((step.endWatts ?? step.watts) - step.watts) * fraction) * intensity / 100);
}
export function supportsIntensity(plan, percent, minimum = 1, maximum = 32767) {
  return Number.isInteger(percent) && percent >= 50 && percent <= 150 && plan.steps.every(s => [s.watts, s.endWatts ?? s.watts].every(w => { const n = Math.round(w * percent / 100); return n >= Math.max(1, minimum) && n <= maximum; }));
}
export function resistanceRide(level) { return validatePlan({ version: 2, kind: 'freeRide', name: 'Resistance ride', resistance: level, steps: [{ name: 'Ride at your own pace', seconds: 86400, watts: 1 }] }); }
