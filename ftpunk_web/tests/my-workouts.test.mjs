import { test, assert, equal, near, throws, rejects, fixture, fixtureText } from './harness.mjs';
import { parseZWO, exportZWO, zwoFileName, looksLikeZWO } from '../src/zwo.mjs';
import { importWorkoutText, MAX_WORKOUT_BYTES } from '../src/workouts.mjs';
import { parseWorkoutText, printWorkoutText, durationText as printedDuration, normalized } from '../src/workout-text.mjs';
import * as C from '../src/custom-workouts.mjs';
import { BuilderState } from '../src/builder-state.mjs';
import { CATALOG, planFor, definition } from '../src/catalog.mjs';
import { validatePlan, resistanceRide } from '../src/training.mjs';
import { parseArchive, archiveText, makeArchive, validateArchive } from '../src/archive.mjs';
import { LocalStore } from '../src/storage.mjs';
import { MemoryStore } from '../src/memory-store.mjs';
import { AppModel } from '../src/app-model.mjs';
import { BluetoothDevices } from '../src/bluetooth.mjs';
import { installCustomWorkouts } from '../src/my-workouts.mjs';
import { rider, ALEX_ID } from '../src/preview-fixtures.mjs';
import { scenarioNames } from '../src/ui/scenarios.mjs';
// Plan 9c: ZWO import and export, the workout text language, custom workouts, the builder's state, the archive's customWorkouts, the model and the screens.
// The fixtures (zwo-cases, workout-text-cases, custom-workouts-250w, portable-v3-custom) are written by Swift tests; nothing here edits them.

const exampleZWO = async () => (await fetch(new URL('./fixtures/workout-example.zwo', import.meta.url))).text();
const message = body => { try { body(); return ''; } catch (error) { return error.message; } };
const RIDER_A = 'a1e00000-0000-4000-8000-000000000001', RIDER_B = '5a400000-0000-4000-8000-000000000002';
const lower = value => JSON.parse(JSON.stringify(value, (key, v) => v === null ? undefined : v).replace(/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/g, id => id.toLowerCase()));
const zwo = (steps, sport = '<sportType>bike</sportType>', name = '<name>Test</name>') => `<?xml version="1.0"?><workout_file>${name}${sport}<workout>${steps}</workout></workout_file>`;
const diff = (a, b, path = '') => JSON.stringify(a) === JSON.stringify(b) ? [] : a && b && typeof a === 'object' && typeof b === 'object' ? [...new Set([...Object.keys(a), ...Object.keys(b)])].flatMap(k => diff(a[k], b[k], `${path}.${k}`)) : [`${path}: ${JSON.stringify(a)} vs ${JSON.stringify(b)}`];
const STEADY = '<SteadyState Duration="60" Power="0.5"/>';

// ---------------------------------------------------------------------------------------------------------------------------------
// ZWO
test('ZWO import and export equal the shared Swift fixture, case for case', async () => {
  const cases = await fixture('zwo-cases'), example = await exampleZWO();
  equal(cases.format, 'ftpunk-zwo-cases'); assert(cases.imports.length >= 30 && cases.exports.length >= 7);
  for (const c of cases.imports) {
    const text = c.file ? example : c.xml; let plan = null, error = '';
    try { plan = parseZWO(text, c.ftp); } catch (e) { error = e.message; }
    if (c.error != null) equal([c.name, error], [c.name, c.error]); else { equal([c.name, error], [c.name, '']); equal([c.name, plan], [c.name, c.plan]); }
  }
  for (const c of cases.exports) {
    let xml = null, error = ''; try { xml = exportZWO(c.plan, c.riderFTP); } catch (e) { error = e.message; }
    equal([c.name, error], [c.name, c.error ?? '']); if (c.xml != null) equal([c.name, xml], [c.name, c.xml]);
    equal([c.name, zwoFileName(c.plan)], [c.name, c.fileName]);
  }
});
test('The shared example expands every ZWO element at the rider\'s FTP', async () => {
  const plan = parseZWO(await exampleZWO(), 250);
  equal([plan.name, plan.ftpWatts, plan.kind, plan.version, plan.steps.length], ['ZWO example', 250, 'workout', 2, 15]);
  equal(plan.steps[0], { name: 'Warm-up', seconds: 300, watts: 125, endWatts: 188 }); equal(plan.steps[1], { name: 'Steady', seconds: 120, watts: 163 });
  equal(plan.steps[2], { name: 'Ramp', seconds: 120, watts: 175, endWatts: 238 }); equal([plan.steps[3], plan.steps[4]], [{ name: 'On', seconds: 180, watts: 263 }, { name: 'Off', seconds: 120, watts: 138 }]);
  equal([plan.steps[9], plan.steps[10]], [{ name: 'On', seconds: 60, watts: 225, endWatts: 300 }, { name: 'Off', seconds: 60, watts: 150, endWatts: 125 }]);
  equal(plan.steps[13], { name: 'Steady', seconds: 60, watts: 200 }); equal(plan.steps.at(-1), { name: 'Cool-down', seconds: 300, watts: 188, endWatts: 100 }); // PowerLow is where it starts
  equal(plan.steps.reduce((n, s) => n + s.seconds, 0), 300 + 120 + 120 + 900 + 240 + 60 + 300);
});
test('ZWO: an import without an FTP says so; unsupported and malformed files are rejected with a clear message', () => {
  equal(message(() => parseZWO(zwo(STEADY), null)), 'Set an FTP first: ZWO powers are fractions of FTP.'); assert(message(() => parseZWO(zwo(STEADY), 0)).includes('Set an FTP first'));
  assert(message(() => parseZWO(zwo(STEADY + '<FreeRide Duration="600"/>'), 250)).includes('free-ride or maximal-effort')); assert(message(() => parseZWO(zwo('<MaxEffort Duration="30"/>'), 250)).includes('maximal-effort'));
  assert(message(() => parseZWO(zwo('<SolidState Duration="30"/>'), 250)).includes('no power target'));
  equal(message(() => parseZWO(zwo(STEADY, '<sportType>run</sportType>'), 250)), 'Only cycling (bike) workouts are supported.'); equal(message(() => parseZWO(zwo(STEADY, ''), 250)), '');
  for (const broken of ['', 'not xml', '<workout_file><workout><SteadyState Duration="60" Power="0.5"/></workout>', '<other/>', '<!DOCTYPE workout_file [<!ENTITY a "b">]><workout_file><workout/></workout_file>']) equal([broken, message(() => parseZWO(broken, 250))], [broken, 'This is not a valid ZWO workout file.']);
  equal(message(() => parseZWO(zwo(''), 250)), 'The workout contains no steps.');
  for (const bad of ['<SteadyState Duration="60" Power="200"/>', '<SteadyState Duration="60"/>', '<Ramp Duration="60" PowerLow="0.5"/>']) assert(message(() => parseZWO(zwo(bad), 250)).includes('fractions of FTP'), bad);
  for (const bad of ['<SteadyState Power="0.5"/>', '<SteadyState Duration="-5" Power="0.5"/>']) assert(message(() => parseZWO(zwo(bad), 250)).includes('timed power'), bad);
});
test('ZWO: the limits match the JSON import (repeats, 500 steps, 24 hours, 2 MiB)', () => {
  equal(message(() => parseZWO(zwo('<IntervalsT Repeat="101" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>'), 250)), 'Invalid repeat count.');
  equal(message(() => parseZWO(zwo('<IntervalsT Repeat="0" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>'), 250)), 'Invalid repeat count.');
  const block = '<IntervalsT Repeat="100" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>';
  equal(parseZWO(zwo(block + block), 250).steps.length, 400); assert(message(() => parseZWO(zwo(block + block + block), 250)).includes('too large'));
  assert(message(() => parseZWO(zwo('<SteadyState Duration="86401" Power="0.5"/>'), 250)).includes('timed power'));
  assert(message(() => parseZWO(zwo('<SteadyState Duration="86000" Power="0.5"/><SteadyState Duration="86000" Power="0.5"/>'), 250)).includes('too large'));
  equal(message(() => parseZWO(' '.repeat(MAX_WORKOUT_BYTES) + zwo(STEADY), 250)), 'Workout files must be under 2 MB.');
});
test('ZWO: every classic workout survives export and import within one watt; export escapes text and uses the plan\'s FTP', () => {
  for (const def of CATALOG) for (const ftp of [180, 250, 333]) {
    const original = planFor(def, ftp), imported = parseZWO(exportZWO(original, null), ftp);
    assert(imported.name === original.name && imported.steps.length === original.steps.length, def.id);
    original.steps.forEach((a, i) => { const b = imported.steps[i]; assert(a.seconds === b.seconds && Math.abs(a.watts - b.watts) <= 1 && (a.endWatts == null) === (b.endWatts == null), `${def.id} ${i}`); });
  }
  const plan = validatePlan({ version: 2, kind: 'workout', name: 'Over & <under> "x"', ftpWatts: 200, steps: [{ name: 'a', seconds: 60, watts: 150 }, { name: 'b', seconds: 90.4, watts: 100, endWatts: 250 }] });
  const text = exportZWO(plan, 999);
  assert(text.includes('<sportType>bike</sportType>') && text.includes('<author>FTPunk</author>') && text.includes('<name>Over &amp; &lt;under&gt; &quot;x&quot;</name>'));
  assert(text.includes('<SteadyState Duration="60" Power="0.750"/>') && text.includes('<Ramp Duration="90" PowerLow="0.500" PowerHigh="1.250"/>'));
  assert(!new DOMParser().parseFromString(text, 'application/xml').querySelector('parsererror'), 'the export is well-formed XML');
  assert(message(() => exportZWO(resistanceRide(50), 250)).includes('timed power') && message(() => exportZWO(validatePlan({ version: 1, kind: 'workout', name: 'W', steps: [{ name: 'a', seconds: 60, watts: 150 }] }), null)).includes('Set an FTP first'));
  equal(zwoFileName(plan), 'FTPunk-Over-under-x.zwo');
});
test('The library import picks the parser by content: ZWO starts with "<", JSON with "{"', async () => {
  assert(looksLikeZWO('﻿  \n<workout_file/>') && !looksLikeZWO('{"a":1}'));
  const zwoResult = importWorkoutText(await exampleZWO(), 250); equal([zwoResult.source, zwoResult.plan.steps.length, zwoResult.plan.ftpWatts], ['Imported ZWO', 15, 250]);
  const json = importWorkoutText(JSON.stringify({ format: 'ftpunk-workout', version: 1, name: 'J', ftpWatts: 200, steps: [{ name: 'a', seconds: 60, watts: 150 }] }), null); equal([json.source, json.plan.name], ['Imported JSON', 'J']);
  equal(message(() => importWorkoutText(zwo(STEADY), null)), 'Set an FTP first: ZWO powers are fractions of FTP.');
});

// ---------------------------------------------------------------------------------------------------------------------------------
// Workout text
test('Workout text equals the shared Swift fixture: parse (blocks or errors), print, names, durations', async () => {
  const cases = await fixture('workout-text-cases'); equal(cases.format, 'ftpunk-workout-text-cases'); assert(cases.parse.length >= 80 && cases.print.length === 80);
  for (const c of cases.parse) {
    const result = parseWorkoutText(c.text);
    if (c.errors) equal([c.text, result.errors, result.blocks, result.isValid], [c.text, c.errors, [], false]); else equal([c.text, result.errors, result.blocks], [c.text, [], c.blocks]);
  }
  for (const c of cases.print) { equal(printWorkoutText(c.blocks), c.text); equal(parseWorkoutText(c.text).blocks, c.blocks); }
  for (const c of cases.names) equal([c.name, C.nameIsPlain(c.name), normalized(c.name)], [c.name, c.plain, c.normalized]);
  for (const c of cases.durations) equal([c.text, C.parseDuration(c.text)], [c.text, c.seconds]);
  for (const c of cases.durationTexts) equal([c.seconds, C.durationText(c.seconds)], [c.seconds, c.text]);
  for (const c of cases.printedDurations) equal([c.seconds, printedDuration(c.seconds)], [c.seconds, c.text]);
});
test('Workout text: every syntax form parses, a pasted Intervals workout imports, every unsupported token names its line', () => {
  const pct = value => C.percent(value), st = C.step;
  const result = parseWorkoutText('Warm-up\n- 10m 50%\nMain set 5x\n- 3m 115%\n- Recovery 1m30 55%\nRamp down\n- 5m ramp 60-40%\nSprint\n- 20s 650w\n- 1h 200W\n- 2m30s ramp 100-200w');
  equal(result.errors, []); equal(result.blocks, [C.stepBlock(st('Warm-up', 600, pct(0.5))), C.repeatBlock(5, [st('', 180, pct(1.15)), st('Recovery', 90, pct(0.55))]), C.stepBlock(st('Ramp down', 300, pct(0.6), pct(0.4))),
    C.stepBlock(st('Sprint', 20, C.watts(650))), C.stepBlock(st('', 3600, C.watts(200))), C.stepBlock(st('', 150, C.watts(100), C.watts(200)))]);
  equal(parseWorkoutText('Warmup\n- 20m 60%\n\nMain set 6x\n- 4m 100%\n- 5m recovery at 40%\n\nCooldown\n- 20m 60%').blocks, [C.stepBlock(st('Warmup', 1200, pct(0.6))), C.repeatBlock(6, [st('', 240, pct(1)), st('recovery', 300, pct(0.4))]), C.stepBlock(st('Cooldown', 1200, pct(0.6)))]);
  equal(parseWorkoutText('- 5m @ 80%\r\n- Time at threshold 10m 95%\r\n').blocks, [C.stepBlock(st('', 300, pct(0.8))), C.stepBlock(st('Time at threshold', 600, pct(0.95)))]);
  for (const [line, token] of [['- 10m 50% 90rpm', 'rpm'], ['- 20m 60% 90-100rpm', 'rpm'], ['- 5m 55% HR', 'HR'], ['- 5m 100% LTHR', 'LTHR'], ['- 60m Z2', 'Z2'], ['- 10m Z2-Z3', 'Z2-Z3'], ['- 5m 70% pace', 'pace'], ['- 1km 80%', '1km'], ['- 800mtr 80%', '800mtr'], ['- 20m freeride', 'freeride'], ['- Press lap 10m 50%', 'Press'], ['- 10m 50% ftp', 'ftp']]) {
    const r = parseWorkoutText(`Warm-up\n- 10m 50%\n\n${line}`);
    assert(r.errors.length === 1 && r.errors[0].line === 4 && r.errors[0].message.includes(token) && r.blocks.length === 0, `${line}: ${JSON.stringify(r.errors)}`);
  }
  equal(parseWorkoutText('- 10m 50% rpm\n- 5m\n- 1m 60%').errors.map(e => e.line), [1, 2]); equal(parseWorkoutText('').errors[0].line, 1);
  equal(parseWorkoutText('- 5m 10m 80%').errors[0].message, 'A step has one duration.'); equal(parseWorkoutText('- 5m 80% 90%').errors[0].message, 'A step has one target.');
  assert(parseWorkoutText('- 10m 80-90%').errors[0].message.includes('Ranges are not supported')); assert(parseWorkoutText('x'.repeat(100001)).errors[0].message === 'The text is too long.');
});

// ---------------------------------------------------------------------------------------------------------------------------------
// Custom workouts
test('Custom workouts resolve exactly like the shared Swift fixture at 250 W: issues, plan, plans without an FTP, text, ranges, load', async () => {
  const data = await fixture('custom-workouts-250w'); equal([data.format, data.ftpWatts], ['ftpunk-custom-workouts', 250]); assert(data.workouts.length >= 25 && data.invalid.length >= 15);
  for (const entry of data.workouts) {
    const label = entry.workout.name, workout = C.validateCustomWorkout(entry.workout);
    equal([label, workout], [label, lower(entry.workout)]); equal([label, C.issues(workout)], [label, entry.issues]); equal([label, C.needsFTP(workout), C.totalSeconds(workout), C.flattened(workout).length], [label, entry.needsFTP, entry.durationSeconds, entry.flatCount]);
    equal([label, printWorkoutText(workout.blocks)], [label, entry.text]); equal([label, C.flatRanges(workout)], [label, entry.flatRanges]);
    for (const [ftp, plan, error] of [[250, entry.plan250, entry.error250], [null, entry.planNoFTP, entry.errorNoFTP], [100, entry.plan100, entry.error100]]) {
      let got = null, failure = ''; try { got = C.planFor(workout, ftp); } catch (e) { failure = e.message; }
      if (error != null) equal([label, ftp, failure], [label, ftp, error]); else equal([label, ftp, got], [label, ftp, plan]);
    }
    const load = C.estimatedLoad(workout, 250);
    if (entry.load250 == null) equal([label, load], [label, null]); else { near(load.intensityFactor, entry.load250.intensityFactor, 1e-9); near(load.tss, entry.load250.tss, 1e-7); }
  }
  for (const entry of data.invalid) { equal([entry.workout.name, C.issues(entry.workout)], [entry.workout.name, entry.issues]); assert(entry.issues.length > 0); throws(() => C.validateCustomWorkout(entry.workout)); }
});
test('Custom workouts: repeats flatten, percent targets resolve once, watts never rescale, a missing FTP is named', () => {
  const pct = C.percent, st = C.step, w = C.newWorkout(RIDER_A, { name: 'Mixed', blocks: [C.stepBlock(st('Warm-up', 300, pct(0.5))), C.repeatBlock(2, [st('Hard', 60, pct(1.2)), st('Easy', 60, C.watts(100))]), C.stepBlock(st('', 120, C.watts(100), C.watts(250)))] });
  equal([C.flattened(w).length, C.totalSeconds(w), C.needsFTP(w)], [6, 660, true]);
  const plan = C.planFor(w, 250); equal([plan.name, plan.ftpWatts, plan.kind, plan.version], ['Mixed', 250, 'workout', 2]); equal(plan.steps.map(s => s.watts), [125, 300, 100, 300, 100, 100]); equal(plan.steps.at(-1).endWatts, 250);
  equal(plan.steps.map(s => s.name), ['Warm-up', 'Hard', 'Easy', 'Hard', 'Easy', 'Step 6']); equal(C.planFor(w, 300).steps.map(s => s.watts), [150, 360, 100, 360, 100, 100]);
  equal(message(() => C.planFor(w, null)), 'This workout has % FTP targets. Set an FTP first.'); equal(message(() => C.planFor(w, 0)), C.NEEDS_FTP);
  const flat = C.newWorkout(RIDER_A, { name: 'Watts', blocks: [C.stepBlock(st('a', 60, C.watts(200)))] }), unscaled = C.planFor(flat, null); equal([C.needsFTP(flat), unscaled.steps[0].watts, unscaled.ftpWatts], [false, 200, null]);
});
test('Custom workouts: units, ranges and limits are enforced, and a name has to survive the text editor', () => {
  const pct = C.percent, st = C.step, problems = (blocks, name = 'Test') => C.issues(C.newWorkout(RIDER_A, { name, blocks })), one = s => [C.stepBlock(s)];
  equal(problems(one(st('', 60, pct(0.5)))), []); assert(problems(one(st('', 60, C.watts(150), pct(0.8)))).some(t => t.includes('one unit')));
  assert(problems([]).includes('Add at least one step.') && problems(one(st('', 60, pct(0.5))), '  ').includes('Give the workout a name.'));
  assert(problems(one(st('', 4, pct(0.5)))).length && problems(one(st('', 14401, pct(0.5)))).length && !problems([C.stepBlock(st('', 5, pct(0.5))), C.stepBlock(st('', 14400, pct(0.5)))]).length);
  assert(problems(one(st('', 60, pct(0.29)))).length && problems(one(st('', 60, pct(2.51)))).length && !problems([C.stepBlock(st('', 60, pct(0.3))), C.stepBlock(st('', 60, pct(2.5)))]).length);
  assert(problems(one(st('', 60, C.watts(19)))).length && problems(one(st('', 60, C.watts(1501)))).length);
  assert(problems([C.repeatBlock(101, [st('', 60, pct(0.5))])]).length && problems([C.repeatBlock(0, [st('', 60, pct(0.5))])]).length && problems([C.repeatBlock(2, [])]).length);
  const five = Array.from({ length: 5 }, () => st('', 5, pct(0.5)));
  equal(problems([C.repeatBlock(100, five)]), []); assert(problems([C.repeatBlock(100, five), C.stepBlock(st('', 5, pct(0.5)))]).length); assert(problems([C.repeatBlock(100, [st('', 14400, pct(0.5))])]).length);
  for (const name of ['5m rest', 'Set 5x', 'two  spaces', 'with\nline']) assert(problems(one(st(name, 60, pct(0.5)))).length, name); equal(problems(one(st('Time at threshold', 60, pct(0.5)))), []);
});
test('Custom workouts: durations typed into fields parse and print back; the load estimate follows the fourth-power mean', () => {
  equal([C.parseDuration('3:30'), C.parseDuration('1:00:00'), C.parseDuration('5'), C.parseDuration('90s'), C.parseDuration('1m30'), C.parseDuration('1h')], [210, 3600, 300, 90, 90, 3600]);
  equal([C.parseDuration('1:75'), C.parseDuration('abc'), C.parseDuration('-3')], [null, null, null]); equal([C.durationText(210), C.durationText(3725)], ['3:30', '1:02:05']);
  const steady = C.newWorkout(RIDER_A, { name: 'S', blocks: [C.stepBlock(C.step('', 3600, C.percent(0.75)))] }), load = C.estimatedLoad(steady, 250); near(load.intensityFactor, 0.75, 0.001); near(load.tss, 56.25, 0.1);
  const hard = C.newWorkout(RIDER_A, { name: 'H', blocks: [C.stepBlock(C.step('', 1800, C.percent(0.5))), C.stepBlock(C.step('', 1800, C.percent(1)))] }); assert(C.estimatedLoad(hard, 250).intensityFactor > 0.75); equal(C.estimatedLoad(steady, null), null);
});
test('Every built-in workout survives blocks and text round trips as the identical plan; an imported plan becomes watt blocks', () => {
  for (const def of CATALOG) for (const ftp of [180, 250, 333]) {
    const expected = planFor(def, ftp), custom = C.fromDefinition(def, RIDER_A); assert(custom, def.id); equal([def.id, C.planFor(custom, ftp)], [def.id, expected]);
    const parsed = parseWorkoutText(printWorkoutText(custom.blocks)); equal([def.id, parsed.errors], [def.id, []]); equal([def.id, parsed.blocks], [def.id, custom.blocks]);
    equal([def.id, C.planFor({ ...custom, blocks: parsed.blocks }, ftp)], [def.id, expected]);
  }
  const plan = validatePlan({ version: 2, kind: 'workout', name: 'Imported', ftpWatts: 250, steps: [{ name: 'Warm-up', seconds: 300, watts: 100, endWatts: 150 }, { name: 'Hard', seconds: 600, watts: 260 }] });
  const custom = C.fromPlan(plan, RIDER_A); assert(!C.needsFTP(custom)); const rebuilt = C.planFor(custom, 250); equal([rebuilt.steps, rebuilt.name], [plan.steps, plan.name]);
  equal(C.fromPlan(validatePlan({ version: 1, kind: 'workout', name: 'Tiny', ftpWatts: null, steps: [{ name: 'blip', seconds: 1, watts: 200 }] }), RIDER_A), null);
  equal(C.copyName('x'.repeat(120)).length, 100);
});

// ---------------------------------------------------------------------------------------------------------------------------------
// Builder state
const blank = () => C.newWorkout(RIDER_A, { name: '', blocks: [] });
test('Builder: switching modes never loses anything, and text errors keep the Text mode with the line to fix', () => {
  const pct = C.percent, st = C.step, w = C.newWorkout(RIDER_A, { name: 'W', blocks: [C.stepBlock(st('Warm-up', 300, pct(0.5))), C.repeatBlock(2, [st('', 60, pct(1.1)), st('', 60, pct(0.5))])] }), state = new BuilderState(w);
  equal(state.mode, 'blocks'); const original = structuredClone(state.blocks);
  assert(state.switchTo('text') && state.mode === 'text' && state.parsed.isValid); equal(state.text, printWorkoutText(original));
  state.setText(state.text + '\n\n- 5m 90rpm');
  assert(!state.parsed.isValid && state.chartIsStale); equal(state.shownBlocks, original); assert(!state.switchTo('blocks') && state.mode === 'text');
  assert(state.notice.startsWith('Fix line 8 first:') && state.text.endsWith('90rpm') && !state.canSave && state.saveBlockers[0].startsWith('Line 8:') && state.hasUnsavedChanges);
  state.setText('Warm-up\n- 5m 50%\n\n- 2m 80%'); assert(state.parsed.isValid && !state.chartIsStale && state.canSave);
  assert(state.switchTo('blocks') && state.mode === 'blocks' && state.notice == null); equal(state.blocks, [C.stepBlock(st('Warm-up', 300, pct(0.5))), C.stepBlock(st('', 120, pct(0.8)))]);
  state.switchTo('text'); state.setBlocks([]); assert(state.blocks.length > 0); state.switchTo('blocks'); state.setText('garbage'); assert(state.text !== 'garbage'); // edits of the other editor are ignored
});
test('Builder: Save is blocked with the reasons, and changes are tracked', () => {
  const b = blank(), state = new BuilderState(b);
  assert(!state.canSave && state.saveBlockers.includes('Give the workout a name.') && state.saveBlockers.includes('Add at least one step.') && !state.hasUnsavedChanges);
  state.name = 'Mine'; state.setBlocks([C.stepBlock(C.step('', 600, C.percent(0.5)))]);
  assert(state.canSave && state.hasUnsavedChanges && state.workout().name === 'Mine' && state.workout().id === b.id); state.setBlocks([C.stepBlock(C.step('', 600, C.watts(150), C.percent(0.8)))]); assert(!state.canSave);
  state.name = '  Spaced   out '; state.setBlocks([C.stepBlock(C.step('', 600, C.percent(0.5)))]); equal(state.workout().name, 'Spaced out');
  const saved = new BuilderState(C.newWorkout(RIDER_A, { name: 'Same', blocks: [C.stepBlock(C.step('x', 60, C.percent(0.5)))] })); assert(!saved.hasUnsavedChanges); saved.name = 'Same '; assert(!saved.hasUnsavedChanges); saved.category = 'tempo'; assert(saved.hasUnsavedChanges);
});

// ---------------------------------------------------------------------------------------------------------------------------------
// Storage and archive
async function withStore(body) {
  const name = 'ftpunk-test-mywk-' + crypto.randomUUID(), store = await LocalStore.open(name);
  try { await body(store); } finally { store.db.close(); await new Promise(resolve => { const request = indexedDB.deleteDatabase(name); request.onsuccess = request.onerror = request.onblocked = resolve; }); }
}
const quick = (riderID, name, id = crypto.randomUUID()) => C.newWorkout(riderID, { id, name, blocks: [C.stepBlock(C.step('', 60, C.percent(0.5)))] });
test('Custom workouts are stored per rider in their own store, never move to another rider, and invalid ones are refused', async () => withStore(async store => {
  const a = rider({ id: RIDER_A }), b = rider({ id: RIDER_B, name: 'Sam', ftp: 180 }); await store.put('profiles', a); await store.put('profiles', b);
  const mine = quick(RIDER_A, 'Mine'); await store.saveCustomWorkout(mine); await store.saveCustomWorkout(quick(RIDER_B, 'Theirs'));
  await store.saveWorkouts([{ id: 'imp', riderID: RIDER_A, source: 'Imported JSON', savedAt: new Date().toISOString(), plan: planFor(definition('tempo-3x5'), 200) }]);
  equal([(await store.customWorkouts()).length, (await store.all('workouts')).length], [2, 1]);
  await store.saveCustomWorkout({ ...mine, name: 'Renamed', updatedAt: new Date(Date.now() + 1000).toISOString() }); equal((await store.customWorkouts()).filter(w => w.riderID === RIDER_A).map(w => w.name), ['Renamed']);
  await rejects(() => store.saveCustomWorkout({ ...mine, riderID: RIDER_B })); await rejects(() => store.saveCustomWorkout(quick(RIDER_A, '')));
  await rejects(() => store.saveCustomWorkout({ ...mine, id: 'not-a-uuid' })); await store.deleteCustomWorkout(mine.id); equal((await store.customWorkouts()).map(w => w.name), ['Theirs']); equal((await store.all('workouts')).length, 1);
}));
test('A rider can keep 200 workouts and no more', async () => withStore(async store => {
  for (let i = 0; i < 200; i++) await store.saveCustomWorkout(quick(RIDER_A, `W${i}`));
  await rejects(() => store.saveCustomWorkout(quick(RIDER_A, 'One too many'))); equal((await store.customWorkouts()).length, 200);
  await store.saveCustomWorkout(quick(RIDER_B, 'Another rider is unaffected')); const first = (await store.customWorkouts()).find(w => w.riderID === RIDER_A); await store.saveCustomWorkout({ ...first, name: 'Editing one is fine' });
}));
test('Portable v3 with custom workouts: the shared fixture validates, restores, exports unchanged and round-trips native -> web -> native', async () => withStore(async store => {
  const text = await fixtureText('portable-v3-custom'), expected = lower(JSON.parse(text)); equal([expected.version, expected.customWorkouts.length, expected.workouts.length], [3, 3, 1]);
  const archive = parseArchive(text); equal(archive.customWorkouts, expected.customWorkouts); const first = diff(lower(JSON.parse(archiveText(archive))), expected); assert(first.length === 0, first.join('; '));   // validate + export keep every field
  await store.restore(archive); await store.restore(archive); equal((await store.customWorkouts()).length, 3);                                    // idempotent
  const back = await store.backup(); equal([back.version, back.customWorkouts.length], [3, 3]); const byID = list => [...list].sort((x, y) => x.id.localeCompare(y.id)), sorted = archive => ({ ...archive, profiles: byID(archive.profiles), customWorkouts: byID(archive.customWorkouts) });
  const exported = lower(JSON.parse(archiveText({ ...back, exportedAt: expected.exportedAt }))), problems = diff(sorted(exported), sorted(expected)); assert(problems.length === 0, problems.join('; '));
  // Only custom workouts and nothing else make an archive v3.
  const lone = makeArchive([rider({ id: RIDER_A })], [], undefined, [], [quick(RIDER_A, 'Alone')]); equal(lone.version, 3); equal(makeArchive([rider({ id: RIDER_A })], []).version, 1);
}));
test('Archives without the key still load; custom workouts need version 3, a known rider and at most 200 per rider', () => {
  return fixtureText('portable-v3-custom').then(raw => {
    const base = JSON.parse(raw); const without = { ...base }; delete without.customWorkouts; equal(validateArchive(without).customWorkouts, undefined); equal(validateArchive(without).profiles.length, 2);
    assert(message(() => validateArchive({ ...base, customWorkouts: [{ ...base.customWorkouts[0], riderID: crypto.randomUUID() }] })).includes('missing rider'));
    assert(message(() => validateArchive({ ...base, version: 2 })).includes('Custom workouts require archive version 3') || message(() => validateArchive({ ...base, version: 2 })).length > 0);
    assert(message(() => validateArchive({ ...base, customWorkouts: [base.customWorkouts[0], base.customWorkouts[0]] })).includes('identities'));
    assert(message(() => validateArchive({ ...base, customWorkouts: [{ ...base.customWorkouts[0], blocks: [] }] })).includes('Add at least one step'));
    assert(message(() => validateArchive({ ...base, customWorkouts: Array.from({ length: 201 }, (_, i) => ({ ...base.customWorkouts[0], id: crypto.randomUUID(), name: `W${i}` })) })).includes('Too many'));
    assert(message(() => validateArchive({ ...base, customWorkouts: 'x' })).length > 0 && message(() => validateArchive({ ...base, customWorkouts: [{ id: 1 }] })).length > 0);
  });
});
test('Importing replaces the incoming riders\' custom workouts by identity, keeps unrelated riders, saves them in the rollback backup, and a collision with another rider changes nothing', async () => withStore(async store => {
  const raw = JSON.parse(await fixtureText('portable-v3-custom')), archive = parseArchive(JSON.stringify(raw));
  const unrelated = rider({ id: crypto.randomUUID(), name: 'Unrelated' }); await store.put('profiles', unrelated); const keep = quick(unrelated.id, 'Unrelated keeps this'); await store.saveCustomWorkout(keep);
  await store.put('profiles', rider({ id: RIDER_A })); const stale = quick(RIDER_A, 'Local only, replaced'); await store.saveCustomWorkout(stale);
  await store.restore(archive); const names = (await store.customWorkouts()).map(w => w.name).sort();
  equal(names, ['Mixed', "Sam's", 'Unrelated keeps this', 'Watts only']);
  const backups = (await store.all('backups')).sort((a, b) => b.createdAt.localeCompare(a.createdAt)); assert(backups[0].archive.customWorkouts.some(w => w.name === 'Local only, replaced') && backups[0].archive.version === 3, 'the backup holds the previous custom workouts');
  const before = JSON.stringify(await store.customWorkouts()), stolen = { ...archive, customWorkouts: [{ ...archive.customWorkouts[0], id: keep.id }] };
  await rejects(() => store.restore(stolen)); equal(JSON.stringify(await store.customWorkouts()), before);
}));

// ---------------------------------------------------------------------------------------------------------------------------------
// The model
async function makeModel(profiles = [rider()]) {
  const store = new MemoryStore(); for (const p of profiles) await store.put('profiles', p);
  const model = new AppModel({ store, devices: new BluetoothDevices({ bluetooth: null }), preview: true, lease: async () => () => {}, prefs: { appearance: 'system', extraLarge: false, powerMatching: true, selectedRider: profiles[0].id, debugUnlocked: false, intervalsHintDismissed: false } });
  installCustomWorkouts(model); await model.boot(); return model;
}
test('The model offers custom workouts like any other: detail, FTP follow, snapshot on start, duplicate, delete', async () => {
  const model = await makeModel(), w = C.newWorkout(ALEX_ID, { name: 'Mine', blocks: [C.stepBlock(C.step('Go', 600, C.percent(0.8)))] });
  await model.saveCustomWorkout(w); equal(model.myCustomWorkouts.map(x => x.name), ['Mine']);
  const detail = model.workoutDetail(`custom:${w.id}`); equal([detail.source, detail.plan.steps[0].watts, detail.needsFTP, detail.custom.id, detail.title], ['My workout', 184, false, w.id, 'Mine']);
  await model.setCurrentFTP(250); equal(model.workoutDetail(`custom:${w.id}`).plan.steps[0].watts, 200);                                            // % targets follow the FTP
  model.demoMode = true; model.draft.speed = 1; await model.startWorkout(`custom:${w.id}`); clearInterval(model.ride.timer);
  const recorded = model.ride.engine.session.training; equal(recorded.steps[0].watts, 200); await model.saveCustomWorkout({ ...w, blocks: [C.stepBlock(C.step('Go', 600, C.percent(1)))] }); equal(model.ride.engine.session.training.steps[0].watts, 200); model.ride.stop();
  await new Promise(resolve => setTimeout(resolve, 50));
  equal([model.duplicateWorkout(`custom:${w.id}`).name, model.duplicateWorkout('classic:endurance-60').name, model.duplicateWorkout('classic:nope')], ['Copy of Mine', 'Copy of Endurance 60', null]);
  await model.chooseFTPEntry('none'); const blocked = model.workoutDetail(`custom:${w.id}`); assert(blocked.needsFTP && blocked.plan === null && blocked.previewPlan.ftpWatts == null && blocked.previewPlan.steps.length === 1);
  await model.deleteCustomWorkout(w.id); equal(model.workoutDetail(`custom:${w.id}`), null); equal(model.myCustomWorkouts.length, 0);
});
test('A custom workout belongs to its rider; the library import reads ZWO and JSON and says what is missing', async () => {
  const sam = rider({ id: RIDER_B, name: 'Sam', ftp: null }), model = await makeModel([rider(), sam]); await model.saveCustomWorkout(quick(ALEX_ID, 'Alex only'));
  equal(model.myCustomWorkouts.length, 1); await model.selectRider(RIDER_B); equal(model.myCustomWorkouts.length, 0);
  const file = new File([await exampleZWO()], 'example.zwo');
  await rejects(() => model.importWorkoutFile(file)); equal((await model.store.all('workouts')).length, 0);              // Sam has no FTP: nothing is saved
  await model.selectRider(ALEX_ID); await model.importWorkoutFile(file); const [saved] = await model.store.all('workouts'); equal([saved.source, saved.plan.steps.length, saved.plan.ftpWatts, saved.riderID], ['Imported ZWO', 15, 230, ALEX_ID]);
  await model.importWorkoutFile(new File([JSON.stringify({ format: 'ftpunk-workout', version: 1, name: 'J', ftpWatts: 200, steps: [{ name: 'a', seconds: 60, watts: 150 }] })], 'j.json')); assert((await model.store.all('workouts')).some(x => x.source === 'Imported JSON'));
  const json = (await model.store.all('workouts')).find(x => x.source === 'Imported JSON'); equal(model.duplicateWorkout('cached:' + saved.id), null); // a step named "Ramp" would not survive the text editor
  model.openBuilder(model.duplicateWorkout('cached:' + json.id), { isNew: true }); assert(model.builder.state.canSave && model.builder.state.mode === 'blocks');
  assert(model.newWorkout('- 10m 50%').startsWith('#/builder') && model.builder.state.mode === 'text' && model.builder.state.canSave === false); // no name yet
});

// ---------------------------------------------------------------------------------------------------------------------------------
// Screens (the real app in an iframe against preview scenarios; reads the DOM, nobody has looked at it)
const frames = [];
async function open(query, { width = 1100, height = 900 } = {}) {
  const frame = document.createElement('iframe'); frame.style.cssText = `width:${width}px;height:${height}px;border:0`; frame.src = `/index.html?${query}&nosw`; document.body.append(frame); frames.push(frame);
  const start = Date.now(); while (!frame.contentWindow?.__ftpunk?.ready) { if (Date.now() - start > 20000) throw Error(`The app did not start for ?${query}`); await new Promise(r => setTimeout(r, 25)); }
  const win = frame.contentWindow, doc = win.document;
  return { frame, win, doc, model: win.__ftpunk.model, errors: win.__ftpunk.errors, text: () => doc.querySelector('#main').textContent.replace(/\s+/g, ' '), q: s => doc.querySelector(s), qa: s => [...doc.querySelectorAll(s)],
    wait: async (condition, label = 'condition') => { const t = Date.now(); while (!condition()) { if (Date.now() - t > 5000) throw Error(`Timed out waiting for ${label}`); await new Promise(r => setTimeout(r, 25)); } },
    type: (selector, value) => { const el = doc.querySelector(selector); el.value = value; el.dispatchEvent(new win.Event('input', { bubbles: true })); el.dispatchEvent(new win.Event('change', { bubbles: true })); }, close: () => frame.remove() };
}
const screen = async (name, body, size) => { const a = await open(`scenario=${name}`, size); try { await body(a); assert(a.errors.length === 0, `Script errors in ${name}: ${a.errors.join('; ')}`); } finally { a.close(); } };

test('The workout scenarios exist', () => { for (const name of ['home-my-workouts', 'home-my-workouts-empty', 'builder-blocks', 'builder-text-error']) assert(scenarioNames().includes(name), name); });
test('My workouts shows its three actions as buttons, the rider\'s workouts as cards with their own actions, and imported files', async () => screen('home-my-workouts', async a => {
  const section = a.q('#my-workouts'), t = section.textContent.replace(/\s+/g, ' ');
  for (const s of ['My workouts', 'New workout', 'Paste as text', 'Import file…', 'Sweet spot 2×15', 'Over-unders in watts', 'Ramp up', 'Club over-unders', '% FTP', 'watts', 'imported']) assert(t.includes(s), `lacks "${s}"`);
  equal(a.qa('#my-workouts .my-actions > button').map(b => b.textContent.trim()), ['New workout', 'Paste as text', 'Import file…']);
  equal(a.qa('#my-workouts .custom-card').length, 3); const first = a.q('#my-workouts .custom-card');
  equal([...first.querySelectorAll('.card-actions button')].map(b => b.textContent.trim()), ['Edit']); assert(!a.q('#my-workouts [role="menu"]'));
  assert(a.q('#workout-file').accept.includes('.zwo') && a.q('#workout-file').accept.includes('.json'));
}));
test('The empty state explains what can go here and offers the example file', async () => screen('home-my-workouts-empty', async a => {
  const t = a.q('#my-workouts').textContent.replace(/\s+/g, ' '); for (const s of ['New workout', 'Paste as text', 'Import file…', 'Zwift .zwo', 'Get an example JSON file', 'stay on this device']) assert(t.includes(s), `lacks "${s}"`); equal(a.qa('#my-workouts .custom-card').length, 0);
}));
test('A custom workout opens in the detail sheet with its actions, exports a ZWO file, and starts through the pre-flight', async () => screen('home-my-workouts', async a => {
  let blob = null; a.win.URL.createObjectURL = b => { blob = b; return 'blob:test'; }; a.win.HTMLAnchorElement.prototype.click = function () { this.dataset.clicked = this.download; };
  const card = a.qa('#my-workouts .workout-card').find(c => c.textContent.includes('Sweet spot 2×15')); card.click(); await a.wait(() => a.q('#dialog').open, 'detail sheet');
  const sheet = a.q('#dialog').textContent.replace(/\s+/g, ' '); for (const s of ['Sweet spot 2×15', 'My workout', 'Edit', 'Duplicate & edit', 'Export as ZWO', 'Delete workout', 'Start', 'follow it when it changes']) assert(sheet.includes(s), `sheet lacks "${s}"`);
  a.q('#dialog [data-dialog="zwo"]').click(); await a.wait(() => blob, 'the ZWO blob'); const xml = await blob.text(); assert(xml.includes('<sportType>bike</sportType>') && xml.includes('<SteadyState') && xml.includes('Sweet spot 2×15'));
  assert(!new a.win.DOMParser().parseFromString(xml, 'application/xml').querySelector('parsererror'));
  a.q('#dialog [data-dialog="start"]').click(); await a.wait(() => a.win.location.hash.startsWith('#/preflight/workout/custom'), 'pre-flight'); await a.wait(() => a.text().includes('Sweet spot 2×15'), 'the workout in the pre-flight');
}));
test('Deleting a custom workout asks first, then removes it (from its detail sheet)', async () => screen('home-my-workouts', async a => {
  const openRamp = async () => { a.qa('#my-workouts .workout-card').find(c => c.textContent.includes('Ramp up')).click(); await a.wait(() => a.q('#dialog').open && a.q('#dialog').textContent.includes('Delete workout'), 'detail sheet'); };
  await openRamp(); [...a.qa('#dialog button')].find(b => b.textContent.trim() === 'Delete workout').click();
  await a.wait(() => a.q('#dialog').textContent.includes('Delete this workout?'), 'confirmation');
  assert(a.model.myCustomWorkouts.length === 3); a.q('#dialog [data-dialog="cancel"]').click(); await a.wait(() => !a.q('#dialog').open); assert(a.model.myCustomWorkouts.length === 3, 'cancel keeps it');
  await openRamp(); [...a.qa('#dialog button')].find(b => b.textContent.trim() === 'Delete workout').click(); await a.wait(() => a.q('#dialog').textContent.includes('Delete this workout?'), 'confirmation again'); a.q('#dialog [data-dialog="confirm"]').click();
  await a.wait(() => a.model.myCustomWorkouts.length === 2 && !a.text().includes('Ramp up'), 'deleted');
}));
test('The builder in Blocks mode: header, steps, live chart and total, and the header stays put when switching to Text and back', async () => screen('builder-blocks', async a => {
  assert(a.win.location.hash === '#/builder/draft'); const t = a.text(); for (const s of ['Edit workout', 'Workout name', 'Category', 'Blocks', 'Text', '+ Step', '+ Repeat block', 'Duplicate', 'Move down']) assert(t.includes(s), `lacks "${s}"`);
  equal(a.q('#builder-name').value, 'Sweet spot 2×15'); assert(a.qa('#builder-preview .profile .bar').length === 6 && a.q('#builder-preview').textContent.includes('55 min'), a.q('#builder-preview').textContent);
  assert(!a.q('#builder-save').disabled); equal(a.qa('[data-block]').length, 3);
  const top = el => Math.round(el.getBoundingClientRect().top), nameTop = top(a.q('#builder-name')), toggleTop = top(a.q('[data-chip="mode"]'));
  a.q('[data-chip="mode"][data-value="text"]').click(); await a.wait(() => a.q('#builder-text'), 'text editor'); equal([top(a.q('#builder-name')), top(a.q('[data-chip="mode"]'))], [nameTop, toggleTop]);
  equal(a.q('#builder-text').value, 'Warm-up\n- 10m 50%\n\n2x\n- Sweet spot 15m 90%\n- Recovery 5m 50%\n\nCool-down\n- 5m 50%'); assert(a.text().includes('Text is valid') && !a.q('#builder-save').disabled);
  a.q('[data-chip="mode"][data-value="blocks"]').click(); await a.wait(() => a.q('[data-block]'), 'blocks editor'); equal([top(a.q('#builder-name')), top(a.q('[data-chip="mode"]'))], [nameTop, toggleTop]); equal(a.model.prefs.builderMode, 'blocks');
}));
test('Blocks mode edits: add, reorder, duplicate, delete, units, ramp, duration; the chart and Save follow, and bad input blocks Save with the reason', async () => screen('builder-blocks', async a => {
  const state = () => a.model.builder.state; a.q('[data-action="add-step"]').click(); await a.wait(() => a.qa('[data-block]').length === 4, 'new step'); equal(state().blocks.length, 4);
  a.q('[data-action="add-repeat"]').click(); await a.wait(() => a.qa('[data-block]').length === 5); a.q('[data-action="add-preset"][data-preset="recovery"]').click(); await a.wait(() => a.qa('[data-block]').length === 6);
  a.q('[data-action="block-up"][data-b="5"]').click(); await a.wait(() => state().blocks[4].step?.name === 'Recovery', 'moved up'); a.q('[data-action="block-duplicate"][data-b="4"]').click(); await a.wait(() => state().blocks.length === 7);
  a.q('[data-action="block-delete"][data-b="5"]').click(); await a.wait(() => state().blocks.length === 6);
  const repeatIndex = state().blocks.findIndex(b => b.kind === 'repeats' && b.steps.length === 2 && b.steps[0].name === 'Hard'); assert(repeatIndex >= 0);
  a.q(`[data-action="repeat-add-step"][data-b="${repeatIndex}"]`).click(); await a.wait(() => state().blocks[repeatIndex].steps.length === 3); a.q(`[data-action="step-delete"][data-b="${repeatIndex}"][data-s="2"]`).click(); await a.wait(() => state().blocks[repeatIndex].steps.length === 2);
  // typing: a duration, a target, the unit and a ramp
  const field = (f, b, s) => `[data-f="${f}"][data-b="${b}"]${s == null ? ':not([data-s])' : `[data-s="${s}"]`}`;
  a.type(field('duration', 0), '12:30'); equal(state().blocks[0].step.seconds, 750); a.type(field('start', 0), '55'); near(state().blocks[0].step.start.value, 0.55, 1e-9); assert(a.q('[data-equivalent]').textContent.includes('127 W') || a.q('[data-equivalent]').textContent.includes('126 W'), a.q('[data-equivalent]').textContent);
  a.q('[data-action="set-unit"][data-unit="watts"][data-b="0"]:not([data-s])').click(); await a.wait(() => state().blocks[0].step.start.unit === 'watts', 'unit'); equal(state().blocks[0].step.start.value, 127);
  a.q(field('ramp', 0)).click(); await a.wait(() => state().blocks[0].step.end, 'ramp'); equal(state().blocks[0].step.end, { unit: 'watts', value: 127 }); a.type(field('end', 0), '200'); equal(state().blocks[0].step.end.value, 200); assert(!a.q('#builder-save').disabled);
  a.type(field('duration', 0), '0:02'); a.q(field('duration', 0)).dispatchEvent(new a.win.Event('change', { bubbles: true })); assert(a.q(field('duration', 0)).getAttribute('aria-invalid') === 'true'); equal(state().blocks[0].step.seconds, 750);
  a.type('#builder-name', ''); assert(a.q('#builder-save').disabled && a.q('#builder-status').textContent.includes('Give the workout a name.')); a.type('#builder-name', 'Edited'); assert(!a.q('#builder-save').disabled);
  a.type(field('name', 0), '5m rest'); assert(a.q('#builder-save').disabled && /name cannot contain/.test(a.q('#builder-status').textContent)); a.type(field('name', 0), 'Warm-up');
  a.type(`[data-f="count"][data-b="${repeatIndex}"]`, '3'); equal(state().blocks[repeatIndex].count, 3);
}));
test('The text editor shows every error with its line, keeps Text mode, disables Save, and a fix lets the rider switch back', async () => screen('builder-text-error', async a => {
  await a.wait(() => a.q('#builder-text'), 'text editor'); const t = a.q('#builder-status').textContent;
  assert(/Line 11: "90rpm" is not supported/.test(t) && /Line 12: This step needs a target/.test(t), t); assert(a.q('#builder-save').disabled && a.q('#builder-text').getAttribute('aria-invalid') === 'true' && a.q('#builder-preview').textContent.includes('Showing the last valid text'));
  a.q('[data-chip="mode"][data-value="blocks"]').click(); await a.wait(() => !a.q('#builder-notice').hidden, 'notice'); assert(a.q('#builder-notice').textContent.startsWith('Fix line 11 first:') && a.q('#builder-text'));
  a.type('#builder-text', 'Warm-up\n- 5m 50%\n\n- 2m 80%'); assert(a.q('#builder-status').textContent.includes('Text is valid') && !a.q('#builder-save').disabled);
  a.q('[data-chip="mode"][data-value="blocks"]').click(); await a.wait(() => a.qa('[data-block]').length === 2, 'back in blocks'); equal(a.model.prefs.builderMode, 'blocks');
}));
test('Cancel asks before discarding changes, Save stores the workout on this device only, and nothing is fetched', async () => screen('builder-blocks', async a => {
  let calls = 0; const original = a.win.fetch; a.win.fetch = (...args) => { calls++; return original(...args); }; a.win.XMLHttpRequest = class { constructor() { calls++; } };
  a.q('[data-action="builder-cancel"]').click(); await a.wait(() => a.win.location.hash === '#/home', 'home (nothing changed, no question)');
  a.model.openBuilder(a.model.customWorkouts[0], {}); a.win.location.hash = '#/builder/draft'; await a.wait(() => a.q('#builder-name'), 'builder'); a.type('#builder-name', 'Changed name');
  a.q('[data-action="builder-cancel"]').click(); await a.wait(() => a.q('#dialog').open && a.q('#dialog').textContent.includes('Discard your changes?'), 'discard question'); a.q('#dialog [data-dialog="cancel"]').click(); await a.wait(() => !a.q('#dialog').open); assert(a.win.location.hash === '#/builder/draft');
  a.q('#builder-save').click(); await a.wait(() => a.win.location.hash === '#/home' && a.model.myCustomWorkouts.some(w => w.name === 'Changed name'), 'saved'); await a.wait(() => a.text().includes('Changed name'), 'card');
  equal(calls, 0);
}));
test('The builder works at 390 px wide without horizontal scrolling, and every control is a real button, input or link', async () => screen('builder-blocks', async a => {
  const root = a.doc.documentElement; assert(root.scrollWidth <= 390, `page is ${root.scrollWidth}px wide`);
  for (const el of a.qa('#main [data-action], #main [data-chip]')) assert(['BUTTON', 'A'].includes(el.tagName), `${el.tagName} ${el.dataset.action}`);
  const wide = [...a.qa('#main *')].filter(el => el.getBoundingClientRect().right > 391 && !el.closest('.profile') && el.getBoundingClientRect().width > 0); equal(wide.map(el => el.tagName + '.' + el.className), []);
}, { width: 390, height: 844 }));
test('My workouts at 390 px: the three actions wrap and nothing overflows', async () => screen('home-my-workouts', async a => {
  assert(a.doc.documentElement.scrollWidth <= 390, `page is ${a.doc.documentElement.scrollWidth}px wide`); const buttons = a.qa('#my-workouts .my-actions > button'); assert(buttons.every(b => b.getBoundingClientRect().right <= 391));
}, { width: 390, height: 844 }));
