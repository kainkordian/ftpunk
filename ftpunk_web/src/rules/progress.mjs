import { DurationFormat, dayAndMonth } from './presentation.mjs';
import { PRESETS, OUTCOMES } from '../domain.mjs';
// Pure rules for the Progress tab, ported from Sources/FTPunkDomain/ProgressRules.swift and RiderHistory.swift.
// A session is the stored recording (see domain.mjs); `riderID` and `riderName` come from its configuration.
export const riderIDOf = session => (session.configuration.riderID ?? '00000000-0000-0000-0000-000000000001').toLowerCase();
export const TREND_METRICS = Object.freeze([{ id: 'watts', title: 'FTP, W' }, { id: 'wattsPerKG', title: 'FTP, W/kg' }]);
export const trendValue = (session, metric) => metric === 'watts' ? session.result?.estimatedFTP ?? null : session.result?.wattsPerKG ?? null;
export const ACTIVITY_FILTERS = Object.freeze([{ id: 'all', title: 'All' }, { id: 'ftpTests', title: 'FTP tests' }, { id: 'workouts', title: 'Workouts' }, { id: 'freeRides', title: 'Free rides' }]);
export function filterMatches(filter, session) {
  switch (filter) {
    case 'ftpTests': return session.training == null;
    case 'workouts': return session.training?.kind === 'workout';
    case 'freeRides': return session.training?.kind === 'freeRide';
    default: return true;
  }
}
/** "25 W / min" etc. A workout is named after its plan. */
export const activityTitle = session => session.training?.name ?? PRESETS[session.configuration.preset]?.title ?? 'FTP test';
const outcomeTitle = outcome => OUTCOMES[outcome] ?? 'Recording';
const BADGES = Object.freeze({ debug: 'Debug', uploaded: 'Uploaded', uploadQueued: 'Upload queued', uploadFailed: 'Upload needs attention', interrupted: 'Interrupted' });
export const badgeText = badge => BADGES[badge];
/** One row of the activity list: date and activity as the title, a result value, and badges. `uploadStatus` is a job status ('queued', 'uploaded', 'failed') or null. */
export function activityRow(session, uploadStatus = null, showRider = true) {
  const length = DurationFormat.compact(session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0);
  const activity = session.training == null ? 'FTP test' : activityTitle(session);
  const value = session.result ? `${Math.round(session.result.estimatedFTP)} W` : session.training != null ? length : null;
  const badges = [];
  if (session.isDemo) badges.push('debug');
  if (session.outcome === 'interrupted') badges.push('interrupted');
  if (uploadStatus === 'uploaded') badges.push('uploaded'); else if (uploadStatus === 'queued' || uploadStatus === 'uploading') badges.push('uploadQueued'); else if (uploadStatus === 'failed' || uploadStatus === 'needsAttention') badges.push('uploadFailed');
  const detail = session.training == null ? outcomeTitle(session.outcome) : length;
  return { id: session.id, title: `${dayAndMonth(session.startedAt)} · ${activity}`, subtitle: showRider ? `${session.configuration.riderName} · ${detail}` : detail, value, badges };
}
/** Sessions that appear in the FTP trend: real results by default, debug results on request. */
export const trendSessions = (sessions, rider, metric, includeDebug) => sessions.filter(s => (rider == null || riderIDOf(s) === rider) && trendValue(s, metric) != null && (includeDebug || !s.isDemo));
/** Newest first, for the selected rider (or everyone) and activity type. */
export const activities = (sessions, rider, filter) => sessions.filter(s => (rider == null || riderIDOf(s) === rider) && filterMatches(filter, s)).sort((a, b) => b.startedAt < a.startedAt ? -1 : b.startedAt > a.startedAt ? 1 : 0);
/** Identity, rather than a display name, keeps different riders' results separate. */
export function riderGroups(sessions, profiles) {
  const groups = new Map();
  for (const s of sessions) { const id = riderIDOf(s); if (!groups.has(id)) groups.set(id, []); groups.get(id).push(s); }
  return [...groups].map(([id, list]) => ({ id, name: profiles.find(p => p.id.toLowerCase() === id)?.name ?? list[0].configuration.riderName, sessions: list.sort((a, b) => b.startedAt < a.startedAt ? -1 : b.startedAt > a.startedAt ? 1 : 0) }))
    .sort((a, b) => { const order = a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' }); return order === 0 ? (a.id < b.id ? -1 : 1) : order; });
}
/** The trend chart's series: one per rider in stable colour order, points oldest first. Marker shape tells real from debug. */
export function trendSeries(groups, metric, includeDebug, riderOrder = []) {
  return groups.map((group, index) => ({ id: group.id, name: group.name, colorIndex: riderOrder.indexOf(group.id) >= 0 ? riderOrder.indexOf(group.id) : index,
    points: group.sessions.filter(s => trendValue(s, metric) != null && (includeDebug || !s.isDemo)).sort((a, b) => a.startedAt < b.startedAt ? -1 : 1).map(s => ({ id: s.id, time: Date.parse(s.startedAt), value: trendValue(s, metric), debug: s.isDemo })) })).filter(series => series.points.length);
}
