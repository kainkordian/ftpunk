import { importWorkout } from '../src/workouts.mjs';
import { resistanceRide, trainingTarget } from '../src/training.mjs';
import { ResistanceRange, supportsResistance } from '../src/protocol.mjs';
import { freeRide, validatePlan, creditSession, progressMilliseconds } from '../src/training.mjs';
import { makeArchive, archiveText, parseArchive, archiveSessions, validateArchive } from '../src/archive.mjs';
import { configuration, PRESETS, rampPower, analyze, RampEngine, mockSample } from '../src/domain.mjs';
import { indoorBike, cyclingPower, heartRate, PowerRange, supportsTargetPower, command, controlResponse, BikeAssembler, CadenceTracker, Measurements, route } from '../src/protocol.mjs';
import { ControlPoint, BluetoothDevices } from '../src/bluetooth.mjs';
import { LocalStore, acquireRideLease, loadPreferences, savePreferences } from '../src/storage.mjs';
import { RideController } from '../src/controller.mjs';
import { csv, tcx } from '../src/export.mjs';
import { IntervalsClient } from '../src/intervals.mjs';

import { test, assert, equal, near, throws, rejects, fixtureText } from './harness.mjs';
const view = bytes => new DataView(Uint8Array.from(bytes).buffer);
const range = () => new PowerRange(0, 1000, 1);
const config = input => configuration({ warmupSeconds: 0, ...input });
function recorded(c = config()) { const e = new RampEngine(c); for (let t = 0; t <= 70; t++) { e.receive({ time: t, power: 300, cadence: 90 }); e.tick(t); } e.finishRamp(70); e.end(71); return e.session; }
class MemoryStore {
  constructor() { this.tables = { sessions: new Map(), profiles: new Map(), jobs: new Map() }; }
  async put(table, value) { this.tables[table].set(value.id, structuredClone(value)); }
  async all(table) { return structuredClone([...this.tables[table].values()]); }
  async delete(table, id) { this.tables[table].delete(id); }
}
function fakeDevices() { return { measurements: new Measurements(), trainerReady: true, range: range(), snapshots: [], commands: [], async start(w) { this.commands.push(['start', w]); }, async setTarget(w) { this.commands.push(['target', w]); }, async stop() { this.commands.push(['stop']); } }; }
const drain = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };

const featureFixture = fixtureText;
test('Shared workout imports expand repeats, preserve resolved watts and interpolate ramps', async () => {
  const plan = importWorkout(await featureFixture('workout-ramps'));
  equal(plan.version, 2); equal(plan.steps.length, 6);
  equal([0, 5, 10, 35, 40].map(t => trainingTarget(plan, t)), [100, 150, 180, 75, null]);
  const resolved = importWorkout(await featureFixture('workout-intervals'), 300);
  equal(resolved.steps.length, 5); equal(resolved.steps[0].endWatts, 200); equal(resolved.steps[1].watts, 180);
});
test('Imports reject oversized expansions, invalid targets and unsupported workout modes', () => {
  const input = steps => JSON.stringify({ format: 'ftpunk-workout', version: 1, steps });
  for (const steps of [
    [{ repeat: 101, steps: [{ seconds: 1, watts: 100 }] }],
    [{ repeat: 100, steps: [{ repeat: 100, steps: [{ seconds: 1, watts: 100 }] }] }],
    [{ seconds: 1, watts: true }], [{ seconds: 1, watts: 100, endWatts: null }],
    [{ seconds: 1, watts: 100, until_lap_press: true }], [{ seconds: 86401, watts: 100 }],
  ]) throws(() => importWorkout(input(steps)));
  throws(() => importWorkout(JSON.stringify({ format: 'ftpunk-workout', version: 1, ftpWatts: '200', steps: [{ seconds: 1, watts: 100 }] })));
  throws(() => importWorkout(JSON.stringify({ type: 'Ride', category: 'WORKOUT', workout_doc: { steps: [{ duration: 10, power: { units: '%hr', value: 80 } }] } })));
});
test('Intensity is based on immutable targets and respects paused ramp time and all endpoints', async () => {
  const plan = importWorkout(await featureFixture('workout-ramps'));
  const e = new RampEngine(config(), { training: plan });
  for (let time = 0; time <= 5; time++) { e.receive({ time, power: 100, cadence: 90 }); e.tick(time); }
  assert(e.setIntensity(105, 5)); equal(e.target, 158);
  assert(e.setIntensity(110, 5)); equal(e.target, 165);
  assert(e.pause(5)); assert(e.setIntensity(95, 5)); equal(e.target, null); equal(e.resumeTarget, 143);
  assert(!e.setIntensity(150, 5, 1, 250)); assert(!e.setIntensity(45, 5)); equal(e.intensity, 95);
  e.receive({ time: 100, power: 100, cadence: 90 }); e.tick(100); assert(e.resume(100));
  equal(e.target, 143); equal(e.trainingElapsed, 5); equal(e.session.training, plan);
});
test('Resistance feature, exact range layout and signed command encoding are verified', () => {
  assert(supportsResistance(view([0,0,0,0,4,0,0,0]))); assert(!supportsTargetPower(view([0,0,0,0,4,0,0,0])));
  const r = ResistanceRange.decode(view([0,0,232,3,10,0])); equal(r.maximum, 1000); equal(r.quantized(107), 110);
  equal(Array.from(command(4, 105)), [4,105,0]); throws(() => command(4, -1));
  throws(() => ResistanceRange.decode(view([0,100,1]))); throws(() => ResistanceRange.decode(view([0,0,100,0,0,0])));
  equal(new ResistanceRange(0, 103, 10).quantized(103), 100);
});
test('Resistance controller starts, adjusts, pauses and resumes without sending ERG or matching commands', async () => {
  let now = 0; const d = fakeDevices(); d.range = null; d.resistanceRange = new ResistanceRange(0, 1000, 10);
  d.startResistance = async level => d.commands.push(['resistance-start', level]);
  d.setResistance = async level => d.commands.push(['resistance', level]);
  d.measurements.receive({ role: 'trainer', time: 0, power: 100 });
  const c = new RideController(d, new MemoryStore(), { now: () => now, lease: async () => () => {} });
  await c.start(config({ powerMatchingEnabled: true }), { training: resistanceRide(100) }); clearInterval(c.timer);
  equal(c.engine.session.configuration.powerMatchingEnabled, false); equal(d.commands, [['resistance-start', 100]]);
  d.onReading({ role: 'trainer', time: now, power: 100, cadence: 90 }); c.tick();
  c.adjustERG(10); equal(c.engine.target, null);
  c.adjustResistance(1); c.tick(); await drain(); equal(d.commands.at(-1), ['resistance', 110]);
  c.pauseTraining(); await drain(); equal(c.engine.phase, 'paused'); equal(d.commands.at(-1), ['stop']);
  c.adjustResistance(1); now = 20; d.onReading({ role: 'trainer', time: now, power: 100, cadence: 90 }); c.tick();
  c.resumeTraining(); await drain(); equal(c.engine.phase, 'riding'); equal(d.commands.at(-1), ['resistance-start', 120]);
  c.stop(); await drain(); equal(d.commands.at(-1), ['stop']); assert(!c.busy);
  assert(d.commands.every(([kind]) => kind !== 'start' && kind !== 'target'));
});
test('Unsupported resistance cannot start and Stop wins an outstanding resistance restart', async () => {
  const d = fakeDevices(); let now = 0; d.measurements.receive({ role: 'trainer', time: 0, power: 100 });
  const c = new RideController(d, new MemoryStore(), { now: () => now, lease: async () => () => {} });
  await c.start(config(), { training: resistanceRide(100) }); assert(!c.busy); equal(d.commands, []);
  d.resistanceRange = new ResistanceRange(0, 1000, 10); d.startResistance = async n => d.commands.push(['resistance-start', n]);
  await c.start(config(), { training: resistanceRide(100) }); clearInterval(c.timer);
  d.onReading({ role: 'trainer', time: now, power: 100, cadence: 90 }); c.tick(); c.pauseTraining(); await drain();
  let finish; d.startResistance = () => new Promise(resolve => { finish = resolve; });
  now = 10; d.onReading({ role: 'trainer', time: now, power: 100, cadence: 90 }); c.tick(); c.resumeTraining(); await drain();
  c.stop(); assert(c.busy); finish(); await drain(); assert(!c.busy); equal(c.engine.phase, 'completed'); equal(d.commands.at(-1), ['stop']);
});
test('Intervals download resolves targets, skips unsupported entries and rejects a changed account', async () => {
  const event = JSON.parse(await featureFixture('workout-intervals')); let requested;
  const client = new IntervalsClient(new MemoryStore(), { fetcher: async (url, options) => { requested = { url, options }; return { ok: true, text: async () => JSON.stringify([event, { id: 456, name: 'Unsupported', type: 'Run' }, null]) }; } });
  client.connection = { id: '123', authorization: 'Bearer test-token' };
  const result = await client.workouts('00000000-0000-0000-0000-000000000001', 300, '2026-10-31', '2026-11-14');
  equal(result.workouts.length, 1); equal(result.skipped.length, 2); equal(result.workouts[0].plan.steps[1].watts, 180);
  const url = new URL(requested.url); equal(url.searchParams.get('resolve'), 'true'); equal(url.searchParams.get('category'), 'WORKOUT');
  equal(requested.options.headers.Authorization, 'Bearer test-token'); assert(!JSON.stringify(result).includes('test-token'));
  client.fetcher = async () => { client.disconnect(); return { ok: true, text: async () => '[]' }; };
  await rejects(() => client.workouts(crypto.randomUUID(), 200, '2026-10-31', '2026-11-14'));
});
test('Portable v3 carries libraries, ramps, resistance and receipts and rejects downgrade', async () => {
  const rider = { id: '00000000-0000-0000-0000-000000000001', name: 'Rider', ftpHistory: [], currentFTPID: null };
  const e = new RampEngine(config({ riderID: rider.id }), { training: resistanceRide(100) });
  e.receive({ time: 0, power: 100, cadence: 90 }); e.tick(0); e.end(1);
  const workout = { id: 'download:123', riderID: rider.id, source: 'Fixture', savedAt: new Date().toISOString(), plan: importWorkout(await featureFixture('workout-ramps')) };
  const archive = parseArchive(archiveText(makeArchive([rider], [e.session], undefined, [workout])));
  equal(archive.version, 3); equal(archive.workouts[0], workout); equal(archiveSessions(archive)[0].training.resistance, 100);
  throws(() => validateArchive({ ...archive, version: 2 }));
  const bad = structuredClone(archive); bad.workouts[0].riderID = crypto.randomUUID(); throws(() => validateArchive(bad));
});

const shortPlan = () => validatePlan({ version: 1, kind: 'workout', name: 'Boundary check', ftpWatts: 200, steps: [{ name: 'Warm-up', seconds: 3, watts: 100 }, { name: 'Effort', seconds: 2, watts: 150 }, { name: 'Cooldown', seconds: 1, watts: 50 }] });
test('Workout waits for movement, follows boundaries and completes without estimating FTP', () => {
  const e = new RampEngine(config(), { training: shortPlan() }); e.tick(10); equal(e.phase, 'waiting');
  for (let t = 10; t <= 16; t++) {
    e.receive({ time: t, power: 100, cadence: 90 }); e.tick(t);
    equal(e.target, t < 13 ? 100 : t < 15 ? 150 : t === 15 ? 50 : null);
  }
  equal(e.session.outcome, 'completed'); equal(e.session.result, null); assert(!('eligibleMilliseconds' in e.session) && !('adventureEnabled' in e.session));
});
test('Free ERG changes persist until changed, and cannot restart an ended ride', () => {
  const e = new RampEngine(config(), { training: freeRide(100) });
  e.adjustERG(110, 0); e.receive({ time: 0, power: 100, cadence: 90 }); e.tick(0); equal(e.target, 110);
  e.adjustERG(120, .5); e.adjustERG(-10, .5); equal(e.target, 120); e.end(1); e.adjustERG(400, 2); equal(e.target, null);
  assert(e.session.events.some(v => v.message === 'ERG target changed to 120 W')); equal(e.session.result, null);
});
test('Workout signal loss and clock suspension stop targets', () => {
  for (const time of [2.01, 10]) {
    const e = new RampEngine(config(), { training: shortPlan() });
    e.receive({ time: 0, power: 100, cadence: 90 }); e.tick(0); e.tick(time);
    equal(e.phase, 'interrupted'); equal(e.target, null);
  }
});
test('A legacy progress ledger credits idempotently, ignores mock rides and new recordings add nothing', () => {
  const legacy = (ms, extra = {}) => ({ id: crypto.randomUUID(), isDemo: false, adventureEnabled: true, eligibleMilliseconds: ms, ...extra });
  const first = legacy(2000);
  let p = creditSession(null, first); p = creditSession(p, first); equal(progressMilliseconds(p), 2000);
  p = creditSession(p, legacy(4000)); equal(progressMilliseconds(p), 6000);
  p = creditSession(p, legacy(1200000, { isDemo: true })); equal(progressMilliseconds(p), 6000);
  p = creditSession(p, { id: crypto.randomUUID(), isDemo: false }); equal(progressMilliseconds(p), 6000);
  const e = new RampEngine(config(), { training: freeRide(10) });
  for (let t = 0; t <= 6; t++) { e.receive({ time: t, power: 100, cadence: 90 }); e.tick(t); }
  equal(progressMilliseconds(creditSession(null, e.session)), 0);
});
test('Offline plans reject invalid duration or power', () => {
  throws(() => freeRide(0));
  const bad = shortPlan(); bad.steps[0].seconds = -1; throws(() => validatePlan(bad));
});
test('Controller uses workout targets, adjusts free ERG, and releases when finished', async () => {
  const devices = fakeDevices(); devices.measurements.receive({ role: 'trainer', time: 0, power: 100 });
  let now = 0; const store = new MemoryStore(), ride = new RideController(devices, store, { now: () => now, lease: async () => () => {} });
  await ride.start(config(), { training: freeRide(150) }); clearInterval(ride.timer);
  equal(devices.commands[0], ['start', 150]);
  devices.onReading({ role: 'trainer', time: 0, power: 150, cadence: 90 }); ride.tick();
  ride.adjustERG(10); now = .5; devices.onReading({ role: 'trainer', time: now, power: 150, cadence: 90 }); ride.tick(); await drain();
  equal(devices.commands.at(-1), ['target', 160]);
  ride.stop(); await drain(); equal(devices.commands.at(-1), ['stop']); assert(!ride.busy);
  const saved = (await store.all('sessions'))[0]; equal(saved.training.kind, 'freeRide'); equal(saved.result, null);
});
test('Portable v2 round-trips training and the legacy ledger and rejects invalid or downgraded data', () => {
  const p = { id: crypto.randomUUID(), name: 'Rider', ftpHistory: [], currentFTPID: null };
  const e = new RampEngine(config({ riderID: p.id }), { training: shortPlan() });
  for (let t = 0; t <= 6; t++) { e.receive({ time: t, power: 100, cadence: 90 }); e.tick(t); }
  // A recording from before the story was removed carries its three legacy fields; the archive must keep them unchanged.
  Object.assign(e.session, { adventureEnabled: true, eligibleMilliseconds: 6000 });
  p.cycleProgress = creditSession(null, e.session);
  const archive = parseArchive(archiveText(makeArchive([p], [e.session])));
  equal(archive.version, 2); equal(archive.activities[0].kind, 'workout'); equal(archiveSessions(archive)[0].training, shortPlan());
  equal(progressMilliseconds(archive.profiles[0].cycleProgress), 6000); equal(archive.activities[0].session.eligibleMilliseconds, 6000); equal(archive.activities[0].session.adventureEnabled, true);
  throws(() => validateArchive({ ...archive, version: 1 }));
  const bad = structuredClone(archive); bad.activities[0].session.training.steps[0].watts = 0; throws(() => validateArchive(bad));
});

test('Both apps read the same v2 workout and legacy ledger unchanged', async () => {
  const url = new URL('./fixtures/portable-v2.json', import.meta.url);
  const text = await (await fetch(url)).text();
  const archive = parseArchive(text), again = parseArchive(archiveText(archive));
  equal(archive.activities[0].session.training, shortPlan()); equal(archive.activities[0].session.result, null);
  equal(again.profiles[0].cycleProgress, archive.profiles[0].cycleProgress); equal(progressMilliseconds(again.profiles[0].cycleProgress), 201 * 6000);
  equal(again.activities.map(a => [a.session.adventureEnabled, a.session.eligibleMilliseconds]), archive.activities.map(a => [a.session.adventureEnabled, a.session.eligibleMilliseconds]));
});
test('Workout preparation rounds trainer increments but refuses targets outside capability', async () => {
  const d = fakeDevices(); d.range = new PowerRange(0, 1000, 5); d.measurements.receive({ role: 'trainer', time: 0, power: 100 });
  const c = new RideController(d, new MemoryStore(), { now: () => 0, lease: async () => () => {} });
  await c.start(config(), { training: freeRide(113) }); clearInterval(c.timer);
  equal(d.commands[0], ['start', 115]); equal(c.engine.session.training.steps[0].watts, 113);
  c.stop(); await drain(); const count = d.commands.length;
  await c.start(config(), { training: freeRide(1001) });
  equal(d.commands.length, count); assert(!c.busy);
});

test('Pause freezes workout time while measurements continue, then resumes exact boundaries', () => {
  const e = new RampEngine(config(), { training: shortPlan() });
  for (let time = 0; time <= 2; time++) { e.receive({ time, power: 100, cadence: 90 }); e.tick(time); }
  assert(e.pause(2)); e.tick(100); equal(e.phase, 'paused'); equal(e.trainingElapsed, 2); equal(e.currentStep.remaining, 1);
  assert(!e.resume(100)); e.receive({ time: 100, power: 100, cadence: 90 });
  assert(e.resume(100)); equal(e.target, 100);
  for (let time = 101; time <= 104; time++) { e.receive({ time, power: 100, cadence: 90 }); e.tick(time); if (time === 101) equal(e.target, 150); }
  equal(e.phase, 'completed'); equal(e.trainingElapsed, 6); equal(e.session.endedAtOffset, 104);
});
test('Zero power cannot resume a paused workout', () => {
  const e = new RampEngine(config(), { training: freeRide(100) });
  e.receive({ time: 0, power: 100, cadence: 90 }); e.tick(0); assert(e.pause(.5));
  e.receive({ time: 1, power: 100, cadence: 90 }); assert(e.resume(1.5));
  e.receive({ time: 2, power: 100, cadence: 90 }); e.tick(2);
  assert(e.pause(2)); e.receive({ time: 3, power: 0, cadence: 0 }); assert(!e.resume(3)); equal(e.target, null);
});
test('Waiting pauses and repeated pauses preserve remaining time; FTP tests never pause', () => {
  const e = new RampEngine(config(), { training: shortPlan() }); assert(e.pause(10)); e.tick(20);
  e.receive({ time: 20, power: 100, cadence: 90 }); assert(e.resume(20)); equal(e.phase, 'waiting'); equal(e.trainingElapsed, 0); e.tick(20);
  for (let time = 21; time <= 22; time++) { e.receive({ time, power: 100, cadence: 90 }); e.tick(time); }
  assert(e.pause(22)); e.receive({ time: 24, power: 100, cadence: 90 }); assert(e.resume(24));
  assert(e.pause(24.5)); e.receive({ time: 30, power: 100, cadence: 90 }); assert(e.resume(30)); equal(e.trainingElapsed, 2.5);
  e.receive({ time: 30.5, power: 100, cadence: 90 }); e.tick(30.5); equal(e.target, 150);
  const ramp = new RampEngine(config()); assert(!ramp.pause(0));
});
test('Pause cancels queued targets, waits for release, and resets matching on resume', async () => {
  const d = fakeDevices(); d.measurements.receive({ role: 'trainer', time: 0, power: 100 });
  let now = 0; const c = new RideController(d, new MemoryStore(), { now: () => now, lease: async () => () => {} });
  await c.start(config(), { training: freeRide(100) }); clearInterval(c.timer);
  d.onReading({ role: 'trainer', time: 0, power: 100, cadence: 90 }); c.tick();
  c.adjustERG(10); c.tick(); c.pauseTraining(); await c.trainingCommand; await drain();
  equal(d.commands, [['start', 100], ['stop']]); equal(c.engine.phase, 'paused'); assert(c.busy);
  c.adjustERG(20); equal(c.engine.resumeTarget, 130); equal(c.engine.target, null);
  now = 10; c.tick(); let error; c.onError = e => { error = e; }; c.resumeTraining(); assert(error); equal(d.commands.length, 2);
  d.onReading({ role: 'trainer', time: 10, power: 100, cadence: 90 }); c.matcher.correction = 20; c.resumeTraining();
  await c.trainingCommand; equal(d.commands.at(-1), ['start', 130]); equal(c.engine.phase, 'riding'); equal(c.matcher.correction, 0);
  c.stop(); await drain(); equal(d.commands.at(-1), ['stop']); assert(!c.busy);
});
test('Pause waits for an in-flight target before releasing and blocks premature resume', async () => {
  const d = fakeDevices(); d.measurements.receive({ role: 'trainer', time: 0, power: 100 });
  const c = new RideController(d, new MemoryStore(), { now: () => 0, lease: async () => () => {} });
  await c.start(config(), { training: freeRide(100) }); clearInterval(c.timer);
  d.onReading({ role: 'trainer', time: 0, power: 100, cadence: 90 }); c.tick();
  let acknowledge; d.setTarget = w => { d.commands.push(['target', w]); return new Promise(resolve => { acknowledge = resolve; }); };
  c.adjustERG(10); c.tick(); await drain(); c.pauseTraining(); c.resumeTraining(); await drain();
  equal(d.commands.at(-1), ['target', 110]); equal(c.trainingTransition, 'pausing');
  acknowledge(); await c.trainingCommand; equal(d.commands.at(-1), ['stop']); equal(c.engine.phase, 'paused');
  c.stop(); await drain(); assert(!c.busy);
});
test('Stop during a pending restart wins and releases the trainer after the late acknowledgement', async () => {
  const d = fakeDevices(); d.measurements.receive({ role: 'trainer', time: 0, power: 100 });
  let now = 0; const c = new RideController(d, new MemoryStore(), { now: () => now, lease: async () => () => {} });
  await c.start(config(), { training: freeRide(100) }); clearInterval(c.timer);
  d.onReading({ role: 'trainer', time: 0, power: 100, cadence: 90 }); c.tick(); c.pauseTraining(); await c.trainingCommand;
  let acknowledge; d.start = w => { d.commands.push(['start', w]); return new Promise(resolve => { acknowledge = resolve; }); };
  c.resumeTraining(); await drain(); c.stop(); assert(c.finishing);
  await c.start(config(), { demo: true }); assert(c.finishing); acknowledge(); await drain();
  equal(c.engine.phase, 'completed'); equal(d.commands.at(-1), ['stop']); assert(!c.busy);
});
test('Power lost during restart and failed pause release both interrupt and attempt final Stop', async () => {
  for (const failure of ['stale', 'release']) {
    const d = fakeDevices(); d.measurements.receive({ role: 'trainer', time: 0, power: 100 });
    let now = 0; const c = new RideController(d, new MemoryStore(), { now: () => now, lease: async () => () => {} });
    await c.start(config(), { training: freeRide(100) }); clearInterval(c.timer);
    d.onReading({ role: 'trainer', time: 0, power: 100, cadence: 90 }); c.tick();
    if (failure === 'release') { let attempt = 0; d.stop = async () => { d.commands.push(['stop']); if (!attempt++) throw Error('Release rejected'); }; }
    c.pauseTraining(); await c.trainingCommand; await drain();
    if (failure === 'stale') { d.start = async w => { d.commands.push(['start', w]); now = 5; }; c.resumeTraining(); await c.trainingCommand; await drain(); }
    equal(c.engine.phase, 'interrupted'); equal(d.commands.at(-1), ['stop']); assert(!c.busy);
  }
});

test('Configuration snapshots input, validates values, and derives warm-up', () => {
  const input = { priorFTP: 250 }; const c = configuration(input); input.priorFTP = 300;
  equal(c.warmupPower, 125); equal(c.priorFTP, 250); equal(configuration({ preset: 'gentle' }).warmupPower, 75);
  for (const bad of [{ weightKG: 0 }, { priorFTP: Infinity }, { manualWarmupPower: 0 }, { ftpFactor: 0.8 }, { riderName: ' ' }, { warmupSeconds: NaN }, { cooldownSeconds: -1 }, { powerSource: 'unknown' }]) throws(() => configuration(bad));
  assert(configuration({ powerMatchingEnabled: true }).powerMatchingEnabled === false);
  assert(configuration({ powerSource: 'externalPowerMeter' }).powerMatchingEnabled === true);
});
test('All three protocols keep exact step boundaries', () => {
  equal(rampPower(config(), 11.99), 100); equal(rampPower(config(), 12), 105);
  equal(rampPower(config({ preset: 'gentle' }), 20), 55);
  equal(rampPower(config({ preset: 'zwift' }), 59.99), 100); equal(rampPower(config({ preset: 'zwift' }), 60), 120);
});
test('Best minute is time weighted, including zeros and irregular intervals', () => {
  const samples = Array.from({ length: 151 }, (_, i) => ({ time: i * 0.8, watts: i * 0.8 < 60 ? 200 : 300 }));
  const result = analyze(samples, 0, 120, 0.8, 75); near(result.bestMinutePower, 300); near(result.wattsPerKG, 3.2);
  equal(analyze(Array.from({ length: 60 }, (_, i) => ({ time: i, watts: i < 30 ? 0 : 200 })), 0, 60).bestMinutePower, 100);
});
test('Scoring rejects gaps, partial minutes, and invalid time ordering', () => {
  const samples = Array.from({ length: 60 }, (_, i) => ({ time: i, watts: 300 })).filter(s => s.time !== 30 && s.time !== 31);
  throws(() => analyze(samples, 0, 60)); throws(() => analyze([{ time: 0, watts: 300 }], 0, 59));
  throws(() => analyze([{ time: 1, watts: 200 }, { time: 0, watts: 300 }], 0, 60));
});
test('Automatic exhaustion excludes the five-second confirmation period', () => {
  const e = new RampEngine(config());
  for (let t = 0; t <= 75; t++) { e.receive({ time: t, power: t >= 70 ? 1000 : 300, cadence: t >= 70 ? 30 : 90 }); e.tick(t); }
  equal(e.phase, 'cooldown'); equal(e.session.rampEnd, 70); equal(e.session.result.bestMinutePower, 300); assert(e.freewheel); equal(e.target, null);
  e.end(76); equal(e.phase, 'completed');
});
test('Late ticks and stale selected power interrupt without an estimate', () => {
  const e = new RampEngine(config()); e.receive({ time: 0, power: 200, cadence: 90 }); e.tick(0); e.tick(10); equal(e.phase, 'interrupted'); equal(e.session.result, null);
  const stale = new RampEngine(config()); stale.receive({ time: 0, power: 200, cadence: 90 }); stale.tick(0); stale.tick(1); stale.tick(2); stale.receive({ time: 3, cadence: 0 }); stale.tick(3); equal(stale.session.outcome, 'interrupted');
});
test('Cadence is optional but its absence never implies exhaustion', () => {
  const e = new RampEngine(config({ cadenceSource: 'unavailable' }));
  for (let t = 0; t <= 75; t++) { e.receive({ time: t, power: t >= 70 ? 0 : 300 }); e.tick(t); }
  equal(e.phase, 'ramp'); e.finishRamp(75); assert(e.session.result); equal(e.session.outcome, 'finishedEarly');
});
test('Low cadence must remain low for five fresh seconds', () => {
  const e = new RampEngine(config());
  for (let t = 0; t <= 75; t++) { e.receive({ time: t, power: 300, cadence: t >= 70 && t < 74 ? 30 : 90 }); e.tick(t); }
  equal(e.phase, 'ramp');
});
test('Live best minute waits for full ramp coverage and retains an earlier maximum', () => {
  const e = new RampEngine(configuration({ warmupSeconds: 10 }));
  for (let t = 0; t <= 180; t += 0.5) { e.receive({ time: t, power: t < 10 ? 900 : t < 120 ? 300 : 150, cadence: 90 }); e.tick(t); if (t < 70) equal(e.liveBest, null); }
  equal(e.liveBest, 300); e.finishRamp(180); equal(e.session.result.bestMinutePower, 300);
});
test('Ramp limits stop the test without an FTP estimate', () => {
  const e = new RampEngine(config({ maximumPower: 105 }));
  for (let t = 0; t <= 25; t++) { e.receive({ time: t, power: 100, cadence: 90 }); e.tick(t); }
  equal(e.session.outcome, 'limitReached'); equal(e.session.result, null);
});
test('Completed scored ramp survives cooldown signal loss', () => {
  const e = new RampEngine(config()); for (let t = 0; t <= 70; t++) { e.receive({ time: t, power: 300, cadence: 90 }); e.tick(t); }
  e.finishRamp(70); e.tick(71); e.tick(72); e.tick(73); equal(e.phase, 'interrupted'); equal(e.session.outcome, 'finishedEarly'); assert(e.session.result);
});
test('Duplicate power timestamps do not invalidate a recording', () => {
  const e = new RampEngine(config());
  for (let t = 0; t <= 70; t++) { e.receive({ time: t, power: 300, cadence: 90 }); e.receive({ time: t, power: 900 }); e.tick(t); }
  e.finishRamp(70); equal(e.session.result.bestMinutePower, 300);
});
test('Trainer packets cannot contaminate external meter scoring', () => {
  const c = config({ powerSource: 'externalPowerMeter', cadenceSource: 'trainer' }), e = new RampEngine(c);
  for (let t = 0; t <= 70; t++) { e.receive(route({ role: 'trainer', time: t, power: 500, cadence: 90 }, c, 0)); e.receive(route({ role: 'externalPowerMeter', time: t + 0.1, power: 300 }, c, 0)); e.tick(t + 0.1); }
  e.finishRamp(70.1); equal(e.session.result.bestMinutePower, 300); equal(e.session.samples[0].trainerPower, 500); equal(e.session.samples[0].power, undefined);
});
test('Trainer notifications do not hide a selected meter dropout', () => {
  const c = config({ powerSource: 'externalPowerMeter', cadenceSource: 'trainer' }), e = new RampEngine(c);
  for (let t = 0; t <= 75 && e.active; t++) { e.receive(route({ role: 'trainer', time: t, power: 500, cadence: 90 }, c, 0)); if (t <= 70) e.receive(route({ role: 'externalPowerMeter', time: t, power: 300 }, c, 0)); e.tick(t); }
  equal(e.phase, 'interrupted'); equal(e.session.result, null);
});
test('Measurements track power and cadence freshness independently', () => {
  const m = new Measurements(); m.receive({ role: 'externalPowerMeter', time: 10, power: 200, cadence: 90 }); m.receive({ role: 'externalPowerMeter', time: 13, cadence: 80 });
  equal(m.fresh('externalPowerMeter', 'power', 13), null); equal(m.cadenceSource('externalPowerMeter', 13), 'externalPowerMeter'); m.reset('externalPowerMeter'); equal(m.cadenceSource('externalPowerMeter', 13), 'unavailable');
});
test('Indoor bike flags, signed watts, and truncated packets match Swift fixtures', () => {
  const full = [0x44, 0, 0xc4, 9, 0xb4, 0, 0xc8, 0]; const r = indoorBike(full); equal(r.power, 200); equal(r.cadence, 90); equal(r.speed, 25);
  equal(indoorBike([0x40, 0, 0, 0, 0xf6, 0xff]).power, -10); equal(indoorBike([0x41, 0, 0xc8, 0]).power, 200);
  for (let n = 0; n < full.length; n++) throws(() => indoorBike(full.slice(0, n)));
});
test('Indoor bike DataView byte offsets and optional fields decode correctly', () => {
  const bytes = Uint8Array.from([0xaa, 0xaa, 0x60, 0, 0, 0, 5, 0xc8, 0]); equal(indoorBike(new DataView(bytes.buffer, 2)).power, 200);
  equal(indoorBike([0x7e, 0, 0xc4, 9, 0, 0, 0xb4, 0, 0, 0, 1, 2, 3, 5, 0xc8, 0]).power, 200);
  const legacy = [0x60, 0, 0, 0, 5, 0, 0xc8, 0]; throws(() => indoorBike(legacy)); equal(indoorBike(legacy, true).power, 200);
});
test('Multi-notification trainer records assemble and expire', () => {
  const a = new BikeAssembler(), first = indoorBike([0x41, 0, 0xc8, 0]), last = indoorBike([4, 0, 0xc4, 9, 0xb4, 0]);
  equal(a.receive(first, 0), null); const r = a.receive(last, 0.1); equal(r.power, 200); equal(r.cadence, 90);
  a.receive(first, 1); equal(a.receive(last, 4).power, undefined);
});
test('Cycling power optional fields and crank rollover match Swift fixtures', () => {
  const p = cyclingPower([0x37, 0, 0xc8, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 0, 0xfc]); equal(p.power, 200); equal(p.leftBalance, 50);
  const tracker = new CadenceTracker(); equal(tracker.receive(p.crank, 0), null); equal(tracker.receive({ revolutions: 0, ticks: 0 }, 1), 60); equal(tracker.receive({ revolutions: 0, ticks: 0 }, 2), null); equal(tracker.receive({ revolutions: 0, ticks: 0 }, 3), 0);
});
test('Heart rate supports 8/16-bit values and rejects truncated optional fields', () => {
  equal(heartRate([0, 155]), 155); equal(heartRate([1, 0, 1]), 256); throws(() => heartRate([1, 0])); throws(() => heartRate([16, 150]));
});
test('Power range and FTMS commands match wire fixtures', () => {
  const r = PowerRange.decode([50, 0, 0xf4, 1, 5, 0]); equal(r.quantized(123), 125); equal(r.quantized(1000), 500);
  equal([...command(5, 200)], [5, 200, 0]); equal([...command(8)], [8, 1]); throws(() => command(5, -1));
  equal(controlResponse([0x80, 5, 1]), { opcode: 5, result: 1 }); throws(() => controlResponse([0x80, 5]));
  assert(supportsTargetPower([0, 0, 0, 0, 8, 0, 0, 0]));
});
// Power matching tests live in tests/matching.test.mjs (the native estimator, ported).
class FakeCharacteristic extends EventTarget {
  constructor() { super(); this.writes = []; }
  async writeValueWithResponse(data) { this.writes.push([...data]); }
  respond(opcode, result = 1) { const e = new Event('characteristicvaluechanged'); Object.defineProperty(e, 'target', { value: { value: view([0x80, opcode, result]) } }); this.dispatchEvent(e); }
}
test('FTMS waits for application acknowledgement and serializes commands', async () => {
  const c = new FakeCharacteristic(), cp = new ControlPoint(c, { timeout: 1000 });
  let finished = false; const a = cp.send(5, 200).then(() => { finished = true; }), b = cp.send(8); await drain(); equal(c.writes.length, 1); assert(!finished); c.respond(7); await drain(); assert(!finished); c.respond(5); await a; await drain(); equal(c.writes[1], [8, 1]); c.respond(8); await b; cp.close();
});
test('FTMS rejection and disconnect reject pending commands', async () => {
  const c = new FakeCharacteristic(), cp = new ControlPoint(c); const rejected = cp.send(5, 200); await drain(); c.respond(5, 5); await rejects(() => rejected);
  const disconnected = cp.send(5, 200); await drain(); cp.close(); await rejects(() => disconnected);
});
test('FTMS timeout marks the control connection unhealthy', async () => {
  const c = new FakeCharacteristic(); let failure; const cp = new ControlPoint(c, { timeout: 5, onFailure: e => { failure = e; } }); await rejects(() => cp.send(5, 200)); assert(failure); await rejects(() => cp.send(5, 210)); cp.close();
});
test('Mock ride completes through the real engine, including cooldown', () => {
  const e = new RampEngine(configuration({ warmupSeconds: 10, cooldownSeconds: 10 }), { demo: true });
  for (let t = 0.5; t <= 1000 && e.active; t += 0.5) { e.receive(mockSample(t, e.target ?? 100, e.phase)); e.tick(t); }
  equal(e.phase, 'completed'); equal(e.session.outcome, 'exhaustion'); assert(e.session.result.estimatedFTP > 150); assert(e.session.isDemo);
});
test('Real controller sends matched commands and persists selected-source power', async () => {
  let now = 0, released = false; const devices = fakeDevices(), store = new MemoryStore(); devices.measurements.receive({ role: 'externalPowerMeter', time: now, power: 80 });
  const ride = new RideController(devices, store, { now: () => now, lease: async () => () => { released = true; } });
  await ride.start(config({ powerSource: 'externalPowerMeter', cadenceSource: 'trainer' })); clearInterval(ride.timer);
  for (let t = 1; t <= 15; t++) { now = t; devices.onReading({ role: 'trainer', time: t, power: 100, cadence: 90 }); devices.onReading({ role: 'externalPowerMeter', time: t + 0.01, power: 80 }); now += 0.01; ride.tick(); await drain(); }
  assert(devices.commands.some(([op, watts]) => op === 'target' && watts > 100)); assert(ride.engine.session.samples.filter(s => s.power != null).every(s => s.power === 80));
  ride.stop(); await drain(); assert(released); equal(devices.commands.at(-1)[0], 'stop'); assert((await store.all('sessions'))[0].endedAtOffset != null);
});
test('Controller interrupts on selected meter disconnect and confirms trainer stop', async () => {
  let now = 0, released = false; const d = fakeDevices(); d.measurements.receive({ role: 'externalPowerMeter', time: 0, power: 100 });
  const ride = new RideController(d, new MemoryStore(), { now: () => now, lease: async () => () => { released = true; } }); await ride.start(config({ powerSource: 'externalPowerMeter' })); clearInterval(ride.timer);
  d.onReading({ role: 'externalPowerMeter', time: 0.1, power: 100 }); d.onReading({ role: 'trainer', time: 0.1, cadence: 90 }); now = 0.1; ride.tick();
  d.onFailure('heartRate', 'Heart rate disconnected'); assert(ride.active); d.onFailure('externalPowerMeter', 'Meter disconnected'); await drain(); equal(ride.engine.phase, 'interrupted'); assert(released); equal(d.commands.at(-1)[0], 'stop');
});
test('Controller stops hardware on storage failure and releases its lease', async () => {
  const d = fakeDevices(); d.measurements.receive({ role: 'trainer', time: 0, power: 100 }); const store = new MemoryStore(); store.put = async () => { throw Error('quota'); }; let released = false, error;
  const ride = new RideController(d, store, { now: () => 0, lease: async () => () => { released = true; } }); ride.onError = e => { error = e; }; await ride.start(config()); assert(!ride.active); assert(error); assert(released); equal(d.commands.at(-1)[0], 'stop');
});
test('Recording-only mode sends the unmodified workout targets', async () => {
  let now = 0; const d = fakeDevices(); d.measurements.receive({ role: 'externalPowerMeter', time: 0, power: 80 });
  const ride = new RideController(d, new MemoryStore(), { now: () => now, lease: async () => () => {} }); await ride.start(config({ powerSource: 'externalPowerMeter', powerMatchingEnabled: false })); clearInterval(ride.timer);
  for (let t = 1; t <= 10; t++) { now = t; d.onReading({ role: 'trainer', time: t, cadence: 90 }); d.onReading({ role: 'externalPowerMeter', time: t, power: 80 }); ride.tick(); await drain(); }
  assert(d.commands.filter(([op]) => op === 'target').every(([, watts]) => watts === 100)); ride.stop(); await drain();
});
test('Session source and matching preferences cannot mutate during a ride', async () => {
  const d = fakeDevices(), input = { ...config({ powerSource: 'externalPowerMeter' }) }; const ride = new RideController(d, new MemoryStore(), { lease: async () => () => {} }); await ride.start(input, { demo: true }); clearInterval(ride.timer); input.powerMatchingEnabled = false; input.powerSource = 'trainer'; assert(ride.engine.session.configuration.powerMatchingEnabled); equal(ride.engine.session.configuration.powerSource, 'externalPowerMeter'); ride.stop(); await drain();
});
test('Cross-tab lease refuses concurrent ownership', async () => {
  let held = false; const locks = { async request(_name, _options, callback) { if (held) return callback(null); held = true; try { return await callback({ name: 'test' }); } finally { held = false; } } };
  const release = await acquireRideLease(locks); await rejects(() => acquireRideLease(locks)); release(); await drain(); const second = await acquireRideLease(locks); second();
});
test('Preferences default matching on and recover from corrupt storage', () => {
  let data = '{broken'; const storage = { getItem: () => data, setItem: (_, value) => { data = value; } }; assert(loadPreferences(storage).powerMatching); savePreferences({ powerMatching: false, appearance: 'dark' }, storage); assert(!loadPreferences(storage).powerMatching); equal(loadPreferences(storage).appearance, 'dark');
});
test('CSV names the source and TCX escapes names with stable timestamps', () => {
  const s = recorded(config({ riderName: '<Rider & friend>' })); assert(csv(s).startsWith('seconds,power_watts')); const text = tcx(s); assert(text.includes('&lt;Rider &amp; friend&gt;')); assert(text.includes('<ns3:Watts>300</ns3:Watts>')); assert(text.includes('Power matching: off')); assert(!text.includes('<Rider & friend>'));
  throws(() => tcx(new RampEngine(config()).session));
});
test('Unfinished recordings recover as interruptions while scored ramps survive', async () => {
  const store = new MemoryStore(); store.recover = LocalStore.prototype.recover; const a = recorded(), b = recorded(); a.endedAtOffset = null; a.rampEnd = null; b.endedAtOffset = null;
  await store.put('sessions', a); await store.put('sessions', b); await store.recover(); const sessions = await store.all('sessions'); equal(sessions[0].outcome, 'interrupted'); equal(sessions[0].result, null); assert(sessions[1].result); assert(sessions.every(s => s.endedAtOffset != null));
});
test('Uploads require a saved real session and the reviewed destination account', async () => {
  const client = new IntervalsClient(new MemoryStore()); client.connection = { id: 'i1', name: 'Rider', authorization: 'test' };
  const s = recorded(); await rejects(() => client.approve(s, 'i2')); s.isDemo = true; await rejects(() => client.approve(s, 'i1')); equal((await client.store.all('jobs')).length, 0);
});
test('Approved uploads freeze the account, avoid duplicate jobs, and never store a key', async () => {
  const calls = [], store = new MemoryStore(), client = new IntervalsClient(store, { fetcher: async (url, options) => { calls.push({ url, options }); return new Response('[]', { status: 200 }); } });
  client.connection = { id: 'i1', name: 'Rider', authorization: 'secret' }; const session = recorded(); await client.approve(session, 'i1'); equal(calls.length, 1); assert(calls[0].url.includes('/athlete/i1/activities?')); assert(calls[0].url.includes(`external_id=ftpunk-web-${session.id}`)); equal(calls[0].options.headers.Authorization, 'secret');
  await client.approve(session, 'i1'); equal(calls.length, 1); const jobs = await store.all('jobs'); equal(jobs.length, 1); equal(jobs[0].status, 'uploaded'); assert(!JSON.stringify(jobs).includes('secret'));
});
test('Only approved uploads for the connected account retry', async () => {
  let calls = 0; const store = new MemoryStore(), client = new IntervalsClient(store, { fetcher: async () => { calls++; return new Response('', { status: 503 }); } });
  client.connection = { id: 'i1', name: 'Rider', authorization: 'secret' }; await client.approve(recorded(), 'i1'); const job = (await store.all('jobs'))[0]; equal(job.status, 'queued'); assert(job.retryAt > Date.now());
  await client.flush(); equal(calls, 1); client.connection.id = 'i2'; await client.flush(true); equal(calls, 1); client.connection.id = 'i1'; client.fetcher = async () => { calls++; return new Response('', { status: 200 }); }; await client.flush(true); equal(calls, 2); equal((await store.all('jobs'))[0].status, 'uploaded');
});
test('Authentication failure disconnects and retains the approved job', async () => {
  const store = new MemoryStore(), client = new IntervalsClient(store, { fetcher: async () => new Response('', { status: 401 }) }); client.connection = { id: 'i1', name: 'Rider', authorization: 'secret' }; await client.approve(recorded(), 'i1'); equal(client.connection, null); equal((await store.all('jobs'))[0].status, 'failed');
});
test('Malformed athlete responses cannot create a connection', async () => {
  const client = new IntervalsClient(new MemoryStore(), { fetcher: async () => new Response('{"name":"No ID"}', { status: 200 }) }); await rejects(() => client.connect('key')); equal(client.connection, null);
});
test('Timed-out control still allows a best-effort acknowledged stop', async () => {
  const c = new FakeCharacteristic(), cp = new ControlPoint(c, { timeout: 5 });
  await rejects(() => cp.send(5, 200));
  const stopped = cp.send(8); await drain(); equal(c.writes.at(-1), [8, 1]); c.respond(8); await stopped; cp.close();
});
function fakePeripheral(role, id) {
  const chars = new Map();
  const characteristic = (uuid, data = []) => {
    const c = new FakeCharacteristic(); c.value = view(data); c.uuid = uuid;
    c.readValue = async () => c.value;
    c.startNotifications = async () => c;
    c.writeValueWithResponse = async bytes => { c.writes.push([...bytes]); queueMicrotask(() => c.respond(bytes[0])); };
    c.measure = bytes => { c.value = view(bytes); c.dispatchEvent(new Event('characteristicvaluechanged')); };
    chars.set(uuid, c); return c;
  };
  if (role === 'trainer') {
    characteristic(0x2acc, [0, 0, 0, 0, 8, 0, 0, 0]); characteristic(0x2ad8, [0, 0, 0xe8, 3, 1, 0]); characteristic(0x2ad9); characteristic(0x2ad2); characteristic(0x2ada);
  } else characteristic(role === 'externalPowerMeter' ? 0x2a63 : 0x2a37);
  const device = new EventTarget(); device.id = id; device.name = `Test ${role}`;
  const server = { connected: false, async connect() { this.connected = true; return this; }, async getPrimaryService() { return { async getCharacteristic(uuid) { if (!chars.has(uuid)) throw Error('Missing characteristic'); return chars.get(uuid); } }; }, disconnect() { this.connected = false; device.dispatchEvent(new Event('gattserverdisconnected')); } };
  device.gatt = server; return { device, chars };
}
test('Web Bluetooth pairing discovers ERG controls and receives real packet notifications', async () => {
  const trainer = fakePeripheral('trainer', 'trainer-id'); let reading;
  const d = new BluetoothDevices({ bluetooth: { requestDevice: async () => trainer.device }, now: () => 10 });
  d.onReading = r => { reading = r; }; await d.connect('trainer'); assert(d.trainerReady); equal(d.range.maximum, 1000); equal(trainer.chars.get(0x2ad9).writes, [[0]]);
  trainer.chars.get(0x2ad2).measure([0x44, 0, 0, 0, 180, 0, 200, 0]); equal(reading.power, 200); equal(reading.cadence, 90);
  await d.start(100); await d.setTarget(125); await d.stop(); equal(trainer.chars.get(0x2ad9).writes.slice(1), [[7], [5, 100, 0], [5, 125, 0], [8, 1]]);
  d.disconnect('trainer'); assert(!d.trainerReady); equal(d.measurements.fresh('trainer', 'power', 10), null);
});
test('Bluetooth resistance requires both advertised support and a valid range', async () => {
  for (const [bits, bytes, allowed, canPair] of [[12, [0,0,232,3,10,0], true, true], [8, [0,0,232,3,10,0], false, true], [12, [0,100,1], false, true], [4, [0,100,1], false, false]]) {
    const trainer = fakePeripheral('trainer', crypto.randomUUID()); trainer.chars.get(0x2acc).value = view([0,0,0,0,bits,0,0,0]);
    trainer.chars.set(0x2ad6, { readValue: async () => view(bytes) });
    const d = new BluetoothDevices({ bluetooth: { requestDevice: async () => trainer.device } });
    if (!canPair) { await rejects(() => d.connect('trainer')); assert(!d.trainerReady); continue; }
    await d.connect('trainer'); equal(!!d.resistanceRange, allowed);
    if (allowed) { await d.startResistance(100); await d.setResistance(110); await d.stop(); equal(trainer.chars.get(0x2ad9).writes, [[0], [7], [4,100,0], [4,110,0], [8,1]]); }
    else await rejects(() => d.startResistance(100));
    d.disconnect('trainer'); equal(d.resistanceRange, null);
  }
});
test('External meter prompts only after successful notification subscription', async () => {
  const meter = fakePeripheral('externalPowerMeter', 'meter-id'); let paired = 0;
  const d = new BluetoothDevices({ bluetooth: { requestDevice: async () => meter.device } }); d.onMeterReady = name => { paired++; equal(name, 'Test externalPowerMeter'); };
  await d.connect('externalPowerMeter'); equal(paired, 1); d.disconnect('externalPowerMeter');
  meter.chars.get(0x2a63).startNotifications = async () => { throw Error('Subscribe failed'); };
  await rejects(() => d.connect('externalPowerMeter')); equal(paired, 1); equal(d.devices.externalPowerMeter, undefined);
});
test('Malformed measurements do not refresh the power timestamp', async () => {
  let now = 10; const trainer = fakePeripheral('trainer', 'trainer-id'); const d = new BluetoothDevices({ bluetooth: { requestDevice: async () => trainer.device }, now: () => now });
  await d.connect('trainer'); trainer.chars.get(0x2ad2).measure([0x40, 0, 0, 0, 200, 0]); now = 13;
  trainer.chars.get(0x2ad2).measure([0x40, 0]); equal(d.measurements.fresh('trainer', 'power', now), null); d.disconnect('trainer');
});
test('Unexpected Bluetooth disconnect clears readiness and notifies the workout owner', async () => {
  const trainer = fakePeripheral('trainer', 'trainer-id'); const d = new BluetoothDevices({ bluetooth: { requestDevice: async () => trainer.device } }); let failed;
  d.onFailure = role => { failed = role; }; await d.connect('trainer'); trainer.device.gatt.disconnect(); equal(failed, 'trainer'); assert(!d.trainerReady); equal(d.devices.trainer, undefined);
});
test('Losing trainer control rejects control and reports the takeover', async () => {
  const trainer = fakePeripheral('trainer', 'trainer-id'); const d = new BluetoothDevices({ bluetooth: { requestDevice: async () => trainer.device } }); let failure;
  d.onFailure = (_, reason) => { failure = reason; }; await d.connect('trainer'); trainer.chars.get(0x2ada).measure([0xff]); assert(!d.trainerReady); assert(failure.includes('Another application')); d.disconnect('trainer');
});
test('Portable archive fixture preserves native results, sources and profile history', async () => {
  const url = new URL('./fixtures/portable-v1.json', import.meta.url);
  const text = await (await fetch(url)).text();
  const archive = parseArchive(text), sessions = archiveSessions(archive), c = sessions[0].configuration;
  equal(c.priorFTP, 250); equal(c.powerSource, 'externalPowerMeter'); equal(c.cadenceSource, 'trainer'); assert(c.powerMatchingEnabled);
  equal(sessions[0].result.estimatedFTP, 225); equal(sessions[0].result.wattsPerKG, 3);
  equal(sessions[0].samples.length, 71); equal(sessions[0].samples[0].trainerPower, 280);
  const roundTrip = parseArchive(archiveText(makeArchive(archive.profiles, sessions)));
  equal(roundTrip.activities[0].session.samples, archive.activities[0].session.samples);
  equal(roundTrip.activities[0].session.configuration.priorFTP.watts, 250);
  equal(roundTrip.profiles, archive.profiles);
});
test('Portable archives reject future formats, live rides, duplicate identities and invalid results', () => {
  const session = recorded(); session.configuration.riderID = LEGACY_PROFILE.id;
  const archive = makeArchive([LEGACY_PROFILE], [session]);
  throws(() => validateArchive({ ...archive, version: 4 }));
  throws(() => validateArchive({ ...archive, profiles: [] }));
  throws(() => validateArchive({ ...archive, activities: [...archive.activities, ...archive.activities] }));
  const live = structuredClone(archive); live.activities[0].session.endedAtOffset = null; throws(() => validateArchive(live));
  const corrupt = structuredClone(archive); corrupt.activities[0].session.result.factor = 4; throws(() => validateArchive(corrupt));
  const malformed = structuredClone(archive); malformed.activities[0].session.samples[0].power = '300'; throws(() => validateArchive(malformed));
});
const LEGACY_PROFILE = { id: '00000000-0000-0000-0000-000000000001', name: 'You', ftpHistory: [], currentFTPID: null, weightKG: null };
test('Legacy web backups convert to portable format without transferring authorization', () => {
  const session = recorded(); session.configuration.riderID = LEGACY_PROFILE.id;
  const old = { format: 'ftpunk-web', version: 1, exportedAt: new Date().toISOString(), profiles: [LEGACY_PROFILE], sessions: [session], jobs: [{ authorization: 'secret' }] };
  old.sessions[0].authorization = 'secret'; old.sessions[0].configuration.apiKey = 'secret';
  const text = archiveText(parseArchive(JSON.stringify(old)));
  assert(!text.includes('secret')); assert(!text.includes('authorization')); equal(parseArchive(text).activities.length, 1);
});
test('Controller releases the trainer while final storage is still pending', async () => {
  const devices = fakeDevices(), store = new MemoryStore(); let now = 0;
  const controller = new RideController(devices, store, { now: () => now, lease: async () => () => {} });
  devices.measurements.receive({ role: 'trainer', time: 0, power: 200, cadence: 90 });
  await controller.start(config()); clearInterval(controller.timer);
  let finishSave; store.put = () => new Promise(resolve => { finishSave = resolve; });
  controller.stop();
  await new Promise(resolve => setTimeout(resolve, 0));
  assert(devices.commands.some(c => c[0] === 'stop')); assert(controller.finishing);
  await controller.start(config()); assert(controller.finishing);
  finishSave(); await new Promise(resolve => setTimeout(resolve, 0)); assert(!controller.busy);
});
test('Stop before a queued target runs prevents the stale increase', async () => {
  const devices = fakeDevices(), controller = new RideController(devices, new MemoryStore(), { lease: async () => () => {} });
  await controller.start(config(), { demo: true }); clearInterval(controller.timer);
  let sent = false; controller.send(async () => { sent = true; }, () => {}); controller.stop();
  await new Promise(resolve => setTimeout(resolve, 0)); assert(!sent); assert(!controller.busy);
});
test('Cancelling a pending start never proceeds to trainer preparation', async () => {
  let grant; const devices = fakeDevices(), controller = new RideController(devices, new MemoryStore(), { lease: () => new Promise(resolve => { grant = resolve; }) });
  const starting = controller.start(config()); controller.stop(); grant(() => {}); await starting;
  equal(devices.commands, []); assert(!controller.busy);
});
test('Unconfirmed trainer stop invalidates readiness until reconnect', async () => {
  const trainer = fakePeripheral('trainer', 'trainer-id');
  const d = new BluetoothDevices({ bluetooth: { requestDevice: async () => trainer.device } });
  await d.connect('trainer'); assert(d.trainerReady);
  d.control.send = async () => { throw Error('Stop rejected'); };
  await rejects(() => d.stop()); assert(!d.trainerReady); assert(!d.control.healthy);
  await rejects(() => d.start(100)); d.disconnect('trainer');
});
test('Import suspends upload retries and cancelled jobs cannot reappear after a response', async () => {
  const store = new MemoryStore(); let complete, calls = 0;
  const client = new IntervalsClient(store, { fetcher: () => { calls++; return new Promise(resolve => { complete = resolve; }); } });
  client.connection = { id: 'i1', name: 'Rider', authorization: 'secret' };
  const resume = client.suspendUploads(); await client.flush(); equal(calls, 0);
  await rejects(() => client.approve(recorded(), 'i1')); resume();
  const uploading = client.approve(recorded(), 'i1'); await drain();
  equal(calls, 1); throws(() => client.suspendUploads());
  const job = (await store.all('jobs'))[0]; await store.delete('jobs', job.id);
  complete(new Response('', { status: 200 })); await uploading;
  equal(await store.all('jobs'), []);
});
test('Optional heart-rate loss during preparation does not cancel the ride', async () => {
  let prepared; const devices = fakeDevices();
  devices.measurements.receive({ role: 'trainer', time: 0, power: 200, cadence: 90 });
  devices.start = () => new Promise(resolve => { prepared = resolve; });
  const controller = new RideController(devices, new MemoryStore(), { now: () => 0, lease: async () => () => {} });
  const starting = controller.start(config()); await drain();
  devices.onFailure('heartRate', 'Optional HR disconnected'); equal(controller.cancelStart, null);
  prepared(); await starting; assert(controller.active); clearInterval(controller.timer);
  controller.stop(); await drain(); assert(!controller.busy);
});
