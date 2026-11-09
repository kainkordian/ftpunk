// Bluetooth SIG packet formats, ported from FTPunkDevices. Truncation never becomes a zero reading.
export class Cursor {
  constructor(data) { this.view = data instanceof DataView ? data : new DataView(Uint8Array.from(data).buffer); this.offset = 0; }
  get remaining() { return this.view.byteLength - this.offset; }
  take(n) { if (n < 0 || this.remaining < n) throw Error('Truncated Bluetooth packet.'); const p = this.offset; this.offset += n; return p; }
  u8() { return this.view.getUint8(this.take(1)); }
  u16() { return this.view.getUint16(this.take(2), true); }
  i16() { return this.view.getInt16(this.take(2), true); }
  u32() { return this.view.getUint32(this.take(4), true); }
  skip(n) { this.take(n); }
  finish() { if (this.remaining) throw Error('Trailing Bluetooth packet bytes.'); }
}
export function indoorBike(data, legacyResistance = false) {
  const c = new Cursor(data), f = c.u16(), r = { moreData: !!(f & 1) };
  if (f & 0xe000) throw Error('Unsupported indoor bike flags.');
  if (!r.moreData) r.speed = c.u16() / 100;
  if (f & 2) c.skip(2);
  if (f & 4) r.cadence = c.u16() / 2;
  if (f & 8) c.skip(2);
  if (f & 16) c.skip(3);
  if (f & 32) c.skip(legacyResistance ? 2 : 1);
  if (f & 64) r.power = c.i16();
  if (f & 128) c.skip(2);
  if (f & 256) c.skip(5);
  if (f & 512) r.heartRate = c.u8();
  if (f & 1024) c.skip(1);
  if (f & 2048) c.skip(2);
  if (f & 4096) c.skip(2);
  c.finish(); return r;
}
export class BikeAssembler {
  constructor() { this.pending = null; this.beganAt = null; }
  receive(v, time) {
    if (this.beganAt != null && (time < this.beganAt || time - this.beganAt > 2)) { this.pending = null; this.beganAt = null; }
    if (v.moreData) { this.beganAt ??= time; this.pending = { ...this.pending, ...v }; return null; }
    const result = { ...this.pending, ...v }; this.pending = null; this.beganAt = null; return result;
  }
}
export function cyclingPower(data) {
  const c = new Cursor(data), f = c.u16(), r = { power: c.i16() };
  if (f & 0xe000) throw Error('Unsupported cycling power flags.');
  if (f & 1) { const balance = c.u8(); if (balance > 200) throw Error('Invalid pedal balance.'); if (f & 2) r.leftBalance = balance / 2; }
  if (f & 4) c.skip(2);
  if (f & 16) c.skip(6);
  if (f & 32) r.crank = { revolutions: c.u16(), ticks: c.u16() };
  for (const [bit, length] of [[6, 4], [7, 4], [8, 3], [9, 2], [10, 2], [11, 2]]) if (f & (1 << bit)) c.skip(length);
  c.finish(); return r;
}
export class CadenceTracker {
  receive(event, time) {
    const previous = this.previous, lastReceipt = this.lastReceipt;
    this.previous = event; this.lastReceipt = time;
    if (!previous || time <= lastReceipt || time - lastReceipt > 5) { this.lastMovement = time; return null; }
    if (event.revolutions === previous.revolutions && event.ticks === previous.ticks) return time - (this.lastMovement ?? time) >= 2 ? 0 : null;
    const revs = (event.revolutions - previous.revolutions + 65536) % 65536, ticks = (event.ticks - previous.ticks + 65536) % 65536;
    this.lastMovement = time;
    if (!revs || !ticks) return null;
    const rpm = 60 * revs * 1024 / ticks;
    return rpm <= 250 ? rpm : null;
  }
}
export function heartRate(data) {
  const c = new Cursor(data), f = c.u8();
  if (f & 0xe0) throw Error('Unsupported heart rate flags.');
  const value = f & 1 ? c.u16() : c.u8();
  if (f & 8) c.skip(2);
  if (f & 16) { if (c.remaining < 2 || c.remaining % 2) throw Error('Truncated RR interval.'); c.skip(c.remaining); }
  c.finish(); return value;
}
export class PowerRange {
  constructor(minimum, maximum, increment) { if (![minimum, maximum, increment].every(Number.isInteger) || minimum < 0 || maximum <= minimum || maximum > 32767 || increment < 1) throw Error('Invalid trainer power range.'); Object.assign(this, { minimum, maximum, increment }); }
  static decode(data) { const c = new Cursor(data), r = new PowerRange(c.i16(), c.i16(), c.u16()); c.finish(); return r; }
  quantized(watts) { const clamped = Math.min(this.maximum, Math.max(this.minimum, watts)); return Math.min(this.maximum, this.minimum + Math.round((clamped - this.minimum) / this.increment) * this.increment); }
}
export function supportsTargetPower(data) { const c = new Cursor(data); c.u32(); const targets = c.u32(); c.finish(); return !!(targets & 8); }
export function command(opcode, watts) {
  if (opcode === 5 || opcode === 4) { if (!Number.isInteger(watts) || watts < 0 || watts > 32767) throw Error('Invalid trainer target.'); return Uint8Array.of(opcode, watts & 255, watts >> 8); }
  if (opcode === 8) return Uint8Array.of(8, 1);
  if (![0, 7].includes(opcode)) throw Error('Unsupported trainer command.');
  return Uint8Array.of(opcode);
}
export function controlResponse(data) { const c = new Cursor(data); if (c.u8() !== 0x80) throw Error('Unexpected control response.'); const opcode = c.u8(), result = c.u8(); c.finish(); if (result < 1 || result > 5) throw Error('Invalid control result.'); return { opcode, result }; }
export class Measurements {
  constructor() { this.values = {}; }
  receive(r) { if (!Number.isFinite(r.time)) return; for (const key of ['power', 'cadence', 'heartRate', 'leftBalance']) if (Number.isFinite(r[key])) { this.values[r.role] ??= {}; this.values[r.role][key] = { value: r[key], time: r.time }; } }
  reset(role) { delete this.values[role]; }
  /** A power meter's balance wins over a trainer's while the meter is reporting one. */
  takesBalance(role, time) { return role !== 'trainer' || this.fresh('externalPowerMeter', 'leftBalance', time) == null; }
  fresh(role, key, time, age = 2) { const v = this.values[role]?.[key]; return v && time >= v.time && time - v.time <= age ? v.value : null; }
  cadenceSource(source, time) { if (source === 'externalPowerMeter' && this.fresh(source, 'cadence', time) != null) return source; return this.fresh('trainer', 'cadence', time) != null ? 'trainer' : 'unavailable'; }
}
export function route(reading, config, origin) {
  const s = { time: reading.time - origin };
  if (!Number.isFinite(s.time) || s.time < 0) return null;
  if (reading.role === config.powerSource) s.power = reading.power;
  if (reading.role === config.cadenceSource) s.cadence = reading.cadence;
  if (reading.role === 'heartRate') s.heartRate = reading.heartRate;
  if (reading.role === 'trainer') s.trainerPower = reading.power;
  if (Number.isFinite(reading.leftBalance)) s.leftBalance = reading.leftBalance;
  return s;
}

export function supportsResistance(data) { const c = new Cursor(data); c.u32(); const targets = c.u32(); c.finish(); return !!(targets & 4); }
export class ResistanceRange extends PowerRange {
  static decode(data) {
    const c = new Cursor(data), r = new ResistanceRange(c.i16(), c.i16(), c.u16()); c.finish();
    if (r.increment > r.maximum - r.minimum) throw Error('Invalid resistance increment.'); return r;
  }
  quantized(level) {
    const steps = Math.round((Math.max(this.minimum, Math.min(this.maximum, level)) - this.minimum) / this.increment);
    return this.minimum + Math.min(Math.floor((this.maximum - this.minimum) / this.increment), steps) * this.increment;
  }
}
