import { test, assert, equal, near, fixture } from './harness.mjs';
import { PowerMatcher, TrainerWarmth, matchingStatusText } from '../src/matching.mjs';
import { PowerRange } from '../src/protocol.mjs';

// Mirrors Tests/FTPunkTests/PowerMatchingTests.swift, and replays contracts/fixtures/power-matching-replay.json (written by
// PowerMatchingFixtureTests.swift from the native matcher): every command within 0.01 W, every status kind and warm-up percent exactly.
const wide = new PowerRange(0, 1000, 1), warm = () => new TrainerWarmth(200);
/** One second of a perfect ERG trainer whose own reading is `reported` and a meter that reads `meter`. */
const ask = (matcher, { target, meter, reported, cadence = 90, at, range = wide, warmth = new TrainerWarmth() }) =>
  matcher.command(target, { time: at, watts: meter }, { time: at, watts: reported }, cadence, at, range, warmth);

test('Matching replay: the JavaScript matcher answers every second like the native one', async () => {
  const data = await fixture('power-matching-replay');
  equal(data.format, 'ftpunk-power-matching-replay'); equal(data.rides.length, 6);
  const seen = new Set(); let seconds = 0;
  for (const ride of data.rides) {
    const range = new PowerRange(ride.range.minimum, ride.range.maximum, ride.range.increment), matcher = new PowerMatcher(), warmth = new TrainerWarmth(ride.warmthKJ);
    warmth.beginSession();
    ride.rows.forEach(([second, target, meterTime, meterWatts, trainerWatts, cadence, restart], i) => {
      const trainer = { time: second, watts: trainerWatts }, meter = meterTime == null ? null : { time: meterTime, watts: meterWatts };
      warmth.add(trainer);
      if (restart) matcher.restartSettle(second);
      const command = matcher.command(target, meter, trainer, cadence, second, range, warmth), [expected, kind, percent, gain, offset, kilojoules] = ride.outputs[i];
      const where = `${ride.name} at ${second} s`;
      assert(Math.abs(command - expected) <= 0.01, `${where}: command ${command}, native ${expected}`);
      equal(matcher.status.kind, kind); equal(matcher.status.percent ?? null, percent);
      if (kind === 'matching') { near(matcher.status.gain, gain, 1e-6); near(matcher.status.offset, offset, 1e-5); }
      if (kind === 'fadeHold') { near(matcher.gain, gain, 1e-6); near(matcher.offset, offset, 1e-5); }
      near(warmth.kilojoules, kilojoules, 1e-6);
      seen.add(kind); seconds++;
    });
  }
  equal([...seen].sort(), ['fadeHold', 'matching', 'warming']); assert(seconds > 3000);
});
test('Power matching converges with either meter offset and never learns before the target settles', () => {
  for (const bias of [-20, 20]) {
    const matcher = new PowerMatcher(); let command = 250;
    for (let second = 0; second <= 100; second++) {
      const previous = command;
      command = ask(matcher, { target: 250, meter: command + bias, reported: command, at: second });  // the trainer holds its own reading; the meter disagrees by a constant
      assert(Math.abs(command - previous) <= 6); assert(command >= 200 && command <= 300);
      if (second < 4) equal(command, 250);
    }
    assert(Math.abs(command + bias - 250) <= 3, `converged to ${command + bias}`);
  }
});
test('Matching waits for fresh samples and settling, and does not learn from exhaustion', () => {
  const matcher = new PowerMatcher(), w = warm();
  for (let second = 0; second <= 10; second++) ask(matcher, { target: 250, meter: 235, reported: 250, at: second, warmth: w });
  const count = matcher.measurementCount, gain = matcher.gain; assert(count > 0 && gain < 1);
  for (let second = 11; second <= 20; second++) matcher.command(250, { time: 10, watts: 150 }, { time: second, watts: 250 }, 90, second, wide, w); // a meter that stops arriving teaches nothing
  assert(matcher.measurementCount === count && matcher.gain === gain);
  for (let second = 21; second <= 40; second++) ask(matcher, { target: 250, meter: second < 30 ? 0 : 50, reported: second < 30 ? 0 : 60, cadence: second < 30 ? 90 : 30, at: second, warmth: w }); // standing still, then low cadence
  assert(matcher.measurementCount === count && matcher.gain === gain);
  for (let second = 41; second <= 44; second++) ask(matcher, { target: 275, meter: 200, reported: 275, at: second, warmth: w }); // a new target is not learned from for 4 s
  equal(matcher.measurementCount, count);
});
test('A new target gets its corrected command in the same tick', () => {
  const matcher = new PowerMatcher(), w = warm();
  for (let second = 0; second <= 120; second++) ask(matcher, { target: 150, meter: (matcher.correction + 150) / 1.05, reported: matcher.correction + 150, at: second, warmth: w }); // the trainer reads 5 % high
  const command = ask(matcher, { target: 200, meter: 150, reported: 150, at: 121, warmth: w });
  assert(command >= 205 && command <= 215, `command ${command}`);
});
test('Commands are limited to the trainer range and to 20 % (35 % while warming)', () => {
  const range = new PowerRange(50, 260, 5), matcher = new PowerMatcher(), low = new PowerMatcher();
  for (let second = 0; second <= 300; second++) { const command = ask(matcher, { target: 250, meter: 100, reported: 250, at: second, range, warmth: warm() }); assert(command <= 260 && command % 5 === 0); }
  for (let second = 0; second <= 300; second++) assert(ask(low, { target: 200, meter: 300, reported: 200, at: second, range, warmth: warm() }) >= 160);
  // An estimate that wants far more than the cap: a cold trainer may be corrected by 35 %, a warm one by 20 %.
  const coldOne = new PowerMatcher(), warmOne = new PowerMatcher(); coldOne.gain = 0.6; warmOne.gain = 0.6;
  equal(ask(coldOne, { target: 200, meter: 100, reported: 200, at: 0, warmth: new TrainerWarmth(10) }), 270); equal(ask(warmOne, { target: 200, meter: 100, reported: 200, at: 0, warmth: warm() }), 240);
});
test('The fade guard freezes the estimate and never raises the correction', () => {
  const matcher = new PowerMatcher(), w = warm(); let command = 200;
  for (let second = 0; second <= 60; second++) command = ask(matcher, { target: 200, meter: 190 * command / 200, reported: command, at: second, warmth: w });
  assert(matcher.correction > 0 && matcher.status.kind !== 'fadeHold');
  for (let second = 61; second <= 70; second++) ask(matcher, { target: 200, meter: 150, reported: 150, at: second, warmth: w }); // the trainer can no longer hold its own command
  assert(matcher.status.kind === 'fadeHold' && matcher.isFading);
  const frozenGain = matcher.gain, frozenCorrection = matcher.correction;
  for (let second = 71; second <= 80; second++) ask(matcher, { target: 200, meter: 150, reported: 150, at: second, warmth: w });
  assert(matcher.gain === frozenGain && matcher.correction <= frozenCorrection);
  ask(matcher, { target: 225, meter: 150, reported: 150, at: 81, warmth: w });
  assert(matcher.correction <= frozenCorrection);
  for (let second = 82; second <= 92; second++) ask(matcher, { target: 225, meter: 215, reported: matcher.correction + 225, at: second, warmth: w }); // 5 s of the trainer holding lifts the guard
  assert(!matcher.isFading); assert(matcher.fadeSeconds > 0);
});
test('Pausing and resuming keeps the estimate', () => {
  const matcher = new PowerMatcher(), w = warm();
  for (let second = 0; second <= 90; second++) ask(matcher, { target: 180 + Math.trunc(second / 30) * 20, meter: 0.96 * matcher.correction + 170, reported: 180 + Math.trunc(second / 30) * 20, at: second, warmth: w });
  const before = [matcher.gain, matcher.offset, matcher.covariance.gain, matcher.covariance.cross, matcher.covariance.offset];
  matcher.restartSettle(91);
  ask(matcher, { target: 240, meter: 230, reported: 240, at: 400, warmth: w }); // resumes much later
  equal([matcher.gain, matcher.offset, matcher.covariance.gain, matcher.covariance.cross, matcher.covariance.offset], before);
});
test('Warmth counts trainer kilojoules and survives new sessions only', () => {
  const warmth = new TrainerWarmth();
  assert(warmth.isWarming && warmth.coldness === 1 && warmth.percentOfWarmup === 0);
  for (let second = 0; second <= 300; second++) warmth.add({ time: second, watts: 200 });
  assert(Math.abs(warmth.kilojoules - 60) < 0.5, `300 s at 200 W is 60 kJ, got ${warmth.kilojoules}`); assert(!warmth.isWarming && warmth.coldness > 0.95);
  for (let second = 301; second <= 900; second++) warmth.add({ time: second, watts: 200 });
  equal(warmth.coldness, 0);
  warmth.beginSession(); const kJ = warmth.kilojoules; warmth.add({ time: 0, watts: 300 }); warmth.add({ time: 1, watts: 300 });
  near(warmth.kilojoules - kJ, 0.3, 1e-9);                   // a new session's clock restarts without counting the gap
  const gap = new TrainerWarmth(); gap.add({ time: 0, watts: 1000 }); gap.add({ time: 60, watts: 1000 }); near(gap.kilojoules, 3);  // gaps count as 3 s
});
test('Matching tracks ramp steps with a delayed trainer response', () => {
  const matcher = new PowerMatcher(), w = warm(); let command = 200, delivered = 180;
  for (let half = 0; half <= 1200; half++) {
    const time = half / 2, target = 200 + Math.trunc(time / 60) * 20;
    delivered += (command / 1.08 - delivered) * (1 - Math.exp(-0.5 / 4));    // a four-second response; the trainer reads 8 % high
    command = matcher.command(target, { time, watts: delivered }, { time, watts: delivered * 1.08 }, 90, time, wide, w);
    if (time > 240 && Math.trunc(time) % 60 >= 45) assert(Math.abs(delivered - target) < 5, `t ${time}: ${delivered} against ${target}`);
  }
});
test('A second ride on the same connection starts warm; a first ride says warming', () => {
  const range = wide, w = new TrainerWarmth(150); w.beginSession();
  const second = new PowerMatcher(); second.command(125, null, null, null, 0, range, w);
  equal(second.status, { kind: 'matching', gain: 1, offset: 0 }); equal(w.coldness, 0);
  const first = new PowerMatcher(); first.command(125, null, null, null, 0, range, new TrainerWarmth());
  equal(first.status, { kind: 'warming', percent: 0 });
});
test('Matching status text names what the matcher is doing', () => {
  equal(matchingStatusText({ kind: 'off' }), ''); assert(matchingStatusText({ kind: 'warming', percent: 40 }).includes('40 %'));
  assert(matchingStatusText({ kind: 'matching', gain: 1.0234, offset: -3.04 }).includes('1.023') && matchingStatusText({ kind: 'matching', gain: 1, offset: -3.04 }).includes('−3.0 W'));
  assert(matchingStatusText({ kind: 'fadeHold' }).toLowerCase().includes('fade'));
});
