import { test, assert, equal, near, fixture } from './harness.mjs';
import { rideVisualState, RideVisualMotion, smoothedPower, sprintPower, sprintPeak, zoneForFraction, standingThreshold, trailOf, showsSweat, showsSparks, showsSpeedLines, resolvePlacement, nextPlacement, placementTitle, HeroLayout, LOOP_DISTANCE, LOOP_TIME, Posture, rideVisualInput } from '../src/chaindance/state.mjs';
import { drawRiderSprite } from '../src/chaindance/rider-sprite.mjs';
import { renderRideVisual, riderRows, fingerprint, pixelHash, ink, mixed, Pixels, textWidth, WIDTH, HEIGHT, HERO_HEIGHT } from '../src/chaindance/raster.mjs';
import { cockpitLayout, coachingText, compactClock } from '../src/chaindance/layout.mjs';
import { RampEngine, configuration } from '../src/domain.mjs';

// Mirrors Tests/FTPunkTests/RideVisualTests.swift, RideVisualStandingTests.swift and RideVisualRasterTests.swift, and replays
// contracts/fixtures/chaindance-fingerprints.json (written by ChaindanceFixtureTests.swift from the native renderer): the same
// derived state, the same markers and the same RGBA bytes (FNV-1a 64) for every case.
const sameNumber = (a, b, where) => { if (a == null || b == null) equal(a ?? null, b ?? null); else assert(Math.abs(a - b) <= 1e-8, `${where}: ${a} against ${b}`); };

function stateOf(spec) { return rideVisualState(spec); }
function summary(state) {
  const trail = trailOf(state);
  return { world: state.world, zone: state.zone, posture: state.posture, motion: state.motion, pedalPeriod: state.pedalPeriod, worldSpeed: state.worldSpeed, animationRate: state.animationRate, rainSlant: state.rainSlant,
    district: state.district, glow: state.glow, level: state.level, spire: state.spire, climbSeconds: state.climbSeconds, descent: state.descent, accessibilitySummary: state.accessibilitySummary,
    trailLength: trail.length, trailDim: trail.dim, sweat: showsSweat(state), sparks: showsSparks(state), speedLines: showsSpeedLines(state), sign: state.sign, upcoming: state.upcoming };
}
function compareState(actual, expected, where) {
  for (const key of ['pedalPeriod', 'worldSpeed', 'rainSlant', 'glow', 'spire', 'climbSeconds', 'descent']) sameNumber(actual[key], expected[key], `${where} ${key}`);
  for (const key of ['world', 'zone', 'posture', 'motion', 'animationRate', 'district', 'level', 'accessibilitySummary', 'trailLength', 'trailDim', 'sweat', 'sparks', 'speedLines', 'sign'])
    equal(actual[key] ?? null, expected[key] ?? null);
  if (expected.upcoming == null) equal(actual.upcoming, null);
  else { const { secondsUntil, ...rest } = actual.upcoming, { secondsUntil: expectedSeconds, ...expectedRest } = expected.upcoming; equal(rest, expectedRest); sameNumber(secondsUntil, expectedSeconds, `${where} upcoming`); }
}

test('Chaindance parity: every fixture case has the native state, scenery markers and pixels', async () => {
  const data = await fixture('chaindance-fingerprints');
  equal(data.format, 'ftpunk-chaindance-fingerprints'); assert(data.cases.length > 60);
  const failures = [];
  for (const entry of data.cases) {
    const { spec } = entry, where = spec.name;
    try {
      const first = stateOf(spec.input), state = spec.thenInput ? stateOf(spec.thenInput) : first;
      const motion = new RideVisualMotion(spec.distance, spec.time, spec.crankTurns);
      if (spec.advance) {
        for (let i = 0; i < spec.advance.steps; i++) motion.advance(spec.advance.dt, first);
        if (spec.thenInput) for (let i = 0; i < spec.advance.steps; i++) motion.advance(spec.advance.dt, state);
      }
      compareState(summary(state), entry.state, where);
      sameNumber(motion.distance, entry.motion.distance, `${where} distance`); sameNumber(motion.time, entry.motion.time, `${where} time`); sameNumber(motion.crankTurns, entry.motion.crankTurns, `${where} cranks`);
      equal(motion.markers.map(m => ({ kind: m.kind, text: m.text })), entry.motion.markers.map(m => ({ kind: m.kind, text: m.text })));
      motion.markers.forEach((m, i) => sameNumber(m.worldX, entry.motion.markers[i].worldX, `${where} marker`));
      equal(motion.segments.length, entry.motion.segments.length); motion.segments.forEach((s, i) => { equal(s.district, entry.motion.segments[i].district); sameNumber(s.startX, entry.motion.segments[i].startX, `${where} segment`); });
      const frame = renderRideVisual({ state, motion, animated: spec.animated, highContrast: spec.highContrast, skyRows: spec.skyRows });
      equal([frame.width, frame.height], [entry.width, entry.height]);
      const print = fingerprint(frame.data);
      if (print !== entry.fingerprint) failures.push(`${where}: ${print}, native ${entry.fingerprint}`);
    } catch (error) { failures.push(`${where}: ${error.message}`); }
  }
  assert(failures.length === 0, `${failures.length} of ${data.cases.length} cases differ:\n${failures.join('\n')}`);
});

// ---- state (RideVisualTests) ----
const base = { mode: 'workout', phase: 'riding', cadence: 90, ftp: 250, weightKG: 70 };
test('Zones come from the shared chart thresholds and the rider stands from 7 W/kg', () => {
  equal([0.4, 0.56, 0.76, 0.88, 0.95, 1.06].map(zoneForFraction), [0, 1, 2, 3, 4, 5]); equal(zoneForFraction(NaN), 0); equal(zoneForFraction(Infinity), 5);
  equal(standingThreshold(70, 250), 490); equal(standingThreshold(null, 250), 400); equal(standingThreshold(null, null), null); equal(standingThreshold(0, 0), null);
  assert(rideVisualState({ ...base, power: 100 }).posture !== Posture.standing);
  equal(rideVisualState({ ...base, power: 450, sprintPower: 500, sprintPeak: 510 }).posture, Posture.standing);
  equal(rideVisualState({ ...base, power: 430, sprintPower: 450, sprintPeak: 500 }).posture, Posture.standing); // held at 85 % after a one-second dip
  assert(rideVisualState({ ...base, power: 300, sprintPower: 450, sprintPeak: 500 }).posture !== Posture.standing);
  equal(rideVisualState({ ...base, mode: 'ftpTest', phase: 'ramp', power: 600, sprintPower: 700, sprintPeak: 700, ramp: { phaseSeconds: 300, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 300 } }).posture, Posture.drops, 'never stands in the ramp');
  equal(rideVisualState({ ...base, mode: 'ftpTest', phase: 'cooldown', power: 600, sprintPower: 700, sprintPeak: 700, ramp: { phaseSeconds: 10, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 300 } }).posture, Posture.standing);
  equal(rideVisualState({ ...base, cadence: 0, power: 600, sprintPower: 700, sprintPeak: 700 }).motion, 'coasting');
});
test('Motion: pedalling, coasting, foot down, and power standing in for cadence', () => {
  equal(rideVisualState({ ...base, power: 200 }).motion, 'pedalling'); equal(rideVisualState({ ...base, power: 200, cadence: 5 }).motion, 'coasting'); equal(rideVisualState({ ...base, phase: 'paused', power: 200 }).motion, 'footDown');
  equal(rideVisualState({ ...base, cadenceAvailable: false, cadence: null, power: 100 }).motion, 'pedalling'); equal(rideVisualState({ ...base, cadenceAvailable: false, cadence: null, power: 3 }).motion, 'coasting');
  near(rideVisualState({ ...base, cadence: 90, power: 200 }).pedalPeriod, 60 / 90); near(rideVisualState({ ...base, cadence: 90, power: 200, playbackSpeed: 99 }).animationRate, 4);
  equal(rideVisualState({ ...base, phase: 'paused' }).worldSpeed, 0); equal(rideVisualState({ ...base, phase: 'paused' }).sign, { kind: 'paused', text: 'PAUSED' });
});
test('The FTP test climbs only during the ramp and announces the next level six seconds ahead', () => {
  const ramp = (phase, phaseSeconds, rampSeconds, best) => rideVisualState({ mode: 'ftpTest', phase, power: 250, cadence: 90, ftp: 250, ramp: { phaseSeconds, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds, bestMinuteWatts: best } });
  equal(ramp('warmup', 10, 0).world, 'boulevard'); equal(ramp('ramp', 100, 100).world, 'skyway'); equal(ramp('ramp', 100, 100).sign, { kind: 'level', text: 'LVL 9' });
  equal(ramp('ramp', 100, 100).upcoming, null); equal(ramp('ramp', 103, 103).upcoming.text, 'LVL 10'); equal(ramp('warmup', 56, 0).upcoming.text, 'LVL 1');
  equal(ramp('cooldown', 1, 560, 290).world, 'rooftop'); equal(ramp('cooldown', 1, 560, 290).sign.text, 'LVL 47 · 290 W'); equal(ramp('cooldown', 90, 560).world, 'descent'); equal(ramp('completed', 0, 560).world, 'rooftop');
});
test('A workout step sets the district, and a recovery is calm teal', () => {
  const step = (watts, extra = {}) => rideVisualState({ ...base, power: watts, step: { index: 1, count: 5, startWatts: watts, endWatts: watts, seconds: 300, remaining: 200, ...extra } });
  equal(step(100).district, { kind: 'residential', zone: 0 }); equal(step(250).district, { kind: 'market', zone: 4 }); equal(step(250).sign, { kind: 'step', text: 'STEP 2/5' });
  equal(step(250, { remaining: 8, next: { seconds: 180, startWatts: 100, endWatts: 100 } }).upcoming.text, 'NEXT 3:00 · 100 W');
  equal(step(250, { remaining: 30, next: { seconds: 180, startWatts: 100, endWatts: 100 } }).upcoming, null);
  equal(rideVisualState({ mode: 'resistance', phase: 'riding', cadence: 90, target: 95 }).sign.text, 'RES 9.5'); equal(rideVisualState({ mode: 'freeERG', phase: 'riding', cadence: 90, target: 150 }).sign.text, '150 W');
});
test('Smoothing: a three-second mean that goes stale after two seconds', () => {
  const samples = [{ time: 1, power: 100 }, { time: 2, power: 200 }, { time: 3, power: 300 }, { time: 3.5, heartRate: 120 }];
  equal(smoothedPower(samples, 3), 200); equal(smoothedPower(samples, 4.5), 250); equal(smoothedPower(samples, 6), null); equal(sprintPower(samples, 3), 250);
  equal(sprintPeak(samples, 3), 250); equal(sprintPeak([], 3), null);
});
test('Placement: a stored choice wins, anything else is the strip, and the menu cycles', () => {
  equal(['off', 'strip', 'hero', 'x', null].map(resolvePlacement), ['off', 'strip', 'hero', 'strip', 'strip']); equal(['off', 'strip', 'hero'].map(nextPlacement), ['strip', 'hero', 'off']); equal(placementTitle('hero'), 'Large');
  equal([HeroLayout.stripRows, HeroLayout.heroRows, HeroLayout.skyRows, HeroLayout.readoutFraction], [60, 96, 36, 36 / 96]);
});
test('The scenery loop lengths are the native ones', () => { equal([LOOP_DISTANCE, LOOP_TIME], [1536, 3]); });

// ---- layout and coaching (PresentationRulesTests) ----
test('The cockpit layout puts blocks in two columns only for the Large view on a wide window', () => {
  const wide = cockpitLayout({ phase: 'ramp', rideVisual: 'hero', containerWidth: 1200, kind: 'workout' });
  assert(wide.sideBySide); equal(wide.leftColumn, ['scene', 'progress']); equal(wide.rightColumn, ['tiles', 'controls', 'notes']); equal(wide.maximumContentWidth, 1400);
  equal(cockpitLayout({ phase: 'riding', rideVisual: 'hero', containerWidth: 1200, kind: 'freeRide' }).leftColumn, ['scene', 'controls']); equal(cockpitLayout({ phase: 'ramp', rideVisual: 'hero', containerWidth: 1200 }).rightColumn, ['tiles', 'notes']);
  assert(!cockpitLayout({ phase: 'ramp', rideVisual: 'hero', containerWidth: 899 }).sideBySide); assert(!cockpitLayout({ phase: 'ramp', rideVisual: 'strip', containerWidth: 1200 }).sideBySide);
  assert(!cockpitLayout({ phase: 'ramp', rideVisual: 'hero', containerWidth: 1200, regularWidthClass: false }).sideBySide);
  const big = cockpitLayout({ phase: 'riding', rideVisual: 'hero', accessibilitySize: true, containerWidth: 1200 });
  equal(big.visual, 'strip'); assert(big.compactHeader && big.metricRows && !big.sideBySide && !big.showsCoachingLine);
  assert(cockpitLayout({ phase: 'warmup' }).showsCoachingLine && !cockpitLayout({ phase: 'ramp' }).showsCoachingLine && !cockpitLayout({ phase: 'warmup', rideVisual: 'strip' }).showsCoachingLine);
  equal(compactClock('8:20', 'warmup'), '8:20 left'); equal(compactClock('8:20', 'ramp'), '8:20');
});
test('Coaching: only the FTP test says to stay seated, and the text agrees with a standing rider', () => {
  const ftpState = rideVisualState({ mode: 'ftpTest', phase: 'ramp', power: 300, cadence: 90, ftp: 250, ramp: { phaseSeconds: 100, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 100 } });
  assert(coachingText(ftpState, 'ramp').startsWith('Stay seated')); assert(coachingText(ftpState, 'cooldown').startsWith('Ramp scored'));
  assert(coachingText(rideVisualState({ ...base, power: 200 }), 'riding').startsWith('Keep a steady'));
  assert(coachingText(rideVisualState({ ...base, power: 500, sprintPower: 520, sprintPeak: 520 }), 'riding').startsWith('Sprint'));
});

// ---- raster (RideVisualRasterTests) ----
const countInk = (frame, color, x0 = 0, x1 = WIDTH, y0 = 0, y1 = HEIGHT) => { let n = 0; for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const i = (y * frame.width + x) * 4; if (((frame.data[i] << 16) | (frame.data[i + 1] << 8) | frame.data[i + 2]) === color) n++; } return n; };
const differing = (a, b, x0 = 0, x1 = WIDTH, y0 = 0, y1 = HEIGHT) => { let n = 0; for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const i = (y * a.width + x) * 4; if (a.data[i] !== b.data[i] || a.data[i + 1] !== b.data[i + 1] || a.data[i + 2] !== b.data[i + 2]) n++; } return n; };
const frameOf = (state, o = {}) => renderRideVisual({ state, motion: new RideVisualMotion(o.distance ?? 40, o.time ?? 0.5, o.crank ?? 0), animated: o.animated ?? true, highContrast: o.contrast ?? false, skyRows: o.sky ?? 0 });
const ramped = (power, phase = 'ramp') => rideVisualState({ mode: 'ftpTest', phase, power, cadence: 92, ftp: 250, ramp: { phaseSeconds: 360, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 360, bestMinuteWatts: 290 } });
const working = (power, mode = 'workout') => rideVisualState({ mode, phase: 'riding', power, cadence: 92, ftp: 250, step: mode === 'workout' ? { index: 2, count: 9, startWatts: power, endWatts: power, seconds: 300, remaining: 150 } : null, target: mode === 'freeERG' ? 150 : null });

test('The frame is a fixed 192 × 60 (96 for the Large view) opaque RGBA buffer', () => {
  const strip = frameOf(working(200), { animated: false }), hero = frameOf(working(200), { sky: 36, animated: false });
  equal([strip.width, strip.height, strip.data.length], [192, 60, 192 * 60 * 4]); equal([hero.width, hero.height], [192, 96]); equal(HERO_HEIGHT, 96);
  for (let i = 3; i < strip.data.length; i += 4) if (strip.data[i] !== 255) throw Error('a pixel is not opaque');
  let moved = 0; for (let row = 50; row < 60; row++) for (let x = 0; x < 192; x++) { const a = (row * 192 + x) * 4, b = ((row + 36) * 192 + x) * 4; if (strip.data[a] !== hero.data[b] || strip.data[a + 1] !== hero.data[b + 1] || strip.data[a + 2] !== hero.data[b + 2]) moved++; }
  equal(moved, 0);                                                                                // the road keeps its row offsets from the bottom edge
});
test('The helmet and the zone colour are drawn for every zone, and the rider stays below the sky band', () => {
  const helmet = ink(255, 0, 154);
  for (const [zone, percent] of [0.4, 0.65, 0.8, 0.91, 1.0, 1.2].entries()) {
    const state = working(250 * percent); equal(state.zone, zone); assert(countInk(frameOf(state), helmet, 40, 100, 10, 50) >= 8, `helmet in zone ${zone}`);
  }
  for (const percent of [0.4, 0.65, 1.2, 3]) {
    const s = working(250 * percent, 'freeERG'), a = riderRows({ state: s, animated: false }), b = riderRows({ state: s, animated: false, skyRows: 36 });
    equal(b[0], a[0] + 36); assert(b[0] > 36, `${percent}: rider top row ${b[0]} is inside the readout band`);
  }
});
test('Pedalling turns in four frames, coasting holds still, Reduce Motion is steady, and increase contrast outlines the rider', () => {
  const s = rideVisualState({ ...base, power: 200, cadence: 92 }), coast = rideVisualState({ ...base, power: 200, cadence: 0 });
  const frames = [0, 1, 2, 3].map(i => frameOf(s, { crank: i / 4 + 0.01 }));
  for (let i = 0; i < 4; i++) for (let j = i + 1; j < 4; j++) assert(differing(frames[i], frames[j], 40, 85, 24, 52) > 3, `frames ${i} and ${j}`);
  equal(differing(frameOf(s, { crank: 1.01 }), frames[0]), 0); equal(differing(frameOf(coast, { crank: 0.01 }), frameOf(coast, { crank: 0.6 })), 0);
  const a = frameOf(s, { distance: 10, time: 0.2, crank: 0.3, animated: false }), b = frameOf(s, { distance: 700, time: 2.4, crank: 0.8, animated: false });
  equal(differing(a, b), 0); assert(differing(a, frameOf(s, { distance: 10, time: 0.2, crank: 0.3 })) > 100);
  const plain = frameOf(s, { animated: false }), outlined = frameOf(s, { animated: false, contrast: true }), dark = ink(3, 3, 12);
  assert(countInk(plain, dark) === 0 && countInk(outlined, dark, 30, 110, 10, 58) > 60);
});
test('The climb is endless: the scenery repeats exactly after a loop, and moves in between', () => {
  for (const percent of [0.6, 1.0, 1.2]) {
    const s = ramped(250 * percent), at = (distance, time, crank) => frameOf(s, { distance, time, crank });
    const a = at(120, 0.7, 0.25);
    equal(differing(a, at(120 + LOOP_DISTANCE, 0.7 + LOOP_TIME, 0.25)), 0); equal(differing(a, at(120 + LOOP_DISTANCE * 7, 0.7 + LOOP_TIME * 5, 12.25)), 0);
    assert(differing(a, at(160, 0.7, 0.25)) > 100); assert(differing(a, at(120, 1.0, 0.25)) > 10);
  }
});
test('Pixel helpers: hashing is the native 64-bit mix, colours mix like the native ones, text is 3 × 5', () => {
  equal([pixelHash(3, 0), pixelHash(7, 4), pixelHash(-5, 91), pixelHash(500, 977)].every(v => Number.isInteger(v) && v >= 0 && v <= 0x7fffffff), true);
  equal(mixed(ink(0, 0, 0), ink(255, 255, 255), 0.5), ink(128, 128, 128)); equal(mixed(ink(10, 20, 30), ink(110, 120, 130), 2), ink(110, 120, 130)); equal(textWidth('LVL 12'), 23);
  const canvas = new Pixels(8, 8, ink(1, 2, 3)); canvas.text('1', 0, 0, ink(9, 9, 9)); equal(canvas.ink(1, 0), ink(9, 9, 9)); equal(canvas.ink(0, 0), ink(1, 2, 3)); equal(canvas.ink(100, 100), 0);
});
test('Reading a live ride: smoothed power, scaled workout targets, and the ramp clock', () => {
  const engine = new RampEngine(configuration({ preset: 'standard', priorFTP: 250, weightKG: 71, warmupSeconds: 60, cooldownSeconds: 180, powerSource: 'trainer', cadenceSource: 'trainer' }), { demo: true });
  for (let t = 0; t <= 80; t += 0.5) { engine.receive({ time: t, power: 200, cadence: 90 }); engine.tick(t); }
  const input = rideVisualInput(engine, 80);
  equal([input.mode, input.phase, input.ftp, input.weightKG, input.cadenceAvailable, input.cadence, input.power], ['ftpTest', 'ramp', 250, 71, true, 90, 200]);
  equal([input.ramp.warmupSeconds, input.ramp.stepSeconds, input.ramp.rampSeconds], [60, 12, 20]);
  assert(rideVisualState(input).world === 'skyway');
});

test('Sprite rider (RG SP design): rider A in rider D colours, drawn only when the scene asks for it', () => {
  const state = working(200, 'freeERG'), motion = () => new RideVisualMotion(40, 0.5, 0.3);
  const plain = renderRideVisual({ state, motion: motion(), animated: true, skyRows: 0 });
  const sprite = renderRideVisual({ state, motion: motion(), animated: true, skyRows: 0, sprite: drawRiderSprite });
  assert(differing(plain, sprite) > 0, 'the sprite changes the frame');
  assert(countInk(sprite, 0xf5d020) > 20, 'yellow helmet and shorts');
  assert(countInk(sprite, 0x7a4ae0) > 20, 'violet jersey');
  equal(countInk(sprite, 0x00b8a8), 0, 'no rider A teal');
  const again = renderRideVisual({ state, motion: motion(), animated: true, skyRows: 0, sprite: drawRiderSprite });
  equal(differing(again, sprite), 0);
});
