import { configuration, RampEngine } from '../src/domain.mjs';
import { freeRide, progressMilliseconds } from '../src/training.mjs';
import { LocalStore } from '../src/storage.mjs';
import { parseArchive } from '../src/archive.mjs';

// Runs against the browser's IndexedDB, or an explicitly injected test factory in Node.
// It uses an isolated database and never opens the application's real store.
export async function runStorageSuite() {
  const assert = (value, message) => { if (!value) throw Error(message); };
  const fixtureURL = new URL('./fixtures/portable-v1.json', import.meta.url);
  const text = typeof window === 'undefined' ? await (await import('node:fs/promises')).readFile(fixtureURL, 'utf8') : await (await fetch(fixtureURL)).text();
  const archive = parseArchive(text), name = 'ftpunk-test-' + crypto.randomUUID();
  let store;
  try {
    // Seed the exact original database version, then exercise the real upgrade code.
    const legacy = await new Promise((resolve, reject) => {
      const req = indexedDB.open(name, 1);
      req.onupgradeneeded = () => { for (const table of ['sessions', 'profiles', 'jobs']) req.result.createObjectStore(table, { keyPath: 'id' }); };
      req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error);
    });
    legacy.close(); store = await LocalStore.open(name);
    assert(store.db.objectStoreNames.contains('backups'), 'Version 1 upgrade omitted rollback storage');
    const other = { id: crypto.randomUUID(), name: 'Other rider', ftpHistory: [], currentFTPID: null };
    await store.put('profiles', other);
    await store.restore(archive); await store.restore(archive);
    assert((await store.all('sessions')).length === 1, 'Repeated import duplicated activities');
    assert((await store.all('profiles')).length === 2, 'Import lost an unrelated rider');
    assert((await store.all('sessions'))[0].result.estimatedFTP === 225, 'Restore changed FTP');
    assert((await store.all('backups')).length === 2, 'Missing pre-import backups');
    await store.restore(archive); await store.restore(archive);
    assert((await store.all('backups')).length === 3, 'Rollback retention is not bounded');
    const before = JSON.stringify(await store.all('sessions'));
    const backupCount = (await store.all('backups')).length;
    // Fail after the transaction has already scheduled deletions/profile writes.
    const originalPut = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args) {
      if (this.transaction.db.name === name && this.name === 'sessions') throw new DOMException('Injected write failure', 'QuotaExceededError');
      return originalPut.apply(this, args);
    };
    let failed = false;
    try { await store.restore(archive); } catch { failed = true; }
    finally { IDBObjectStore.prototype.put = originalPut; }
    assert(failed, 'The injected database failure was ignored');
    assert(JSON.stringify(await store.all('sessions')) === before, 'Failed import partially replaced history');
    assert((await store.all('profiles')).length === 2, 'Failed import partially replaced profiles');
    assert((await store.all('backups')).length === backupCount, 'Failed import committed only its backup');
    const bad = structuredClone(archive); bad.activities[0].session.endedAtOffset = null;
    failed = false; try { await store.restore(bad); } catch { failed = true; }
    assert(failed && JSON.stringify(await store.all('sessions')) === before, 'Invalid archive changed history');
    store.db.close(); store = await LocalStore.open(name);
    assert(JSON.stringify(await store.all('sessions')) === before, 'Restored data did not survive reopen');
    const engine = new RampEngine(configuration({ riderID: other.id }), { training: freeRide(100), adventure: true });
    for (let t = 0; t <= 6; t++) {
      engine.receive({ time: t, power: 100, cadence: 90 }); engine.tick(t);
      await store.saveSession(engine.session); await store.saveSession(engine.session);
    }
    engine.end(6); await store.saveSession(engine.session);
    const savedProgress = async () => (await store.all('profiles')).find(p => p.id === other.id).cycleProgress;
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Repeated checkpoints duplicated XP');
    await store.put('profiles', { ...other, name: 'Edited rider' });
    assert(progressMilliseconds(await savedProgress()) === 6000, 'A stale rider edit erased progress');
    // Fail the profile write after the activity write is scheduled: neither may commit.
    const snapshot = JSON.stringify(await store.all('sessions'));
    IDBObjectStore.prototype.put = function (...args) {
      if (this.transaction.db.name === name && this.name === 'profiles') throw new DOMException('Injected progress failure', 'QuotaExceededError');
      return originalPut.apply(this, args);
    };
    failed = false;
    try { await store.saveSession({ ...engine.session, eligibleMilliseconds: 1200000 }); } catch { failed = true; }
    finally { IDBObjectStore.prototype.put = originalPut; }
    assert(failed && JSON.stringify(await store.all('sessions')) === snapshot, 'Progress write failure partially committed the activity');
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Failed checkpoint changed XP');
    const trainingArchive = await store.backup(); assert(trainingArchive.version === 2, 'Training did not export as v2');
    await store.restore(trainingArchive); await store.restore(trainingArchive);
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Repeated v2 restore duplicated XP');
    await store.delete('sessions', engine.session.id);
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Deleting a recording erased progression');
    store.db.close(); store = await LocalStore.open(name);
    assert(progressMilliseconds(await savedProgress()) === 6000, 'XP did not survive reopen');
    assert(store.db.objectStoreNames.contains('workouts'), 'Upgrade omitted the offline library');
    const plan = { version: 2, kind: 'workout', name: 'Ramp', steps: [{ name: 'Build', seconds: 10, watts: 100, endWatts: 200 }] };
    const workout = { id: 'intervals:fixture', riderID: other.id, source: 'Fixture', savedAt: new Date().toISOString(), plan };
    await store.saveWorkouts([workout]); await store.saveWorkouts([workout]);
    assert((await store.all('workouts')).length === 1, 'Repeated download duplicated a workout');
    const libraryArchive = await store.backup(); assert(libraryArchive.version === 3, 'Library did not export as v3');
    await store.restore(libraryArchive); await store.restore(libraryArchive);
    assert((await store.all('workouts')).length === 1, 'Repeated v3 restore duplicated the library');
    const collision = { ...workout, riderID: archive.profiles[0].id };
    failed = false;
    try { await store.saveWorkouts([{ ...workout, id: 'new' }, collision]); } catch { failed = true; }
    assert(failed && (await store.all('workouts')).length === 1, 'Conflicting cache batch partially committed');
    failed = false;
    try { await store.restore({ ...archive, version: 3, workouts: [collision] }); } catch { failed = true; }
    assert(failed && (await store.all('workouts'))[0].riderID === other.id, 'Import overwrote an unrelated rider workout');
    const oldLibrary = JSON.stringify(await store.all('workouts'));
    IDBObjectStore.prototype.put = function (...args) {
      if (this.transaction.db.name === name && this.name === 'workouts') throw new DOMException('Injected library failure', 'QuotaExceededError');
      return originalPut.apply(this, args);
    };
    failed = false;
    try { await store.restore(libraryArchive); } catch { failed = true; }
    finally { IDBObjectStore.prototype.put = originalPut; }
    assert(failed && JSON.stringify(await store.all('workouts')) === oldLibrary, 'Failed restore partly replaced library');
    store.db.close(); store = await LocalStore.open(name);
    assert(JSON.stringify(await store.all('workouts')) === oldLibrary, 'Offline library did not survive reopen');
    return 'Offline workout caching, v3 transfer, library identity protection and rollback; IndexedDB v1 migration, idempotent restore, unrelated rider preservation, rollback retention, transaction abort, training/XP atomicity, duplicate credits, deletion and reopen';
  } finally {
    store?.db.close();
    await new Promise((resolve, reject) => { const req = indexedDB.deleteDatabase(name); req.onsuccess = resolve; req.onerror = () => reject(req.error); });
  }
}
