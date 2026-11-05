import { test, assert, equal, rejects } from './harness.mjs';
import { AppModel } from '../src/app-model.mjs';
import { MemoryStore } from '../src/memory-store.mjs';
import { BluetoothDevices } from '../src/bluetooth.mjs';
import { rider, finishedRamp, ALEX_ID } from '../src/preview-fixtures.mjs';
import { planFor, definition } from '../src/catalog.mjs';
import { isAdopted } from '../src/rules/presentation.mjs';
import { creditSession } from '../src/training.mjs';

const drain = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
async function makeModel(profiles = [rider()], options = {}) {
  const store = new MemoryStore(); for (const p of profiles) await store.put('profiles', p);
  const model = new AppModel({ store, devices: new BluetoothDevices({ bluetooth: null }), prefs: { appearance: 'system', extraLarge: false, powerMatching: true, selectedRider: profiles[0]?.id ?? null, debugUnlocked: false, intervalsHintDismissed: false }, preview: true, lease: async () => () => {}, ...options });
  await model.boot(); return model;
}

test('First launch has no rider; onboarding saves the rider with an optional FTP and weight', async () => {
  const model = await makeModel([]); assert(model.onboardingPending);
  assert(!(await model.completeOnboarding({ name: ' ', weight: '', ftp: '' })).ok && model.onboardingPending);
  assert((await model.completeOnboarding({ name: 'Robin', weight: '64', ftp: '210' })).ok); assert(!model.onboardingPending);
  equal([model.profile.name, model.profile.weightKG, model.ftp, model.ftpEntry.source], ['Robin', 64, 210, 'Manual']); equal(model.draft.preset, 'standard');
  const skipped = await makeModel([]); await skipped.skipOnboarding(); equal([skipped.onboardingPending, skipped.profile.name], [false, 'You']);
});
test('Riders are separate; weight drives the recommended ramp unless one was chosen', async () => {
  const model = await makeModel(); equal(model.draft.preset, 'standard');
  await rejects(() => model.addRider('alex')); const sam = await model.addRider('Sam'); equal(model.profile.id, sam.id); equal(model.ftp, null);
  await model.saveRiderDetails({ name: 'Sam', weight: '55' }); equal(model.draft.preset, 'gentle'); model.choosePreset('zwift'); await model.saveRiderDetails({ name: 'Sam', weight: '80' }); equal(model.draft.preset, 'zwift');
  model.useRecommendedProtocol(); equal(model.draft.preset, 'standard'); await rejects(() => model.saveRiderDetails({ name: 'Sam', weight: '-1' }));
  await model.setCurrentFTP('201'); equal(model.ftp, 201); await model.setCurrentFTP('230'); equal(model.profile.ftpHistory.length, 2); await model.chooseFTPEntry('none'); equal(model.ftp, null);
  await model.selectRider(ALEX_ID); equal(model.ftp, 230);
});
test('Workout references resolve for classics and cached files, follow the FTP, and other plans can register their own prefix', async () => {
  const model = await makeModel([rider({ ftp: null })]), none = model.workoutDetail('classic:sweet-spot-3x10');
  assert(none.needsFTP && none.plan === null && none.previewPlan.ftpWatts == null && none.duration === 3300); equal(model.workoutDetail('classic:nope'), null); equal(model.workoutDetail('cached:nope'), null); equal(model.workoutDetail('mystery:1'), null);
  await model.setCurrentFTP(250); const ready = model.workoutDetail('classic:sweet-spot-3x10'); assert(!ready.needsFTP); equal([ready.plan.steps[1].watts, ready.plan.ftpWatts], [225, 250]);
  const record = { id: 'imp-1', riderID: model.profile.id, source: 'Imported JSON', savedAt: new Date().toISOString(), plan: planFor(definition('tempo-3x5'), 200) };
  await model.store.saveWorkouts([record]); await model.reload(); const cached = model.workoutDetail('cached:imp-1'); equal([cached.source, cached.needsFTP, cached.plan.ftpWatts], ['Imported', false, 200]);
  model.workoutResolvers.set('custom', id => ({ ref: `custom:${id}`, title: 'Mine', plan: ready.plan, previewPlan: ready.plan, needsFTP: false })); equal(model.workoutDetail('custom:abc').title, 'Mine');
});
test('A start is blocked with the reason, and a mock ride starts with the 72 % configuration', async () => {
  const model = await makeModel(); await rejects(() => model.startFTPTest()); assert(!model.busy);
  model.demoMode = true; model.draft.quickDebug = true; model.draft.speed = 1; assert(await model.startFTPTest()); clearInterval(model.ride.timer);
  equal([model.ride.engine.session.configuration.ftpFactor, model.ride.engine.session.configuration.priorFTP, model.ride.engine.session.isDemo], [0.72, 230, true]); assert(!('adventureEnabled' in model.ride.engine.session));
  model.ride.advanceMock(8); assert(model.ride.engine.phase !== 'waiting'); model.ride.stop(); await drain(); assert(!model.busy);
});
test('A workout starts at the chosen intensity and the first target is scaled once', async () => {
  const model = await makeModel(); model.demoMode = true; model.draft.speed = 1; model.draft.intensity = 110;
  assert(await model.startWorkout('classic:sweet-spot-3x10')); clearInterval(model.ride.timer); equal(model.ride.engine.intensity, 110); equal(model.draft.intensity, 100);
  model.ride.advanceMock(5); equal(model.ride.engine.target, 127); equal(model.ride.engine.session.training.steps[0].watts, 115); // 115 W at 110 %, snapshotted at 230 W FTP
  await model.setCurrentFTP('180').then(() => { throw Error('FTP changed during a ride'); }, () => {}); equal(model.ftp, 230); model.ride.stop(); await drain();
  const none = await makeModel([rider({ ftp: null })]); await rejects(() => none.startWorkout('classic:tempo-3x5'));
});
test('Free ERG and resistance rides use their own controls and never scale', async () => {
  const model = await makeModel(); model.demoMode = true; model.draft.speed = 1; model.draft.freeWatts = 150; assert(await model.startFreeRide()); clearInterval(model.ride.timer);
  equal(model.ride.engine.session.training.kind, 'freeRide'); model.ride.stop(); await drain();
  model.draft.resistance = 100; assert(await model.startResistance()); clearInterval(model.ride.timer); equal(model.ride.engine.resistanceLevel, 100); model.ride.stop(); await drain();
  const live = await makeModel(); equal(live.resistanceRange, null); await rejects(() => live.startResistance());
});
test('Adopting a result adds a Ramp test entry once; deleting the recording keeps the adopted FTP and a legacy ledger', async () => {
  const p = rider({ ftp: 200 }), engine = finishedRamp(p, { daysAgo: 0, scale: 1.05 }), session = engine.session;
  p.cycleProgress = creditSession(null, { id: session.id, isDemo: false, adventureEnabled: true, eligibleMilliseconds: 6000 });
  const model = await makeModel([p]); await model.store.saveSession(session); await model.reload();
  assert(!isAdopted(model.profile, session.result, session.startedAt)); await model.adopt(session); assert(isAdopted(model.profile, session.result, session.startedAt)); equal(model.ftpEntry.source, 'Ramp test');
  const demo = { ...session, id: crypto.randomUUID(), isDemo: true }; const before = model.profile.ftpHistory.length; await model.adopt(demo); equal(model.profile.ftpHistory.length, before);
  await model.store.put('jobs', { id: 'j1', sessionID: session.id, accountID: 'a', status: 'queued' }); await model.deleteSession(session);
  equal([model.history.length, model.jobs.length, model.ftpEntry.source], [0, 0, 'Ramp test']); // the adopted FTP is kept, as in the native app equal(Object.keys(model.profile.cycleProgress.credits).length, 1); 
});
test('The calendar download saves dated workouts, prunes stale entries, backs off after a failure and never runs in a preview', async () => {
  const model = await makeModel(); model.preview = false; model.intervals.connection = { id: 'acct', name: 'Athlete', authorization: 'x' };
  const entry = (n, date) => ({ id: `intervals:acct:${model.profile.id}:${n}`, riderID: model.profile.id, source: 'Intervals.icu · X', savedAt: new Date().toISOString(), plan: planFor(definition('tempo-3x5'), 230), ...(date ? { scheduledDate: date } : {}) });
  const soon = new Date(); soon.setDate(soon.getDate() + 2); const day = `${soon.getFullYear()}-${String(soon.getMonth() + 1).padStart(2, '0')}-${String(soon.getDate()).padStart(2, '0')}`;
  await model.store.saveWorkouts([entry(1, day), entry(2, day)]); await model.reload();
  model.intervals.workouts = async () => ({ workouts: [entry(1, day)], skipped: [] }); await model.downloadCalendar();
  equal(model.workouts.map(w => w.id), [entry(1).id]); assert(model.lastDownload('acct') > 0); assert(!model.shouldRefreshCalendar());
  let calls = 0; model.intervals.workouts = async () => { calls++; throw Error('offline'); }; delete model.prefs['downloadedAt.acct'];
  await model.refreshCalendarIfNeeded(); await model.refreshCalendarIfNeeded(); equal(calls, 1); assert(/not refreshed/.test(model.calendarMessage));
  model.preview = true; assert(!model.shouldRefreshCalendar()); await model.downloadCalendar(); assert(/Preview mode/.test(model.importReport)); equal(calls, 1);
});
test('Starting a recording and results: a finished ride is shown once and the live bar logic follows the phase', async () => {
  const model = await makeModel(); model.demoMode = true; model.draft.speed = 1; model.draft.quickDebug = true; await model.startFTPTest(); clearInterval(model.ride.timer);
  let change = model.phaseChange(); equal([change.previous, change.present], [null, false]); model.ride.advanceMock(2000); await drain();
  change = model.phaseChange(); assert(change.present || ['completed', 'interrupted'].includes(change.phase)); equal(model.phaseChange().present, false); assert(model.resultSession.id === model.ride.engine.session.id);
});
