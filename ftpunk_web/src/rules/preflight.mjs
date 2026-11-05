import { configuration, PRESETS } from '../domain.mjs';
import { supportsIntensity } from '../training.mjs';
// Pure pre-flight rules: the configuration a new test starts with, and whether the entries are valid.
// FTP tests always use the conservative 72 % estimate; there is no choice (recordings made with 75 % keep their own factor).
export const FTP_FACTOR = 0.72;
export const DEBUG_PHASE_SECONDS = 10;
export const defaultDraft = () => ({ preset: 'standard', presetChosen: false, warmupMinutes: 10, cooldownMinutes: 3, automaticWarmup: true, manualWarmup: '', intensity: 100, freeWatts: 100, resistance: 0, quickDebug: true, speed: 12, scenario: 'exhaustion' });
const whole = (value, min, max) => Number.isInteger(value) && value >= min && value <= max;
/** Warm-up and cool-down minutes (0 skips a phase) and a manual warm-up wattage, unless mock sensors use the 10 second debug timing. */
export function durationsValid(draft, { mock = false } = {}) {
  if (mock && draft.quickDebug) return true;
  const manual = draft.automaticWarmup || whole(Number(draft.manualWarmup), 1, 32767);
  return whole(Number(draft.warmupMinutes), 0, 60) && whole(Number(draft.cooldownMinutes), 0, 60) && manual;
}
/** The configuration for a new FTP test (or, with `training`, for a workout, free ERG or resistance ride, which have no warm-up or ramp). */
export function buildConfiguration({ draft, rider, ftp, powerSource, cadenceSource, powerMatching, mock = false, training = null }) {
  const quick = mock && draft.quickDebug;
  return configuration({
    preset: draft.preset, priorFTP: ftp ?? null, weightKG: rider.weightKG ?? null,
    warmupSeconds: training ? 0 : quick ? DEBUG_PHASE_SECONDS : Number(draft.warmupMinutes) * 60,
    cooldownSeconds: training ? 0 : quick ? DEBUG_PHASE_SECONDS : Number(draft.cooldownMinutes) * 60,
    manualWarmupPower: training ? training.steps[0].watts : draft.automaticWarmup ? null : Number(draft.manualWarmup),
    ftpFactor: FTP_FACTOR, powerSource, cadenceSource, powerMatchingEnabled: powerMatching, riderID: rider.id, riderName: rider.name,
  });
}
/** Do the plan's targets, scaled by `intensity`, fit the trainer's power range? Without a known range they do (the blocker for that comes first). */
export const targetsInRange = (plan, intensity, range) => !plan || !range || (supportsIntensity(plan, intensity, range.minimum, range.maximum) && plan.steps.every(s => [s.watts, s.endWatts ?? s.watts].every(w => range.quantized(Math.round(w * intensity / 100)) > 0)));
export const presetTitle = key => PRESETS[key]?.title;
/** Power mode: one rider-facing choice that maps onto the power source and the matching preference. */
export const POWER_MODES = Object.freeze([['trainer', 'Trainer'], ['meterMatched', 'Power meter — trainer follows the meter'], ['meterRecordOnly', 'Power meter — record only, no matching']]);
export const resolvePowerMode = (powerSource, matchingEnabled, meterConnected) => !meterConnected || powerSource !== 'externalPowerMeter' ? 'trainer' : matchingEnabled ? 'meterMatched' : 'meterRecordOnly';
export const powerModeSettings = (mode, currentMatching) => mode === 'meterMatched' ? { powerSource: 'externalPowerMeter', matching: true } : mode === 'meterRecordOnly' ? { powerSource: 'externalPowerMeter', matching: false } : { powerSource: 'trainer', matching: currentMatching };
