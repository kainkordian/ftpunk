import { test, assert, equal } from './harness.mjs';
import { RideController, warmthFor } from '../src/controller.mjs';
import { configuration } from '../src/domain.mjs';
import { freeRide } from '../src/training.mjs';
import { Measurements, PowerRange } from '../src/protocol.mjs';

// The controller feeds the matcher the trainer's own reported power and keeps the trainer's warmth with the Bluetooth connection.
class MemoryStore {
  constructor() { this.tables = { sessions: new Map(), profiles: new Map(), jobs: new Map() }; }
  async put(table, value) { this.tables[table].set(value.id, structuredClone(value)); }
  async all(table) { return structuredClone([...this.tables[table].values()]); }
  async delete(table, id) { this.tables[table].delete(id); }
}
const drain = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
/** `entry` is the Bluetooth trainer connection; a new object is a new connection. */
function devices(entry = {}) {
  return { measurements: new Measurements(), trainerReady: true, range: new PowerRange(0, 1000, 1), snapshots: [], commands: [], devices: { trainer: entry },
    async start(w) { this.commands.push(['start', w]); }, async setTarget(w) { this.commands.push(['target', w]); }, async stop() { this.commands.push(['stop']); } };
}
const meterRide = (extra = {}) => configuration({ warmupSeconds: 0, powerSource: 'externalPowerMeter', cadenceSource: 'externalPowerMeter', priorFTP: 250, ...extra });

/** A pedalling rider on a trainer that holds the last command and reads `bias` times what a meter reads, for `seconds` of 1 Hz ticks. */
async function ride(c, d, clock, seconds, { bias = 1 / 0.9, start = clock.now } = {}) {
  for (let i = 0; i < seconds; i++) {
    clock.now = start + i + 1; const held = d.commands.findLast(([kind]) => kind === 'start' || kind === 'target')?.[1] ?? 200;
    const reported = held, meter = reported / bias;
    d.onReading({ role: 'externalPowerMeter', time: clock.now, power: meter, cadence: 90 }); d.onReading({ role: 'trainer', time: clock.now, power: reported });
    d.measurements.receive({ role: 'externalPowerMeter', time: clock.now, power: meter }); c.tick(); await drain();
  }
}
async function begin(d, clock, config, options = {}) {
  d.measurements.receive({ role: 'externalPowerMeter', time: 0, power: 150 });
  const c = new RideController(d, new MemoryStore(), { now: () => clock.now, lease: async () => () => {} }); await c.start(config, options); clearInterval(c.timer); return c;
}

test('Power matching corrects the command from the trainer-reported power, and the cockpit can read its status', async () => {
  const d = devices(), clock = { now: 0 }; warmthFor(d.devices.trainer).kilojoules = 150; // warm
  const c = await begin(d, clock, meterRide(), { training: freeRide(200) });
  await ride(c, d, clock, 60);
  const commands = d.commands.filter(([kind]) => kind === 'target' || kind === 'start').map(([, w]) => w), last = commands.at(-1);
  assert(last > 205 && last <= 240, `a meter that reads 10 % low raises the command: ${commands.join(',')}`); equal(c.matchingStatus.kind, 'matching'); assert(c.matchingStatus.gain < 0.95, `gain ${c.matchingStatus.gain}`);
  assert(c.lastTrainerPower.time === 60 && c.lastTrainerPower.watts > 200, 'the controller keeps the trainer-reported power the engine does not expose'); c.stop(); await drain();
});
test('Recording-only mode sends unmodified targets and reports no matching status', async () => {
  const d = devices(), clock = { now: 0 }, c = await begin(d, clock, meterRide({ powerMatchingEnabled: false }), { training: freeRide(200) });
  await ride(c, d, clock, 40); equal(d.commands.filter(([kind]) => kind === 'target' || kind === 'start').map(([, w]) => w), [200]); equal(c.matchingStatus, { kind: 'off' }); c.stop(); await drain();
});
test('A cold trainer reports warming until 60 kJ, and warmth survives a second ride on the same connection but not a reconnect', async () => {
  const entry = {}, d = devices(entry), clock = { now: 0 }, first = await begin(d, clock, meterRide(), { training: freeRide(200) });
  await ride(first, d, clock, 30);
  const kJ = first.warmth.kilojoules; assert(kJ > 3 && kJ < 10, `30 s at about 200 W is about 6 kJ: ${kJ}`); equal(first.matchingStatus.kind, 'warming'); first.stop(); await drain(); first.engine = null;
  // the same connection: the same warmth, not reset
  clock.now = 100; const second = new RideController(d, new MemoryStore(), { now: () => clock.now, lease: async () => () => {} }); d.measurements.receive({ role: 'externalPowerMeter', time: 100, power: 150 });
  await second.start(meterRide(), { training: freeRide(200) }); clearInterval(second.timer);
  assert(second.warmth === first.warmth && second.warmth.kilojoules === kJ && second.warmth.lastTime == null, 'warmth is kept, only the ride clock restarts'); second.stop(); await drain();
  // a reconnect is a new trainer record: cold again
  const reconnected = devices({}); clock.now = 200; reconnected.measurements.receive({ role: 'externalPowerMeter', time: 200, power: 150 });
  const third = new RideController(reconnected, new MemoryStore(), { now: () => clock.now, lease: async () => () => {} }); await third.start(meterRide(), { training: freeRide(200) }); clearInterval(third.timer);
  equal(third.warmth.kilojoules, 0); await ride(third, reconnected, clock, 3); equal(third.matchingStatus.kind, 'warming'); third.stop(); await drain();
});
test('Pause and resume restart the settling but keep the estimate and the warmth', async () => {
  const d = devices(), clock = { now: 0 }; warmthFor(d.devices.trainer).kilojoules = 150;
  const c = await begin(d, clock, meterRide(), { training: freeRide(200) }); await ride(c, d, clock, 40);
  const gain = c.matcher.gain, kJ = c.warmth.kilojoules, settled = c.matcher.settledAt; assert(gain < 1);
  c.adjustERG(10); assert(c.matcher.settledAt > settled, 'an ERG change waits for the trainer to settle again'); equal(c.matcher.gain, gain); equal(c.warmth.kilojoules, kJ); c.stop(); await drain();
});
test('The FTP test logs what the matcher did at the start of the ramp', async () => {
  const d = devices(), clock = { now: 0 }; warmthFor(d.devices.trainer).kilojoules = 150;
  const c = await begin(d, clock, meterRide()); await ride(c, d, clock, 20);
  const line = c.engine.session.events.find(e => e.message.startsWith('Power matching (ramp start)'));
  assert(line && /gain [\d.]+, offset [+-][\d.]+ W, trainer warmth \d+ kJ, fade guard \d+ s, \d+ measurements/.test(line.message), line?.message); c.stop(); await drain();
});
