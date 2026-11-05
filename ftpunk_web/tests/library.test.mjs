import { test, assert, equal, near, throws, fixture } from './harness.mjs';
import { CATALOG, classics, definition, definitionsIn, planFor, retargetExample, intensityLabel, mainSetWatts, categoryTitle, CATEGORIES } from '../src/catalog.mjs';
import { previewSteps, previewGroups, mainSetText, profileBars, profileSegments, peakWatts, averageWatts, zoneFor, zoneTitle, stepAtFraction } from '../src/rules/preview.mjs';
import { DurationFormat } from '../src/rules/presentation.mjs';
import { validatePlan, duration } from '../src/training.mjs';
import { validateCachedWorkout, ScheduledDate } from '../src/workouts.mjs';

test('The classic library equals the shared fixture at 250 W, field for field', async () => {
  const expected = await fixture('workout-library-250w');
  equal(expected.format, 'ftpunk-workout-library'); equal(expected.ftpWatts, 250);
  const actual = classics(250).map(c => ({ id: c.id, name: c.plan.name, category: c.category, durationSeconds: duration(c.plan), steps: c.plan.steps }));
  equal(actual.length, expected.workouts.length); equal(actual.length, 14);
  for (const [i, workout] of expected.workouts.entries()) {
    equal(actual[i].id, workout.id); equal(actual[i].name, workout.name); equal(actual[i].category, workout.category); equal(actual[i].durationSeconds, workout.durationSeconds);
    equal(actual[i].steps, workout.steps);
  }
});
test('Library warm-ups, cool-downs and recoveries are flat, and no classic contains a ramp', () => {
  for (const { plan } of classics(250)) assert(plan.steps.every(s => s.endWatts == null) && plan.version === 1, plan.name);
  const sweet = classics(250).find(c => c.id === 'sweet-spot-3x10').plan;
  equal(sweet.steps[0], { name: 'Warm-up', seconds: 600, watts: 125 }); equal(sweet.steps.at(-1), { name: 'Cool-down', seconds: 300, watts: 125 });
});
test('Classics need an FTP, follow the current one and keep whole watts', () => {
  throws(() => classics(null)); throws(() => planFor(definition('tempo-3x5'), 0)); throws(() => planFor(definition('tempo-3x5'), Infinity));
  equal(planFor(definition('sweet-spot-3x10'), 250).steps[1].watts, 225); equal(planFor(definition('sweet-spot-3x10'), 200).steps[1].watts, 180);
  equal(planFor(definition('sweet-spot-3x10'), 250).ftpWatts, 250); equal(definition('nope'), null);
  equal(definition('sweet-spot-3x10').duration, 3300); equal(definitionsIn('vo2max').map(d => d.id), ['vo2max-5x3', 'vo2max-4x4']); equal(definitionsIn(null).length, 14);
  equal(CATEGORIES.map(c => c.title), ['Endurance', 'Tempo', 'Sweet spot', 'Over-unders', 'Threshold', 'VO2max']); equal(categoryTitle('sweetSpot'), 'Sweet spot');
});
test('A new FTP retargets the main set of a library workout', () => {
  equal(retargetExample(250, 188).text, 'Sweet spot 3×10: 225 → 169 W');
  equal(retargetExample(null, 188), null); equal(retargetExample(250, NaN), null); equal(retargetExample(250, 188, 'nope'), null);
});
test('Intensity labels describe the hardest constant step', () => {
  const plan = (watts, ftp = 200) => ({ ftpWatts: ftp, steps: [{ name: 'Ramp', seconds: 60, watts: 100, endWatts: 190 }, { name: 'Main', seconds: 600, watts }] });
  equal(intensityLabel(plan(100)), 'Easy · active recovery'); equal(intensityLabel(plan(130)), 'Endurance'); equal(intensityLabel(plan(170)), 'Tempo');
  equal(intensityLabel(plan(200)), 'Threshold'); equal(intensityLabel(plan(240)), 'VO2max and above'); equal(intensityLabel(plan(240, null)), 'Custom power targets');
  equal(mainSetWatts(plan(170)), 170);
});
test('The workout preview equals the Swift fixture: main set, durations, step texts with values on and off, groups and bars', async () => {
  const expected = await fixture('workout-preview-250w');
  equal(expected.format, 'ftpunk-workout-preview'); equal(expected.workouts.length, 14);
  const strip = steps => steps.map(({ name, valueText, spokenText, wattsText, durationText, zone, percentText }) => ({ name, valueText, spokenText, wattsText, durationText, zone: zoneTitle(zone), percentText }));
  for (const want of expected.workouts) {
    const plan = planFor(definition(want.id), 250), label = want.id;
    equal([label, duration(plan)], [label, want.durationSeconds]); equal(DurationFormat.workout(duration(plan)), want.durationText); equal(intensityLabel(plan), want.intensityLabel); equal(mainSetWatts(plan), want.mainSetWatts);
    equal([label, mainSetText(plan)], [label, want.mainSetText]); equal(mainSetText(plan, 100, false), want.mainSetTextNoValues); equal(mainSetText(plan, 110), want.mainSetText110);
    near(averageWatts(plan), want.averageWatts, 1e-6);
    equal(strip(previewSteps(plan)), want.steps); equal(strip(previewSteps(plan, 100, false)), want.stepsNoValues); equal(strip(previewSteps(plan, 110)), want.steps110);
    equal(previewGroups(plan).map(g => ({ start: g.start, end: g.end, repeats: g.repeats, text: g.text })), want.groups);
    const bars = profileBars(plan); equal(bars.length, want.bars.length);
    for (const [i, bar] of want.bars.entries()) { near(bars[i].start, bar.start, 1e-6); near(bars[i].end, bar.end, 1e-6); near(bars[i].startHeight, bar.startHeight, 1e-6); near(bars[i].endHeight, bar.endHeight, 1e-6); equal(zoneTitle(bars[i].zone), bar.zone); }
  }
});
test('Preview text for ramps, hidden values and an unknown FTP', () => {
  const plan = validatePlan({ version: 2, kind: 'workout', name: 'Ramp', ftpWatts: 250, steps: [{ name: 'Cool-down', seconds: 300, watts: 150, endWatts: 100 }, { name: 'Hold', seconds: 120, watts: 288 }] });
  const [ramp, hold] = previewSteps(plan);
  equal(ramp.valueText, '5:00 · 60→40 % · 150→100 W'); equal(hold.valueText, '2:00 · 115 % · 288 W'); equal(mainSetText(plan), '2:00 @ 115 % (288 W)');
  equal(previewSteps(plan, 100, false)[0].valueText, '5:00');
  const noFTP = validatePlan({ version: 1, kind: 'workout', name: 'Fixed', steps: [{ name: 'Hold', seconds: 120, watts: 200 }] });
  equal(previewSteps(noFTP)[0].valueText, '2:00'); equal(previewSteps(noFTP)[0].zone, null); equal(profileBars(noFTP)[0].zone, null); near(profileBars(noFTP)[0].startHeight, 1);
  equal(mainSetText(validatePlan({ version: 2, kind: 'workout', name: 'R', ftpWatts: 200, steps: [{ name: 'a', seconds: 60, watts: 100, endWatts: 150 }] })), null);
});
test('Profile segments scale original targets; zones round the percentage first; the step under a position is found', () => {
  const plan = validatePlan({ version: 2, kind: 'workout', name: 'Test', ftpWatts: 200, steps: [{ name: 'Ramp', seconds: 60, watts: 100, endWatts: 140 }, { name: 'Hold', seconds: 120, watts: 180 }] });
  const segments = profileSegments(plan); equal(segments.map(s => s.start), [0, 60]); equal(segments.map(s => s.end), [60, 180]); equal(segments[0].averageWatts, 120);
  equal(peakWatts(plan), 180); near(profileSegments(plan, 110)[1].startWatts, 198); near(averageWatts(plan), (120 * 60 + 180 * 120) / 180);
  equal([0.549, 0.55, 0.56, 0.75, 0.76, 0.87, 0.88, 0.94, 0.95, 1.05, 1.06].map(zoneFor), [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5]);
  equal(stepAtFraction(0, plan), 0); equal(stepAtFraction(60 / 180, plan), 1); equal(stepAtFraction(1, plan), 1); equal(stepAtFraction(1.5, plan), null);
});
test('Scheduled dates are real calendar days and keep the Intervals local day', () => {
  assert(ScheduledDate.isValid('2026-11-02') && ScheduledDate.isValid('2028-02-29')); assert(!ScheduledDate.isValid('2027-02-29') && !ScheduledDate.isValid('2026-1-2') && !ScheduledDate.isValid('20261102') && !ScheduledDate.isValid(''));
  equal(ScheduledDate.fromIntervalsLocal('2026-11-02T06:30:00'), '2026-11-02'); equal(ScheduledDate.fromIntervalsLocal('2026-11-02'), '2026-11-02'); equal(ScheduledDate.fromIntervalsLocal('nonsense!!!'), null); equal(ScheduledDate.fromIntervalsLocal(null), null);
  equal(ScheduledDate.stringFor(new Date(2026, 10, 2, 23, 59)), '2026-11-02'); equal(ScheduledDate.dateFrom('2026-11-02').getDate(), 2);
  const plan = planFor(definition('tempo-3x5'), 200), base = { id: 'intervals:1:r:2', riderID: crypto.randomUUID(), source: 'S', savedAt: new Date().toISOString(), plan };
  equal(validateCachedWorkout({ ...base, scheduledDate: '2026-11-02' }).scheduledDate, '2026-11-02'); assert(!('scheduledDate' in validateCachedWorkout(base)));
  throws(() => validateCachedWorkout({ ...base, scheduledDate: '2026-02-30' })); throws(() => validateCachedWorkout({ ...base, scheduledDate: 'tomorrow' }));
});
