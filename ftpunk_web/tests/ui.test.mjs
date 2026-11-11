import { test, assert, equal } from './harness.mjs';
import { scenarioNames } from '../src/ui/scenarios.mjs';
import { parseHash, hashFor } from '../src/ui/shell.mjs';
import { ZONES } from '../src/rules/preview.mjs';
// Boots the real app in an iframe against each preview scenario (in-memory store, a made-up rider: 71 kg, 230 W) and checks what is on the page.
// This reads the DOM text; nobody has looked at it on a screen.
const STORY = /Cyclepunk|Lowline|Last Light|\bXP\b|\bCity\b/;
const frames = [];
async function open(query, { timeout = 20000, width = 1100, height = 900 } = {}) {
  const frame = document.createElement('iframe'); frame.style.cssText = `width:${width}px;height:${height}px;border:0`; frame.src = `/index.html?${query}&nosw`; document.body.append(frame); frames.push(frame);
  const start = Date.now();
  while (!(frame.contentWindow?.__ftpunk?.ready)) { if (Date.now() - start > timeout) throw Error(`The app did not start for ?${query}: ${(frame.contentWindow?.__ftpunkErrors ?? []).join('; ')} [state ${frame.contentDocument?.readyState}, main: ${frame.contentDocument?.querySelector('#main')?.textContent.slice(0, 80)}, url ${frame.contentWindow?.location.href}, loaded modules ${frame.contentWindow?.performance.getEntriesByType('resource').filter(e => e.name.endsWith('.mjs')).length}]`); await new Promise(r => setTimeout(r, 25)); }
  const win = frame.contentWindow, doc = win.document;
  const api = { frame, win, doc, app: win.__ftpunk, model: win.__ftpunk.model, text: () => doc.querySelector('#main').textContent.replace(/\s+/g, ' '), q: s => doc.querySelector(s), qa: s => [...doc.querySelectorAll(s)],
    wait: async (condition, label = 'condition') => { const t = Date.now(); while (!condition()) { if (Date.now() - t > 5000) throw Error(`Timed out waiting for ${label}`); await new Promise(r => setTimeout(r, 25)); } },
    close: () => { frame.remove(); } };
  assert(!win.__ftpunk.error, `Boot failed: ${win.__ftpunk.error}`);
  return api;
}
const scenario = async (name, body, size) => { const a = await open(`scenario=${name}`, size); try { assert(a.app.errors.length === 0, `Script errors in ${name}: ${a.app.errors.join('; ')}`); await body(a); assert(a.app.errors.length === 0, `Script errors in ${name}: ${a.app.errors.join('; ')}`); } finally { a.close(); } };

test('Routes parse and build, and old hashes still work', () => {
  equal(parseHash('#/preflight/workout/classic%3Atempo-3x5'), { name: 'preflight', params: ['workout', 'classic:tempo-3x5'] }); equal(parseHash(''), { name: 'home', params: [] });
  equal(parseHash('#history').name, 'progress'); equal(parseHash('#train').name, 'home'); equal(parseHash('#/activity/abc').params, ['abc']); equal(hashFor('preflight', 'workout', 'classic:x'), '#/preflight/workout/classic%3Ax');
});
test('Every preview scenario boots without script errors, and none mentions the story', async () => {
  for (const name of scenarioNames()) await scenario(name, a => { const text = a.doc.body.textContent; assert(a.text().length > 40, `${name} is empty`); assert(!STORY.test(text), `${name} mentions the story: ${text.match(STORY)}`); });
  assert(scenarioNames().length >= 8);
  for (const needed of ['home', 'home-empty', 'preflight-ftp', 'ride-ftp', 'ride-workout', 'result', 'progress', 'settings']) assert(scenarioNames().includes(needed), needed);
});
test('Home shows the rider, today, the FTP card, quick rides and the 14 classics', async () => scenario('home', async a => {
  const t = a.text();
  for (const s of ['Alex', 'Today · from Intervals.icu', 'Sweet spot 3×12', '230 W', 'W/kg', 'Quick ride', 'Free ERG', 'Resistance', 'Workouts', 'Upcoming', 'Endurance with tempo', 'My workouts', 'Club over-unders']) assert(t.includes(s), `Home lacks "${s}"`);
  equal(a.qa('#library .workout-card').length, 14); assert(t.includes('3.24 W/kg')); assert(a.q('#ftp-age') || a.q('#retest-due'));
  assert(a.qa('#sidebar-nav a').map(x => x.textContent.trim()).join('|').includes('Home') && a.qa('#tabbar a').length === 3);
  a.qa('[data-chip="category"]').find(c => c.dataset.value === 'vo2max').click(); await a.wait(() => a.qa('#library .workout-card').length === 2, 'category filter');
}));
test('Home without an FTP asks for a test first and marks classics as needing FTP', async () => scenario('home-empty', async a => {
  assert(a.text().includes('No FTP yet') && a.text().includes('Take an FTP test')); assert(a.q('.ftp-card') === a.q('.stack-l').firstElementChild.querySelector('.ftp-card') || a.q('.ftp-card')); equal(a.qa('#library .pill').length, 14);
  a.qa('#library .workout-card')[0].click(); await a.wait(() => a.q('#dialog').open, 'detail sheet'); assert(a.q('#dialog').textContent.includes('Needs FTP')); assert(a.q('#dialog [data-dialog="start"]').disabled);
}));
test('The retest prompt appears after eight weeks', async () => scenario('home-retest-due', async a => assert(a.q('#retest-due') && /time to retest/.test(a.q('#retest-due').textContent))));
test('The workout detail sheet shows the profile, steps with % FTP and watts, and the main set', async () => scenario('workout-detail', async a => {
  await a.wait(() => a.q('#dialog').open, 'detail sheet'); const t = a.q('#dialog').textContent.replace(/\s+/g, ' ');
  for (const s of ['VO2max 5×3', 'Main set: 5 × 3:00 @ 115 % (265 W)', '10:00', '50 %', '115 W']) assert(t.includes(s), `Detail lacks "${s}": ${t.slice(0, 300)}`);
  assert(a.qa('#dialog .profile .bar').length === 11 && a.qa('#dialog .steps li').length === 11);
  assert(ZONES.length === 6);
}));
test('First launch asks for a name, then shows Home with the new rider; the FTP is saved', async () => {
  const name = 'ftpunk-test-ui-' + crypto.randomUUID(), a = await open(`db=${name}&test=1`);
  try {
    assert(a.q('#onboarding-name') && a.text().includes('Welcome to FTPunk')); a.q('[data-action="onboarding-continue"]').click(); await a.wait(() => !a.q('#onboarding-error').hidden, 'name error');
    a.q('#onboarding-name').value = 'Robin'; a.q('#onboarding-weight').value = '64'; a.q('#onboarding-ftp').value = '210'; a.q('[data-action="onboarding-continue"]').click();
    await a.wait(() => a.text().includes('Quick ride'), 'home'); assert(a.text().includes('Robin') && a.text().includes('210 W'));
    const saved = (await a.model.store.all('profiles'))[0]; equal([saved.name, saved.weightKG, saved.ftpHistory[0].watts, saved.ftpHistory[0].source], ['Robin', 64, 210, 'Manual']);
  } finally { a.close(); await new Promise(r => setTimeout(r, 100)); await new Promise((res, rej) => { const req = indexedDB.deleteDatabase(name); req.onsuccess = res; req.onerror = rej; req.onblocked = res; }); }
});
test('Pre-flight lists the checklist and has no 72/75 picker; a blocked start explains why', async () => scenario('preflight-ftp', async a => {
  const t = a.text(); for (const s of ['Rider', 'Alex · 71 kg · FTP 230 W', 'Devices', 'Protocol', '25 W / min', 'Estimate', '72 % of your best minute', 'Warm-up and cool-down', 'Warm-up 10 min at 115 W · cool-down 3 min']) assert(t.includes(s), `Pre-flight lacks "${s}"`);
  assert(!/75\s?%/.test(t) && !a.q('#ftpFactor')); const start = a.q('#start-button'); assert(start.disabled); assert(a.q('#start-reason').textContent.length > 10 && !a.q('#start-reason').hidden);
}));
test('A new FTP test always has the 72 % factor, and a 60 kg rider is recommended the gentle ramp', async () => scenario('preflight-ftp', async a => {
  const m = a.model; equal(m.testConfiguration().ftpFactor, 0.72); m.demoMode = true; m.draft.quickDebug = true; equal(m.testConfiguration().ftpFactor, 0.72);
  equal(m.testConfiguration().warmupSeconds, 10); equal(m.testConfiguration().priorFTP, 230);
  await m.saveRiderDetails({ name: 'Alex', weight: '58' }); equal(m.draft.preset, 'gentle'); equal(m.testConfiguration().preset, 'gentle'); equal(m.testConfiguration().ftpFactor, 0.72);
}));
test('A workout pre-flight shows the profile, FTP used and the intensity stepper, which scales the targets', async () => scenario('preflight-workout', async a => {
  const t = a.text(); for (const s of ['Sweet spot 3×10', 'FTP used', '230 W', 'Intensity', '100 %', 'Tempo']) assert(t.includes(s), `Missing "${s}"`);
  a.q('[data-action="intensity-plus"]').click(); await a.wait(() => a.q('#pf-intensity').textContent === '105 %', 'intensity'); equal(a.model.draft.intensity, 105);
}));
test('The FTP cockpit mid-ramp shows target, actual, the step countdown and a hold-to-finish button', async () => scenario('ride-ftp', async a => {
  await a.wait(() => a.q('#cockpit-title')?.textContent.startsWith('RAMP'), 'ramp title'); assert(/^\d+$/.test(a.q('#live-target').textContent) && /^\d+$/.test(a.q('#live-power').textContent));
  assert(a.q('.ring-row') && a.q('[data-hold="finish"]') && a.q('[data-testid="stop-save"]')); assert(a.q('.timeline')); assert(/MAX|Best/.test(a.text()) && /^\d+$/.test(a.q('#live-best').textContent));
  assert(a.q('#live-link, #live-bar')?.hidden !== false); equal(a.model.ride.engine.session.configuration.ftpFactor, 0.72);
}));
test('The workout cockpit shows the profile with a progress marker, the step and the intensity controls', async () => scenario('ride-workout', async a => {
  await a.wait(() => a.q('#cd-step-corner')?.textContent.includes('/'), 'step'); assert(a.q('#profile-marker') && a.q('[data-action="intensity-minus"]') && a.q('[data-action="pause-resume"]'));
  const before = a.q('#live-target').textContent; a.q('[data-action="intensity-plus"]').click(); await a.wait(() => a.model.ride.engine.intensity === 105, 'intensity'); await a.wait(() => a.q('#cd-intensity-corner')?.textContent.includes('105'), 'intensity shown');
  a.q('[data-action="pause-resume"]').click(); await a.wait(() => a.model.ride.engine.phase === 'paused', 'pause'); assert(before.length);
}));
test('The result shows the estimate with its delta, the chart and adoption; adopting updates the rider', async () => scenario('result', async a => {
  const t = a.text(); for (const s of ['ESTIMATED FTP', 'W/kg', '% of your best minute', 'How this is calculated', 'Use ']) assert(t.includes(s), `Result lacks "${s}"`);
  assert(/(\+|−)\d+ W vs 230 W|Same as your current 230 W/.test(t)); assert(a.q('.power-chart') && a.q('.power-chart .best-window')); assert(a.q('.power-chart .band-label'));
  a.q('[data-action="adopt"]').click(); await a.wait(() => a.q('#ftp-adopted'), 'adoption'); assert(a.q('#training-handoff') && /Library workouts now use/.test(a.text())); assert(a.model.ftp > 0 && a.model.ftpEntry.source === 'Ramp test');
  a.q('[data-action="done"]').click(); await a.wait(() => a.text().includes('Quick ride'), 'home');
}));
test('An interrupted result says what happened and what was saved', async () => scenario('result-interrupted', async a => { const t = a.text(); assert(t.includes('Test interrupted') && t.includes('Saved on this device') && t.includes('No FTP estimate')); }));
test('A finished workout shows its time and average power', async () => scenario('result-workout', async a => { const t = a.text(); assert(t.includes('Ride saved') || t.includes('Ride complete')); assert(t.includes('Average power') && t.includes('Time')); }));
test('Progress shows per-rider trends, filters, rows and confirms before deleting', async () => scenario('progress', async a => {
  const t = a.text(); for (const s of ['FTP trend', 'Alex', 'FTP tests', 'Workouts', 'Free rides', 'FTP test']) assert(t.includes(s), `Progress lacks "${s}"`);
  assert(a.q('.trend-chart') && a.qa('.trend-chart .point').length >= 2); equal(a.qa('.activity-row').length, 2); // current rider only
  a.q('#pg-scope').value = 'all'; a.q('#pg-scope').dispatchEvent(new a.win.Event('change', { bubbles: true })); await a.wait(() => a.qa('.activity-row').length === 3, 'all riders');
  assert(a.qa('.trend-chart .series').length === 2); a.qa('[data-chip="Activity type"]').find(c => c.dataset.value === 'workouts').click(); await a.wait(() => a.qa('.activity-row').length === 0, 'filter');
  a.qa('[data-chip="Activity type"]').find(c => c.dataset.value === 'all').click(); await a.wait(() => a.qa('.activity-row').length === 3, 'filter back');
  a.q('[data-action="delete-activity"]').click(); await a.wait(() => a.q('#dialog').open && a.q('#dialog').textContent.includes('Delete this activity?'), 'confirmation'); assert(a.qa('.activity-row').length === 3);
  a.q('#dialog [data-dialog="confirm"]').click(); await a.wait(() => a.qa('.activity-row').length === 2, 'deleted');
  a.q('[data-action="open-activity"]').click(); await a.wait(() => a.win.location.hash.startsWith('#/activity/'), 'detail'); await a.wait(() => a.q('.power-chart'), 'detail chart'); assert(/This activity/.test(a.text()) && /Estimate factor/.test(a.text()));
}));
test('Settings has the native groups, and debug unlocks after ten taps on About', async () => scenario('settings', async a => {
  const t = a.text(); for (const s of ['Riders', 'Devices', 'Ride display', 'Intervals.icu', 'Backup & transfer', 'About', 'Extra-large ride numbers', 'Theme']) assert(t.includes(s), `Settings lacks "${s}"`);
  assert(!a.q('#settings-debug')); for (let i = 0; i < 10; i++) a.q('[data-action="about-tap"]').click(); await a.wait(() => a.q('#settings-debug'), 'debug group'); assert(a.model.demoMode && a.model.prefs.debugUnlocked);
  a.q('[data-action="hide-debug"]').click(); await a.wait(() => !a.q('#settings-debug'), 'debug hidden'); assert(!a.model.demoMode);
}));
test('Appearance and ride-number preferences apply to the page', async () => scenario('settings', async a => {
  a.qa('[data-chip="Theme"]').find(c => c.dataset.value === 'dark').click(); await a.wait(() => a.doc.documentElement.dataset.appearance === 'dark', 'dark'); const extra = a.q('#st-extra-large'); extra.checked = true; extra.dispatchEvent(new a.win.Event('change', { bubbles: true }));
  await a.wait(() => a.doc.documentElement.classList.contains('large-numbers'), 'large numbers');
}));
test('The rider sheet switches riders and the devices sheet opens from the pill', async () => scenario('progress', async a => {
  a.q('#sidebar-nav a[href="#/home"]').click(); await a.wait(() => a.q('.rider-chip'), 'home'); a.q('.rider-chip').click(); await a.wait(() => a.q('#dialog').open && a.q('#dialog').textContent.includes('Riders'), 'rider sheet'); assert(a.q('#dialog').textContent.includes('Sam'));
  a.q('#dialog [data-dialog^="select:"]:not([aria-pressed="true"])').click(); await a.wait(() => a.model.profile.name === 'Sam', 'switch'); a.q('#dialog [data-dialog="close"]').click(); await a.wait(() => !a.q('#dialog').open, 'closed');
  a.q('.devices-pill').click(); await a.wait(() => a.q('#dialog').open && a.q('#dialog').textContent.includes('Smart trainer'), 'devices sheet'); a.q('#dialog [data-dialog="close"]').click();
}));

test('No scenario overflows the page sideways on a small phone (360 px), a phone (390 px) or a desktop window (1280 px)', async () => {
  for (const [width, height] of [[360, 800], [390, 844], [1280, 800]]) for (const name of scenarioNames()) await scenario(name, async a => {
    const root = a.doc.documentElement, wide = [...a.doc.querySelectorAll('main *')].filter(e => e.getBoundingClientRect().right > root.clientWidth + 1 && !e.closest('.chips, .profile, svg, dialog, [hidden]'));
    assert(root.scrollWidth <= root.clientWidth + 1, `${name} at ${width}px scrolls sideways (${root.scrollWidth} > ${root.clientWidth}); first wide element: ${wide[0]?.tagName}.${wide[0]?.className}`);
  }, { width, height });
});
test('Every interactive control has an accessible name', async () => {
  for (const name of ['home', 'preflight-ftp', 'ride-ftp', 'result', 'progress', 'settings']) await scenario(name, async a => {
    for (const el of a.qa('main button, main a[href], main input, main select, #tabbar a, #sidebar-nav a')) { const label = el.getAttribute('aria-label') || el.textContent.trim() || el.labels?.[0]?.textContent.trim() || el.getAttribute('title'); assert(label, `${name}: unnamed ${el.tagName} ${el.outerHTML.slice(0, 120)}`); }
  });
});
