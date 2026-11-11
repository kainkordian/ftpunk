import { test, assert, equal, fixture } from './harness.mjs';
import { heartRateChart } from '../src/ui/charts.mjs';
import { ChaindanceView, chaindanceHTML, placementMenuHTML } from '../src/chaindance/view.mjs';
import { RampEngine, configuration } from '../src/domain.mjs';

// The ride screen in the real app, in an iframe against the preview scenarios (in-memory store, a made-up rider: 71 kg, 230 W). These read the DOM,
// the canvas pixels and layout bounds; nobody has looked at them on a screen.
const frames = [];
async function open(query, { timeout = 20000, width = 1280, height = 900 } = {}) {
  const frame = document.createElement('iframe'); frame.style.cssText = `width:${width}px;height:${height}px;border:0`; frame.src = `/index.html?${query}&nosw`; document.body.append(frame); frames.push(frame);
  const start = Date.now();
  while (!(frame.contentWindow?.__ftpunk?.ready)) { if (Date.now() - start > timeout) throw Error(`The app did not start for ?${query}: ${(frame.contentWindow?.__ftpunkErrors ?? []).join('; ')}`); await new Promise(r => setTimeout(r, 50)); }
  const win = frame.contentWindow, doc = win.document;
  return { frame, win, doc, model: win.__ftpunk.model, app: win.__ftpunk, q: s => doc.querySelector(s), qa: s => [...doc.querySelectorAll(s)], text: () => doc.querySelector('#main').textContent.replace(/\s+/g, ' '),
    wait: async (condition, label = 'condition') => { const t = Date.now(); while (!condition()) { if (Date.now() - t > 5000) throw Error(`Timed out waiting for ${label}`); await new Promise(r => setTimeout(r, 25)); } },
    close: () => frame.remove() };
}
const scenario = async (name, body, size) => { const a = await open(`scenario=${name}`, size); try { assert(a.app.errors.length === 0, `Script errors in ${name}: ${a.app.errors.join('; ')}`); await body(a); assert(a.app.errors.length === 0, `Script errors in ${name}: ${a.app.errors.join('; ')}`); } finally { a.close(); } };
const pixels = canvas => { const { width, height } = canvas, data = canvas.getContext('2d').getImageData(0, 0, width, height).data; let lit = 0; for (let i = 0; i < data.length; i += 4) if (data[i] + data[i + 1] + data[i + 2] > 120) lit++; return { width, height, lit }; };

test('The heart-rate chart keeps its title on a row of its own above the plot', async () => {
  const base = await fixture('fit-ftp-test.session');
  for (const [lowest, highest] of [[140, 142], [95, 175], [58, 201]]) {
    const samples = base.samples.map((s, i) => ({ ...s, heartRate: i % 2 ? lowest : highest }));
    const svg = new DOMParser().parseFromString(heartRateChart({ ...base, samples }), 'image/svg+xml');
    const title = [...svg.querySelectorAll('.axis-title')].find(t => t.textContent === 'bpm'), ticks = [...svg.querySelectorAll('.axis[text-anchor="end"]')].map(t => Number(t.getAttribute('y')));
    // Measured at the 17-unit phone-width axis text: a 4-unit descender on the title, 13-unit digits on the tick.
    assert(Number(title.getAttribute('y')) + 4 <= Math.min(...ticks) - 13, `bpm collides with the top tick for ${lowest} to ${highest}`);
    equal(svg.documentElement.getAttribute('viewBox'), '0 0 600 172');
  }
});

for (const [label, size] of [['wide', { width: 1280, height: 900 }], ['on a phone', { width: 390, height: 844 }]]) test(`The balance reading stays on one line with its unit, ${label}`, async () => scenario('ride-workout-strip', async a => {
  const value = a.q('#live-balance'), tile = value.closest('.cd-box'), unit = tile.querySelector('.cd-unit'); assert(tile && unit, 'the balance tile has a value and a unit');
  for (const text of ['50 / 50', '100 / 0']) {
    value.textContent = text; const v = value.getBoundingClientRect(), u = unit.getBoundingClientRect(), t = tile.getBoundingClientRect();
    equal(value.getClientRects().length, 1); assert(u.top < v.bottom && u.bottom > v.top, 'the unit shares the line');
    assert(v.left >= t.left && u.right <= t.right - 1, `the reading fits the tile: ${u.right} against ${t.right}`); assert(tile.scrollWidth <= tile.clientWidth, 'nothing is clipped');
  }
}, size));

test('The target legend swatch is dashed in light and dark', async () => scenario('ride-workout-strip', async a => {
  a.q('#main').insertAdjacentHTML('beforeend', '<div class="chart-legend"><span class="swatch target"></span></div>'); const swatch = a.q('.chart-legend .swatch.target');
  for (const appearance of ['light', 'dark']) { a.doc.documentElement.dataset.appearance = appearance; const style = a.win.getComputedStyle(swatch); assert(/repeating-linear-gradient.*rgba\(0, 0, 0, 0\)/.test(style.backgroundImage), `no dashes in ${appearance}: ${style.backgroundImage}`); assert(swatch.getBoundingClientRect().height >= 2, 'the swatch is drawn'); }
}));

test('The workout cockpit is the dashboard: no Chaindance, the figures grid, and a Skip button that skips', async () => scenario('ride-workout-strip', async a => {
  assert(a.q('.cockpit.dash') && !a.q('#chaindance-canvas') && !a.q('#chaindance-placement'), 'no Chaindance in the workout cockpit');
  equal(a.qa('#cd-figures .cd-fig').length, 11, 'every figure box is there'); assert(a.q('#cockpit-profile svg') && a.q('#live-power') && a.q('#live-target'));
  const before = a.model.ride.engine.session.events.length, skip = a.q('#skip-step'); assert(skip && !skip.disabled); skip.click();
  await a.wait(() => a.model.ride.engine.session.events.some(e => /^Skipped ahead [\d.]+ s to step \d+$/.test(e.message)), 'skip event'); assert(a.model.ride.engine.session.events.length > before);
}));
test('The dashboard header and canvases are not rebuilt by telemetry; only text changes', async () => scenario('ride-workout-strip', async a => {
  const header = a.q('.cockpit-header'), figures = a.q('#cd-figures'), big = a.q('#cd-big'), profile = a.q('#cockpit-profile svg');
  for (let i = 0; i < 5; i++) { a.model.ride.advanceMock(3); a.model.onChange(); await new Promise(r => setTimeout(r, 30)); }
  assert(a.q('.cockpit-header') === header && a.q('#cd-figures') === figures && a.q('#cd-big') === big && a.q('#cockpit-profile svg') === profile, 'the elements keep their identity across ticks');
}));
test('Free rides and resistance rides use the dashboard too; the FTP cockpit keeps Chaindance', async () => {
  for (const name of ['ride-free', 'ride-resistance']) await scenario(name, async a => { assert(a.q('.cockpit.dash') && !a.q('#chaindance-canvas'), `${name} is the dashboard`); });
  await scenario('ride-ftp', async a => { assert(!a.q('.cockpit.dash') && a.q('#chaindance-canvas'), 'the FTP cockpit is unchanged'); });
});
test('Matching status: warming shows in the warm-up like native, and a fade hold is reported', async () => {
  await scenario('ride-ftp-cold', async a => {
    equal(a.model.ride.matchingStatus.kind, 'warming'); assert(a.model.ride.engine.session.configuration.powerMatchingEnabled, 'the ride uses power matching');
    await a.wait(() => /Power matching: Warming up the trainer · \d+ %/.test(a.q('#cockpit-matching').textContent), 'the status line'); assert(a.q('#chaindance-canvas') && a.q('#cockpit-timeline'));
    equal(a.q('#cockpit-notes').textContent, '', 'native shows the coaching line only without Chaindance');
    const menu = a.q('#chaindance-placement'); menu.value = 'off'; menu.dispatchEvent(new a.win.Event('change', { bubbles: true }));
    await a.wait(() => /Trainer warming up — power matching is settling/.test(a.q('#cockpit-notes')?.textContent ?? ''), 'the warm-up line');
  });
  await scenario('ride-ftp-fade', async a => {
    equal(a.model.ride.matchingStatus.kind, 'fadeHold'); await a.wait(() => /Fade hold/.test(a.q('#cockpit-matching').textContent), 'the fade status');
    equal(a.q('.cockpit').dataset.kind, 'ftp'); assert(/RAMP/.test(a.q('#cockpit-title').textContent) && a.q('[data-hold="finish"]'));
  });
});
test('The ramp never stands the rider up, and the FTP cockpit keeps its coaching text off while the strip is on', async () => scenario('ride-ftp', async a => {
  assert(a.q('#chaindance-canvas') && /Chaindance: .*level \d+/.test(a.q('#chaindance-canvas').getAttribute('aria-label'))); assert(!/out of the saddle/.test(a.text())); equal(a.q('#cockpit-notes').textContent, '');
  equal(a.model.ride.matchingStatus.kind, 'off');
}));
test('Settings → Ride display offers Chaindance on/off and its layout, and they change the same preference', async () => scenario('settings', async a => {
  assert(a.text().includes('Show Chaindance during rides')); const layout = a.q('#st-chaindance-layout'); assert(layout && layout.value === 'strip');
  layout.value = 'hero'; layout.dispatchEvent(new a.win.Event('change', { bubbles: true })); await a.wait(() => a.model.prefs.rideVisualPlacement === 'hero', 'layout');
  const toggle = a.q('#st-chaindance'); toggle.checked = false; toggle.dispatchEvent(new a.win.Event('change', { bubbles: true })); await a.wait(() => a.model.prefs.rideVisualPlacement === 'off' && !a.q('#st-chaindance-layout'), 'off');
  const again = a.q('#st-chaindance'); again.checked = true; again.dispatchEvent(new a.win.Event('change', { bubbles: true })); await a.wait(() => a.model.prefs.rideVisualPlacement === 'strip', 'on restores the strip');
}));
test('Extra-large ride numbers use the compact header on the dashboard', async () => {
  const a = await open('scenario=ride-workout-large'); try {
    a.model.prefs.extraLarge = true; a.model.savePrefs(); a.win.__ftpunk.rerender?.(); a.win.dispatchEvent(new a.win.HashChangeEvent('hashchange'));
    await a.wait(() => a.q('.cockpit-header')?.classList.contains('compact'), 'compact header'); assert(a.q('.cockpit.dash') && !a.q('#chaindance-canvas'));
  } finally { a.close(); }
});

// ---- the view itself, with a fake environment ----
const fakeEnv = ({ reduce = false, hidden = false } = {}) => ({ document: { hidden }, matchMedia: query => ({ matches: reduce && query.includes('reduced-motion'), addEventListener() {}, removeEventListener() {} }) });
function rideSource() {
  const engine = new RampEngine(configuration({ priorFTP: 230, weightKG: 71, warmupSeconds: 60 }), { demo: true });
  for (let t = 0; t <= 90; t += 0.5) { engine.receive({ time: t, power: 200, cadence: 90 }); engine.tick(t); }
  return { engine, elapsed: 90, playbackSpeed: 1, mockPaused: false };
}
function makeView(env, hero = false) {
  const holder = document.createElement('div'); holder.innerHTML = chaindanceHTML({ hero }); document.body.append(holder);
  const view = new ChaindanceView(holder.firstElementChild, rideSource, { env, now: () => performance.now() / 1000 }); let draws = 0; view.ctx = { putImageData: () => { draws++; } }; view.signature = null;
  return { view, holder, draws: () => draws };
}
test('The view animates while visible and stops for Reduce Motion, a hidden tab and a paused debug stream', () => {
  const live = makeView(fakeEnv()); live.view.frame(); live.view.frame(); assert(live.view.animating); equal(live.draws(), 2, 'every frame draws while animating'); live.view.stop(); live.holder.remove();
  const calm = makeView(fakeEnv({ reduce: true })); calm.view.frame(); calm.view.frame(); calm.view.frame(); assert(!calm.view.animating); equal(calm.draws(), 1, 'Reduce Motion draws once until the state changes'); calm.view.stop(); calm.holder.remove();
  const hidden = makeView(fakeEnv({ hidden: true })); assert(!hidden.view.animating); hidden.view.stop(); hidden.holder.remove();
  const paused = makeView(fakeEnv()); const source = paused.view.source; paused.view.source = () => ({ ...source(), mockPaused: true }); assert(!paused.view.animating); paused.view.stop(); paused.holder.remove();
});
test('The view stops itself when it leaves the page, and never calls anything on the ride', () => {
  const v = makeView(fakeEnv()); let touched = 0; const source = v.view.source; v.view.source = () => { const r = source(); return new Proxy(r, { get: (t, k) => { if (typeof t[k] === 'function') touched++; return t[k]; } }); };
  v.view.frame(); equal(touched, 0); v.holder.remove(); v.view.frame(); equal(v.view.timer, null);
  assert(chaindanceHTML({ hero: true }).includes('chaindance-readout') && !chaindanceHTML().includes('chaindance-readout')); assert(placementMenuHTML('hero').includes('value="hero" selected'));
});
