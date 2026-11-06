import { PRESETS, OUTCOMES } from './domain.mjs';
import { fitFile } from './fit.mjs';
import { activityTitle } from './rules/progress.mjs';
const xml = text => String(text).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c]);
export function description(s) { const c = s.configuration; return `${s.isDemo ? 'DEMO — synthetic activity. ' : ''}FTPunk ${s.training?.name ?? PRESETS[c.preset].title}. ${OUTCOMES[s.outcome] ?? 'Recording'}. Rider: ${c.riderName}. Power source: ${c.powerSource}. Cadence source: ${c.cadenceSource}. Power matching: ${c.powerMatchingEnabled ? 'on' : 'off'}.${s.result ? ` Estimated FTP: ${Math.round(s.result.estimatedFTP)} W.` : ''}`; }
export function csv(s) {
  return ['seconds,power_watts,cadence_rpm,heart_rate_bpm,trainer_watts,power_source,cadence_source', ...s.samples.map(r => [r.time, r.power ?? '', r.cadence ?? '', r.heartRate ?? '', r.trainerPower ?? '', s.configuration.powerSource, s.configuration.cadenceSource].join(','))].join('\n');
}
export function tcx(s) {
  if (s.endedAtOffset == null || !s.samples.length) throw Error('Finish and save the recording before exporting TCX.');
  const timestamp = offset => new Date(Date.parse(s.startedAt) + offset * 1000).toISOString();
  const boundaries = [...new Set([0, s.rampStart, s.rampEnd, s.endedAtOffset].filter(t => Number.isFinite(t) && t >= 0 && t <= s.endedAtOffset))].sort((a, b) => a - b);
  const laps = boundaries.slice(0, -1).map((a, i) => {
    const b = boundaries[i + 1];
    const points = s.samples.filter(p => p.time >= a && (p.time < b || b === s.endedAtOffset && p.time === b)).map(p => `<Trackpoint><Time>${timestamp(p.time)}</Time>${p.heartRate != null ? `<HeartRateBpm><Value>${p.heartRate}</Value></HeartRateBpm>` : ''}${p.cadence != null ? `<Cadence>${Math.round(Math.min(254, Math.max(0, p.cadence)))}</Cadence>` : ''}${p.power != null ? `<Extensions><ns3:TPX><ns3:Watts>${Math.round(Math.max(0, p.power))}</ns3:Watts></ns3:TPX></Extensions>` : ''}</Trackpoint>`).join('');
    return `<Lap StartTime="${timestamp(a)}"><TotalTimeSeconds>${b - a}</TotalTimeSeconds><DistanceMeters>0</DistanceMeters><Calories>0</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod><Track>${points}</Track></Lap>`;
  }).join('');
  return `<?xml version="1.0" encoding="UTF-8"?><TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Activities><Activity Sport="Biking"><Id>${timestamp(0)}</Id>${laps}<Notes>${xml(description(s))}</Notes></Activity></Activities></TrainingCenterDatabase>`;
}
export function download(text, filename, type = 'application/json') {
  const url = URL.createObjectURL(new Blob([text], { type })), link = document.createElement('a');
  link.href = url; link.download = filename; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// ----- files for the result screen and the activity detail ------------------------------------------------------------------------------
export const FORMATS = Object.freeze({
  fit: { title: 'FIT', type: 'application/octet-stream' }, tcx: { title: 'TCX', type: 'application/vnd.garmin.tcx+xml' },
  csv: { title: 'CSV', type: 'text/csv' }, json: { title: 'JSON', type: 'application/json' },
});
/** COROS Training Hub accepts files from 20 KB (per COROS support). */
export const COROS_MINIMUM_BYTES = 20000;
/** `FTPunk-yyyy-MM-dd-<activity title>.<ext>` with the title reduced to letters, digits and hyphens; debug rides start with `DEMO-` (as native). */
export function fileName(session, format) {
  const d = new Date(session.startedAt), pad = n => String(n).padStart(2, '0'), day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  let title = ''; for (const { segment: c } of new Intl.Segmenter().segment(activityTitle(session))) { if (/^[A-Za-z0-9]$/.test(c)) title += c; else if (!title.endsWith('-')) title += '-'; }
  title = title.replace(/^-+|-+$/g, '');
  return `${session.isDemo ? 'DEMO-' : ''}FTPunk-${day}-${title || 'Activity'}.${format}`;
}
/** The bytes of one export: { name, type, bytes } (bytes is a string for the text formats, a Uint8Array for FIT). */
export function exportFile(session, format) {
  const bytes = format === 'fit' ? fitFile(session) : format === 'csv' ? csv(session) : format === 'tcx' ? tcx(session) : JSON.stringify(session, null, 2);
  return { name: fileName(session, format), type: FORMATS[format].type, bytes };
}
