// A minimal FIT activity file writer with no dependencies, ported from Sources/FTPunkStorage/FITEncoder.swift. The output is byte-identical to the
// native encoder for the same session (tests compare against the Swift-written fixtures `fit-*.fit` in contracts/fixtures/).
// Field numbers and base types follow FIT profile 21.221 (see the Swift file for the table). Messages: file_id, event, record, lap, session, activity.
import { ridePauses, rideTrack, rideBalance, trackSpan, kilocaloriesOf } from './rules/virtual-ride.mjs';
export const PROFILE_VERSION = 21221;
export const EPOCH_OFFSET = 631065600; // Unix seconds at 1989-12-31 00:00:00 UTC

const ENUM = { id: 0x00, size: 1, invalid: 0xFF }, UINT8 = { id: 0x02, size: 1, invalid: 0xFF }, UINT16 = { id: 0x84, size: 2, invalid: 0xFFFF },
  UINT32 = { id: 0x86, size: 4, invalid: 0xFFFFFFFF }, UINT32Z = { id: 0x8C, size: 4, invalid: 0 };
const NO_RECORDS = 'This recording has no power, cadence or heart-rate data to export.';

/** The FIT SDK's CRC-16 (nibble table). */
export function crc16(bytes, seed = 0) {
  const table = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, 0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400];
  let crc = seed;
  for (const byte of bytes) {
    let tmp = table[crc & 0xF]; crc = (crc >> 4) & 0x0FFF; crc = crc ^ tmp ^ table[byte & 0xF];
    tmp = table[crc & 0xF]; crc = (crc >> 4) & 0x0FFF; crc = crc ^ tmp ^ table[(byte >> 4) & 0xF];
  }
  return crc;
}
const little = (value, size) => Array.from({ length: size }, (_, i) => Math.floor(value / 2 ** (8 * i)) % 256);

class Writer {
  constructor() { this.data = []; this.defined = new Set(); }
  /** `fields`: [number, baseType, value|null]. A definition is written the first time a local message type is used. */
  message(local, global, fields) {
    if (!this.defined.has(local)) {
      this.defined.add(local);
      this.data.push(0x40 | local, 0, 0, ...little(global, 2), fields.length);
      for (const [number, type] of fields) this.data.push(number, type.size, type.id);
    }
    this.data.push(local);
    for (const [, type, value] of fields) this.data.push(...little(value ?? type.invalid, type.size));
  }
}

export const pauses = ridePauses;
const finite = n => typeof n === 'number' && Number.isFinite(n);
/** Warm-up, ramp and cool-down edges (plus the start and the end), shared by the TCX and FIT laps. */
export const phaseBoundaries = (session, end) => [...new Set([0, session.rampStart, session.rampEnd, end].filter(t => finite(t) && t >= 0 && t <= end))].sort((a, b) => a - b);
/** Where the laps start, as offsets from the start of the recording. Tests use the warm-up, ramp and cool-down edges. A workout gets one lap per step
    when it has at most 100 steps, mapped through its pauses. */
export function lapStarts(session, end, pauseList) {
  const plan = session.training, begin = (session.events ?? []).find(e => e.message === 'Training')?.time;
  if (plan?.kind === 'workout' && plan.steps.length > 1 && plan.steps.length <= 100 && begin != null) {
    const starts = [0], sorted = [...pauseList].sort((a, b) => a.stop - b.stop); let active = 0;
    for (const step of plan.steps.slice(0, -1)) {
      active += step.seconds; let wall = begin + active;
      for (const pause of sorted) if (pause.stop <= wall) wall += (pause.resume ?? end) - pause.stop;
      if (wall > starts.at(-1) && wall < end) starts.push(wall);
    }
    return starts;
  }
  return phaseBoundaries(session, end).slice(0, -1);
}
/** One record per second: notifications from the meter, the trainer and the strap arrive separately, and the latest real value of each field in
    that second is kept. Seconds with no value at all, and paused time, are left out. */
function merge(samples, pauseList, end) {
  const records = new Map();
  for (const sample of samples) {
    if (!finite(sample.time) || sample.time < 0 || sample.time > end) continue;
    if (pauseList.some(p => sample.time >= p.stop && sample.time < (p.resume ?? Infinity))) continue;
    const second = Math.floor(sample.time), value = records.get(second) ?? { time: second, heartRate: null, cadence: null, power: null };
    if (sample.heartRate != null) value.heartRate = Math.min(254, Math.max(0, sample.heartRate));
    if (finite(sample.cadence)) value.cadence = Math.min(254, Math.max(0, Math.round(sample.cadence)));
    if (finite(sample.power)) value.power = Math.min(65534, Math.max(0, Math.round(sample.power)));
    records.set(second, value);
  }
  return [...records.values()].filter(r => r.heartRate != null || r.cadence != null || r.power != null).sort((a, b) => a.time - b.time);
}
const stats = values => values.length ? { average: Math.round(values.reduce((a, b) => a + b, 0) / values.length), maximum: values.reduce((m, v) => Math.max(m, v), 0) } : null;
const priorFTP = session => { const p = session.configuration?.priorFTP; return typeof p === 'number' ? p : p?.watts ?? null; };
const serialOf = id => { const hex = String(id ?? '').replace(/[^0-9a-f]/gi, '').slice(0, 8); return Math.max(1, hex.length === 8 ? parseInt(hex, 16) : 0); };

/** The FIT file for a finished recording as a Uint8Array. `utcOffsetSeconds` is the local time zone's offset from UTC at the end of the ride
    (the activity message's local_timestamp); it defaults to this browser's. Throws when the recording is not finished or holds no data. */
export function fitFile(session, { utcOffsetSeconds = null } = {}) {
  const end = session.endedAtOffset;
  if (end == null) throw Error('Finish and save the recording before exporting FIT.');
  if (!session.samples?.length) throw Error(NO_RECORDS);
  const pauseList = pauses(session), records = merge(session.samples, pauseList, end);
  if (!records.length) throw Error(NO_RECORDS);
  const startMs = Date.parse(session.startedAt);
  const fit = offset => Math.max(0, Math.floor(startMs / 1000 + offset - EPOCH_OFFSET));
  const ms = seconds => Math.max(0, Math.round(seconds * 1000));
  const pausedSeconds = pauseList.reduce((n, p) => n + Math.min(end, p.resume ?? end) - Math.min(end, p.stop), 0), timerSeconds = Math.max(0, end - pausedSeconds);
  const startTime = fit(0), endTime = fit(end), writer = new Writer();
  const capped = (value, limit) => Math.min(limit, Math.max(0, Math.round(value))), UINT32_MAX = 4294967294;
  const track = rideTrack(session, { pauses: pauseList, end }), trackBySecond = new Map(track.points.map(p => [p.second, p]));
  const balance = rideBalance(session, track, { pauses: pauseList, end }), leftBySecond = new Map((balance?.seconds ?? []).map(s => [s.second, s.left]));
  let covered = null;

  writer.message(0, 0, [[0, ENUM, 4], [1, UINT16, 255], [2, UINT16, 1], [3, UINT32Z, serialOf(session.id)], [4, UINT32, startTime]]);
  const timer = (type, at) => writer.message(1, 21, [[253, UINT32, fit(at)], [0, ENUM, 0], [1, ENUM, type]]);
  // Records and timer events in time order: start, [stop, start]..., records, final stop.
  const items = records.map(r => ({ time: r.time, order: 1, record: r }));
  for (const pause of pauseList) {
    items.push({ time: pause.stop, order: 0, stop: pause.stop });
    if (pause.resume != null && pause.resume < end) items.push({ time: pause.resume, order: 0, start: pause.resume });
  }
  items.sort((a, b) => a.time - b.time || a.order - b.order);
  timer(0, records[0].time);
  for (const item of items) {
    if (item.record) {
      const point = trackBySecond.get(item.record.time), left = leftBySecond.get(item.record.time); if (point) covered = point.distance;
      writer.message(2, 20, [[253, UINT32, fit(item.record.time)], [3, UINT8, item.record.heartRate], [4, UINT8, item.record.cadence], [7, UINT16, item.record.power],
        [5, UINT32, covered == null ? null : capped(covered * 100, UINT32_MAX)], [6, UINT16, point ? capped(point.speed * 1000, 65534) : null], [30, UINT8, left == null ? null : 0x80 | capped(100 - left, 100)]]);
    }
    else if (item.stop != null) timer(4, item.stop);
    else timer(0, item.start);
  }
  if (!(pauseList.length && pauseList.at(-1).resume == null)) timer(4, end);

  const starts = lapStarts(session, end, pauseList);
  starts.forEach((begin, index) => {
    const finish = index + 1 < starts.length ? starts[index + 1] : end;
    const paused = pauseList.reduce((n, p) => n + Math.max(0, Math.min(finish, p.resume ?? end) - Math.max(begin, p.stop)), 0);
    const lap = trackSpan(track, begin, index + 1 < starts.length ? finish : Infinity), on = lap.seconds > 0;
    writer.message(3, 19, [[254, UINT16, index], [253, UINT32, fit(finish)], [0, ENUM, 9], [1, ENUM, 1], [2, UINT32, fit(begin)], [7, UINT32, ms(finish - begin)],
      [8, UINT32, ms(Math.max(0, finish - begin - paused))], [25, ENUM, 2], [39, ENUM, 6],
      [9, UINT32, on ? capped(lap.distance * 100, UINT32_MAX) : null], [11, UINT16, on ? capped(kilocaloriesOf(lap.joules), 65534) : null], [13, UINT16, on ? capped(lap.distance / lap.seconds * 1000, 65534) : null],
      [14, UINT16, on ? capped(lap.maximumSpeed * 1000, 65534) : null], [41, UINT32, on ? capped(lap.joules, UINT32_MAX) : null]]);
  });
  const ridden = track.seconds > 0;
  const power = stats(records.map(r => r.power).filter(v => v != null)), heart = stats(records.map(r => r.heartRate).filter(v => v != null)), cadence = stats(records.map(r => r.cadence).filter(v => v != null));
  const threshold = priorFTP(session);
  writer.message(4, 18, [[254, UINT16, 0], [253, UINT32, endTime], [0, ENUM, 8], [1, ENUM, 1], [2, UINT32, startTime], [5, ENUM, 2], [6, ENUM, 6],
    [7, UINT32, ms(end)], [8, UINT32, ms(timerSeconds)], [16, UINT8, heart?.average ?? null], [17, UINT8, heart?.maximum ?? null],
    [18, UINT8, cadence?.average ?? null], [19, UINT8, cadence?.maximum ?? null], [20, UINT16, power?.average ?? null], [21, UINT16, power?.maximum ?? null],
    [25, UINT16, 0], [26, UINT16, starts.length], [45, UINT16, finite(threshold) ? Math.min(65534, Math.max(0, Math.round(threshold))) : null],
    [9, UINT32, ridden ? capped(track.distance * 100, UINT32_MAX) : null], [11, UINT16, ridden ? capped(track.kilocalories, 65534) : null], [14, UINT16, ridden ? capped(track.distance / track.seconds * 1000, 65534) : null],
    [15, UINT16, ridden ? capped(track.maximumSpeed * 1000, 65534) : null], [37, UINT16, balance ? 0x8000 | capped((100 - balance.left) * 100, 10000) : null], [48, UINT32, ridden ? capped(track.joules, UINT32_MAX) : null]]);
  const zone = utcOffsetSeconds ?? -new Date(startMs + end * 1000).getTimezoneOffset() * 60;
  writer.message(5, 34, [[253, UINT32, endTime], [0, UINT32, ms(timerSeconds)], [1, UINT16, 1], [2, ENUM, 0], [3, ENUM, 26], [4, ENUM, 1], [5, UINT32, Math.max(0, endTime + zone)]]);

  const header = [14, 0x20, ...little(PROFILE_VERSION, 2), ...little(writer.data.length, 4), ...Array.from('.FIT', c => c.charCodeAt(0))];
  header.push(...little(crc16(header), 2));
  const file = [...header, ...writer.data]; file.push(...little(crc16(file), 2));
  return Uint8Array.from(file);
}
