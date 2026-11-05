import { rider, finishedRamp, ALEX_ID, SAM_ID } from '../preview-fixtures.mjs';
import { definition, planFor } from '../catalog.mjs';
import { uuid } from '../domain.mjs';
import { ScheduledDate } from '../workouts.mjs';
// Preview scenarios: `?scenario=<name>` boots the app against an in-memory store seeded with a made-up rider (Alex, 71 kg, 230 W).
// Each scenario is a function (ctx) -> hash to show. `ctx = { model, store, seed(profile, sessions?, workouts?), startRamp(), startWorkout(id, seconds), day(offset) }`.
// A scenario never touches the real database. Each plan adds its own scenarios in its own marked block below and edits nothing else here.
export const SCENARIOS = {};
const alex = (options = {}) => rider({ id: ALEX_ID, ...options });

// ======== foundation plan: Home, pre-flight, cockpit, result, progress, settings ========
Object.assign(SCENARIOS, {
  'first-launch': async ({ model }) => { model.onboardingPending = true; return '#/home'; },
  home: async ({ seed, day, intervals }) => { await seed(alex(), { workouts: await intervals(alex()) }); return '#/home'; },
  'home-empty': async ({ seed }) => { await seed(alex({ ftp: null })); return '#/home'; },
  'home-not-connected': async ({ seed }) => { await seed(alex()); return '#/home'; },
  'home-retest-due': async ({ seed }) => { await seed(alex({ daysAgo: 63 })); return '#/home'; },
  'workout-detail': async ({ seed, openDetail }) => { await seed(alex()); openDetail('classic:vo2max-5x3'); return '#/home'; },
  'preflight-ftp': async ({ seed }) => { await seed(alex()); return '#/preflight/ftpTest'; },
  'preflight-workout': async ({ seed }) => { await seed(alex()); return '#/preflight/workout/classic:sweet-spot-3x10'; },
  'preflight-blocked': async ({ seed, model }) => { await seed(alex()); model.demoMode = false; return '#/preflight/ftpTest'; },
  'ride-ftp': async ({ seed, startRamp, model }) => { await seed(alex()); await startRamp(); model.ride.advanceMock(60 + 95); return '#/ride'; },
  'ride-warmup': async ({ seed, startRamp, model }) => { await seed(alex()); await startRamp(); model.ride.advanceMock(30); return '#/ride'; },
  'ride-cooldown': async ({ seed, startRamp, model }) => { await seed(alex()); await startRamp(); for (let i = 0; i < 4000 && model.ride.engine.phase !== 'cooldown'; i++) model.ride.advanceMock(1); return '#/ride'; },
  'ride-workout': async ({ seed, startWorkout }) => { await seed(alex()); await startWorkout('sweet-spot-3x10', 760); return '#/ride'; },
  'ride-free': async ({ seed, model }) => { await seed(alex()); model.demoMode = true; model.draft.speed = 1; model.draft.freeWatts = 150; await model.startFreeRide(); clearInterval(model.ride.timer); model.ride.advanceMock(60); return '#/ride'; },
  'ride-resistance': async ({ seed, model }) => { await seed(alex()); model.demoMode = true; model.draft.speed = 1; model.draft.resistance = 100; await model.startResistance(); clearInterval(model.ride.timer); model.ride.advanceMock(45); return '#/ride'; },
  result: async ({ seed, model }) => { const p = alex(), e = finishedRamp(p, { daysAgo: 0, scale: 1.05 }); await seed(p, { sessions: [e.session] }); model.resultSessionID = e.session.id; return '#/result'; },
  'result-interrupted': async ({ seed, startRamp, model }) => { await seed(alex()); await startRamp(); model.ride.advanceMock(60 + 100); model.ride.interrupt('The trainer disconnected (simulated).'); await new Promise(r => setTimeout(r, 50)); return '#/result'; },
  'result-workout': async ({ seed, startWorkout, model }) => { await seed(alex()); await startWorkout('tempo-3x5', 600); model.ride.stop(); await new Promise(r => setTimeout(r, 50)); return '#/result'; },
  progress: async ({ seed }) => { const a = alex(), s = rider({ id: SAM_ID, name: 'Sam', weightKG: null, ftp: 180, daysAgo: 30 }); await seed([a, s], { sessions: [finishedRamp(a, { daysAgo: 56, scale: .94 }).session, finishedRamp(a, { daysAgo: 21, scale: .98 }).session, finishedRamp(s, { daysAgo: 14, scale: .85, preset: 'gentle' }).session] }); return '#/progress'; },
  'progress-empty': async ({ seed }) => { await seed(alex()); return '#/progress'; },
  settings: async ({ seed }) => { await seed(alex()); return '#/settings'; },
  'settings-debug': async ({ seed, model }) => { await seed(alex()); model.prefs.debugUnlocked = true; model.demoMode = true; return '#/settings'; },
});
// ======== end of foundation scenarios ========

// ======== ride plan (live power matching, Chaindance, cockpit): add its scenarios here ========
// ======== Intervals.icu and files plan: add its scenarios here ========
// ======== workouts plan (My workouts, builder, ZWO): add its scenarios here ========

export const scenarioNames = () => Object.keys(SCENARIOS);
/** Seed the model and return the hash to show. Uses the real model and the in-memory store of `?scenario=`. */
export async function applyScenario(name, model) {
  const scenario = SCENARIOS[name]; if (!scenario) throw Error(`Unknown scenario "${name}". Known: ${scenarioNames().join(', ')}`);
  const store = model.store;
  const ctx = {
    model, store,
    async seed(profiles, { sessions = [], workouts = [] } = {}) {
      for (const profile of [].concat(profiles)) await store.put('profiles', profile);
      for (const session of sessions) await store.put('sessions', session);
      if (workouts.length) await store.saveWorkouts(workouts);
      await model.reload(); model.prefs.selectedRider = [].concat(profiles)[0].id; model.applyRecommendation(); model.onboardingPending = false;
    },
    day: offset => { const d = new Date(); d.setDate(d.getDate() + offset); return ScheduledDate.stringFor(d); },
    async intervals(profile) {
      const plan = (id, name) => ({ ...planFor(definition(id), 230), name });
      const entry = (n, name, base, offset) => ({ id: `intervals:preview:${profile.id}:${n}`, riderID: profile.id, source: `Intervals.icu · ${name}`, savedAt: new Date().toISOString(), plan: plan(base, name), ...(offset == null ? {} : { scheduledDate: ctx.day(offset) }) });
      model.intervals.connection = { id: 'preview', name: 'Preview athlete', authorization: 'preview-only' };
      return [entry(1001, 'Sweet spot 3×12', 'sweet-spot-3x10', 0), entry(1002, 'Endurance with tempo', 'tempo-3x10', 1), entry(1003, 'Threshold 2×20', 'threshold-2x20', 4), entry(1004, 'Older calendar entry', 'endurance-60', null),
        { id: uuid(), riderID: profile.id, source: 'Imported JSON', savedAt: new Date().toISOString(), plan: { ...planFor(definition('over-unders-3x9'), 230), name: 'Club over-unders' } }];
    },
    async startRamp() { model.demoMode = true; Object.assign(model.draft, { quickDebug: false, warmupMinutes: 1, cooldownMinutes: 3, speed: 1 }); await model.startFTPTest(); clearInterval(model.ride.timer); },
    async startWorkout(id, seconds) { model.demoMode = true; model.draft.speed = 1; await model.startWorkout(`classic:${id}`); clearInterval(model.ride.timer); model.ride.advanceMock(seconds); },
    openDetail: ref => { model.pendingDetail = ref; },
  };
  return scenario(ctx);
}
