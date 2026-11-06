import { test, assert, equal, rejects, throws, fixture } from './harness.mjs';
import { fitFile, crc16, pauses } from '../src/fit.mjs';
import { exportFile, fileName, FORMATS } from '../src/export.mjs';
import { shouldAskToUpload } from '../src/rules/upload.mjs';
import { decodeAthleteSettings, athleteChanges, applyChanges, syncNote, isEmpty, shouldRefreshAthlete } from '../src/rules/athlete-sync.mjs';
import { IntervalsClient, sealKey, openKey, connectRider, disconnectRider, syncAthlete, syncAthleteIfNeeded, shouldPromptForUpload, setAskToUpload, setSyncEnabled, PREVIEW_AUTHORIZATION } from '../src/intervals.mjs';
import { AppModel } from '../src/app-model.mjs';
import { MemoryStore } from '../src/memory-store.mjs';
import { LocalStore, DB_SCHEMA } from '../src/storage.mjs';
import { BluetoothDevices } from '../src/bluetooth.mjs';
import { archiveText } from '../src/archive.mjs';
import { rider, finishedRamp, ALEX_ID, SAM_ID } from '../src/preview-fixtures.mjs';
import { scenarioNames } from '../src/ui/scenarios.mjs';
// Plan 9b: FIT export (byte parity with the native encoder), export file names, the upload prompt rule, FTP and weight sync, one Intervals.icu connection per
// rider, and the remembered key (AES-GCM, non-extractable). Nothing here talks to Intervals.icu: every client gets a fake fetcher.

const KEY = 'secret-key-0123456789', KEY_B = 'other-key-9876543210';
const bytesOf = async name => new Uint8Array(await (await fetch(new URL(`./fixtures/${name}`, import.meta.url))).arrayBuffer());
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const drain = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
const json = body => new Response(JSON.stringify(body), { status: 200 });
const athlete = (id, extra = {}) => ({ id, name: `Athlete ${id}`, icu_weight: 71.5, sportSettings: [{ types: ['Ride', 'VirtualRide'], ftp: 262, indoor_ftp: 250 }], ...extra });
/** A fetcher that answers /athlete/0 by the Authorization header (key -> account) and records every call. */
function fakeIntervals(accounts = { [KEY]: athlete('i1'), [KEY_B]: athlete('i2') }) {
  const calls = [];
  const fetcher = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    const auth = options.headers?.Authorization ?? '', key = Object.keys(accounts).find(k => auth === `Basic ${btoa(`API_KEY:${k}`)}`);
    if (!key) return new Response('', { status: 401 });
    if (String(url).endsWith('/athlete/0')) return json(accounts[key]);
    if (String(url).includes('/events')) return json([]);
    return new Response('{}', { status: 200 });
  };
  return { fetcher, calls };
}
const preferences = id => ({ appearance: 'system', extraLarge: false, powerMatching: true, selectedRider: id, debugUnlocked: false, intervalsHintDismissed: false });
async function makeModel({ riders = [rider()], store = new MemoryStore(), accounts } = {}) {
  for (const p of riders) await store.put('profiles', p);
  const model = new AppModel({ store, devices: new BluetoothDevices({ bluetooth: null }), prefs: preferences(riders[0].id), lease: async () => () => {} });
  const fake = fakeIntervals(accounts); model.intervals.fetcher = fake.fetcher; model.calls = fake.calls;
  await model.boot(); return model;
}
const freshDatabase = async () => LocalStore.open(`ftpunk-test-intervals-${crypto.randomUUID()}`);
/** Every stored value of every store as text, with binary values written out as bytes and base64 so a plaintext key can be searched for anywhere. */
async function everything(store) {
  const out = [];
  for (const name of Object.keys(DB_SCHEMA)) for (const value of await store.all(name)) out.push(JSON.stringify(value, (k, v) => {
    if (v instanceof ArrayBuffer) v = new Uint8Array(v);
    if (ArrayBuffer.isView(v)) return { bytes: [...v], text: String.fromCharCode(...v), base64: btoa(String.fromCharCode(...v)) };
    if (typeof CryptoKey !== 'undefined' && v instanceof CryptoKey) return { cryptoKey: true };
    return v;
  }));
  return out.join('\n');
}
const leaks = (text, ...secrets) => secrets.filter(s => text.includes(s) || text.includes(btoa(s)) || text.includes(btoa(`API_KEY:${s}`)) || text.includes(JSON.stringify([...new TextEncoder().encode(s)]).slice(1, -1)));

// ----- FIT --------------------------------------------------------------------------------------------------------------------------------------------
test('FIT files are byte-identical to the ones the native encoder wrote (an FTP test with a meter and strap, a paused workout with trainer power)', async () => {
  const offsets = (await fixture('fit-offsets')).utcOffsetSeconds;
  for (const name of ['ftp-test', 'workout']) {
    const session = await fixture(`fit-${name}.session`), expected = await bytesOf(`fit-${name}.fit`), actual = fitFile(session, { utcOffsetSeconds: offsets[name] });
    assert(same(actual, expected), `${name}: ${actual.length} bytes against ${expected.length}; first difference at ${actual.findIndex((v, i) => v !== expected[i])}`);
    // Without an explicit offset the browser's own is used: only the local timestamp (4 bytes) and the file checksum (2 bytes) may differ.
    const local = fitFile(session); equal(local.length, expected.length); assert(same(local.slice(0, -6), expected.slice(0, -6)));
  }
});
test('FIT header, checksums, records and laps follow the format', async () => {
  const session = await fixture('fit-ftp-test.session'), file = fitFile(session), view = new DataView(file.buffer);
  equal([file[0], file[1], view.getUint16(2, true), String.fromCharCode(...file.slice(8, 12))], [14, 0x20, 21221, '.FIT']);
  equal(view.getUint32(4, true), file.length - 16); equal(crc16(file.slice(0, 12)), view.getUint16(12, true)); equal(crc16(file.slice(0, -2)), view.getUint16(file.length - 2, true));
  equal(crc16(new TextEncoder().encode('123456789')), 0xBB3D); equal(crc16([]), 0);
  // Messages by global number: records are one per second with data (dropouts are left out); the ramp test has three laps (warm-up, ramp, cool-down).
  const counts = {}; let at = 14; const defs = {};
  while (at < file.length - 2) {
    const header = file[at++], local = header & 15;
    if (header & 0x40) { const global = view.getUint16(at + 2, true), n = file[at + 4]; defs[local] = { global, size: Array.from({ length: n }, (_, i) => file[at + 6 + i * 3]).reduce((a, b) => a + b, 0) }; at += 5 + n * 3; }
    else { counts[defs[local].global] = (counts[defs[local].global] ?? 0) + 1; at += defs[local].size; }
  }
  equal(at, file.length - 2); equal([counts[0], counts[18], counts[34], counts[19]], [1, 1, 1, 3]);
  const seconds = new Set(session.samples.map(s => Math.floor(s.time))); equal(counts[20], seconds.size); assert(counts[20] < 421);
});
test('FIT pauses stop the timer, workouts get one lap per step, and unfinished or empty recordings are refused', async () => {
  const session = await fixture('fit-workout.session');
  equal(pauses(session), [{ stop: 401, resume: 460 }]);
  const file = fitFile(session, { utcOffsetSeconds: 0 }); assert(file.length > 1000);
  const open = structuredClone(session); open.endedAtOffset = null; throws(() => fitFile(open));
  const empty = structuredClone(session); empty.samples = []; throws(() => fitFile(empty));
  const silent = structuredClone(session); silent.samples = [{ time: 1 }, { time: 2 }]; throws(() => fitFile(silent));
  // A recording made by this app (numeric prior FTP, web event names) encodes too.
  const web = finishedRamp(rider(), { daysAgo: 1 }).session; assert(fitFile(web).length > 1000); equal(typeof web.configuration.priorFTP, 'number');
});
test('Export file names follow the native pattern and every format can be built', async () => {
  const session = finishedRamp(rider(), { daysAgo: 1 }).session, d = new Date(session.startedAt), day = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  equal(fileName(session, 'fit'), `FTPunk-${day}-25-W-min.fit`); equal(fileName({ ...session, isDemo: true }, 'csv'), `DEMO-FTPunk-${day}-25-W-min.csv`);
  equal(fileName({ ...session, training: { name: '  VO2 max 5×3 (hard!) ' } }, 'tcx'), `FTPunk-${day}-VO2-max-5-3-hard.tcx`); equal(fileName({ ...session, training: { name: '!!!' } }, 'json'), `FTPunk-${day}-Activity.json`);
  for (const format of Object.keys(FORMATS)) { const file = exportFile(session, format); assert(file.name.endsWith(`.${format}`) && file.bytes.length > 100 && file.type); }
  assert(exportFile(session, 'fit').bytes instanceof Uint8Array);
});

// ----- upload prompt rule (IntervalsPerRiderTests.swift) -------------------------------------------------------------------------------------------------
const promptSession = ({ training = null, outcome, ended, result = false, demo = false }) => ({ training, outcome, endedAtOffset: ended, result: result ? { bestMinutePower: 300 } : null, isDemo: demo });
const ask = (session, { connected = true, enabled = true, job = null } = {}) => shouldAskToUpload({ session, hasConnection: connected, askEnabled: enabled, existingJob: job });
test('The upload prompt rule matches native for every case', () => {
  const workout = { kind: 'workout', name: 'W', steps: [{ name: 'a', seconds: 600, watts: 150 }] }, free = { kind: 'freeRide', name: 'Free ERG ride', steps: [{ name: 'Ride', seconds: 86400, watts: 150 }] };
  assert(ask(promptSession({ outcome: 'exhaustion', ended: 900, result: true })));                                   // FTP result
  assert(ask(promptSession({ outcome: 'finishedEarly', ended: 900, result: true })));                                // finished early with an estimate
  assert(!ask(promptSession({ outcome: 'aborted', ended: 900 })));                                                  // FTP test stopped without a result
  assert(!ask(promptSession({ outcome: 'limitReached', ended: 900, result: true })));                               // an estimate needs exhaustion or finishing early
  assert(ask(promptSession({ training: workout, outcome: 'completed', ended: 1800 })));                              // completed workout
  assert(ask(promptSession({ training: workout, outcome: 'aborted', ended: 600 })));                                 // stopped by the rider after 10 minutes
  assert(ask(promptSession({ training: free, outcome: 'aborted', ended: 300 })));                                    // exactly 5 minutes
  assert(!ask(promptSession({ training: free, outcome: 'aborted', ended: 240 })));                                   // 4 minutes
  assert(!ask(promptSession({ training: workout, outcome: 'interrupted', ended: 1200 })));                           // interrupted rides are never prompted
  assert(!ask(promptSession({ outcome: 'exhaustion', ended: 900, result: true, demo: true })));                      // debug
  assert(!ask(promptSession({ training: workout, outcome: 'completed', ended: 1800 }), { job: { status: 'queued' } })); // already queued or uploaded
  assert(!ask(promptSession({ training: workout, outcome: 'completed', ended: 1800 }), { connected: false }));
  assert(!ask(promptSession({ training: workout, outcome: 'completed', ended: 1800 }), { enabled: false }));
  assert(!ask({ ...promptSession({ training: workout, outcome: 'completed', ended: 1800 }), endedAtOffset: null }));  // not finished
});

// ----- athlete sync (AthleteSyncTests.swift) -----------------------------------------------------------------------------------------------------------
const profile = (ftp = null, weight = null) => ({ id: crypto.randomUUID(), name: 'A', weightKG: weight, ftpHistory: ftp == null ? [] : [{ id: 'e1', watts: ftp, date: '2026-01-01T00:00:00Z', source: 'Manual' }], currentFTPID: ftp == null ? null : 'e1' });
test('Athlete settings prefer the indoor FTP of VirtualRide and decode leniently', () => {
  equal(decodeAthleteSettings({ icu_weight: 71.5, sportSettings: [{ types: ['Ride', 'VirtualRide'], ftp: 250, indoor_ftp: 240 }, { types: ['Run'], ftp: 400 }] }), { weightKG: 71.5, ftpWatts: 240 });
  equal(decodeAthleteSettings({ sportSettings: [{ types: ['Ride'], ftp: 262, indoor_ftp: 0 }] }), { weightKG: null, ftpWatts: 262 });
  equal(decodeAthleteSettings({ sportSettings: [{ types: ['Ride'], ftp: 300 }, { types: ['VirtualRide'], ftp: 255 }] }).ftpWatts, 255);
  const none = { weightKG: null, ftpWatts: null };
  equal(decodeAthleteSettings({}), none); equal(decodeAthleteSettings({ icu_weight: 0, sportSettings: [{ types: ['Ride'], ftp: -5 }] }), none);
  equal(decodeAthleteSettings({ icu_weight: 12, sportSettings: [{ types: ['Ride'], ftp: 5000 }] }), none); equal(decodeAthleteSettings({ icu_weight: 'heavy', sportSettings: 'none' }), none);
  equal(decodeAthleteSettings({ icu_weight: true, sportSettings: [{ types: ['Ride'], ftp: true }] }), none);
  equal(decodeAthleteSettings({ sportSettings: [{ types: ['Ride'], ftp: 250, indoor_ftp: 9999 }] }).ftpWatts, 250); // a bad indoor value falls back to the outdoor one
  throws(() => decodeAthleteSettings([1])); throws(() => decodeAthleteSettings(null));
});
test('The first sync applies both values; local edits survive an unchanged remote; tolerance avoids churn', () => {
  const first = athleteChanges({ weightKG: 71.5, ftpWatts: 262 }, { lastSeenFTP: null, lastSeenWeight: null }, profile(200, 80));
  equal(first.changes, { ftp: 262, weight: 71.5 }); equal(first.state, { lastSeenFTP: 262, lastSeenWeight: 71.5 }); equal(syncNote(first.changes), 'FTP 262 W and weight 71.5 kg updated from Intervals.icu');
  const state = { lastSeenFTP: 262, lastSeenWeight: 71.5 };
  const kept = athleteChanges({ weightKG: 71.5, ftpWatts: 262 }, state, profile(255, 73)); assert(isEmpty(kept.changes)); equal(kept.state, state);
  const changed = athleteChanges({ weightKG: 71.5, ftpWatts: 270 }, state, profile(255, 73)); equal(changed.changes, { ftp: 270, weight: null }); equal(changed.state.lastSeenFTP, 270);
  assert(isEmpty(athleteChanges({ weightKG: 71.54, ftpWatts: 262.4 }, state, profile(255, 73)).changes));
  const same = athleteChanges({ weightKG: null, ftpWatts: 270 }, state, profile(270.2)); assert(isEmpty(same.changes)); equal(same.state.lastSeenFTP, 270); // remembered
  const none = athleteChanges({ weightKG: null, ftpWatts: null }, state, profile()); assert(isEmpty(none.changes)); equal(none.state, state);
  equal(syncNote({ ftp: null, weight: null }), null); equal(syncNote({ ftp: 251, weight: null }), 'FTP 251 W updated from Intervals.icu');
});
test('Applying a sync adds an FTP entry without touching history, and the hourly policy never runs during a ride', () => {
  const original = profile(200, 80), updated = applyChanges({ ftp: 262, weight: 71.5 }, original);
  equal([updated.ftpHistory.length, updated.ftpHistory[1], updated.ftpHistory[0].source, updated.ftpHistory[0].watts, updated.currentFTPID === updated.ftpHistory[0].id, updated.weightKG], [2, original.ftpHistory[0], 'Intervals.icu', 262, true, 71.5]);
  equal(original.ftpHistory.length, 1);
  const now = Date.parse('2026-11-05T12:00:00Z'), base = { now, connected: true, enabled: true, rideActive: false };
  assert(shouldRefreshAthlete({ ...base, lastSynced: null })); assert(!shouldRefreshAthlete({ ...base, lastSynced: '2026-11-05T11:30:00Z' })); assert(shouldRefreshAthlete({ ...base, lastSynced: '2026-11-05T10:59:00Z' }));
  assert(!shouldRefreshAthlete({ ...base, lastSynced: null, rideActive: true })); assert(!shouldRefreshAthlete({ ...base, lastSynced: null, connected: false })); assert(!shouldRefreshAthlete({ ...base, lastSynced: null, enabled: false })); assert(!shouldRefreshAthlete({ ...base, lastSynced: null, alreadyRunning: true }));
});
test('Syncing applies to the connected rider, is skipped during a ride and in a preview, and follows the toggle', async () => {
  const model = await makeModel({ riders: [rider({ ftp: 200, weightKG: 80 })] }), id = model.profile.id;
  await connectRider(model, KEY); equal([model.ftp, model.profile.weightKG, model.ftpEntry.source], [250, 71.5, 'Intervals.icu']); // indoor_ftp wins
  assert(model.profile.ftpHistory.length === 2);
  const calls = model.calls.length; await syncAthlete(model); equal(model.calls.length, calls + 1); equal(model.ftp, 250);
  // A local edit survives a remote that did not change; a changed remote applies again.
  await model.setCurrentFTP(240); await syncAthlete(model); equal(model.ftp, 240);
  model.intervals.fetcher = fakeIntervals({ [KEY]: athlete('i1', { sportSettings: [{ types: ['VirtualRide'], indoor_ftp: 262 }] }) }).fetcher; await syncAthlete(model); equal(model.ftp, 262);
  // Never during a ride, never in a preview, and not when the rider switched it off.
  Object.defineProperty(model.ride, 'busy', { get: () => true, configurable: true }); equal(await syncAthlete(model), null); delete model.ride.busy;
  model.preview = true; equal(await syncAthlete(model), null); model.preview = false;
  await setSyncEnabled(model, id, false); model.intervals.fetcher = fakeIntervals({ [KEY]: athlete('i1', { sportSettings: [{ types: ['VirtualRide'], indoor_ftp: 300 }] }) }).fetcher; equal(await syncAthlete(model), null); equal(model.ftp, 262);
});
test('Home refresh syncs at most hourly and only for a connected rider with sync on', async () => {
  const model = await makeModel(); await syncAthleteIfNeeded(model); equal(model.calls.length, 0); // not connected
  await connectRider(model, KEY); const after = model.calls.length; await syncAthleteIfNeeded(model); equal(model.calls.length, after); // just synced
  const settings = await model.store.riderSettings(model.profile.id); settings.sync.lastSynced = new Date(Date.now() - 2 * 3600000).toISOString(); await model.store.put('riderSettings', settings);
  await syncAthleteIfNeeded(model); equal(model.calls.length, after + 1); await syncAthleteIfNeeded(model); equal(model.calls.length, after + 1); // and not twice within the minute
});

// ----- one connection per rider -------------------------------------------------------------------------------------------------------------------------
test('Each rider has their own connection; one rider\'s ride can never be uploaded to another rider\'s account', async () => {
  const model = await makeModel({ riders: [rider(), rider({ id: SAM_ID, name: 'Sam', weightKG: null, ftp: 180 })] }), client = model.intervals;
  await connectRider(model, KEY); equal(model.connectionFor(ALEX_ID).id, 'i1'); equal(model.connectionFor(SAM_ID), null);
  await model.selectRider(SAM_ID); equal(model.connection, null); await connectRider(model, KEY_B); equal([model.connectionFor(SAM_ID).id, model.connectionFor(ALEX_ID).id], ['i2', 'i1']);
  assert(!JSON.stringify(model.connectionFor(ALEX_ID)).includes(KEY) && !('authorization' in model.connectionFor(ALEX_ID)));
  const alexRide = finishedRamp(rider(), { daysAgo: 1 }).session, samRide = finishedRamp(rider({ id: SAM_ID, name: 'Sam', ftp: 180 }), { daysAgo: 1 }).session;
  await model.store.put('sessions', alexRide); await model.store.put('sessions', samRide);
  await rejects(() => client.approve(alexRide, 'i2')); await rejects(() => client.approve(samRide, 'i1')); equal((await model.store.all('jobs')).length, 0);
  model.calls.length = 0; await client.approve(alexRide, 'i1');
  const post = model.calls.filter(c => c.options.method === 'POST'); equal(post.length, 1); assert(post[0].url.includes('/athlete/i1/activities')); equal(post[0].options.headers.Authorization, `Basic ${btoa(`API_KEY:${KEY}`)}`);
  // A job approved for Alex waits when only Sam is connected: Sam's account never receives it.
  await client.disconnect(ALEX_ID); equal(client.connectionFor(ALEX_ID), null);
  const job = { id: crypto.randomUUID(), sessionID: alexRide.id, riderID: ALEX_ID, accountID: 'i1', accountName: 'x', file: '<x/>', name: 'n', description: 'd', status: 'queued', attempts: 0, retryAt: 0, error: null };
  await model.store.put('jobs', job); model.calls.length = 0; await client.flush(true); equal(model.calls.filter(c => c.options.method === 'POST').length, 0);
  // An older job without a rider is attributed through its recording.
  delete job.riderID; await model.store.put('jobs', job); await client.flush(true); equal(model.calls.filter(c => c.options.method === 'POST').length, 0);
});
test('An Intervals.icu account cannot be connected to two riders, and the same rider can reconnect another account', async () => {
  const model = await makeModel({ riders: [rider(), rider({ id: SAM_ID, name: 'Sam', ftp: 180 })] });
  await connectRider(model, KEY); await model.selectRider(SAM_ID); await rejects(() => connectRider(model, KEY)); equal(model.connectionFor(SAM_ID), null);
  await model.selectRider(ALEX_ID); await connectRider(model, KEY_B); equal(model.connectionFor(ALEX_ID).id, 'i2');
});
test('Calendar and upload settings belong to the selected rider; the upload prompt follows the ride\'s own rider', async () => {
  const model = await makeModel({ riders: [rider(), rider({ id: SAM_ID, name: 'Sam', ftp: 180 })] }), session = finishedRamp(rider(), { daysAgo: 0 }).session;
  assert(!(await shouldPromptForUpload(model, session))); // no connection
  await connectRider(model, KEY); assert(await shouldPromptForUpload(model, session));
  await model.selectRider(SAM_ID); assert(await shouldPromptForUpload(model, session)); // Sam is selected but the ride is Alex's: Alex's connection counts
  const samRide = finishedRamp(rider({ id: SAM_ID, name: 'Sam', ftp: 180 }), { daysAgo: 0 }).session; assert(!(await shouldPromptForUpload(model, samRide)));
  await setAskToUpload(model, ALEX_ID, false); assert(!(await shouldPromptForUpload(model, session))); equal((await model.store.riderSettings(SAM_ID)).askToUpload, true);
  await setAskToUpload(model, ALEX_ID, true); await model.store.put('jobs', { id: 'j1', sessionID: session.id, riderID: ALEX_ID, accountID: 'i1', status: 'uploaded' }); await model.reload(); assert(!(await shouldPromptForUpload(model, session)));
  model.calls.length = 0; await model.downloadCalendar().catch(() => {}); equal(model.calls.length, 0); // Sam has no connection: no request at all
  await model.selectRider(ALEX_ID); model.preview = false; await model.downloadCalendar(); assert(model.calls.some(c => c.url.includes('/athlete/i1/events')));
});
test('A placeholder connection from a preview never sends a request', async () => {
  let calls = 0; const client = new IntervalsClient(new MemoryStore(), { fetcher: async () => { calls++; return json({}); }, selectedRider: () => ALEX_ID });
  client.connections.set(ALEX_ID, { id: 'preview', name: 'Preview', authorization: PREVIEW_AUTHORIZATION });
  await rejects(() => client.athleteSettings(ALEX_ID)); await rejects(() => client.workouts(ALEX_ID, 230, '2026-11-05', '2026-11-19')); equal(calls, 0);
});

// ----- credentials --------------------------------------------------------------------------------------------------------------------------------------
test('Without "Remember" no credential reaches IndexedDB, localStorage or a queued job', async () => {
  const store = await freshDatabase(), model = await makeModel({ store, riders: [rider()] }), before = JSON.stringify({ ...localStorage });
  const result = await connectRider(model, KEY, { remember: false }); equal([result.remembered, model.connectionFor(ALEX_ID).remembered], [false, false]);
  equal((await store.all('credentials')).length, 0); equal(leaks(await everything(store), KEY).length, 0); equal(JSON.stringify({ ...localStorage }), before); assert(!JSON.stringify({ ...localStorage }).includes(KEY));
  const session = finishedRamp(rider(), { daysAgo: 1 }).session; await store.put('sessions', session); await model.intervals.approve(session, 'i1');
  const jobs = await store.all('jobs'); equal(jobs.length, 1); equal(jobs[0].status, 'uploaded'); equal(leaks(await everything(store), KEY).length, 0); assert(!JSON.stringify(jobs).includes('Basic '));
  // A reload (a new client on the same database) is not connected: the key was in memory only.
  const reloaded = new IntervalsClient(store, { selectedRider: () => ALEX_ID }); equal(await reloaded.restoreAll(), []); equal(reloaded.connectionFor(ALEX_ID), null);
});
test('With "Remember" only ciphertext and a non-extractable CryptoKey are stored, and a reload reconnects', async () => {
  const store = await freshDatabase(), model = await makeModel({ store }), result = await connectRider(model, KEY, { remember: true });
  equal([result.remembered, model.connectionFor(ALEX_ID).remembered], [true, true]);
  const records = await store.all('credentials'); equal(records.length, 1); const record = records[0];
  equal(Object.keys(record).sort(), ['accountID', 'accountName', 'ciphertext', 'iv', 'key', 'riderID', 'savedAt']);
  assert(record.key instanceof CryptoKey && record.key.extractable === false && record.key.algorithm.name === 'AES-GCM'); await rejects(() => crypto.subtle.exportKey('raw', record.key));
  assert(record.ciphertext instanceof ArrayBuffer && record.ciphertext.byteLength > KEY.length && record.iv.length === 12);
  equal(leaks(await everything(store), KEY).length, 0); assert(!JSON.stringify({ ...localStorage }).includes(KEY));
  // A new client on the same database (a reload) reads it back and can call Intervals.icu with it.
  const fake = fakeIntervals(), reloaded = new IntervalsClient(store, { fetcher: fake.fetcher, selectedRider: () => ALEX_ID });
  equal(await reloaded.restoreAll(), []); equal(reloaded.connectionFor(ALEX_ID), { id: 'i1', name: 'Athlete i1', remembered: true });
  await reloaded.workouts(ALEX_ID, 230, '2026-11-05', '2026-11-19'); equal(fake.calls[0].options.headers.Authorization, `Basic ${btoa(`API_KEY:${KEY}`)}`);
  // The model restores at boot too.
  const booted = new AppModel({ store, devices: new BluetoothDevices({ bluetooth: null }), prefs: preferences(ALEX_ID), lease: async () => () => {} }); await booted.boot(); equal(booted.connectionFor(ALEX_ID).id, 'i1');
});
test('A damaged, moved or foreign record is deleted and the rider is asked to reconnect; disconnecting deletes the record', async () => {
  const store = await freshDatabase(), model = await makeModel({ store, riders: [rider(), rider({ id: SAM_ID, name: 'Sam', ftp: 180 })] });
  await connectRider(model, KEY, { remember: true }); const [record] = await store.all('credentials');
  const damaged = structuredClone(record); damaged.ciphertext = new Uint8Array(damaged.ciphertext).map((v, i) => i === 3 ? v ^ 1 : v).buffer; await store.put('credentials', damaged);
  let client = new IntervalsClient(store, { fetcher: fakeIntervals().fetcher }); equal(await client.restoreAll(), [ALEX_ID]); equal(client.connectionFor(ALEX_ID), null); equal((await store.all('credentials')).length, 0);
  // The same ciphertext filed under another rider or account does not decrypt (they are authenticated data).
  await store.put('credentials', { ...record, riderID: SAM_ID }); client = new IntervalsClient(store); equal(await client.restoreAll(), [SAM_ID]); equal((await store.all('credentials')).length, 0);
  await store.put('credentials', { ...record, accountID: 'i9' }); client = new IntervalsClient(store); equal(await client.restoreAll(), [ALEX_ID]);
  const notices = []; await store.put('credentials', { ...record, ciphertext: new ArrayBuffer(4) });
  const fresh = new AppModel({ store, devices: new BluetoothDevices({ bluetooth: null }), prefs: preferences(ALEX_ID), lease: async () => () => {} }); fresh.onNotice = m => notices.push(m); await fresh.boot();
  assert(notices.some(n => n.includes('Connect again')), 'asks to reconnect'); equal((await store.all('credentials')).length, 0); equal(fresh.connectionFor(ALEX_ID), null);
  // Disconnect deletes the record and the connection; the queue stays for a reconnect.
  const again = await makeModel({ store: await freshDatabase() }); await connectRider(again, KEY, { remember: true }); equal((await again.store.all('credentials')).length, 1);
  await disconnectRider(again); equal((await again.store.all('credentials')).length, 0); equal(again.connectionFor(ALEX_ID), null); equal((await again.store.riderSettings(ALEX_ID)).sync.linkedAccountID, null);
  // Connecting again without "Remember" removes an older remembered key.
  await connectRider(again, KEY, { remember: true }); await disconnectRider(again); await connectRider(again, KEY, { remember: true }); await connectRider(again, KEY, { remember: false }); equal((await again.store.all('credentials')).length, 0);
});
test('Sealing is AES-GCM with a fresh non-extractable key and IV each time', async () => {
  const a = await sealKey('r', 'i1', KEY), b = await sealKey('r', 'i1', KEY);
  assert(!same(new Uint8Array(a.ciphertext), new Uint8Array(b.ciphertext)) && !same(a.iv, b.iv) && a.key.extractable === false);
  equal(await openKey({ riderID: 'r', accountID: 'i1', ...a }), KEY); await rejects(() => openKey({ riderID: 'r', accountID: 'i2', ...a })); await rejects(() => openKey({ riderID: 'x', accountID: 'i1', ...a })); await rejects(() => openKey({}));
});
test('No credential reaches an archive, a rollback backup or a queued job; deleted riders lose their credential and queue', async () => {
  const store = await freshDatabase(), model = await makeModel({ store, riders: [rider(), rider({ id: SAM_ID, name: 'Sam', ftp: 180 })] });
  await connectRider(model, KEY, { remember: true }); const session = finishedRamp(rider(), { daysAgo: 1 }).session; await store.put('sessions', session); await model.intervals.approve(session, 'i1');
  const archive = await store.backup(); let text = archiveText(archive); equal(leaks(text, KEY).length, 0); assert(!/credential|authorization|Basic /i.test(text));
  await store.restore(archive); const backups = await store.all('backups'); equal(backups.length, 1); text = JSON.stringify(backups); equal(leaks(text, KEY).length, 0); assert(!/credential|authorization|Basic /i.test(text));
  equal(leaks(JSON.stringify(await store.all('jobs')), KEY).length, 0);
  // An import that replaces the riders (here: only Sam is left) removes Alex's credential, settings and queue with them.
  await store.delete('profiles', ALEX_ID); await model.reload(); await model.intervals.purgeOrphans(model.profiles);
  equal((await store.all('credentials')).length, 0); equal(model.connectionFor(ALEX_ID), null); equal((await store.all('jobs')).length, 0); equal((await store.all('riderSettings')).filter(s => s.riderID === ALEX_ID).length, 0);
});

// ----- screens (the real app in an iframe against the preview scenarios; nobody has looked at these on a screen) ----------------------------------------------
const frames = [];
async function open(query) {
  const frame = document.createElement('iframe'); frame.style.cssText = 'width:1100px;height:900px;border:0'; frame.src = `/index.html?${query}&nosw`; document.body.append(frame); frames.push(frame);
  const start = Date.now(); while (!frame.contentWindow?.__ftpunk?.ready) { if (Date.now() - start > 20000) throw Error(`The app did not start for ?${query}`); await new Promise(r => setTimeout(r, 25)); }
  const win = frame.contentWindow, doc = win.document, violations = []; doc.addEventListener('securitypolicyviolation', e => violations.push(`${e.violatedDirective} ${e.blockedURI}`));
  assert(!win.__ftpunk.error, `Boot failed: ${win.__ftpunk.error}`);
  return { win, doc, model: win.__ftpunk.model, violations, text: () => doc.querySelector('#main').textContent.replace(/\s+/g, ' '), q: s => doc.querySelector(s), qa: s => [...doc.querySelectorAll(s)], close: () => frame.remove(),
    wait: async (condition, label = 'condition') => { const t = Date.now(); while (!condition()) { if (Date.now() - t > 5000) throw Error(`Timed out waiting for ${label}`); await new Promise(r => setTimeout(r, 25)); } } };
}
const scenario = async (name, body) => { const a = await open(`scenario=${name}`); try { await body(a); assert(a.win.__ftpunk.errors.length === 0, `Script errors in ${name}: ${a.win.__ftpunk.errors.join('; ')}`); assert(a.violations.length === 0, `CSP violations in ${name}: ${a.violations.join('; ')}`); } finally { a.close(); } };

test('The page carries a Content-Security-Policy that allows only itself and Intervals.icu', async () => {
  const html = await (await fetch('/index.html')).text(), policy = html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)?.[1] ?? ''; assert(policy, 'CSP meta tag');
  for (const part of ["default-src 'self'", "connect-src 'self' https://intervals.icu", "img-src 'self' data: blob:", "style-src 'self'", "script-src 'self'", "object-src 'none'", "base-uri 'none'", "form-action 'none'"]) assert(policy.includes(part), part);
  assert(!/unsafe-inline|unsafe-eval|https?:\/\/(?!intervals\.icu)/.test(policy));
});
test('The four Intervals.icu and file scenarios exist', () => { for (const name of ['result-upload-prompt', 'settings-intervals-connected', 'settings-intervals-synced', 'progress-detail-export']) assert(scenarioNames().includes(name), name); });
test('Scenario result-upload-prompt asks by itself, names the rider and the account, and uploads nothing', async () => {
  await scenario('result-upload-prompt', async a => {
    let requests = 0; a.win.fetch = () => { requests++; return Promise.reject(Error('no network in tests')); };
    await a.wait(() => a.q('#dialog')?.open, 'the dialog');
    const dialog = a.q('#dialog').textContent.replace(/\s+/g, ' '); for (const s of ['Upload this activity?', 'Alex', 'Preview athlete', 'Account ID: preview', 'Upload activity', 'Keep local']) assert(dialog.includes(s), `dialog lacks "${s}"`);
    assert(a.text().includes('Estimated FTP') || a.text().includes('ESTIMATED FTP')); equal(a.model.jobs.length, 0);
    a.q('[data-dialog="local"]').click(); await a.wait(() => !a.q('#dialog').open); equal(requests, 0); equal(a.model.jobs.length, 0);
  });
});
test('Without a connection the result shows a quiet link instead of a dialog', async () => {
  await scenario('result', async a => { await new Promise(r => setTimeout(r, 150)); assert(!a.q('#dialog').open); const link = a.q('[data-testid="connect-to-upload"]'); assert(link && link.textContent.includes('Connect Intervals.icu to upload') && link.getAttribute('href') === '#/settings'); });
});
test('Scenarios settings-intervals-connected and -synced show this rider\'s connection, the toggles, the sync status and the remember note when disconnected', async () => {
  await scenario('settings-intervals-connected', async a => {
    const t = a.q('#settings-intervals').textContent.replace(/\s+/g, ' '); for (const s of ['Preview athlete', 'Account preview', 'connected for this tab', 'Ask to upload after each ride', 'Use FTP and weight from Intervals.icu', 'Last synced: Not yet', 'Sync now', 'Disconnect', 'This connection belongs to Alex']) assert(t.includes(s), `lacks "${s}"`);
    assert(a.q('#st-ask-upload').checked && a.q('#st-sync').checked && !a.q('#api-key'));
  });
  await scenario('settings-intervals-synced', async a => {
    const t = a.q('#settings-intervals').textContent.replace(/\s+/g, ' '); for (const s of ['remembered on this browser', 'FTP 230 W and weight 71.0 kg updated from Intervals.icu']) assert(t.includes(s), `lacks "${s}"`); assert(!t.includes('Last synced: Not yet'));
    // Turning the upload prompt off is saved per rider.
    const box = a.q('#st-ask-upload'); box.checked = false; box.dispatchEvent(new a.win.Event('change', { bubbles: true }));
    await a.wait(() => a.model.store.tables.riderSettings.get(ALEX_ID)?.askToUpload === false, 'the saved setting'); await a.wait(() => !a.q('#st-ask-upload').checked, 'the screen to follow');
  });
  await scenario('settings', async a => {
    const t = a.q('#settings-intervals').textContent.replace(/\s+/g, ' '); for (const s of ['Remember on this browser', 'encrypted in this browser', 'copying the browser’s files', 'a script running on this site', 'other GitHub Pages sites by the same author share this storage']) assert(t.includes(s), `lacks "${s}"`);
    assert(a.q('#api-remember') && !a.q('#api-remember').checked, 'Remember is off by default'); assert(a.q('#api-key').type === 'password');
  });
});
test('Scenario progress-detail-export offers FIT first with the COROS note, then TCX, CSV and JSON', async () => {
  await scenario('progress-detail-export', async a => {
    const buttons = a.qa('[data-slot="export"] [data-action^="export-"]').map(b => b.dataset.action); equal(buttons, ['export-fit', 'export-tcx', 'export-csv', 'export-json']);
    const t = a.q('[data-slot="export"]').textContent.replace(/\s+/g, ' '); assert(t.includes('For COROS, Garmin, Strava and TrainingPeaks') && t.includes('Upload this file in their web app'));
    const session = a.model.history[0]; for (const format of ['fit', 'tcx', 'csv', 'json']) assert(exportFile(session, format).bytes.length > 100);
    assert(a.q('[data-action="request-upload"]'), 'the manual upload button');
  });
});
