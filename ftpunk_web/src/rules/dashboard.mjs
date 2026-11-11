import { rideSummary } from './ride-summary.mjs';
import { speedAt, liveBalance } from './virtual-ride.mjs';
import { DurationFormat } from './presentation.mjs';
// What the workout / free-ride dashboard shows, as plain data. Mirrors App/Features/Ride/WorkoutCockpitView.swift and App/DesignSystem/WorkoutProfileChart.swift.

export const PROFILE_WIDTH = 1000, PROFILE_HEIGHT = 100, HEART_GAP_SECONDS = 5;
/** The heart-rate line over the workout profile as an SVG path. Its own scale: 0 to 200 bpm (or the highest reading, if higher). A gap over five seconds (a pause, a lost signal) breaks the line. Empty with fewer than two points. */
export function heartLinePath(points, totalSeconds) {
  if (!points || points.length < 2 || !(totalSeconds > 0)) return '';
  const top = Math.max(200, ...points.map(p => p.bpm)); let path = '', previous = null;
  for (const p of points) {
    const x = PROFILE_WIDTH * Math.min(1, Math.max(0, p.time / totalSeconds)), y = PROFILE_HEIGHT * (1 - p.bpm / top);
    path += `${previous != null && p.time - previous <= HEART_GAP_SECONDS ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`; previous = p.time;
  }
  return path;
}
/** The target box: caption, value and unit. A resistance ride shows the level; a pause shows where the ride resumes. */
export function targetBoxState({ resistanceLevel, paused, target, resumeTarget }) {
  if (resistanceLevel != null) return { caption: paused ? 'Resume level' : 'Resistance', value: (resistanceLevel / 10).toFixed(1), unit: '' };
  if (paused) return { caption: 'Paused · resumes at', value: resumeTarget == null ? null : String(resumeTarget), unit: 'W' };
  const watts = target ?? resumeTarget; return { caption: 'Target', value: watts == null ? null : String(watts), unit: 'W' };
}
/** The line under the profile: the next step with the intensity applied, "LAST STEP", or the waiting prompt. */
export function nextStepText({ current, steps, intensity, waiting }) {
  if (current) {
    const next = current.index + 1 < steps.length ? steps[current.index + 1] : null;
    return next ? { label: 'NEXT ▸ ', text: `${next.name} · ${DurationFormat.compact(next.seconds)} · ${Math.round(next.watts * intensity / 100)} W` } : { label: '', text: 'LAST STEP' };
  }
  return waiting ? { label: '', text: 'Start pedaling to begin.' } : { label: '', text: '' };
}
const whole = value => Number.isFinite(value) ? String(Math.round(value)) : null;
/** The figure boxes in display order. Balance is only shown when a meter or the trainer reports it. */
export const FIGURES = Object.freeze([
  { id: 'avg-power', caption: 'Avg power', unit: 'W' }, { id: 'np', caption: 'NP', unit: 'W' }, { id: 'max-power', caption: 'Max power', unit: 'W' },
  { id: 'avg-hr', caption: 'Avg HR', unit: 'bpm' }, { id: 'max-hr', caption: 'Max HR', unit: 'bpm' }, { id: 'avg-rpm', caption: 'Avg RPM', unit: 'rpm' },
  { id: 'work', caption: 'Work', unit: 'kJ' }, { id: 'kcal', caption: 'Calories', unit: 'kcal', note: 'Est.' },
  { id: 'speed', caption: 'Speed', unit: 'km/h', note: 'Sim.' }, { id: 'distance', caption: 'Distance', unit: 'km', note: 'Sim.' }, { id: 'balance', caption: 'Balance', unit: 'L/R' },
]);
/** Every other ride figure, always shown: power (average, normalized, maximum), heart rate (average, maximum), average cadence, work, calories, simulated speed and distance, and pedal balance when it is reported. `value` is null where there is nothing yet. */
export function rideFigures(session, track) {
  const summary = rideSummary(session, { track }), ridden = track.seconds > 0, left = liveBalance(session.samples), rounded = left == null ? null : Math.round(left);
  const values = {
    'avg-power': whole(summary.averagePower), np: whole(summary.normalizedPower), 'max-power': whole(summary.maximumPower), 'avg-hr': whole(summary.averageHeartRate), 'max-hr': whole(summary.maximumHeartRate),
    'avg-rpm': whole(summary.averageCadence), work: ridden ? whole(track.kilojoules) : null, kcal: ridden ? whole(track.kilocalories) : null,
    speed: ridden ? (speedAt(track, session.samples.at(-1)?.time ?? 0) * 3.6).toFixed(1) : null, distance: ridden ? (track.distance / 1000).toFixed(2) : null, balance: rounded == null ? null : `${rounded} / ${100 - rounded}`,
  };
  return FIGURES.map(f => ({ ...f, value: values[f.id], hidden: f.id === 'balance' && rounded == null }));
}
