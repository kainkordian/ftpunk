import { test, assert, equal, near } from './harness.mjs';
import * as P from '../src/rules/presentation.mjs';
import * as H from '../src/rules/home.mjs';
import * as G from '../src/rules/progress.mjs';
import { planFor, definition } from '../src/catalog.mjs';
import { RampEngine, configuration } from '../src/domain.mjs';

// Mirrors Tests/FTPunkTests/PresentationRulesTests.swift, HomeAndLibraryTests.swift, HomeWorkflowTests.swift and ProgressTests.swift.
const ready = (kind = 'ftpTest', change = {}) => ({ kind, trainerConnected: true, trainerControlReady: true, powerRangeKnown: true, freshSelectedPower: true, supportsResistance: true, ...change });
test('Start blockers are reported in the order a rider can fix them', () => {
  equal(P.startBlocker(ready()), null);
  equal(P.startBlocker(ready('ftpTest', { isFinishing: true, trainerConnected: false })), 'finishing'); equal(P.startBlocker(ready('ftpTest', { isBusy: true })), 'busy');
  equal(P.startBlocker(ready('ftpTest', { trainerConnected: false, trainerControlReady: false })), 'trainerMissing'); equal(P.startBlocker(ready('ftpTest', { trainerControlReady: false })), 'trainerControl');
  equal(P.startBlocker(ready('ftpTest', { powerRangeKnown: false })), 'powerRange'); equal(P.startBlocker(ready('ftpTest', { matchingChoicePending: true, trainerConnected: false })), 'matchingChoice');
  equal(P.startBlocker(ready('ftpTest', { freshSelectedPower: false })), 'noPowerTrainer'); equal(P.startBlocker(ready('ftpTest', { freshSelectedPower: false, powerSource: 'externalPowerMeter' })), 'noPowerMeter');
  equal(P.startBlocker(ready('ftpTest', { durationsValid: false })), 'invalidDurations'); equal(P.startBlocker(ready('workout', { needsFTP: true })), 'needsFTP');
  equal(P.startBlocker(ready('ftpTest', { bluetoothAvailable: false })), 'unsupported');
});
test('Resistance needs advertised support but not a power range; durations only matter for the FTP test', () => {
  equal(P.startBlocker(ready('resistance', { supportsResistance: false })), 'resistanceUnsupported'); equal(P.startBlocker(ready('resistance', { powerRangeKnown: false })), null); equal(P.startBlocker(ready('freeERG', { durationsValid: false })), null);
});
test('Mock rides skip hardware blockers but still explain the rest', () => {
  equal(P.startBlocker({ kind: 'ftpTest', isMock: true, bluetoothAvailable: false }), null); equal(P.startBlocker({ kind: 'ftpTest', isMock: true, durationsValid: false }), 'invalidDurations');
});
test('Targets outside the trainer range block start before asking the rider to pedal', () => {
  equal(P.startBlocker(ready('workout', { targetsInRange: false })), 'targetsOutOfRange'); equal(P.startBlocker(ready('workout', { targetsInRange: false, freshSelectedPower: false })), 'targetsOutOfRange'); assert(P.BLOCKER_TEXT.targetsOutOfRange.includes('intensity'));
});
test('Every blocker has a plain reason ending in a full stop', () => {
  assert(Object.values(P.BLOCKER_TEXT).every(t => t.length && t.endsWith('.'))); equal(P.blockerReason('trainerMissing'), 'Connect your trainer to start.'); equal(P.blockerReason(null), null);
});
test('The protocol recommendation follows the reference weight guideline', () => {
  equal(P.recommendProtocol(75).preset, 'standard'); equal(P.recommendProtocol(75).reason, '75 kg → 25 W/min'); equal(P.recommendProtocol(60).preset, 'standard');
  equal(P.recommendProtocol(59.5).preset, 'gentle'); equal(P.recommendProtocol(59.5).reason, '59.5 kg → 15 W/min'); equal(P.recommendProtocol(null).preset, 'standard'); equal(P.recommendProtocol(-3).preset, 'standard');
});
test('The retest prompt starts at eight weeks', () => {
  const now = new Date(2027, 0, 20, 12), ago = days => { const d = new Date(now); d.setDate(d.getDate() - days); return d; };
  equal(P.retestAdvice(null, now).kind, 'never'); equal(P.retestAdvice(ago(0), now).weeks, 0); equal(P.retestAdvice(ago(55), now).isDue, false); equal(P.retestAdvice(ago(56), now).isDue, true);
  equal(P.retestAdvice(ago(63), now).message(), 'Last test 9 weeks ago, time to retest?'); equal(P.retestAdvice(ago(14), now).message(), 'Last test 2 weeks ago'); equal(P.retestAdvice(ago(7), now).message('FTP set'), 'FTP set 1 week ago');
  const tomorrow = new Date(now); tomorrow.setDate(tomorrow.getDate() + 1); equal(P.retestAdvice(tomorrow, now).weeks, 0); equal(P.retestAdvice(null, now).message(), null);
  // A week across the daylight saving change is still a week.
  equal(P.retestAdvice(new Date(2027, 2, 20, 23), new Date(2027, 2, 27, 1)).weeks, 1);
});
test('The FTP status line says when and how long ago, or prompts a retest', () => {
  const now = new Date(2026, 10, 5, 12), at = (m, d) => new Date(2026, m, d, 9);
  equal(P.ftpStatusLine({ date: at(10, 2), isRamp: true, source: 'Ramp test', now }), { text: 'Tested 2 Nov · this week', isRetestPrompt: false });
  equal(P.ftpStatusLine({ date: at(9, 12), isRamp: false, source: 'Manual', now }).text, 'Set 12 Oct · 3 weeks ago · Manual');
  equal(P.ftpStatusLine({ date: at(8, 1), isRamp: true, source: 'Ramp test', now }), { text: 'Tested 1 Sep · 9 weeks ago · time to retest?', isRetestPrompt: true });
  equal(P.ftpStatusLine({ date: null, isRamp: false, source: 'Entered for this ride', now }), { text: 'Entered for this ride', isRetestPrompt: false });
});
test('The result delta names the change from the current FTP', () => {
  equal(P.resultDelta(209.3, 250).text, '−41 W vs 250 W'); equal(P.resultDelta(209.3, 250).watts, -41); equal(P.resultDelta(262, 250).text, '+12 W vs 250 W');
  equal(P.resultDelta(250.2, 250).text, 'Same as your current 250 W'); equal(P.resultDelta(210, null).text, 'First FTP for this rider'); equal(P.resultDelta(210, NaN).watts, 0);
});
test('The cadence guard warns only during the ramp and never changes the finish rule', () => {
  const g = P.CadenceGuard; equal(g.state(59.9, 'ramp'), 'low'); equal(g.state(60, 'ramp'), 'ok'); equal(g.state(null, 'ramp'), 'unknown'); equal(g.state(40, 'warmup'), 'ok'); equal(g.state(40, 'ramp', false), 'ok');
  equal(g.finishBelow, 45); equal(g.message, 'Ramp ends below 45 rpm');
  // The engine still ends the ramp at 45 rpm held for five seconds, whatever the guard shows.
  const e = new RampEngine(configuration({ warmupSeconds: 0 }));
  for (let t = 0; t <= 20; t++) { e.receive({ time: t, power: 150, cadence: t < 12 ? 90 : 44 }); e.tick(t); }
  equal(e.session.outcome, 'exhaustion');
});
test('Hold to finish needs one and a half seconds', () => {
  equal(P.holdFraction(0), 0); equal(P.holdFraction(0.75), 0.5); assert(!P.holdComplete(1.49)); assert(P.holdComplete(1.5)); equal([P.holdFraction(-2), P.holdFraction(NaN), P.holdFraction(99)], [0, 0, 1]);
});
test('The phase timeline has segments and progress', () => {
  const warm = P.phaseTimeline({ phase: 'warmup', warmup: 600, cooldown: 180, elapsedInPhase: 300 });
  equal(warm.segments.map(s => s.phase), ['warmup', 'ramp', 'cooldown']); equal(warm.segments[0].start, 0); near(warm.segments.at(-1).end, 1, 1e-9); assert(warm.progress > 0 && warm.progress < warm.segments[0].end);
  const ramp = P.phaseTimeline({ phase: 'ramp', warmup: 600, cooldown: 180, elapsedInPhase: 120 }); assert(ramp.progress > warm.segments[0].end && ramp.progress < ramp.segments[1].end);
  equal(P.phaseTimeline({ phase: 'ramp', warmup: 0, cooldown: 0, elapsedInPhase: 10 }).segments.map(s => s.phase), ['ramp']);
  equal(P.phaseTimeline({ phase: 'completed', warmup: 600, cooldown: 180, elapsedInPhase: 0 }).progress, 1); equal(P.phaseTimeline({ phase: 'waiting', warmup: 600, cooldown: 180, elapsedInPhase: 0 }).progress, 0);
  assert(P.phaseTimeline({ phase: 'ramp', warmup: 60, cooldown: 60, elapsedInPhase: 1500, rampElapsed: 1500 }).progress <= 1);
});
test('The device summary distinguishes ready, attention and off', () => {
  const off = P.deviceSummary({ mock: false, trainerConnected: false, trainerReady: false, powerSource: 'trainer', externalMeterConnected: false, heartRateConnected: false }); equal([off.trainer, off.power, off.heartRate], ['off', 'off', 'off']);
  const attention = P.deviceSummary({ mock: false, trainerConnected: true, trainerReady: false, powerSource: 'trainer', externalMeterConnected: false, heartRateConnected: true }); equal([attention.trainer, attention.power, attention.heartRate], ['attention', 'attention', 'ready']);
  const meter = P.deviceSummary({ mock: false, trainerConnected: true, trainerReady: true, powerSource: 'externalPowerMeter', externalMeterConnected: false, heartRateConnected: false }); equal([meter.trainer, meter.power, meter.heartRate], ['ready', 'attention', 'off']); assert(meter.description.includes('external meter'));
  const mock = P.deviceSummary({ mock: true }); equal(mock.trainer, 'ready'); assert(mock.description.startsWith('Mock sensors'));
});
test('Rider initials, chip names and the devices line', () => {
  equal([P.riderInitials('Alex'), P.riderInitials('alex rider'), P.riderInitials('Alex Van Rider'), P.riderInitials('  ')], ['A', 'AR', 'AV', '?']);
  equal(P.riderChipName('Alexandria Van Rider'), 'Alexandria Va…'); equal(P.riderChipName('  Sam  '), 'Sam');
  equal(P.devicesLine({ trainerName: null, powerSource: 'trainer', meterName: null, heartRateName: null }), 'Trainer: not connected · Power: from trainer · Heart rate: none');
  equal(P.devicesLine({ trainerName: 'Suito-T', powerSource: 'externalPowerMeter', meterName: 'Assioma', heartRateName: 'HRM' }), 'Trainer: Suito-T · Power: from Assioma · Heart rate: HRM');
});
test('The cadence row is a problem only once devices are connected', () => {
  equal(P.cadenceStatus('trainer', true), { text: 'From trainer', isProblem: false }); equal(P.cadenceStatus('externalPowerMeter', true).text, 'From power meter');
  equal(P.cadenceStatus('unavailable', false), { text: 'No cadence yet: connect and pedal', isProblem: false }); assert(P.cadenceStatus('unavailable', true).isProblem);
});
test('Duration formats for cards and clocks', () => {
  const D = P.DurationFormat; equal([D.compact(3300), D.compact(3900), D.compact(500), D.compact(45), D.compact(NaN)], ['55 min', '1 h 05 min', '8 min 20 s', '45 s', '—']);
  equal([D.clock(440), D.clock(-1)], ['7:20', '0:00']); equal([D.workout(3600), D.workout(5700), D.workout(8100), D.workout(7200), D.workout(30)], ['60 min', '95 min', '2 h 15 min', '2 h', '30 s']);
});
test('Adoption is detected from the rider history', () => {
  const result = { estimatedFTP: 261 }, start = new Date(1e12).toISOString(), at = ms => new Date(1e12 + ms).toISOString();
  let rider = { ftpHistory: [] }; assert(!P.isAdopted(rider, result, start)); assert(!P.isAdopted(null, result, start));
  rider = { ftpHistory: [{ watts: 261, date: at(-60000), source: 'Ramp test' }] }; assert(!P.isAdopted(rider, result, start));
  rider.ftpHistory.push({ watts: 261, date: at(600000), source: 'Ramp test' }); assert(P.isAdopted(rider, result, start));
  assert(!P.isAdopted({ ftpHistory: [{ watts: 261, date: at(600000), source: 'Manual' }] }, result, start));
});
test('The result shows the training result before what it changes and sharing', () => {
  equal(P.resultSections({ isFTPResult: true, adopted: true, canUpload: true }), ['headline', 'chart', 'decision', 'trainingHandoff', 'upload']);
  equal(P.resultSections({ isFTPResult: true, adopted: false, canUpload: false }), ['headline', 'chart']); equal(P.resultSections({ isFTPResult: false, adopted: true, canUpload: false }), ['headline', 'chart']);
  equal(P.resultSections({ isFTPResult: false, adopted: false, canUpload: true }), ['headline', 'chart', 'upload']);
});
test('An interruption explains what was saved and whether a result exists', () => {
  const session = { training: null, endedAtOffset: 500, outcome: 'interrupted', endReason: 'Power from the selected source is no longer fresh.', result: null, samples: [] };
  const lost = P.interruptionSummary(session); equal(lost.headline, 'Test interrupted'); assert(!lost.hasResult && lost.saved.includes('8 min 20 s') && lost.saved.includes('No FTP estimate')); equal(lost.reason, session.endReason);
  const kept = P.interruptionSummary({ ...session, result: { bestMinutePower: 300 } }); assert(kept.hasResult && kept.headline === 'Cool-down interrupted' && kept.saved.includes('result was kept'));
  const ride = P.interruptionSummary({ ...session, result: null, training: { name: 'x' }, endReason: null }); equal(ride.headline, 'Ride interrupted'); equal(ride.reason, 'The ride stopped unexpectedly.');
});
test('Average power ignores gaps and is time weighted', () => {
  const samples = [{ time: 0, power: 100 }, { time: 1, power: 200 }, { time: 3, power: 300 }, { time: 20, power: 50 }];
  near(P.averagePower(samples), (100 * 1 + 200 * 2 + 300 * 2) / 5, 1e-9); equal(P.averagePower([]), null); equal(P.averagePower([{ time: 0 }, { time: 1 }]), null);
});
test('A ride ending while minimised brings its result back', () => {
  assert(P.shouldPresentResult('ramp', 'completed', false)); assert(P.shouldPresentResult('riding', 'interrupted', false)); assert(!P.shouldPresentResult('ramp', 'completed', true));
  assert(!P.shouldPresentResult('ramp', 'cooldown', false)); assert(!P.shouldPresentResult(null, 'completed', false)); assert(!P.shouldPresentResult('completed', null, false));
});
test('Result chart bands follow the scored phases and labels fit their band', () => {
  const session = { training: null, rampStart: 600, rampEnd: 1000, cooldownStart: 1000, endedAtOffset: 1180, samples: [], result: { bestMinutePower: 290, windowStart: 900, windowEnd: 960 } };
  equal(P.resultBands(session).map(b => b.title), ['Warm-up', 'Ramp', 'Cool-down']); equal(P.resultBands(session)[1], { title: 'Ramp', start: 600, end: 1000 });
  equal(P.bestMinuteBand(session), { title: 'Best minute 290 W', start: 900, end: 960 }); equal(P.resultBands({ ...session, training: { kind: 'freeRide' } }), []);
  const L = P.ResultChartLayout; equal(L.fittingLabel('Warm-up', 80, 6.4), 'Warm-up'); equal(L.fittingLabel('Warm-up', 40, 6.4), 'Warm'); equal(L.fittingLabel('Warm-up', 10, 6.4), null);
  equal(L.fittingLabel('Best minute 290 W', 80, 7.6), 'Best 290 W'); equal(L.clampedLeading(10, 100, 300), 0); equal(L.clampedLeading(290, 100, 300), 200); near(L.ceiling(250), 330);
});
test('Only the FTP test says stay seated', () => {
  equal(P.coachingLine(true, 'ramp'), 'Stay seated. Keep a steady, comfortable cadence.'); equal(P.coachingLine(true, 'cooldown'), 'Ramp scored. Spin gently to cool down.'); equal(P.coachingLine(false, 'riding'), 'Keep a steady, comfortable cadence.');
});

const rider = '00000000-0000-0000-0000-000000000001', plan = planFor(definition('tempo-3x5'), 200);
const cached = (id, date, { r = rider, intervals = true, saved = 0 } = {}) => ({ id: intervals ? `intervals:1:${r}:${id}` : id, riderID: r, source: intervals ? `Intervals.icu · ${id}` : 'Imported JSON', savedAt: new Date(saved).toISOString(), plan, ...(date ? { scheduledDate: date } : {}) });
test('The Today card shows today, or the next planned workout, or a single hint', () => {
  const library = [cached('a', '2026-11-02'), cached('b', '2026-11-02'), cached('c', '2026-11-04'), cached('d', '2026-11-03'), cached('old', '2026-10-30'), cached('legacy', null), cached('mine', null, { intervals: false }), cached('other', '2026-11-02', { r: crypto.randomUUID() })];
  const id = name => library.find(w => w.id.endsWith(`:${name}`) || w.id === name).id;
  equal(H.selectToday(library, rider, '2026-11-02', true), { kind: 'today', ids: [id('a'), id('b')] }); equal(H.selectToday(library, rider, '2026-11-02', false), { kind: 'today', ids: [id('a'), id('b')] });
  equal(H.selectToday(library, rider, '2026-11-01', true), { kind: 'nothingToday', next: id('a') }); equal(H.selectToday(library, rider, '2026-11-05', true), { kind: 'nothingToday', next: null });
  equal(H.selectToday([], rider, '2026-11-02', false), { kind: 'notConnected' }); equal(H.selectToday([], rider, '2026-11-02', true), { kind: 'nothingToday', next: null });
  equal(H.upcoming(library, rider, '2026-11-02').map(w => w.id), [id('d'), id('c'), id('legacy')]); equal(H.mine(library, rider).map(w => w.id), ['mine']);
});
test('Stale calendar entries inside the downloaded window are pruned', () => {
  const kept = cached('kept', '2026-11-05'), gone = cached('gone', '2026-11-06'), later = cached('later', '2026-12-25'), past = cached('past', '2026-10-01'), undated = cached('undated', null), own = cached('mine', null, { intervals: false });
  const stale = H.staleEntries([kept, gone, later, past, undated, own], rider, '1', new Set([kept.id]), '2026-11-02', '2026-11-16');
  equal(new Set(stale), new Set([gone.id, undated.id])); equal(stale.sort(), [gone.id, undated.id].sort());
});
test('The calendar refreshes after an hour and never during a ride', () => {
  const now = 1.8e12, base = { now, connected: true, rideActive: false };
  assert(H.shouldRefresh({ ...base, lastDownload: null })); assert(!H.shouldRefresh({ ...base, lastDownload: now - 3599000 })); assert(H.shouldRefresh({ ...base, lastDownload: now - 3601000 }));
  assert(!H.shouldRefresh({ ...base, lastDownload: null, rideActive: true })); assert(!H.shouldRefresh({ ...base, lastDownload: null, connected: false })); assert(!H.shouldRefresh({ ...base, lastDownload: null, alreadyRunning: true }));
});
test('Onboarding needs a name; weight and FTP are optional positive numbers', () => {
  assert(!H.parseOnboarding({ name: '  ', weight: '', ftp: '' }).ok); assert(!H.parseOnboarding({ name: 'Robin', weight: 'abc', ftp: '' }).ok); assert(!H.parseOnboarding({ name: 'Robin', weight: '', ftp: '-4' }).ok);
  equal(H.parseOnboarding({ name: ' Robin ', weight: '64', ftp: '210' }), { ok: true, name: 'Robin', weightKG: 64, ftp: 210 }); equal(H.parseOnboarding({ name: 'Sam', weight: '', ftp: '' }).weightKG, null);
  equal(H.dateText('2026-11-02'), 'Mon 2 Nov'); equal(H.dateText(null), 'Date not set');
});

const mk = (rider, daysAgo, { demo = false, training = null, outcome = 'exhaustion', result = true, scale = 1 } = {}) => ({
  id: crypto.randomUUID(), startedAt: new Date(Date.now() - daysAgo * 86400000).toISOString(), isDemo: demo, training, outcome, endedAtOffset: 1800,
  configuration: { preset: 'standard', riderID: rider.id, riderName: rider.name, weightKG: rider.weightKG }, samples: [{ time: 0, power: 100 }],
  result: result && !training ? { bestMinutePower: 300 * scale, estimatedFTP: 216 * scale, wattsPerKG: rider.weightKG ? 216 * scale / rider.weightKG : null } : null });
const alex = { id: 'a1e00000-0000-4000-8000-000000000001', name: 'Alex', weightKG: 71 }, sam = { id: '5a400000-0000-4000-8000-000000000002', name: 'Sam', weightKG: null };
test('Activity filters separate tests, workouts and free rides, newest first', () => {
  const test1 = mk(alex, 3), workout = mk(alex, 2, { training: { kind: 'workout', name: 'Tempo 3×5' }, outcome: 'completed' }), free = mk(alex, 1, { training: { kind: 'freeRide', name: 'Free ERG ride' }, outcome: 'completed' }), all = [test1, workout, free];
  equal(G.activities(all, null, 'all').map(s => s.id), [free.id, workout.id, test1.id]); equal(G.activities(all, null, 'ftpTests').map(s => s.id), [test1.id]);
  equal(G.activities(all, null, 'workouts').map(s => s.id), [workout.id]); equal(G.activities(all, null, 'freeRides').map(s => s.id), [free.id]); equal(G.activities(all, crypto.randomUUID(), 'all'), []);
  equal(G.ACTIVITY_FILTERS.map(f => f.title), ['All', 'FTP tests', 'Workouts', 'Free rides']);
});
test('Activity rows show date, activity, result and badges', () => {
  const test1 = mk(alex, 3), row = G.activityRow(test1, 'uploaded');
  assert(row.title.endsWith('· FTP test')); equal(row.value, '216 W'); equal(row.badges, ['uploaded']); assert(row.subtitle.startsWith('Alex')); equal(G.activityRow(test1, null, false).subtitle, 'Ramp complete');
  const debug = mk(alex, 1, { demo: true }); equal(G.activityRow(debug, 'queued').badges, ['debug', 'uploadQueued']); equal(G.activityRow(debug, 'failed').badges, ['debug', 'uploadFailed']);
  const broken = mk(alex, 1, { outcome: 'interrupted', result: false }); equal(G.activityRow(broken).badges, ['interrupted']); equal(G.activityRow(broken).value, null);
  const ride = mk(alex, 1, { training: { kind: 'workout', name: 'Tempo 3×5' }, outcome: 'completed' }), rideRow = G.activityRow(ride); assert(rideRow.title.endsWith('· Tempo 3×5')); equal(rideRow.value, '30 min'); equal(rideRow.badges, []);
});
test('The trend shows real results by default and debug results on request, per rider', () => {
  const real = mk(alex, 10), debug = mk(alex, 5, { demo: true }), other = mk(sam, 8), none = mk(alex, 2, { training: { kind: 'workout', name: 'W' }, outcome: 'completed' }), all = [real, debug, other, none];
  equal(new Set(G.trendSessions(all, null, 'watts', false).map(s => s.id)), new Set([real.id, other.id])); equal(G.trendSessions(all, null, 'watts', true).length, 3);
  equal(G.trendSessions(all, alex.id, 'watts', false).map(s => s.id), [real.id]); equal(G.trendSessions(all, sam.id, 'wattsPerKG', false), []); equal(G.trendSessions(all, alex.id, 'wattsPerKG', false).length, 1);
  equal(G.TREND_METRICS.map(m => m.title), ['FTP, W', 'FTP, W/kg']);
});
test('Two riders keep separate groups and trend series', () => {
  const sessions = [mk(alex, 56), mk(alex, 21), mk(sam, 14)], groups = G.riderGroups(sessions, [alex, sam]);
  equal(groups.map(g => g.name), ['Alex', 'Sam']); equal(groups.map(g => g.sessions.length), [2, 1]);
  const series = G.trendSeries(groups, 'watts', false, [sam.id, alex.id]); equal(series.map(s => s.colorIndex), [1, 0]); assert(series[0].points[0].time < series[0].points[1].time);
});
