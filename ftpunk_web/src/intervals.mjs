import { importWorkout, ScheduledDate } from './workouts.mjs';
import { uuid } from './domain.mjs';
import { description, tcx } from './export.mjs';
import { defaultRiderSettings } from './storage.mjs';
import { decodeAthleteSettings, athleteChanges, applyChanges, syncNote, isEmpty, shouldRefreshAthlete, emptyState } from './rules/athlete-sync.mjs';
import { shouldAskToUpload } from './rules/upload.mjs';
import { riderIDOf } from './rules/progress.mjs';
// Intervals.icu, one connection per rider (API key only; there is no OAuth on the web). By default a key lives in memory for this tab. "Remember on this
// browser" (opt-in, per rider) stores it only as AES-GCM ciphertext under a non-extractable CryptoKey in the `credentials` store. A credential never goes
// into localStorage, a backup, a rollback backup, a queued job, a log line or an error message.
const BASE = 'https://intervals.icu/api/v1';
/** Scenarios connect with this placeholder; no request is ever sent with it. */
export const PREVIEW_AUTHORIZATION = 'preview-only';
const LEGACY_SLOT = '';
const MAX_ATHLETE_BYTES = 2 * 1024 * 1024;
const norm = id => id == null ? null : String(id).toLowerCase();
const encoder = new TextEncoder(), decoder = new TextDecoder();
const authorizationFor = apiKey => `Basic ${btoa(`API_KEY:${apiKey}`)}`;
const aadFor = (riderID, accountID) => encoder.encode(`ftpunk-intervals|${riderID}|${accountID}`);

/** Encrypts an API key for storage: a fresh AES-GCM key that can never be exported, a random IV, and the rider and account as authenticated data. */
export async function sealKey(riderID, accountID, apiKey) {
  const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aadFor(riderID, accountID) }, key, encoder.encode(apiKey));
  return { key, iv, ciphertext };
}
/** The API key from a stored record, or an error when the record is damaged or was moved to another rider or account. */
export async function openKey(record) {
  if (!record || !record.key || !record.iv || !record.ciphertext) throw Error('Stored key is incomplete.');
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: record.iv, additionalData: aadFor(norm(record.riderID), record.accountID) }, record.key, record.ciphertext);
  return decoder.decode(plain);
}

export class IntervalsClient {
  /** `selectedRider` tells the client which rider `connection` means (the one on screen). Everything that uploads or downloads names its rider. */
  constructor(store, { fetcher = globalThis.fetch, selectedRider = () => null } = {}) {
    Object.assign(this, { store, fetcher, selectedRider }); this.connections = new Map(); this.busy = false; this.suspended = false;
  }
  slot(riderID = this.selectedRider()) { return norm(riderID) ?? LEGACY_SLOT; }
  /** The connection used for a rider's work. Only a client with no riders at all (a single unnamed connection) answers for everyone. */
  lookup(riderID) {
    const own = this.connections.get(norm(riderID) ?? LEGACY_SLOT); if (own) return own;
    return this.connections.size === 1 && this.connections.has(LEGACY_SLOT) ? this.connections.get(LEGACY_SLOT) : null;
  }
  /** The selected rider's connection. */
  get connection() { return this.connections.get(this.slot()) ?? null; }
  set connection(value) { if (value) this.connections.set(this.slot(), value); else this.connections.delete(this.slot()); }
  /** What the screens may know about a rider's connection: never the authorization. */
  connectionFor(riderID) { const c = this.connections.get(this.slot(riderID)); return c ? { id: c.id, name: c.name, remembered: c.remembered === true } : null; }
  async request(path, options = {}) {
    if (options.headers?.Authorization === PREVIEW_AUTHORIZATION) throw Error('Preview mode: no request is sent to Intervals.icu.');
    const response = await this.fetcher(`${BASE}${path}`, { ...options, signal: AbortSignal.timeout(60000) });
    if (!response.ok) { const error = Error([401, 403].includes(response.status) ? 'Reconnect your Intervals.icu account.' : `Intervals.icu returned HTTP ${response.status}.`); error.status = response.status; error.retryAfter = Number(response.headers?.get('Retry-After')) || 60; throw error; }
    return response;
  }
  /** Connects the rider (default: the selected one). Returns { id, name, settings, remembered, rememberFailed }; `settings` is the athlete's FTP and weight. */
  async connect(apiKey, { riderID = this.selectedRider(), remember = false } = {}) {
    const key = String(apiKey ?? '').trim(); if (!key) throw Error('Enter your personal API key.');
    const authorization = authorizationFor(key), slot = this.slot(riderID);
    const athlete = await (await this.request('/athlete/0', { headers: { Authorization: authorization } })).json();
    if (typeof athlete?.id !== 'string' || !athlete.id) throw Error('Intervals.icu returned an unexpected account.');
    for (const [other, c] of this.connections) if (other !== slot && c.id === athlete.id) throw Error('This Intervals.icu account is already connected to another rider.');
    const connection = { id: athlete.id, name: athlete.name || athlete.id, authorization, remembered: false }; let rememberFailed = false;
    if (slot !== LEGACY_SLOT) {
      if (remember) {
        try { const sealed = await sealKey(slot, athlete.id, key); await this.store.put('credentials', { riderID: slot, accountID: athlete.id, accountName: connection.name, savedAt: new Date().toISOString(), ...sealed }); connection.remembered = true; }
        catch { rememberFailed = true; await this.forget(slot); }
      } else await this.forget(slot);
    }
    this.connections.set(slot, connection);
    return { id: connection.id, name: connection.name, settings: decodeAthleteSettings(athlete), remembered: connection.remembered, rememberFailed };
  }
  async forget(riderID) { const slot = this.slot(riderID); if (slot === LEGACY_SLOT) return; try { await this.store.delete('credentials', slot); } catch { /* nothing stored */ } }
  /** Reads every remembered key back at start-up. A record that cannot be decrypted is deleted. Returns the riders who must reconnect. */
  async restoreAll() {
    const failed = []; let records = [];
    try { records = await this.store.all('credentials'); } catch { return failed; }
    for (const record of records) {
      const slot = norm(record.riderID); if (!slot || this.connections.has(slot)) continue;
      try {
        const apiKey = await openKey(record);
        if (typeof record.accountID !== 'string' || !record.accountID) throw Error('Stored account is incomplete.');
        this.connections.set(slot, { id: record.accountID, name: record.accountName || record.accountID, authorization: authorizationFor(apiKey), remembered: true });
      } catch { failed.push(slot); await this.forget(slot); }
    }
    return failed;
  }
  /** Deletes the credential, settings and queued uploads of riders that no longer exist (after an import replaced them). */
  async purgeOrphans(profiles) {
    if (!profiles.length) return;
    const riders = new Set(profiles.map(p => norm(p.id)));
    for (const record of await this.store.all('credentials')) {
      const slot = norm(record.riderID); if (riders.has(slot)) continue;
      this.connections.delete(slot); await this.store.delete('credentials', record.riderID);
      for (const job of await this.store.all('jobs')) if (job.accountID === record.accountID && (job.riderID == null || norm(job.riderID) === slot)) await this.store.delete('jobs', job.id);
    }
    for (const settings of await this.store.all('riderSettings')) if (!riders.has(norm(settings.riderID))) await this.store.delete('riderSettings', settings.riderID);
  }
  /** Disconnects a rider (default: the selected one) and deletes the remembered key. Approved queued uploads stay and wait for a reconnect. */
  async disconnect(riderID = this.selectedRider()) { this.connections.delete(this.slot(riderID)); await this.forget(riderID); }
  async drop(connection) { for (const [slot, c] of this.connections) if (c === connection) { this.connections.delete(slot); await this.forget(slot); } }
  /** FTP and weight from the athlete record of a rider's account. A 401/403 throws with `status`; callers treat it as "skip", not as a broken connection. */
  async athleteSettings(riderID) {
    const connection = this.lookup(riderID); if (!connection) throw Error('Connect Intervals.icu in Settings first.');
    const text = await (await this.request('/athlete/0', { headers: { Authorization: connection.authorization } })).text();
    if (text.length > MAX_ATHLETE_BYTES) throw Error('Intervals.icu returned an unexpected response.');
    return decodeAthleteSettings(JSON.parse(text));
  }
  async workouts(riderID, ftp, oldest, newest) {
    const connection = this.lookup(riderID);
    if (!connection) throw Error('Connect Intervals.icu in Settings before downloading workouts.');
    const params = new URLSearchParams({ category: 'WORKOUT', resolve: 'true', oldest, newest });
    const response = await this.request(`/athlete/${encodeURIComponent(connection.id)}/events?${params}`, { headers: { Authorization: connection.authorization } });
    const text = await response.text(); if (text.length > 10 * 1024 * 1024) throw Error('Workout response is too large.');
    const events = JSON.parse(text); if (!Array.isArray(events) || events.length > 1000) throw Error('Invalid workout response.');
    if (this.lookup(riderID) !== connection) throw Error('The Intervals.icu connection changed. Download again.');
    const workouts = [], skipped = [];
    for (const event of events) {
      try {
        if (!['string', 'number'].includes(typeof event.id) || !String(event.id).length || String(event.id).length > 80 || typeof event.id === 'number' && !Number.isSafeInteger(event.id)) throw Error('Missing workout identity.');
        const plan = importWorkout(JSON.stringify(event), ftp);
        const scheduledDate = ScheduledDate.fromIntervalsLocal(event.start_date_local);
        workouts.push({ id: `intervals:${connection.id}:${riderID}:${event.id}`, riderID, source: `Intervals.icu · ${plan.name}`, savedAt: new Date().toISOString(), plan, ...(scheduledDate ? { scheduledDate } : {}) });
      } catch (e) { skipped.push(`${event?.name ?? 'Untitled workout'}: ${e.message}`); }
    }
    return { workouts, skipped };
  }
  suspendUploads() {
    if (this.busy || this.suspended) throw Error('Wait for the current upload or import to finish.');
    this.suspended = true; return () => { this.suspended = false; };
  }
  /** Queues an approved upload and tries it. The activity goes to the account of its own rider and to no other. */
  async approve(session, accountID) {
    if (this.suspended) throw Error('Wait for the import to finish before approving uploads.');
    const riderID = riderIDOf(session), connection = this.lookup(riderID);
    if (!connection || connection.id !== accountID) throw Error('The destination account changed. Review the upload again.');
    if (session.isDemo || !session.samples.length || session.endedAtOffset == null) throw Error('Only saved, real recordings can upload.');
    const jobs = await this.store.all('jobs');
    if (this.suspended || this.lookup(riderID) !== connection) throw Error('The account or import state changed. Review the upload again.');
    if (jobs.some(j => j.sessionID === session.id && j.accountID === accountID && j.status === 'uploaded')) return;
    const existing = jobs.find(j => j.sessionID === session.id && j.accountID === accountID);
    const job = { id: existing?.id ?? uuid(), sessionID: session.id, riderID, accountID, accountName: connection.name, file: tcx(session), name: `FTPunk · ${session.configuration.riderName}`, description: description(session), status: 'queued', attempts: existing?.attempts ?? 0, retryAt: 0, error: null };
    await this.store.put('jobs', job); return this.flush(true);
  }
  /** The rider a queued job belongs to: stored on the job, or (older jobs) read from its recording. */
  async jobRider(job) {
    if (job.riderID) return norm(job.riderID);
    const session = (await this.store.all('sessions')).find(s => s.id === job.sessionID);
    return session ? riderIDOf(session) : null;
  }
  /** Retries queued jobs. A job only goes out while its own rider is connected to the account it was approved for. */
  async flush(manual = false) {
    if (this.busy || this.suspended || !this.connections.size) return;
    this.busy = true;
    try {
      for (const job of await this.store.all('jobs')) {
        if (!(job.status === 'queued' || manual && job.status === 'failed') || !manual && job.retryAt > Date.now()) continue;
        const riderID = await this.jobRider(job), connection = this.lookup(riderID);
        if (!connection || connection.id !== job.accountID) continue;
        if (!(await this.store.all('jobs')).some(j => j.id === job.id)) continue;
        try {
          const params = new URLSearchParams({ external_id: `ftpunk-web-${job.sessionID}`, name: job.name, description: job.description, device_name: 'FTPunk Web' });
          const form = new FormData(); form.append('file', new Blob([job.file], { type: 'application/vnd.garmin.tcx+xml' }), `${job.sessionID}.tcx`);
          await this.request(`/athlete/${encodeURIComponent(job.accountID)}/activities?${params}`, { method: 'POST', headers: { Authorization: connection.authorization }, body: form });
          job.status = 'uploaded'; job.error = null;
        } catch (error) {
          job.attempts++; job.error = error.message;
          job.status = !error.status || error.status === 429 || error.status >= 500 ? 'queued' : 'failed';
          job.retryAt = Date.now() + Math.min(3600, (error.retryAfter ?? 60) * 2 ** Math.min(job.attempts - 1, 5)) * 1000;
          if (error.status === 401 || error.status === 403) await this.drop(connection);
        }
        if ((await this.store.all('jobs')).some(j => j.id === job.id)) await this.store.put('jobs', job);
      }
    } finally { this.busy = false; }
  }
}

// ----- per-rider state the screens read ---------------------------------------------------------------------------------------------------
// Everything below takes the app model. Settings live in the `riderSettings` store ({ riderID, askToUpload, sync }); the screens render from a cache
// that `loadRiderSettings` fills, because rendering is synchronous.
const UI = new WeakMap();
export function intervalsState(model) {
  if (!UI.has(model)) UI.set(model, { settings: new Map(), notes: new Map(), syncing: new Set(), needsReconnect: new Set(), attempted: new Map() });
  return UI.get(model);
}
export const cachedRiderSettings = (model, riderID) => intervalsState(model).settings.get(norm(riderID)) ?? defaultRiderSettings(norm(riderID));
export async function loadRiderSettings(model, riderID) {
  const settings = await model.store.riderSettings(riderID); intervalsState(model).settings.set(norm(riderID), settings); return settings;
}
async function saveRiderSettings(model, settings) { await model.store.put('riderSettings', settings); intervalsState(model).settings.set(norm(settings.riderID), settings); }
export async function setAskToUpload(model, riderID, enabled) { await saveRiderSettings(model, { ...(await loadRiderSettings(model, riderID)), askToUpload: enabled === true }); model.invalidate(); }
export async function setSyncEnabled(model, riderID, enabled) {
  const settings = await loadRiderSettings(model, riderID); await saveRiderSettings(model, { ...settings, sync: { ...settings.sync, enabled: enabled === true } });
  if (!enabled) intervalsState(model).notes.delete(norm(riderID));
  model.invalidate(); if (enabled) await syncAthlete(model, { riderID, manual: true });
}

/** At start-up: reads remembered keys back (a record that cannot be decrypted is deleted and the rider asked to reconnect) and removes what belongs to riders who no longer exist. */
export async function startIntervals(model) {
  const failed = await model.intervals.restoreAll();
  try { await model.intervals.purgeOrphans(model.profiles); } catch { /* nothing to clean */ }
  if (failed.length) model.notify('A remembered Intervals.icu key could not be read and was deleted. Connect again in Settings.', true);
}
/** Connects the selected rider, links the account for sync, reads FTP and weight once and retries approved uploads. */
export async function connectRider(model, apiKey, { remember = false } = {}) {
  const rider = model.profile; if (!rider) throw Error('Add a rider first.');
  const result = await model.intervals.connect(apiKey, { riderID: rider.id, remember });
  const saved = await model.store.get('riderSettings', rider.id), current = await loadRiderSettings(model, rider.id);
  if (!saved || current.sync.linkedAccountID !== result.id) await saveRiderSettings(model, { ...current, sync: { enabled: saved ? current.sync.enabled : true, linkedAccountID: result.id, lastSynced: null, state: emptyState() } });
  const st = intervalsState(model); st.notes.delete(norm(rider.id)); st.needsReconnect.delete(norm(rider.id));
  await syncAthlete(model, { riderID: rider.id, remote: result.settings });
  await model.intervals.flush(); await model.reload(); model.invalidate();
  return result;
}
export async function disconnectRider(model) {
  const rider = model.profile; if (!rider) return;
  await model.intervals.disconnect(rider.id);
  const settings = await loadRiderSettings(model, rider.id), st = intervalsState(model);
  await saveRiderSettings(model, { ...settings, sync: { enabled: true, linkedAccountID: null, lastSynced: null, state: emptyState() } });
  st.notes.delete(norm(rider.id)); st.needsReconnect.delete(norm(rider.id)); model.invalidate();
}

/** Reads the athlete record (or uses `remote`) and applies a changed FTP and weight to the rider who owns the connection. Never during a ride; a failure
    never breaks the connection. Returns what changed, or null when nothing was attempted. */
export async function syncAthlete(model, { riderID = model.profile?.id, remote = null, manual = false } = {}) {
  const st = intervalsState(model), key = norm(riderID), client = model.intervals;
  if (!key || model.preview || model.busy || st.syncing.has(key)) return null;
  const connection = client.lookup(key); if (!connection) return null;
  let settings = await loadRiderSettings(model, key); if (!settings.sync.enabled) return null;
  st.syncing.add(key);
  try {
    const values = remote ?? await client.athleteSettings(key);
    if (model.busy || client.lookup(key) !== connection) return null;
    st.needsReconnect.delete(key);
    const rider = model.profiles.find(p => norm(p.id) === key); if (!rider) return null;
    const { changes, state } = athleteChanges(values, settings.sync.state, rider);
    if (!isEmpty(changes)) { await model.store.put('profiles', applyChanges(changes, rider)); await model.reload(); model.applyRecommendation(); st.notes.set(key, syncNote(changes)); }
    settings = { ...(await loadRiderSettings(model, key)) }; settings.sync = { ...settings.sync, state, lastSynced: new Date().toISOString(), linkedAccountID: connection.id };
    await saveRiderSettings(model, settings); model.invalidate();
    return changes;
  } catch (error) {
    if (error.status === 401 || error.status === 403) { st.needsReconnect.add(key); model.invalidate(); } else if (manual) throw error;
    return null;
  } finally { st.syncing.delete(key); }
}
/** Home refresh: sync when the last sync is over an hour old (at most one try a minute). */
export async function syncAthleteIfNeeded(model) {
  const riderID = model.profile?.id; if (!riderID || model.preview) return;
  const st = intervalsState(model), key = norm(riderID), settings = await loadRiderSettings(model, riderID);
  if (Date.now() - (st.attempted.get(key) ?? 0) < 60000) return;
  if (!shouldRefreshAthlete({ lastSynced: settings.sync.lastSynced, connected: !!model.connectionFor(riderID), enabled: settings.sync.enabled, rideActive: model.busy, alreadyRunning: st.syncing.has(key) })) return;
  st.attempted.set(key, Date.now()); await syncAthlete(model, { riderID });
}
/** After a finished ride: should the upload dialog open? Decided by UploadPromptRule's port; the rider's own connection and setting count. */
export async function shouldPromptForUpload(model, session) {
  const riderID = riderIDOf(session), connection = model.connectionFor(riderID), settings = await loadRiderSettings(model, riderID);
  const existingJob = model.jobs.find(j => j.sessionID === session.id && j.accountID === connection?.id) ?? null;
  return shouldAskToUpload({ session, hasConnection: !!connection, askEnabled: settings.askToUpload, existingJob });
}
