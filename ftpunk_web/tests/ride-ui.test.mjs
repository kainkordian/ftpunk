import { test, assert, equal } from './harness.mjs';
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

test('The cockpit draws Chaindance as a strip by default, with the placement menu in the header', async () => scenario('ride-workout-strip', async a => {
  const canvas = a.q('#chaindance-canvas'); assert(canvas); equal([canvas.width, canvas.height], [192, 60]); assert(!a.q('#chaindance-readout'));
  assert(pixels(canvas).lit > 200, 'the strip is not blank'); assert(/Chaindance/.test(canvas.getAttribute('aria-label')) && canvas.getAttribute('role') === 'img');
  assert(a.win.getComputedStyle(canvas).imageRendering === 'pixelated');
  const menu = a.q('#chaindance-placement'); assert(menu && menu.value === 'strip' && menu.options.length === 3 && menu.closest('.cockpit-header'));
  // The strip sits between the readings: after the target and actual, before the supporting tiles.
  const order = a.qa('.cockpit [data-block]').map(b => b.dataset.block); equal(order, ['progress', 'heroTiles', 'strip', 'tiles', 'controls', 'notes']);
  assert(a.q('#blk-notes').textContent.length > 5);
}));
test('The menu is outside the per-tick update path: telemetry never rebuilds it', async () => scenario('ride-workout-strip', async a => {
  const menu = a.q('#chaindance-placement'), canvas = a.q('#chaindance-canvas'), header = a.q('.cockpit-header');
  for (let i = 0; i < 5; i++) { a.model.ride.advanceMock(3); a.model.onChange(); await new Promise(r => setTimeout(r, 30)); }
  assert(a.q('#chaindance-placement') === menu && a.q('#chaindance-canvas') === canvas && a.q('.cockpit-header') === header, 'the header, the menu and the canvas keep their elements');
}));
test('Changing the placement re-renders once, is a preference, and Off removes the visual', async () => scenario('ride-workout-strip', async a => {
  const menu = a.q('#chaindance-placement'); menu.value = 'hero'; menu.dispatchEvent(new a.win.Event('change', { bubbles: true }));
  await a.wait(() => a.q('.cockpit')?.dataset.visual === 'hero' && a.q('#chaindance-canvas')?.height === 96, 'Large view'); equal(a.model.prefs.rideVisualPlacement, 'hero');
  const off = a.q('#chaindance-placement'); off.value = 'off'; off.dispatchEvent(new a.win.Event('change', { bubbles: true }));
  await a.wait(() => a.q('.cockpit')?.dataset.visual === 'off', 'Off'); assert(!a.q('#chaindance') && a.q('#live-target')); equal(a.model.prefs.rideVisualPlacement, 'off');
  assert(a.q('#chaindance-placement').value === 'off');
}));
test('The Large view: a taller raster, the readout in the sky band, and two columns on a wide window', async () => scenario('ride-workout-large', async a => {
  const canvas = a.q('#chaindance-canvas'); equal([canvas.width, canvas.height], [192, 96]); assert(pixels(canvas).lit > 300);
  const readout = a.q('#chaindance-readout'), box = a.q('#chaindance').getBoundingClientRect(), r = readout.getBoundingClientRect();
  assert(Math.abs(r.height / box.height - 36 / 96) < 0.01, `readout is ${(r.height / box.height).toFixed(3)} of the scene`); assert(r.top >= box.top - 1 && r.bottom <= box.top + box.height * 0.376 + 1);
  assert(/\d/.test(a.q('#readout-target').textContent) && /\d/.test(a.q('#readout-actual').textContent) && /STEP \d\/\d+ · \d+:\d\d/.test(a.q('#readout-detail').textContent), 'target, actual and the step show in the sky');
  assert(!a.q('#live-target'), 'the big tiles are replaced by the readout');
  const cols = a.q('#cockpit-cols'); assert(cols.classList.contains('side-by-side'), 'wide window: two columns');
  equal(a.qa('#col-main > [data-block]').map(b => b.dataset.block), ['scene', 'progress']); equal(a.qa('#col-side > [data-block]').map(b => b.dataset.block), ['tiles', 'controls', 'notes']);
  const left = a.q('#col-main').getBoundingClientRect(), right = a.q('#col-side').getBoundingClientRect(); assert(right.left >= left.right - 1 && right.width <= 421, 'the readings column is beside the scene');
  assert(a.q('#blk-scene').getBoundingClientRect().width > 450, 'the scene takes the wide column');
}));
test('The Large view stays one column on a narrow window and puts the scene first', async () => scenario('ride-workout-large', async a => {
  assert(!a.q('#cockpit-cols').classList.contains('side-by-side')); equal(a.qa('#col-main > [data-block]').map(b => b.dataset.block), ['progress', 'scene', 'tiles', 'controls', 'notes']); assert(a.q('#col-side').children.length === 0);
  const box = a.q('#chaindance').getBoundingClientRect(); assert(box.width <= 400 && box.width > 300, `the scene fills the phone width: ${box.width}`);
}, { width: 390, height: 844 }));
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
test('Extra-large ride numbers use the compact cockpit and fall back from the Large view to the strip', async () => {
  const a = await open('scenario=ride-workout-large'); try {
    a.model.prefs.extraLarge = true; a.model.savePrefs(); a.win.__ftpunk.rerender?.(); a.win.dispatchEvent(new a.win.HashChangeEvent('hashchange'));
    await a.wait(() => a.q('.cockpit')?.dataset.visual === 'strip', 'strip fallback'); assert(a.q('.cockpit-header').classList.contains('compact')); assert(a.q('.support-tiles.rows'));
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
