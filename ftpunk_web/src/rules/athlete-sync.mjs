import { currentFTP } from './home.mjs';
// FTP and weight as Intervals.icu reports them, and when to apply them to a rider. Ported from Sources/FTPunkDomain/AthleteSync.swift and SyncPolicy
// (tests mirror AthleteSyncTests.swift). Pure: no network, no storage.

export const WEIGHT_RANGE = Object.freeze([30, 250]), FTP_RANGE = Object.freeze([50, 1000]);
export const FTP_TOLERANCE = 0.5, WEIGHT_TOLERANCE = 0.05, REFRESH_SECONDS = 3600;
const inRange = (value, [low, high]) => value >= low && value <= high;
const number = value => typeof value === 'number' && Number.isFinite(value) ? value : null;

/** Lenient decoding of `GET /api/v1/athlete/0`: { weightKG, ftpWatts }, each null when missing, zero, non-numeric or out of range. The field names
    (`icu_weight`, `sportSettings[].types / ftp / indoor_ftp`; `indoor_ftp` wins when valid) were verified against a live account for the native app. */
export function decodeAthleteSettings(json) {
  if (json == null || typeof json !== 'object' || Array.isArray(json)) throw Error('Intervals.icu returned an unexpected response.');
  const weight = number(json.icu_weight), sports = Array.isArray(json.sportSettings) ? json.sportSettings.filter(s => s && typeof s === 'object') : [];
  const entry = type => sports.find(s => Array.isArray(s.types) && s.types.includes(type));
  let ftp = null;
  for (const type of ['VirtualRide', 'Ride']) {
    const settings = entry(type); if (!settings) continue;
    const value = [number(settings.indoor_ftp), number(settings.ftp)].filter(v => v != null).find(v => inRange(v, FTP_RANGE));
    if (value != null) { ftp = value; break; }
  }
  return { weightKG: weight != null && inRange(weight, WEIGHT_RANGE) ? weight : null, ftpWatts: ftp };
}
export const emptyState = () => ({ lastSeenFTP: null, lastSeenWeight: null });
export const isEmpty = changes => changes.ftp == null && changes.weight == null;

/** A remote value is applied only when it changed on Intervals.icu since the last sync and differs from the rider's current local value.
    `lastSeen*` follows the remote either way, so a local edit is never fought over. Returns { changes: { ftp, weight }, state }. */
export function athleteChanges(remote, state, rider) {
  const changes = { ftp: null, weight: null }, seen = { ...emptyState(), ...state }, next = { ...seen };
  if (remote.ftpWatts != null) {
    const ftp = remote.ftpWatts;
    if (seen.lastSeenFTP == null || Math.abs(seen.lastSeenFTP - ftp) > FTP_TOLERANCE) {
      const local = currentFTP(rider)?.watts;
      if (local == null || Math.abs(local - ftp) > FTP_TOLERANCE) changes.ftp = ftp;
      next.lastSeenFTP = ftp;
    }
  }
  if (remote.weightKG != null) {
    const weight = remote.weightKG;
    if (seen.lastSeenWeight == null || Math.abs(seen.lastSeenWeight - weight) > WEIGHT_TOLERANCE) {
      if (rider.weightKG == null || Math.abs(rider.weightKG - weight) > WEIGHT_TOLERANCE) changes.weight = weight;
      next.lastSeenWeight = weight;
    }
  }
  return { changes, state: next };
}
/** "FTP 262 W and weight 71.5 kg updated from Intervals.icu", or null when nothing changed. */
export function syncNote(changes) {
  const parts = [changes.ftp != null ? `FTP ${Math.round(changes.ftp)} W` : null, changes.weight != null ? `weight ${changes.weight.toFixed(1)} kg` : null].filter(Boolean);
  return parts.length ? `${parts.join(' and ')} updated from Intervals.icu` : null;
}
/** The rider with the changes applied: FTP becomes a new current history entry (existing entries are untouched), weight replaces the weight. */
export function applyChanges(changes, rider, { now = new Date(), id = crypto.randomUUID() } = {}) {
  const next = structuredClone(rider);
  if (changes.ftp != null) { next.ftpHistory.unshift({ id, watts: changes.ftp, date: now.toISOString(), source: 'Intervals.icu' }); next.currentFTPID = id; }
  if (changes.weight != null) next.weightKG = changes.weight;
  return next;
}
/** Athlete settings refresh when the last sync is over an hour old, never during a ride. */
export const shouldRefreshAthlete = ({ lastSynced, now = Date.now(), connected, enabled, rideActive, alreadyRunning = false }) =>
  connected && enabled && !rideActive && !alreadyRunning && (lastSynced == null || (now - Date.parse(lastSynced)) / 1000 > REFRESH_SECONDS);
