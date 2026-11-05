import { ScheduledDate } from '../workouts.mjs';
// Pure rules for Home, ported from Sources/FTPunkDomain/HomeRules.swift. Tests mirror HomeAndLibraryTests.swift and HomeWorkflowTests.swift.
// A cached workout is { id, riderID, source, savedAt, plan, scheduledDate? }.
export const isFromIntervals = workout => workout.id.startsWith('intervals:');
const forRider = (workouts, riderID) => workouts.filter(w => w.riderID === riderID && isFromIntervals(w));
const byDate = (a, b) => a.scheduledDate != null && b.scheduledDate != null ? (a.scheduledDate === b.scheduledDate ? (a.id < b.id ? -1 : 1) : a.scheduledDate < b.scheduledDate ? -1 : 1) : a.scheduledDate != null ? -1 : b.scheduledDate != null ? 1 : (a.id < b.id ? -1 : 1);
/** After today, in date order; entries without a date (older caches) follow. */
export const upcoming = (workouts, riderID, today) => forRider(workouts, riderID).filter(w => w.scheduledDate == null || w.scheduledDate > today).sort(byDate);
/** Today's workouts, shown even offline. Otherwise connected riders see the next planned workout, and riders who are not connected see a single quiet hint. */
export function selectToday(workouts, riderID, today, connected) {
  const todays = forRider(workouts, riderID).filter(w => w.scheduledDate === today).map(w => w.id);
  if (todays.length) return { kind: 'today', ids: todays };
  if (!connected) return { kind: 'notConnected' };
  return { kind: 'nothingToday', next: upcoming(workouts, riderID, today).find(w => w.scheduledDate != null)?.id ?? null };
}
/** Imported files; the calendar and the built-in classics have their own sections. */
export const mine = (workouts, riderID) => workouts.filter(w => w.riderID === riderID && !isFromIntervals(w)).sort((a, b) => b.savedAt < a.savedAt ? -1 : b.savedAt > a.savedAt ? 1 : 0);
/** Cached calendar entries inside the downloaded window that the latest download no longer returned. */
export function staleEntries(cached, riderID, accountID, downloaded, today, windowEnd) {
  const prefix = `intervals:${accountID}:${riderID.toLowerCase()}:`;
  return cached.filter(w => w.id.startsWith(prefix) && !downloaded.has(w.id) && (w.scheduledDate == null || (w.scheduledDate >= today && w.scheduledDate <= windowEnd))).map(w => w.id);
}
/** The calendar refreshes when Home appears if the last download is over an hour old, never during a ride. */
export const REFRESH_SECONDS = 3600;
export const shouldRefresh = ({ lastDownload, now = Date.now(), connected, rideActive, alreadyRunning = false }) => connected && !rideActive && !alreadyRunning && (lastDownload == null || (now - lastDownload) / 1000 > REFRESH_SECONDS);
/** "Mon 2 Nov" for a scheduled day, or "Date not set". */
export function dateText(scheduled) {
  const d = ScheduledDate.dateFrom(scheduled);
  return d ? d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }).replace(',', '') : 'Date not set';
}

/** Onboarding: a name is required, weight and FTP are optional numbers. Returns { ok, error, name, weightKG, ftp }. */
export function parseOnboarding({ name, weight, ftp }) {
  const trimmed = String(name ?? '').trim();
  if (!trimmed) return { ok: false, error: 'Enter your name to continue.' };
  if ([...trimmed].length > 80) return { ok: false, error: 'Use a name of up to 80 characters.' };
  const number = (text, max) => { const t = String(text ?? '').trim(); if (!t) return { value: null }; const n = Number(t.replace(',', '.')); return Number.isFinite(n) && n > 0 && n <= max ? { value: n } : { error: true }; };
  const w = number(weight, 500), f = number(ftp, 32767);
  if (w.error) return { ok: false, error: 'Weight must be a positive number in kg.' };
  if (f.error) return { ok: false, error: 'FTP must be a positive number of watts.' };
  return { ok: true, name: trimmed, weightKG: w.value, ftp: f.value };
}
/** The FTP a rider's library and pre-flight use: their current entry. */
export const currentFTP = profile => profile?.ftpHistory?.find(e => e.id === profile.currentFTPID) ?? null;
