import { configuration, RampEngine } from '../src/domain.mjs';
import { freeRide, progressMilliseconds } from '../src/training.mjs';
import { LocalStore } from '../src/storage.mjs';
import { parseArchive } from '../src/archive.mjs';

// A database exactly as the previous release (version 3) left it, with data in it. Opening it with this release must add the
// stores for custom workouts, remembered credentials and per-rider settings, and keep every existing record.
async function upgradeFromVersion3() {
  const name = 'ftpunk-test-upgrade-' + crypto.randomUUID(), assert = (value, message) => { if (!value) throw Error(message); };
  const riderID = crypto.randomUUID();
  try {
    const old = await new Promise((resolve, reject) => {
      const req = indexedDB.open(name, 3);
      req.onupgradeneeded = () => { for (const table of ['sessions', 'profiles', 'jobs', 'backups', 'workouts']) req.result.createObjectStore(table, { keyPath: 'id' }); };
      req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error);
    });
    await new Promise((resolve, reject) => {
      const tx = old.transaction(['profiles', 'workouts', 'jobs'], 'readwrite');
      tx.objectStore('profiles').put({ id: riderID, name: 'Upgrade rider', weightKG: 71, ftpHistory: [], currentFTPID: null });
      tx.objectStore('workouts').put({ id: 'w1', riderID, source: 'Kept', savedAt: new Date().toISOString(), plan: { version: 1, kind: 'workout', name: 'Kept', ftpWatts: null, steps: [{ name: 'Steady', seconds: 60, watts: 100 }] } });
      tx.objectStore('jobs').put({ id: 'j1', sessionID: 's1', accountID: 'a', status: 'queued' });
      tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
    });
    old.close();
    const store = await LocalStore.open(name);
    for (const table of ['customWorkouts', 'credentials', 'riderSettings']) assert(store.db.objectStoreNames.contains(table), `Upgrade omitted ${table}`);
    assert(store.db.version === 4, 'Upgrade did not reach version 4');
    assert((await store.all('profiles'))[0].name === 'Upgrade rider' && (await store.all('workouts'))[0].source === 'Kept' && (await store.all('jobs')).length === 1, 'Upgrade lost existing records');
    const settings = await store.riderSettings(riderID);
    assert(settings.askToUpload === true && settings.sync.enabled === false && settings.sync.state.lastSeenFTP === null, 'Default rider settings are wrong');
    await store.put('riderSettings', { ...settings, askToUpload: false, sync: { ...settings.sync, enabled: true, linkedAccountID: 'i1' } });
    await store.put('customWorkouts', { id: crypto.randomUUID(), riderID, name: 'Mine' }); await store.put('customWorkouts', { id: crypto.randomUUID(), riderID: crypto.randomUUID(), name: 'Other' });
    const mine = await new Promise((resolve, reject) => { const tx = store.db.transaction('customWorkouts'), req = tx.objectStore('customWorkouts').index('riderID').getAll(riderID); tx.oncomplete = () => resolve(req.result); tx.onerror = () => reject(tx.error); });
    assert(mine.length === 1 && mine[0].name === 'Mine', 'The customWorkouts index by rider does not work');
    store.db.close();
    const reopened = await LocalStore.open(name);
    const again = await reopened.riderSettings(riderID);
    assert(again.askToUpload === false && again.sync.enabled && again.sync.linkedAccountID === 'i1', 'Rider settings did not survive reopen');
    assert((await reopened.get('credentials', riderID)) === undefined, 'An unsaved credential exists');
    // Backups and rollback snapshots never include credentials or settings.
    assert(!JSON.stringify(await reopened.backup()).includes('askToUpload'), 'A backup leaked rider settings');
    reopened.db.close();
  } finally { await new Promise((resolve, reject) => { const req = indexedDB.deleteDatabase(name); req.onsuccess = resolve; req.onerror = () => reject(req.error); }); }
}

// Runs against the browser's IndexedDB, or an explicitly injected test factory in Node.
// It uses an isolated database and never opens the application's real store.
export async function runStorageSuite() {
  const assert = (value, message) => { if (!value) throw Error(message); };
  const fixtureURL = new URL('./fixtures/portable-v1.json', import.meta.url);
  const text = await (await fetch(fixtureURL)).text();
  const archive = parseArchive(text), name = 'ftpunk-test-' + crypto.randomUUID();
  let store;
  await upgradeFromVersion3();
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
    const engine = new RampEngine(configuration({ riderID: other.id }), { training: freeRide(100) });
    // A recording from before the story was removed: its legacy fields still credit the rider's ledger, once.
    Object.assign(engine.session, { adventureEnabled: true, eligibleMilliseconds: 6000 });
    for (let t = 0; t <= 6; t++) {
      engine.receive({ time: t, power: 100, cadence: 90 }); engine.tick(t);
      await store.saveSession(engine.session); await store.saveSession(engine.session);
    }
    engine.end(6); await store.saveSession(engine.session);
    const savedProgress = async () => (await store.all('profiles')).find(p => p.id === other.id).cycleProgress;
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Repeated checkpoints duplicated legacy credit');
    await store.put('profiles', { ...other, name: 'Edited rider' });
    assert(progressMilliseconds(await savedProgress()) === 6000, 'A stale rider edit erased the legacy ledger');
    // Fail the profile write after the activity write is scheduled: neither may commit.
    const snapshot = JSON.stringify(await store.all('sessions'));
    IDBObjectStore.prototype.put = function (...args) {
      if (this.transaction.db.name === name && this.name === 'profiles') throw new DOMException('Injected progress failure', 'QuotaExceededError');
      return originalPut.apply(this, args);
    };
    failed = false;
    try { await store.saveSession({ ...engine.session, eligibleMilliseconds: 1200000 }); } catch { failed = true; }
    finally { IDBObjectStore.prototype.put = originalPut; }
    assert(failed && JSON.stringify(await store.all('sessions')) === snapshot, 'Ledger write failure partially committed the activity');
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Failed checkpoint changed the ledger');
    const trainingArchive = await store.backup(); assert(trainingArchive.version === 2, 'Legacy ledger did not export as v2');
    await store.restore(trainingArchive); await store.restore(trainingArchive);
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Repeated v2 restore duplicated the ledger');
    await store.delete('sessions', engine.session.id);
    assert(progressMilliseconds(await savedProgress()) === 6000, 'Deleting a recording erased the ledger');
    store.db.close(); store = await LocalStore.open(name);
    assert(progressMilliseconds(await savedProgress()) === 6000, 'The ledger did not survive reopen');
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
    return 'Version 3 to 4 upgrade (new stores, rider settings, kept data), offline workout caching, v3 transfer, library identity protection and rollback; IndexedDB v1 migration, idempotent restore, unrelated rider preservation, rollback retention, transaction abort, training/legacy-ledger atomicity, duplicate credits, deletion and reopen';
  } finally {
    store?.db.close();
    await new Promise((resolve, reject) => { const req = indexedDB.deleteDatabase(name); req.onsuccess = resolve; req.onerror = () => reject(req.error); });
  }
}
