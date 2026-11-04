import { importWorkout } from './workouts.mjs';
import { uuid } from './domain.mjs';
import { description, tcx } from './export.mjs';
const BASE = 'https://intervals.icu/api/v1';
export class IntervalsClient {
  constructor(store, { fetcher = globalThis.fetch } = {}) { this.store = store; this.fetcher = fetcher; this.connection = null; this.busy = false; this.suspended = false; }
  async request(path, options = {}) {
    const response = await this.fetcher(`${BASE}${path}`, { ...options, signal: AbortSignal.timeout(60000) });
    if (!response.ok) { const error = Error([401, 403].includes(response.status) ? 'Reconnect your Intervals.icu account.' : `Intervals.icu returned HTTP ${response.status}.`); error.status = response.status; error.retryAfter = Number(response.headers?.get('Retry-After')) || 60; throw error; }
    return response;
  }
  async connect(apiKey) {
    if (!apiKey.trim()) throw Error('Enter your personal API key.');
    const auth = `Basic ${btoa(`API_KEY:${apiKey.trim()}`)}`;
    const athlete = await (await this.request('/athlete/0', { headers: { Authorization: auth } })).json();
    if (typeof athlete.id !== 'string' || !athlete.id) throw Error('Intervals.icu returned an unexpected account.');
    // Credentials intentionally live in memory only, never in browser storage or backups.
    this.connection = { id: athlete.id, name: athlete.name || athlete.id, authorization: auth };
    return { id: this.connection.id, name: this.connection.name };
  }
  async workouts(riderID, ftp, oldest, newest) {
    const connection = this.connection;
    if (!connection) throw Error('Connect Intervals.icu in Settings before downloading workouts.');
    const params = new URLSearchParams({ category: 'WORKOUT', resolve: 'true', oldest, newest });
    const response = await this.request(`/athlete/${encodeURIComponent(connection.id)}/events?${params}`, { headers: { Authorization: connection.authorization } });
    const text = await response.text(); if (text.length > 10 * 1024 * 1024) throw Error('Workout response is too large.');
    const events = JSON.parse(text); if (!Array.isArray(events) || events.length > 1000) throw Error('Invalid workout response.');
    if (this.connection !== connection) throw Error('The Intervals.icu connection changed. Download again.');
    const workouts = [], skipped = [];
    for (const event of events) {
      try {
        if (!['string', 'number'].includes(typeof event.id) || !String(event.id).length || String(event.id).length > 80 || typeof event.id === 'number' && !Number.isSafeInteger(event.id)) throw Error('Missing workout identity.');
        const plan = importWorkout(JSON.stringify(event), ftp);
        workouts.push({ id: `intervals:${connection.id}:${riderID}:${event.id}`, riderID, source: `Intervals.icu · ${plan.name}`, savedAt: new Date().toISOString(), plan });
      } catch (e) { skipped.push(`${event?.name ?? 'Untitled workout'}: ${e.message}`); }
    }
    return { workouts, skipped };
  }
  disconnect() { this.connection = null; }
  suspendUploads() {
    if (this.busy || this.suspended) throw Error('Wait for the current upload or import to finish.');
    this.suspended = true; return () => { this.suspended = false; };
  }
  async approve(session, accountID) {
    if (this.suspended) throw Error('Wait for the import to finish before approving uploads.');
    if (!this.connection || this.connection.id !== accountID) throw Error('The destination account changed. Review the upload again.');
    if (session.isDemo || !session.samples.length || session.endedAtOffset == null) throw Error('Only saved, real recordings can upload.');
    const jobs = await this.store.all('jobs');
    if (this.suspended || this.connection?.id !== accountID) throw Error('The account or import state changed. Review the upload again.');
    if (jobs.some(j => j.sessionID === session.id && j.accountID === accountID && j.status === 'uploaded')) return;
    const existing = jobs.find(j => j.sessionID === session.id && j.accountID === accountID);
    const job = { id: existing?.id ?? uuid(), sessionID: session.id, accountID, accountName: this.connection.name, file: tcx(session), name: `FTPunk · ${session.configuration.riderName}`, description: description(session), status: 'queued', attempts: existing?.attempts ?? 0, retryAt: 0, error: null };
    await this.store.put('jobs', job); return this.flush(true);
  }
  async flush(manual = false) {
    if (this.busy || this.suspended || !this.connection) return;
    this.busy = true;
    try {
      for (const job of await this.store.all('jobs')) {
        if (job.accountID !== this.connection?.id || !(job.status === 'queued' || manual && job.status === 'failed') || !manual && job.retryAt > Date.now()) continue;
        if (!(await this.store.all('jobs')).some(j => j.id === job.id)) continue;
        const connection = this.connection;
        if (!connection || connection.id !== job.accountID) continue;
        try {
          const params = new URLSearchParams({ external_id: `ftpunk-web-${job.sessionID}`, name: job.name, description: job.description, device_name: 'FTPunk Web' });
          const form = new FormData(); form.append('file', new Blob([job.file], { type: 'application/vnd.garmin.tcx+xml' }), `${job.sessionID}.tcx`);
          await this.request(`/athlete/${encodeURIComponent(job.accountID)}/activities?${params}`, { method: 'POST', headers: { Authorization: connection.authorization }, body: form });
          job.status = 'uploaded'; job.error = null;
        } catch (error) {
          job.attempts++; job.error = error.message;
          job.status = !error.status || error.status === 429 || error.status >= 500 ? 'queued' : 'failed';
          job.retryAt = Date.now() + Math.min(3600, (error.retryAfter ?? 60) * 2 ** Math.min(job.attempts - 1, 5)) * 1000;
          if (error.status === 401 || error.status === 403) this.connection = null;
        }
        if ((await this.store.all('jobs')).some(j => j.id === job.id)) await this.store.put('jobs', job);
      }
    } finally { this.busy = false; }
  }
}
