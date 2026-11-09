// Simulated speed, distance, work and pedal balance. Mirrors Sources/FTPunkDomain/VirtualRide.swift; only + - * / and square roots are used so that
// the FIT files written here and by the app match byte for byte.

const DEFAULT_RIDER_KG = 75, BIKE_KG = 10, AIR_DENSITY = 1.225, ROLLING = 0.0055, DRIVETRAIN = 0.97, GRAVITY = 9.81, HUMAN_EFFICIENCY = 0.24, JOULES_PER_KCAL = 4184;
const finite = n => typeof n === 'number' && Number.isFinite(n);

/** Pause requests, confirmed release and resume are stored as timestamped events. The timer stops at the confirmed release
    (the request when no confirmation was recorded) and starts again at resume. */
export function ridePauses(session) {
  const result = []; let requested = null, confirmed = null;
  for (const event of [...(session.events ?? [])].sort((a, b) => a.time - b.time)) {
    switch (event.message) {
      case 'Training paused; trainer release requested': requested = event.time; confirmed = null; break;
      case 'Trainer release confirmed for pause': if (requested != null && confirmed == null) confirmed = event.time; break;
      case 'Training resumed': if (requested != null) result.push({ stop: confirmed ?? requested, resume: event.time }); requested = null; confirmed = null; break;
    }
  }
  if (requested != null) result.push({ stop: confirmed ?? requested, resume: null });
  return result;
}
const inPause = (pauses, time) => pauses.some(p => time >= p.stop && time < (p.resume ?? Infinity));

/** CdA in m² for a gravel bike on the hoods: 0.07 for the bike, 0.35 for a 75 kg rider, following the tangent at 75 kg of mass^(2/3). */
export const dragArea = riderKG => 0.07 + 0.35 * (75 + 2 * riderKG) / 225;
export const simulatedRiderKG = weight => finite(weight) && weight > 0 ? Math.min(150, Math.max(40, weight)) : DEFAULT_RIDER_KG;
/** The speed in m/s after one second at `watts`, from the energy balance of rider and bike. */
export function virtualStep(speed, watts, riderKG) {
  const mass = riderKG + BIKE_KG;
  const resisting = 0.5 * AIR_DENSITY * dragArea(riderKG) * speed * speed * speed + ROLLING * mass * GRAVITY * speed;
  const energy = 0.5 * mass * speed * speed + watts * DRIVETRAIN - resisting;
  return energy > 0 ? Math.sqrt(2 * energy / mass) : 0;
}
export const kilocaloriesOf = joules => joules / HUMAN_EFFICIENCY / JOULES_PER_KCAL;

const endOf = session => session.endedAtOffset ?? session.samples?.at(-1)?.time ?? 0;

/** Second-by-second simulated speed, distance and work. Paused time adds nothing and the bike restarts from a standstill after it. */
export function rideTrack(session, { pauses = ridePauses(session), end = endOf(session) } = {}) {
  const points = [];
  if (finite(end) && end >= 0) {
    const size = Math.floor(end) + 1, sums = new Float64Array(size), counts = new Int32Array(size); let last = -1;
    for (const s of session.samples ?? []) {
      if (!finite(s.time) || s.time < 0 || s.time > end || !finite(s.power) || inPause(pauses, s.time)) continue;
      const second = Math.floor(s.time); sums[second] += Math.max(0, s.power); counts[second]++; last = Math.max(last, second);
    }
    const weight = simulatedRiderKG(session.configuration?.weightKG);
    let held = null, heldAt = 0, speed = 0, distance = 0, joules = 0, started = false;
    for (let second = 0; second <= last; second++) {
      let watts = 0;
      if (counts[second] > 0) { watts = sums[second] / counts[second]; held = watts; heldAt = second; started = true; }
      else if (inPause(pauses, second)) { speed = 0; held = null; continue; }
      else if (!started) continue;
      else if (held != null && second - heldAt <= 2) watts = held;
      const next = virtualStep(speed, watts, weight);
      distance += (speed + next) / 2; joules += watts; speed = next;
      points.push({ second, power: watts, speed, distance, joules });
    }
  }
  return { points, distance: points.at(-1)?.distance ?? 0, joules: points.at(-1)?.joules ?? 0, seconds: points.length,
    kilojoules: (points.at(-1)?.joules ?? 0) / 1000, kilocalories: kilocaloriesOf(points.at(-1)?.joules ?? 0), averagePower: points.length ? points.at(-1).joules / points.length : null,
    maximumSpeed: points.reduce((m, p) => Math.max(m, p.speed), 0) };
}
/** What the rider is doing now: nothing once the last riding second is more than three seconds old (a pause or a dropout). */
export function speedAt(track, time) { const last = track.points.at(-1); return last && time - last.second <= 3 ? last.speed : 0; }
/** The seconds from `begin` up to, but not including, `finish`. */
export function trackSpan(track, begin, finish) {
  let before = null, after = null, seconds = 0, maximumSpeed = 0;
  for (const p of track.points) {
    if (p.second < begin) { before = p; continue; }
    if (p.second >= finish) break;
    after = p; seconds++; maximumSpeed = Math.max(maximumSpeed, p.speed);
  }
  return after ? { distance: after.distance - (before?.distance ?? 0), joules: after.joules - (before?.joules ?? 0), seconds, maximumSpeed } : { distance: 0, joules: 0, seconds: 0, maximumSpeed: 0 };
}

/** Pedal balance per second of riding, or null. Readings count only in seconds with power: a meter's balance at zero watts means nothing. */
export function rideBalance(session, track = rideTrack(session), { pauses = ridePauses(session), end = endOf(session) } = {}) {
  if (!finite(end) || end < 0) return null;
  const size = Math.floor(end) + 1, sums = new Float64Array(size), counts = new Int32Array(size);
  for (const s of session.samples ?? []) {
    if (!finite(s.time) || s.time < 0 || s.time > end || !finite(s.leftBalance) || s.leftBalance < 0 || s.leftBalance > 100 || inPause(pauses, s.time)) continue;
    const second = Math.floor(s.time); sums[second] += s.leftBalance; counts[second]++;
  }
  const seconds = track.points.filter(p => p.power > 0 && counts[p.second] > 0).map(p => ({ second: p.second, left: sums[p.second] / counts[p.second], power: p.power }));
  if (!seconds.length) return null;
  return { seconds, left: seconds.reduce((n, x) => n + x.left * x.power, 0) / seconds.reduce((n, x) => n + x.power, 0) };
}
/** The last ten seconds of balance readings, or null. */
export function liveBalance(samples) {
  const now = samples.at(-1)?.time; if (now == null) return null;
  let total = 0, count = 0;
  for (let i = samples.length - 1; i >= 0 && now - samples[i].time <= 10; i--) { const s = samples[i]; if (finite(s.leftBalance) && (!finite(s.power) || s.power > 0)) { total += s.leftBalance; count++; } }
  return count ? total / count : null;
}
/** How far the chart's axis reaches either side of 50 %: at least 4 points, in steps of 2, with some room above the largest swing. */
export const balanceAxisReach = points => Math.min(50, Math.max(4, Math.ceil(points.reduce((m, p) => Math.max(m, Math.abs(p.left - 50)), 0) / 2) * 2 + 2));
/** A 30-second power-weighted trailing mean, thinned to at most about 300 points. A gap of more than five seconds starts a new segment. */
export function balanceSeries(balance, maximumPoints = 300) {
  const seconds = balance.seconds, stride = Math.max(1, Math.floor(seconds.length / Math.max(1, maximumPoints))), result = [];
  let first = 0, weighted = 0, work = 0, segment = 0;
  seconds.forEach((entry, index) => {
    if (index > 0 && entry.second - seconds[index - 1].second > 5) { segment++; first = index; weighted = 0; work = 0; }
    weighted += entry.left * entry.power; work += entry.power;
    while (entry.second - seconds[first].second >= 30) { weighted -= seconds[first].left * seconds[first].power; work -= seconds[first].power; first++; }
    if (index - first >= 4 && (index % stride === 0 || index === seconds.length - 1)) result.push({ time: entry.second, left: weighted / work, segment });
  });
  return result;
}
