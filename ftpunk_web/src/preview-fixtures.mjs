import { RampEngine, configuration, mockSample } from './domain.mjs';
// Deterministic riders and recordings for preview scenarios (`?scenario=` boots with an in-memory store, never the real database).
// The rider is made up: 71 kg and 230 W. Recordings run through the real engine with the mock sensor stream.
export const ALEX_ID = 'a1e00000-0000-4000-8000-000000000001', SAM_ID = '5a400000-0000-4000-8000-000000000002';
const entryID = watts => `f7000000-0000-4000-8000-${String(Math.round(watts)).padStart(12, '0')}`;
export function rider({ id = ALEX_ID, name = 'Alex', weightKG = 71, ftp = 230, daysAgo = 21, source = 'Ramp test' } = {}) {
  const entry = ftp == null ? null : { id: entryID(ftp), watts: ftp, date: new Date(Date.now() - daysAgo * 86400000).toISOString(), source };
  return { id, name, weightKG, ftpHistory: entry ? [entry] : [], currentFTPID: entry?.id ?? null };
}
/** A finished ramp. `scale` shapes the power a rider holds (the mock rider gives up once the target passes 300 W). */
export function finishedRamp(profile, { daysAgo, scale = 1, demo = false, preset = 'standard' }) {
  const ftp = profile.ftpHistory.find(e => e.id === profile.currentFTPID)?.watts ?? null;
  const config = configuration({ preset, priorFTP: ftp, weightKG: profile.weightKG, warmupSeconds: 10, cooldownSeconds: 10, riderID: profile.id, riderName: profile.name });
  const engine = new RampEngine(config, { demo, date: new Date(Date.now() - daysAgo * 86400000).toISOString() });
  for (let index = 1; index <= 3600 && engine.active; index++) {
    const time = index / 2, target = engine.target ?? config.warmupPower;
    engine.receive(mockSample(time, target * scale, engine.phase, 'exhaustion')); engine.tick(time);
  }
  return engine;
}
