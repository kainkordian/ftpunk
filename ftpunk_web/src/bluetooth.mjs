import { Measurements, BikeAssembler, CadenceTracker, indoorBike, cyclingPower, heartRateMeasurement, PowerRange, ResistanceRange, supportsResistance, supportsTargetPower, command, controlResponse } from './protocol.mjs';
export const SERVICES = { trainer: 0x1826, externalPowerMeter: 0x1818, heartRate: 0x180d };
export const DEVICE_LABELS = { trainer: 'Smart trainer', externalPowerMeter: 'External power meter', heartRate: 'Heart rate' };
const clock = () => performance.now() / 1000;
/** Chrome's bare "Connection attempt failed" says nothing a rider can act on; add the usual remedies. */
export function connectionError(error, role) {
  if (error?.name !== 'NetworkError' && !/connection attempt failed|connection failed/i.test(error?.message ?? '')) return error;
  const wrapped = Error(`${DEVICE_LABELS[role]} could not be reached. Close other apps or devices using it, wake it up, and if it still fails forget it in your system Bluetooth settings and pair again.`);
  wrapped.cause = error; return wrapped;
}

// GATT write success is not an FTMS acknowledgement. One command remains in flight
// until its matching Control Point indication arrives (or it times out).
export class ControlPoint {
  constructor(characteristic, { timeout = 2000, onFailure = () => {} } = {}) {
    this.characteristic = characteristic; this.timeout = timeout; this.onFailure = onFailure; this.tail = Promise.resolve(); this.pending = null; this.closed = false; this.healthy = true;
    this.listener = e => {
      try {
        const response = controlResponse(e.target.value);
        if (response.opcode !== this.pending?.opcode) return;
        this.settle(response.result === 1 ? null : Error(`Trainer rejected the command (result ${response.result}).`));
      } catch (error) { this.settle(error); this.onFailure(error); }
    };
    characteristic.addEventListener('characteristicvaluechanged', this.listener);
  }
  settle(error) {
    const p = this.pending; this.pending = null;
    if (!p) return;
    clearTimeout(p.timer); error ? p.reject(error) : p.resolve();
  }
  send(opcode, watts) {
    const bytes = command(opcode, watts);
    const run = this.tail.catch(() => {}).then(() => {
      if (this.closed) throw Error('Trainer control disconnected.');
      if (!this.healthy && opcode !== 8) throw Error('Trainer control needs reconnecting.');
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          const error = Error('Trainer target confirmation was delayed. Reconnect the trainer.');
          this.healthy = false; this.settle(error); this.onFailure(error);
        }, this.timeout);
        this.pending = { opcode, resolve, reject, timer };
        Promise.resolve().then(() => this.characteristic.writeValueWithResponse(bytes)).catch(error => { this.settle(error); this.onFailure(error); });
      });
    });
    this.tail = run; return run;
  }
  close() { this.closed = true; this.settle(Error('Trainer control disconnected.')); this.characteristic.removeEventListener('characteristicvaluechanged', this.listener); }
}

export class BluetoothDevices {
  constructor({ bluetooth = globalThis.navigator?.bluetooth, now = clock } = {}) {
    this.bluetooth = bluetooth; this.now = now; this.devices = {}; this.measurements = new Measurements(); this.trainerReady = false; this.control = null; this.range = null; this.resistanceRange = null; this.legacyResistance = false; this.captureEnabled = false; this.captures = [];
    this.onReading = () => {}; this.onChange = () => {}; this.onFailure = () => {}; this.onMeterReady = () => {};
  }
  get available() { return !!this.bluetooth && globalThis.isSecureContext !== false; }
  get snapshots() { return Object.entries(this.devices).filter(([, d]) => d.ready).map(([role, d]) => ({ role, name: d.name, localIdentifier: d.device.id, capabilities: role === 'trainer' ? { ...this.range, ...(this.resistanceRange ? { resistanceTenths: `${this.resistanceRange.minimum}...${this.resistanceRange.maximum} step ${this.resistanceRange.increment}` } : {}) } : {} })); }
  fail(role, error) { this.measurements.reset(role); if (role === 'trainer') this.trainerReady = false; this.onFailure(role, error.message); this.onChange(); }
  async connect(role) {
    if (!this.available) throw Error('Open FTPunk in Chrome using localhost or HTTPS to connect Bluetooth devices.');
    // Must be invoked directly by the pairing button's user gesture.
    const device = await this.bluetooth.requestDevice({ filters: [{ services: [SERVICES[role]] }], ...(role === 'trainer' ? { optionalServices: [SERVICES.externalPowerMeter] } : {}) });
    if (Object.entries(this.devices).some(([r, d]) => r !== role && d.device.id === device.id)) throw Error('Use a separate external meter, or select Trainer as the power source.');
    this.disconnect(role);
    const entry = { device, name: device.name || DEVICE_LABELS[role], ready: false, listeners: [] };
    this.devices[role] = entry;
    const disconnected = () => {
      if (this.devices[role] !== entry) return;
      if (role === 'trainer') { this.control?.close(); this.control = null; this.range = null; this.resistanceRange = null; }
      delete this.devices[role]; this.fail(role, Error(`${DEVICE_LABELS[role]} disconnected.`));
    };
    device.addEventListener('gattserverdisconnected', disconnected); entry.disconnected = disconnected; this.onChange();
    try {
      const server = await device.gatt.connect(), service = await server.getPrimaryService(SERVICES[role]);
      const notify = async (id, decode, from = service) => {
        const characteristic = await from.getCharacteristic(id);
        const listener = event => {
          if (this.devices[role] !== entry) return;
          const time = this.now(), data = event.target.value;
          if (this.captureEnabled) { this.captures.push({ role, time, characteristic: id, hex: [...new Uint8Array(data.buffer, data.byteOffset, data.byteLength)].map(v => v.toString(16).padStart(2, '0')).join(' ') }); if (this.captures.length > 500) this.captures.shift(); }
          try { const value = decode(data, time); if (value) { const r = { role, time, ...value }; this.measurements.receive(r); this.onReading(r); } }
          catch (error) { entry.notice = `Discarded malformed measurement: ${error.message}`; this.onChange(); }
        };
        characteristic.addEventListener('characteristicvaluechanged', listener); entry.listeners.push([characteristic, listener]);
        await characteristic.startNotifications(); return characteristic;
      };
      if (role === 'trainer') {
        const features = await (await service.getCharacteristic(0x2acc)).readValue();
        const erg = supportsTargetPower(features), resistance = supportsResistance(features);
        if (!erg && !resistance) throw Error('This trainer does not expose ERG or resistance control.');
        if (erg) this.range = PowerRange.decode(await (await service.getCharacteristic(0x2ad8)).readValue());
        if (resistance) {
          try { this.resistanceRange = ResistanceRange.decode(await (await service.getCharacteristic(0x2ad6)).readValue()); }
          catch (e) { if (!erg) throw e; entry.notice = 'Resistance range could not be verified; ERG remains available.'; }
        }
        const cp = await service.getCharacteristic(0x2ad9);
        this.control = new ControlPoint(cp, { onFailure: error => this.fail('trainer', error) });
        await cp.startNotifications();
        const assembler = new BikeAssembler();
        await notify(0x2ad2, (data, time) => assembler.receive(indoorBike(data, this.legacyResistance), time));
        await notify(0x2ada, data => { if (data.byteLength && data.getUint8(0) === 0xff) { this.control?.close(); this.fail('trainer', Error('Another application took trainer control.')); } return null; });
        // A trainer may also expose the Cycling Power service. It is only read for pedal balance; a power meter's balance wins, and it is fine when it is missing.
        try {
          await notify(0x2a63, (data, time) => { const left = cyclingPower(data).leftBalance; return Number.isFinite(left) && this.measurements.takesBalance('trainer', time) ? { leftBalance: left } : null; }, await server.getPrimaryService(SERVICES.externalPowerMeter));
        } catch { /* no balance from this trainer */ }
        await this.control.send(0); this.trainerReady = true;
      } else if (role === 'externalPowerMeter') {
        const tracker = new CadenceTracker();
        await notify(0x2a63, (data, time) => { const r = cyclingPower(data); return { power: r.power, cadence: r.crank ? tracker.receive(r.crank, time) : null, leftBalance: r.leftBalance }; });
      } else await notify(0x2a37, data => heartRateMeasurement(data));
      if (!device.gatt.connected || this.devices[role] !== entry) throw Error('The device disconnected while pairing.');
      entry.ready = true; this.onChange();
      if (role === 'externalPowerMeter') this.onMeterReady(entry.name);
    } catch (error) { this.disconnect(role); throw connectionError(error, role); }
  }
  disconnect(role) {
    const d = this.devices[role]; if (!d) return;
    delete this.devices[role];
    d.device.removeEventListener('gattserverdisconnected', d.disconnected);
    for (const [c, listener] of d.listeners) c.removeEventListener('characteristicvaluechanged', listener);
    if (role === 'trainer') { this.control?.close(); this.control = null; this.range = null; this.resistanceRange = null; this.trainerReady = false; }
    d.device.gatt.disconnect(); this.measurements.reset(role); this.onChange();
  }
  async start(watts) { if (!this.trainerReady) throw Error('Pair and enable your trainer first.'); await this.control.send(7); await this.setTarget(watts); }
  async startResistance(level) { if (!this.trainerReady || !this.resistanceRange) throw Error('Resistance control is unavailable.'); await this.control.send(7); await this.setResistance(level); }
  async setResistance(level) { if (!this.trainerReady || !this.resistanceRange || this.resistanceRange.quantized(level) !== level) throw Error('Unsupported resistance target.'); await this.control.send(4, level); }
  async setTarget(watts) { if (!this.trainerReady || !this.range) throw Error('Trainer control is not ready.'); if (watts < this.range.minimum || watts > this.range.maximum) throw Error('The target is outside the trainer’s supported power range.'); await this.control.send(5, this.range.quantized(watts)); }
  async stop() {
    try {
      if (!this.control || !this.devices.trainer?.device.gatt.connected) throw Error('Trainer stop could not be confirmed: the trainer is disconnected.');
      await this.control.send(8);
    } catch (error) {
      this.trainerReady = false; if (this.control) this.control.healthy = false; this.onChange(); throw error;
    }
  }
}
