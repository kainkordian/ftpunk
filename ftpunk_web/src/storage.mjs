import { validateCachedWorkout } from './workouts.mjs';
import { creditSession } from './training.mjs';
import { makeArchive, validateArchive, archiveSessions, archiveText } from './archive.mjs';
export const DB_NAME = 'ftpunk-web-v1';
const STORES = ['sessions', 'profiles', 'jobs', 'backups', 'workouts'];
export class LocalStore {
  static async open(name = DB_NAME) {
    if (!globalThis.indexedDB) throw Error('Local storage is unavailable. Enable browser storage before starting a test.');
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open(name, 3);
      request.onupgradeneeded = () => { for (const name of STORES) if (!request.result.objectStoreNames.contains(name)) request.result.createObjectStore(name, { keyPath: 'id' }); };
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
      request.onblocked = () => reject(Error('Close other FTPunk tabs to update local storage.'));
    });
    db.onversionchange = () => db.close(); return new LocalStore(db);
  }
  constructor(db) { this.db = db; }
  request(store, mode, run) {
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(store, mode), req = run(tx.objectStore(store));
      tx.oncomplete = () => resolve(req?.result); tx.onerror = () => reject(tx.error ?? Error('Local storage failed.')); tx.onabort = () => reject(tx.error ?? Error('Local storage was interrupted.'));
    });
  }
  all(store) { return this.request(store, 'readonly', s => s.getAll()); }
  put(store, value) {
    if (store !== 'profiles') return this.request(store, 'readwrite', s => s.put(structuredClone(value)));
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction('profiles', 'readwrite'), table = tx.objectStore('profiles'), req = table.get(value.id);
      tx.oncomplete = () => resolve(); tx.onerror = tx.onabort = () => reject(tx.error ?? Error('Rider could not be saved.'));
      req.onsuccess = () => {
        const next = structuredClone(value), saved = req.result?.cycleProgress;
        if (saved) {
          next.cycleProgress ??= { version: 1, credits: {} };
          for (const [id, ms] of Object.entries(saved.credits)) next.cycleProgress.credits[id] = Math.max(next.cycleProgress.credits[id] ?? 0, ms);
        }
        table.put(next);
      };
    });
  }
  saveWorkouts(workouts) {
    const clean = workouts.map(validateCachedWorkout);
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction('workouts', 'readwrite'), table = tx.objectStore('workouts');
      tx.oncomplete = () => resolve(); tx.onerror = tx.onabort = () => reject(tx.error ?? Error('Workout library could not be saved.'));
      const existing = table.getAll(); existing.onsuccess = () => {
        const owners = new Map(existing.result.map(w => [w.id, w.riderID]));
        for (const workout of clean) {
          if (owners.has(workout.id) && owners.get(workout.id) !== workout.riderID) { tx.abort(); return; }
          owners.set(workout.id, workout.riderID); table.put(workout);
        }
        if (owners.size > 2000) tx.abort();
      };
    });
  }
  saveSession(session) {
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(['sessions', 'profiles'], 'readwrite');
      tx.oncomplete = () => resolve(); tx.onerror = tx.onabort = () => reject(tx.error ?? Error('Recording and progress could not be saved.'));
      tx.objectStore('sessions').put(structuredClone(session));
      if (!session.isDemo && session.adventureEnabled === true) {
        const id = session.configuration.riderID ?? '00000000-0000-0000-0000-000000000001';
        const req = tx.objectStore('profiles').get(id);
        req.onsuccess = () => {
          try {
            const profile = req.result ?? { id, name: session.configuration.riderName ?? 'You', ftpHistory: [], currentFTPID: null };
            profile.cycleProgress = creditSession(profile.cycleProgress, session); tx.objectStore('profiles').put(profile);
          } catch { tx.abort(); }
        };
      }
    });
  }
  delete(store, id) { return this.request(store, 'readwrite', s => s.delete(id)); }
  async recover() {
    for (const session of await this.all('sessions')) if (session.endedAtOffset == null) {
      if (session.rampEnd == null) { session.outcome = 'interrupted'; session.result = null; }
      session.endReason = 'Recovered after the browser stopped.';
      session.endedAtOffset = session.samples.at(-1)?.time ?? 0;
      await this.put('sessions', session);
    }
  }
  async backup() {
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(['profiles', 'sessions', 'workouts'], 'readonly');
      const profiles = tx.objectStore('profiles').getAll(), sessions = tx.objectStore('sessions').getAll(), workouts = tx.objectStore('workouts').getAll();
      tx.oncomplete = () => { try { resolve(makeArchive(profiles.result, sessions.result, undefined, workouts.result)); } catch (e) { reject(e); } };
      tx.onerror = tx.onabort = () => reject(tx.error ?? Error('Backup could not be read.'));
    });
  }
  async restore(input) {
    const archive = validateArchive(input), incoming = archiveSessions(archive);
    const riders = new Set(archive.profiles.map(p => p.id)), ids = new Set(incoming.map(s => s.id));
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(STORES, 'readwrite'), requests = {};
      let pending = STORES.length, failure, backupID;
      tx.oncomplete = () => resolve(backupID);
      tx.onabort = tx.onerror = () => reject(failure ?? tx.error ?? Error('Import was interrupted. Nothing was changed.'));
      for (const name of STORES) {
        const req = tx.objectStore(name).getAll(); requests[name] = req;
        req.onsuccess = () => {
          if (--pending) return;
          try {
            const oldSessions = requests.sessions.result, oldProfiles = requests.profiles.result;
            const owner = s => (s.configuration.riderID ?? '00000000-0000-0000-0000-000000000001').toLowerCase();
            if (oldSessions.some(s => ids.has(s.id.toLowerCase()) && !riders.has(owner(s)))) throw Error('An imported activity belongs to a different local rider. Nothing was changed.');
            const workoutIDs = new Set((archive.workouts ?? []).map(w => w.id));
            if (requests.workouts.result.some(w => workoutIDs.has(w.id) && !riders.has(w.riderID.toLowerCase()))) throw Error('An imported workout belongs to a different local rider. Nothing was changed.');
            const before = makeArchive(oldProfiles, oldSessions, undefined, requests.workouts.result); archiveText(before);
            backupID = crypto.randomUUID();
            tx.objectStore('backups').put({ id: backupID, createdAt: new Date().toISOString(), archive: before });
            // Retain the latest three rollback snapshots without growing the database forever.
            for (const old of requests.backups.result.sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(2)) tx.objectStore('backups').delete(old.id);
            const removed = new Set();
            for (const s of oldSessions) if (riders.has(owner(s))) { removed.add(s.id); tx.objectStore('sessions').delete(s.id); }
            for (const p of oldProfiles) if (riders.has(p.id.toLowerCase())) tx.objectStore('profiles').delete(p.id);
            for (const j of requests.jobs.result) if (removed.has(j.sessionID)) tx.objectStore('jobs').delete(j.id);
            for (const w of requests.workouts.result) if (riders.has(w.riderID.toLowerCase())) tx.objectStore('workouts').delete(w.id);
            for (const w of archive.workouts ?? []) tx.objectStore('workouts').put(w);
            for (const p of archive.profiles) tx.objectStore('profiles').put(p);
            for (const s of incoming) tx.objectStore('sessions').put(s);
          } catch (e) { failure = e; tx.abort(); }
        };
      }
    });
  }
}
// Only one tab may recover sessions or own a live/mock workout at a time.
export async function acquireRideLease(locks = globalThis.navigator?.locks) {
  if (!locks) throw Error('This browser cannot reserve trainer control. Use a current version of Chrome.');
  return new Promise((resolve, reject) => {
    locks.request('ftpunk-web-ride', { ifAvailable: true }, lock => {
      if (!lock) { reject(Error('Another FTPunk tab is running a test. End that test first.')); return; }
      return new Promise(release => resolve(release));
    }).catch(reject);
  });
}
export function loadPreferences(storage = globalThis.localStorage) {
  const defaults = { appearance: 'system', extraLarge: false, powerMatching: true, adventure: false, selectedRider: null };
  try { const p = JSON.parse(storage.getItem('ftpunk.preferences') || '{}'); return { ...defaults, appearance: ['light', 'dark', 'system'].includes(p.appearance) ? p.appearance : 'system', extraLarge: p.extraLarge === true, powerMatching: p.powerMatching !== false, adventure: p.adventure === true, selectedRider: typeof p.selectedRider === 'string' ? p.selectedRider : null }; } catch { return defaults; }
}
export function savePreferences(p, storage = globalThis.localStorage) { storage.setItem('ftpunk.preferences', JSON.stringify(p)); }
