import { duration } from '../training.mjs';
import { DurationFormat } from './presentation.mjs';
// Ports of Sources/FTPunkDomain/WorkoutPreview.swift and WorkoutProfile.swift: step summaries, % FTP / W text, repeat groups,
// the main-set caption and the profile chart's bars. tests/fixtures/workout-preview-250w.json (written by a Swift test) is the truth.

export const ZONES = Object.freeze(['Recovery', 'Endurance', 'Tempo', 'Sweet spot', 'Threshold', 'VO2max']);
/** Training zones by share of FTP. Percent is rounded to a whole number first: recovery up to 55 %, endurance 56–75, tempo 76–87, sweet spot 88–94, threshold 95–105, VO2max from 106. */
export function zoneFor(fraction) {
  if (!Number.isFinite(fraction)) return fraction > 0 ? 5 : 0;
  const p = Math.round(fraction * 100);
  return p < 56 ? 0 : p <= 75 ? 1 : p <= 87 ? 2 : p <= 94 ? 3 : p <= 105 ? 4 : 5;
}
export const zoneTitle = zone => zone == null ? null : ZONES[zone];

export const SCALE_MAX_PERCENT = 130;
/** Segments at the given intensity (percent). Targets are the plan's original watts scaled once. */
export function profileSegments(plan, intensity = 100) {
  let cursor = 0; const scale = intensity / 100;
  return plan.steps.map(step => {
    const segment = { name: step.name, start: cursor, end: cursor + step.seconds, startWatts: step.watts * scale, endWatts: (step.endWatts ?? step.watts) * scale };
    cursor += step.seconds; return { ...segment, seconds: step.seconds, averageWatts: (segment.startWatts + segment.endWatts) / 2 };
  });
}
export const peakWatts = (plan, intensity = 100) => Math.max(0, ...profileSegments(plan, intensity).map(s => Math.max(s.startWatts, s.endWatts)));
export function averageWatts(plan) { const total = duration(plan); return total > 0 ? profileSegments(plan).reduce((n, s) => n + s.averageWatts * s.seconds, 0) / total : 0; }
/** Bars on a fixed 0–130 % of FTP scale, so VO2max looks taller than tempo on every card. Without an FTP heights follow the plan's own peak and no zone is given. */
export function profileBars(plan, intensity = 100) {
  const segments = profileSegments(plan, intensity), total = Math.max(1, duration(plan)), ftp = plan.ftpWatts > 0 ? plan.ftpWatts : null;
  const reference = ftp ? ftp * SCALE_MAX_PERCENT / 100 : Math.max(1, peakWatts(plan, intensity)), height = w => Math.min(1, Math.max(0, w / reference));
  return segments.map(s => ({ start: s.start / total, end: s.end / total, startHeight: height(s.startWatts), endHeight: height(s.endWatts), zone: ftp ? zoneFor(s.averageWatts / ftp) : null }));
}

const compactText = step => step.percentText == null ? step.durationText : `${step.durationText} @ ${step.percentText} (${step.wattsText})`;
/** Steps with % FTP and watts at the given intensity. `showValues: false` gives durations only (no FTP yet). */
export function previewSteps(plan, intensity = 100, showValues = true) {
  const scale = intensity / 100, ftp = showValues && plan.ftpWatts > 0 && Number.isFinite(plan.ftpWatts) ? plan.ftpWatts : null;
  let cursor = 0;
  return plan.steps.map((step, index) => {
    const start = Math.round(step.watts * scale), end = step.endWatts == null ? null : Math.round(step.endWatts * scale), percent = w => ftp ? Math.round(w / ftp * 100) : null;
    const average = (start + (end ?? start)) / 2, percentStart = percent(start), percentEnd = end == null ? null : percent(end);
    const result = {
      index, name: step.name, start: cursor, seconds: step.seconds, watts: start, endWatts: end, percent: percentStart, endPercent: percentEnd, zone: ftp ? zoneFor(average / ftp) : null,
      durationText: DurationFormat.clock(step.seconds),
      percentText: percentStart == null ? null : percentEnd == null ? `${percentStart} %` : `${percentStart}→${percentEnd} %`,
      wattsText: end == null ? `${start} W` : `${start}→${end} W`,
    };
    cursor += step.seconds;
    result.valueText = result.percentText == null ? result.durationText : `${result.durationText} · ${result.percentText} · ${result.wattsText}`;
    result.spokenText = result.percent == null ? `${step.name}, ${DurationFormat.compact(step.seconds)}` : `${step.name}, ${DurationFormat.compact(step.seconds)}, ${result.valueText.split('·').slice(1).map(p => p.trim()).join(', ')}`;
    result.compactText = compactText(result);
    return result;
  });
}
/** The step under a horizontal position (0...1 across the duration), for hover and drag. A boundary belongs to the later step. */
export function stepAtFraction(x, plan) {
  const total = duration(plan);
  if (!Number.isFinite(x) || x < 0 || x > 1 || !plan.steps.length || !(total > 0)) return null;
  const time = x * total; let end = 0;
  for (const [index, step] of plan.steps.entries()) { end += step.seconds; if (time < end) return index; }
  return plan.steps.length - 1;
}
const baseName = name => name.replace(/ \d+ of \d+$/, '');
/** Groups runs of identical (seconds, watts) patterns that repeat at least twice. A block may end after its work step without the final recovery. */
export function previewGroups(plan, intensity = 100, showValues = true) {
  const summaries = previewSteps(plan, intensity, showValues), keys = plan.steps.map(s => `${s.seconds}|${s.watts}|${s.endWatts ?? ''}`), result = [];
  const same = (a, b, n) => { for (let k = 0; k < n; k++) if (keys[a + k] !== keys[b + k]) return false; return true; };
  let i = 0;
  while (i < keys.length) {
    let best = null;
    for (let length = 1; length <= Math.min(8, keys.length - i); length++) {
      let repeats = 1, cursor = i + length;
      while (cursor + length <= keys.length && same(i, cursor, length)) { repeats++; cursor += length; }
      let covered = repeats * length;
      if (length > 1 && cursor + length - 1 <= keys.length && same(i, cursor, length - 1)) { repeats++; covered += length - 1; }
      if (repeats >= 2 && covered > (best?.covered ?? 0)) best = { length, repeats, covered };
    }
    const pattern = best ? summaries.slice(i, i + best.length) : [summaries[i]], count = best?.repeats ?? 1, covered = best?.covered ?? 1;
    const body = pattern.map(s => `${baseName(s.name)} ${s.compactText}`).join(' / ');
    result.push({ start: i, end: i + covered, repeats: count, pattern, text: count > 1 ? `${count}× ${body}` : body });
    i += covered;
  }
  return result;
}
/** "5 × 3:00 @ 115 % (288 W)": the constant step that does the most work (occurrences × duration × watts), and how often it occurs. Null for ramp-only plans. */
export function mainSetText(plan, intensity = 100, showValues = true) {
  const constant = previewSteps(plan, intensity, showValues).filter(s => s.endWatts == null);
  const count = s => constant.filter(o => o.watts === s.watts && o.seconds === s.seconds).length, work = s => count(s) * s.seconds * s.watts;
  let top = null;
  for (const s of constant) if (top == null || work(s) > work(top)) top = s;
  if (!top) return null;
  const n = count(top);
  return n > 1 ? `${n} × ${top.compactText}` : top.compactText;
}
