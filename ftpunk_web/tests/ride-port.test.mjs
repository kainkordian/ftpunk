import { test, assert, equal, near } from './harness.mjs';
import { RampEngine, configuration } from '../src/domain.mjs';
import { RideController } from '../src/controller.mjs';
import { skipMessage } from '../src/training.mjs';
import { rideTrack } from '../src/rules/virtual-ride.mjs';
import { rideSummary, targetSeries, targetValue, rideMoment, WorkoutClock } from '../src/rules/ride-summary.mjs';
import { heartRateVariability, beats, rmssd, alpha1 } from '../src/rules/hrv.mjs';
import { heartLinePath, targetBoxState, nextStepText, rideFigures, FIGURES } from '../src/rules/dashboard.mjs';
import { rideCharts, summaryCard, alpha1Chart } from '../src/ui/charts.mjs';
// Mirrors Tests/FTPunkTests/WorkoutFeaturesTests.swift (skipping a step), RideSummaryTests.swift (trainer power, a moment of the recording) and
// HeartRateVariabilityTests.swift, with the same numbers. The FIT hold tests are in intervals-files.test.mjs.

const plan = (name, steps) => ({ version: 2, kind: 'workout', name, ftpWatts: null, steps: steps.map(([n, seconds, watts]) => ({ name: n, seconds, watts })) });

test('Skipping a step moves the training clock, and the recorded target and heart rate follow', () => {
  const engine = new RampEngine(configuration({ warmupSeconds: 0 }), { training: plan('Skips', [['Warm', 20, 100], ['Work', 20, 200], ['Cool', 20, 120]]) });
  for (let t = 0; t <= 5; t++) { engine.receive({ time: t, power: 100, cadence: 90, heartRate: 120 + t }); engine.tick(t); }
  equal(engine.currentStep.index, 0); assert(engine.canSkipStep);
  assert(engine.skipStep(5));
  equal([engine.currentStep.index, engine.target, engine.trainingElapsed], [1, 200, 20]);
  assert(engine.pause(6)); assert(engine.skipStep(6)); equal(engine.currentStep.index, 2);
  assert(!engine.canSkipStep); assert(!engine.skipStep(6));
  for (let t = 6; t <= 9; t++) engine.receive({ time: t, power: 120, cadence: 90, heartRate: 130 });
  assert(engine.resume(9)); engine.tick(9); equal(engine.target, 120);
  const clock = WorkoutClock.of(engine.session);
  equal([clock.trainingTime(4), clock.trainingTime(5), clock.trainingTime(7), clock.trainingTime(9)], [4, 20, null, 40]);
  assert(targetSeries(engine.session).some(p => p.time === 5 && p.watts === 200));
  const heart = clock.heartRate(engine.session);
  equal(heart[0].time, 0); assert(heart.some(p => p.time === 20 && p.bpm === 125)); assert(!heart.some(p => p.time > 20 && p.time < 40));
});
test('The skip event reads like the native one, and only workouts skip', () => {
  equal(skipMessage(15, 1), 'Skipped ahead 15.0 s to step 2'); equal(skipMessage(0.25, 4), 'Skipped ahead 0.3 s to step 5');
  const engine = new RampEngine(configuration({ warmupSeconds: 0 }), { training: plan('Two', [['A', 20, 100], ['B', 20, 150]]) });
  assert(!engine.canSkipStep && !engine.skipStep(0)); // still waiting
  for (let t = 0; t <= 4; t++) { engine.receive({ time: t, power: 100, cadence: 90 }); engine.tick(t); }
  assert(engine.skipStep(4)); equal(engine.session.events.at(-1), { time: 4, message: 'Skipped ahead 16.0 s to step 2' });
  assert(!engine.skipStep(3)); // time runs backwards
  const free = new RampEngine(configuration({ warmupSeconds: 0 }), { training: { version: 2, kind: 'freeRide', name: 'Free', ftpWatts: null, steps: [{ name: 'Free', seconds: 3600, watts: 150 }] } });
  for (let t = 0; t <= 4; t++) { free.receive({ time: t, power: 100, cadence: 90 }); free.tick(t); }
  assert(!free.canSkipStep && !free.skipStep(4));
  const test = new RampEngine(configuration({ warmupSeconds: 0 })); assert(!test.canSkipStep);
});
test('The controller skips through the normal tick path and restarts the matching settle', () => {
  const controller = new RideController({ onReading: null }, { put: async () => {} }, { now: () => 0 });
  controller.demo = true; controller.engine = new RampEngine(configuration({ warmupSeconds: 0 }), { demo: true, training: plan('S', [['A', 20, 100], ['B', 20, 150], ['C', 20, 120]]) });
  controller.store = { put: async () => {} };
  let restarted = 0; controller.restartMatching = () => restarted++;
  for (let t = 0; t <= 3; t++) { controller.elapsed = t; controller.engine.receive({ time: t, power: 100, cadence: 90 }); controller.engine.tick(t); }
  controller.skipStep(); equal([controller.engine.currentStep.index, controller.engine.target, restarted], [1, 150, 1]);
  controller.trainingTransition = 'pausing'; controller.skipStep(); equal(controller.engine.currentStep.index, 1);
});

const meterConfig = () => configuration({ warmupSeconds: 0, powerSource: 'externalPowerMeter', cadenceSource: 'externalPowerMeter' });
const baseSession = (config = configuration({ warmupSeconds: 0 })) => ({ id: 'x', startedAt: '2026-11-11T10:00:00Z', configuration: config, training: null, samples: [], events: [], devices: [], isDemo: false, outcome: null, result: null, endedAtOffset: null });
test('Trainer power is summarised only while a meter is the source', () => {
  const session = baseSession(meterConfig());
  for (let t = 0; t <= 120; t++) { session.samples.push({ time: t, power: 200, cadence: 90 }); session.samples.push({ time: t + 0.4, trainerPower: 210 }); }
  session.endedAtOffset = 120.4;
  const summary = rideSummary(session);
  near(summary.averagePower, 200, 0.001); near(summary.trainerAveragePower, 210, 0.001); near(summary.trainerNormalizedPower, 210, 0.001);
  const trainerOnly = baseSession(); trainerOnly.samples = Array.from({ length: 121 }, (_, t) => ({ time: t, power: 200, trainerPower: 200 }));
  equal(rideSummary(trainerOnly).trainerAveragePower, null); equal(rideSummary(trainerOnly).trainerNormalizedPower, null);
  // Paused samples are excluded from the trainer figures too.
  const paused = structuredClone(session); paused.events = [{ time: 50, message: 'Training paused; trainer release requested' }, { time: 70, message: 'Training resumed' }];
  paused.samples = paused.samples.map(s => s.time >= 50 && s.time < 70 && s.trainerPower != null ? { ...s, trainerPower: 900 } : s);
  near(rideSummary(paused).trainerAveragePower, 210, 0.001);
});
test('A moment of the recording has every fresh reading', () => {
  const engine = new RampEngine(configuration({ warmupSeconds: 0 }), { training: plan('Hover', [['Warm', 20, 100], ['Work', 40, 200]]) });
  for (let t = 0; t <= 30; t++) { engine.receive({ time: t, power: 205, cadence: 90, heartRate: 140 }); engine.tick(t); }
  const moment = rideMoment(engine.session, 25.5);
  equal([moment.power, moment.heartRate, moment.cadence, moment.trainerPower], [205, 140, 90, null]);
  equal(moment.target, targetValue(engine.session, 25.5)); equal(moment.target, 200);
  const stale = rideMoment(engine.session, 40); equal([stale.power, stale.heartRate], [null, null]);
  const paired = baseSession(meterConfig());
  for (let t = 0; t <= 10; t++) { paired.samples.push({ time: t, power: 200, cadence: 90 }); paired.samples.push({ time: t + 0.4, trainerPower: 190 }); }
  const both = rideMoment(paired, 5.5); equal([both.power, both.trainerPower], [200, 190]);
});

/** Deterministic noise in -0.5...0.5 (the native test's 64-bit generator). */
function noiseFrom(seed) {
  let state = BigInt(seed);
  return () => { state = BigInt.asUintN(64, state * 6364136223846793005n + 1442695040888963407n); return Number(state >> 11n) / 2 ** 53 - 0.5; };
}
test('DFA alpha1 separates uncorrelated from strongly correlated beats', () => {
  const noise = noiseFrom(7), white = Array.from({ length: 2000 }, () => 0.8 + 0.05 * noise());
  const walk = []; let level = 0; for (let i = 0; i < 2000; i++) { level += 0.002 * noise(); walk.push(0.8 + level); }
  assert(Math.abs(alpha1(white) - 0.5) < 0.1, `white ${alpha1(white)}`); assert(Math.abs(alpha1(walk) - 1.5) < 0.15, `walk ${alpha1(walk)}`);
  equal(alpha1(white.slice(0, 49)), null);
});
test('RMSSD is the root mean square of successive differences', () => {
  const alternating = Array.from({ length: 40 }, (_, i) => i % 2 === 0 ? 0.80 : 0.82);
  near(rmssd(alternating), 20, 1e-9); equal(rmssd(alternating.slice(0, 29)), null);
});
test('Ride HRV times beats, rejects artifacts and skips windows with too many', () => {
  const session = baseSession(), noise = noiseFrom(3); let time = 0, beat = 0;
  while (time < 600) {
    let interval = 0.8 + 0.04 * noise();
    if (time > 360 && time < 480 && beat % 5 === 0) interval *= 2;
    time += interval; beat++; session.samples.push({ time, heartRate: 75, rrIntervals: [interval] });
  }
  session.endedAtOffset = time;
  const list = beats(session); equal(list.length, session.samples.length); assert(Math.abs(list[10].time - session.samples[10].time) < 1e-9);
  const result = heartRateVariability(session);
  assert(result.artifactShare > 0.02 && result.artifactShare < 0.06, `share ${result.artifactShare}`);
  assert(result.rmssd > 10 && result.rmssd < 30, `rmssd ${result.rmssd}`);
  assert(result.alpha1.length > 0); assert(!result.alpha1.some(p => p.time > 400 && p.time < 480));
  assert(result.alpha1.every(p => p.alpha1 > 0.2 && p.alpha1 < 0.9));
  const two = baseSession(); two.samples = [{ time: 10, heartRate: 70, rrIntervals: [0.9, 0.8] }];
  const placed = beats(two).map(b => b.time); near(placed[0], 9.2, 1e-9); near(placed[1], 10, 1e-9);
  equal(heartRateVariability(two), null);
});
test('No alpha1 window spans a gap over three seconds', () => {
  const session = baseSession(); let time = 0;
  while (time < 400) { const gap = time > 190 && time < 200 ? 0 : 1; time += 0.8; if (!(time > 195 && time < 199.5)) session.samples.push({ time, rrIntervals: [0.8 + 0.01 * Math.sin(time * 7)] }); }
  const result = heartRateVariability(session);
  assert(!result.alpha1.some(p => p.time - 120 < 195 && p.time > 195));
});

// ---- the dashboard's data, and the ride overview ----
test('The heart-rate line scales to 200 bpm and breaks at gaps over five seconds', () => {
  equal(heartLinePath([{ time: 0, bpm: 100 }], 100), '');
  equal(heartLinePath([{ time: 0, bpm: 100 }, { time: 5, bpm: 100 }, { time: 20, bpm: 200 }], 100), 'M0.0 50.0L50.0 50.0M200.0 0.0');
  assert(heartLinePath([{ time: 0, bpm: 100 }, { time: 1, bpm: 250 }], 10).includes('L100.0 0.0'), 'a reading above 200 raises the scale');
});
test('The target box, the next-step line and the figure list follow native', () => {
  equal(targetBoxState({ resistanceLevel: 55, paused: false, target: null, resumeTarget: null }), { caption: 'Resistance', value: '5.5', unit: '' });
  equal(targetBoxState({ resistanceLevel: null, paused: true, target: 200, resumeTarget: 180 }), { caption: 'Paused · resumes at', value: '180', unit: 'W' });
  equal(targetBoxState({ resistanceLevel: null, paused: false, target: 200, resumeTarget: null }).value, '200');
  const steps = [{ name: 'A', seconds: 60, watts: 100 }, { name: 'B', seconds: 120, watts: 200 }];
  equal(nextStepText({ current: { index: 0 }, steps, intensity: 105, waiting: false }), { label: 'NEXT ▸ ', text: 'B · 2 min · 210 W' });
  equal(nextStepText({ current: { index: 1 }, steps, intensity: 100, waiting: false }).text, 'LAST STEP'); equal(nextStepText({ current: null, steps, intensity: 100, waiting: true }).text, 'Start pedaling to begin.');
  equal(FIGURES.length, 11); equal(FIGURES.at(-1).id, 'balance');
});
test('Figures are blank before riding and the balance box hides until a leg split is reported', () => {
  const session = baseSession(), track = rideTrack(session);
  const figs = rideFigures(session, track); equal(figs.length, 11); assert(figs.every(f => f.value == null)); assert(figs.find(f => f.id === 'balance').hidden);
});
const hrvSession = () => {
  const session = baseSession(meterConfig()), noise = noiseFrom(3); let time = 0, beat = 0;
  while (time < 600) { time += 0.8 + 0.04 * noise(); beat++; session.samples.push({ time, power: 200, trainerPower: 190, heartRate: 75, cadence: 90, rrIntervals: [time - (session.samples.at(-1)?.time ?? 0)] }); }
  session.endedAtOffset = time; return session;
};
test('The ride overview lists trainer power and HRV, draws the alpha1 chart, and the hover only moves the overlay', async () => {
  const session = hrvSession(), card = summaryCard(session);
  for (const label of ['Trainer power (average)', 'Trainer power (normalized)', 'HRV (RMSSD)']) assert(card.includes(label), label);
  assert(!card.includes('Beat artifacts'), 'a clean recording has no artifact row');
  const plain = baseSession(); plain.samples = [{ time: 1, power: 100 }, { time: 2, power: 100 }]; plain.endedAtOffset = 2; assert(!summaryCard(plain).includes('HRV')); assert(!summaryCard(plain).includes('Trainer power'));
  const html = rideCharts(session); assert(html.includes('alpha-chart') && html.includes('0.75 ≈ aerobic threshold') && html.includes('class="reference"')); equal(alpha1Chart(plain), '');
  const host = document.createElement('div'); host.style.cssText = 'width:600px'; host.innerHTML = html; document.body.append(host);
  try {
    const svg = host.querySelector('svg.power-chart'), box = svg.getBoundingClientRect(), paths = host.querySelectorAll('polyline').length, wrap = host.querySelector('.ride-charts');
    svg.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: box.left + box.width / 2, clientY: box.top + 10 }));
    const card1 = host.querySelector('.hover-card'); assert(!card1.hidden, 'the card shows'); assert(/Power 200 W/.test(card1.textContent) && /Heart rate 75 bpm/.test(card1.textContent) && /Trainer 190 W/.test(card1.textContent), card1.textContent);
    assert([...host.querySelectorAll('.hover-rule')].every(r => r.getAttribute('visibility') === 'visible'), 'a rule on every chart'); equal(host.querySelectorAll('polyline').length, paths); assert(host.querySelector('.ride-charts') === wrap);
    host.dispatchEvent(new PointerEvent('pointerout', { bubbles: true, relatedTarget: document.body })); svg.dispatchEvent(new PointerEvent('pointerout', { bubbles: true, relatedTarget: document.body }));
    assert(card1.hidden && [...host.querySelectorAll('.hover-rule')].every(r => r.getAttribute('visibility') === 'hidden'), 'leaving clears it');
  } finally { host.remove(); }
});
