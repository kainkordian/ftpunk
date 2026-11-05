import { test, assert, equal, fixtureText } from './harness.mjs';
import { parseArchive, archiveText, archiveSessions, makeArchive } from '../src/archive.mjs';
import { LocalStore } from '../src/storage.mjs';
import { MemoryStore } from '../src/memory-store.mjs';
import { RampEngine, configuration } from '../src/domain.mjs';
// The story is gone from the app, but its data stays in backups: contracts/README.md, "Story fields are legacy".
const STORY_FIELDS = ['adventureEnabled', 'eligibleMilliseconds', 'adventureStartMilliseconds'];
const story = archive => ({ ledgers: archive.profiles.map(p => [p.id, p.cycleProgress ?? null]), sessions: archive.activities.map(a => [a.session.id, ...STORY_FIELDS.map(k => a.session[k] ?? null)]) });

for (const version of [1, 2, 3]) test(`Archive v${version} fixture imports and re-exports with its story fields unchanged`, async () => {
  const original = JSON.parse(await fixtureText(`portable-v${version}`)), archive = parseArchive(JSON.stringify(original)), again = parseArchive(archiveText(archive));
  equal(again.version, original.version); equal(story(again), story(original)); equal(story(archive), story(original));
  // The in-app round trip (import into the browser's format and export again) changes nothing either.
  const sessions = archiveSessions(archive), exported = parseArchive(archiveText(makeArchive(archive.profiles, sessions, archive.exportedAt, archive.workouts ?? [])));
  equal(story(exported), story(original)); equal(exported.version, original.version);
  if (version >= 2) assert(story(original).sessions.some(s => s[1] === true)); if (version === 2) assert(original.profiles.some(p => p.cycleProgress));
  if (version === 3) assert(story(original).sessions.some(s => s[3] === 0));
});
test('New recordings omit the story fields and never add credits to a rider', async () => {
  const e = new RampEngine(configuration({ warmupSeconds: 0 }), {}); for (let t = 0; t <= 70; t++) { e.receive({ time: t, power: 300, cadence: 90 }); e.tick(t); } e.finishRamp(70); e.end(71);
  const store = new MemoryStore(), rider = { id: e.session.configuration.riderID ?? '00000000-0000-0000-0000-000000000001', name: 'You', ftpHistory: [], currentFTPID: null };
  for (const field of STORY_FIELDS) assert(!(field in e.session), field);
  const archive = makeArchive([rider], [e.session]); equal(archive.version, 1); for (const a of archive.activities) for (const field of STORY_FIELDS) assert(!(field in a.session), field);
  await store.saveSession(e.session); assert(!(await store.all('profiles')).some(p => p.cycleProgress));
});
