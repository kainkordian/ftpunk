import { esc, $, $$ } from './components.mjs';
import { DurationFormat, riderInitials } from '../rules/presentation.mjs';
import { PHASES } from '../domain.mjs';
// The shell: hash router, sidebar and tab bar, live-ride bar, notices, sheets (dialogs) and the guards that protect a live ride.
// Screens register themselves with `registerRoute`; the shell never imports a screen. Owned by the foundation plan only.

export const DESTINATIONS = Object.freeze([['home', 'Home', '⌂'], ['progress', 'Progress', '↗'], ['settings', 'Settings', '⚙']]);
const routes = new Map(), globalActions = new Map();
let model = null, current = null, sheet = null, lastRenderKey = null;

/** spec: { tab?, render(model, params) -> html, bind?(root, model, params), update?(model, params), actions?(model, params) -> { name: (element, event) => void },
            events?(model, params) -> { change|input|submit: { id: handler } }, onRideSaved?(model, session), standalone? (no tab bar highlight) } */
export const registerRoute = (name, spec) => routes.set(name, spec);
/** Actions available on every screen (open the rider sheet, the devices sheet, ...). */
export const registerGlobalAction = (name, handler) => globalActions.set(name, handler);
export const routeNames = () => [...routes.keys()];

const LEGACY = { train: 'home', setup: 'home', city: 'home', history: 'progress', settings: 'settings', ride: 'ride' };
/** '#/preflight/workout/classic:tempo-3x5' -> { name: 'preflight', params: ['workout', 'classic:tempo-3x5'] }. Old hashes (#train, #history, ...) still work. */
export function parseHash(hash = location.hash) {
  const parts = hash.replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeURIComponent);
  const name = parts[0] ? (LEGACY[parts[0]] ?? parts[0]) : 'home';
  return { name, params: parts.slice(1) };
}
export const hashFor = (name, ...params) => `#/${[name, ...params].map(encodeURIComponent).join('/')}`;
export function navigate(hash, { replace = false } = {}) { if (replace) { history.replaceState(null, '', hash); render(); } else if (location.hash === hash) render(); else location.hash = hash; }

// ----- notices, announcements, safety wrappers ---------------------------------------------------------------------------------
export function notify(message, error = false) {
  const box = $('#notice'); if (!box) return; box.hidden = !message; box.className = error ? 'notice error' : 'notice'; box.replaceChildren(); box.setAttribute('role', error ? 'alert' : 'status');
  if (message) { const text = document.createElement('span'); text.textContent = message; const button = document.createElement('button'); button.type = 'button'; button.className = 'btn tertiary small'; button.textContent = 'Dismiss'; button.onclick = () => notify(null); box.append(text, button); }
}
export const fail = error => { if (error?.name === 'NotFoundError') return; notify(error?.message ?? String(error), true); };
export const safely = action => async (...args) => { try { await action(...args); } catch (error) { fail(error); } };
export const announce = text => { const box = $('#announce'); if (box) box.textContent = text; };
export function applyPreferences(prefs) { document.documentElement.dataset.appearance = prefs.appearance; document.documentElement.classList.toggle('large-numbers', prefs.extraLarge); }

// ----- sheets --------------------------------------------------------------------------------------------------------------------
/** A modal sheet. `content` and `actions` are HTML strings or functions returning them (functions are re-evaluated by `refreshSheet` when `live`).
    `handler(action, dialog, event)` runs for every [data-dialog] button; an error it throws is shown inside the sheet. `onChange(event, dialog)` for form controls. */
export function openSheet({ title, content, actions = '', handler = null, live = false, onOpen = null, onChange = null }) {
  const dialog = $('#dialog'); if (dialog.open) dialog.close();
  sheet = { title, content, actions, handler, live, onChange, html: null };
  dialog.innerHTML = `<div class="dialog-head"><h2 id="dialog-title">${esc(title)}</h2><button type="button" class="icon-btn" data-close aria-label="Close dialog">×</button></div><div class="dialog-content"></div><div class="dialog-actions"></div>`;
  paintSheet(dialog); dialog.showModal();
  // showModal() focuses the first control, the ✕ in the header, which then shows a focus ring. The dialog itself takes focus instead (named by its title).
  dialog.tabIndex = -1; dialog.focus({ preventScroll: true });
  onOpen?.(dialog); return dialog;
}
const valueOf = part => typeof part === 'function' ? part() : part;
function paintSheet(dialog = $('#dialog')) {
  if (!sheet) return; const body = $('.dialog-content', dialog), bar = $('.dialog-actions', dialog), html = `${valueOf(sheet.content)}\u0000${valueOf(sheet.actions)}`;
  if (sheet.html === html) return; sheet.html = html;
  const error = $('.dialog-error', body)?.textContent;
  body.innerHTML = valueOf(sheet.content); bar.innerHTML = valueOf(sheet.actions);
  if (error) showSheetError(error);
}
/** Re-renders a `live` sheet if what it shows has changed (device connections, readings). */
export function refreshSheet() { if (sheet?.live && $('#dialog').open) paintSheet(); }
export const closeSheet = () => { const dialog = $('#dialog'); if (dialog.open) dialog.close(); };
export const sheetIsOpen = () => $('#dialog')?.open === true;
function showSheetError(text) {
  const body = $('#dialog .dialog-content'); let message = $('.dialog-error', body);
  if (!message) { message = document.createElement('p'); message.className = 'dialog-error'; message.setAttribute('role', 'alert'); body.append(message); }
  message.textContent = text; message.scrollIntoView({ block: 'nearest' });
}
function installDialogEvents() {
  const dialog = $('#dialog');
  dialog.addEventListener('click', async event => {
    const button = event.target.closest('[data-dialog], [data-close]'); if (!button || !dialog.contains(button)) return;
    if (button.hasAttribute('data-close')) { dialog.close(); return; }
    try { await sheet?.handler?.(button.dataset.dialog, dialog, event); } catch (error) { showSheetError(error.message ?? String(error)); }
  });
  dialog.addEventListener('submit', event => { event.preventDefault(); dialog.querySelector('[data-dialog]:not([data-dialog="cancel"])')?.click(); });
  dialog.addEventListener('change', event => { try { sheet?.onChange?.(event, dialog); } catch (error) { showSheetError(error.message); } });
  dialog.addEventListener('close', () => { sheet = null; update(); });
}
/** A yes/no confirmation. Resolves nothing; `onConfirm` runs on the confirm button. */
export function confirmSheet({ title, text, confirm, cancel = 'Cancel', danger = true, onConfirm }) {
  openSheet({ title, content: `<p>${esc(text)}</p>`, actions: `<button type="button" class="btn ${danger ? 'danger' : 'primary'}" data-dialog="confirm">${esc(confirm)}</button><button type="button" class="btn secondary" data-dialog="cancel">${esc(cancel)}</button>`,
    handler: async (action, dialog) => { if (action === 'confirm') await onConfirm(); dialog.close(); } });
}

// ----- rendering -----------------------------------------------------------------------------------------------------------------
function navHTML(kind) {
  const here = current?.tab ?? current?.name;
  return DESTINATIONS.map(([id, title, symbol]) => `<a href="#/${id}" data-tab="${id}" ${here === id ? 'aria-current="page"' : ''}><span aria-hidden="true">${symbol}</span><span>${title}</span></a>`).join('');
}
function renderNav() { for (const id of ['#sidebar-nav', '#tabbar']) { const nav = $(id); if (nav) nav.innerHTML = navHTML(); } }
function pickRoute() {
  const parsed = parseHash();
  if (model.onboardingPending) return { ...parsed, name: 'onboarding', params: [] };
  // A ride that is not running has no cockpit: show what it left behind.
  if (parsed.name === 'ride' && !model.ride.busy) return { name: model.ride.engine ? 'result' : 'home', params: [], redirect: true };
  if (!routes.has(parsed.name)) return { name: 'home', params: [], redirect: true };
  return parsed;
}
export function render() {
  if (!model) return;
  const route = pickRoute(), spec = routes.get(route.name); if (!spec) return;
  if (route.redirect) history.replaceState(null, '', hashFor(route.name, ...route.params));
  current = { ...route, spec, tab: spec.tab ?? null, key: `${route.name}/${route.params.join('/')}` };
  const main = $('#main'), keep = lastRenderKey === current.key ? main.scrollTop : 0;
  main.innerHTML = spec.render(model, route.params); lastRenderKey = current.key;
  document.body.dataset.route = route.name; document.title = `${spec.documentTitle?.(model, route.params) ?? 'FTPunk'} · FTPunk`;
  renderNav(); spec.bind?.(main, model, route.params); spec.update?.(model, route.params); updateLiveBar();
  if (keep) main.scrollTop = keep;
}
export const rerender = render;
function installDelegation() {
  const main = $('#main');
  main.addEventListener('click', event => {
    const chip = event.target.closest('[data-chip]'); const element = event.target.closest('[data-action]');
    if (chip && main.contains(chip)) { const handler = current?.spec.chips?.(model, current.params)?.[chip.dataset.chip]; if (handler) { void safely(handler)(chip.dataset.value, chip, event); return; } }
    if (!element || !main.contains(element) || element.disabled) return;
    const name = element.dataset.action, handler = current?.spec.actions?.(model, current.params)?.[name] ?? globalActions.get(name);
    if (handler) { event.preventDefault(); void safely(handler)(element, event); }
  });
  for (const type of ['change', 'input', 'submit']) main.addEventListener(type, event => {
    const target = event.target, key = target.id || target.name; if (type === 'submit') event.preventDefault();
    const handler = current?.spec.events?.(model, current.params)?.[type]?.[type === 'submit' ? target.id : key]; if (handler) void safely(handler)(target, event);
  });
}
/** Re-renders a live ride's numbers and the live-ride bar; screens refresh only what changes (`spec.update`). */
export function update() {
  if (!model) return;
  const { present, phase, previous } = model.phaseChange(); if (phase && previous !== phase) announce(PHASES[phase] ?? phase);
  if (present) { model.resultSessionID = null; if (current?.name !== 'result') navigate('#/result'); }
  current?.spec.update?.(model, current.params); refreshSheet(); updateLiveBar();
}
function updateLiveBar() {
  const bar = $('#live-bar'), engine = model.ride.engine, show = model.ride.active && current?.name !== 'ride';
  bar.hidden = !show; document.body.classList.toggle('has-live-bar', show);
  if (!show) { bar.replaceChildren(); return; }
  if (!bar.firstElementChild) {
    bar.innerHTML = `<span class="live-summary" id="live-summary"></span><a class="btn primary small" href="#/ride">Return</a><button type="button" class="btn secondary small" id="live-stop">Stop &amp; save</button>`;
    $('#live-stop').onclick = () => model.ride.stop();
  }
  const watts = engine.lastPower && model.ride.elapsed - engine.lastPower.time <= 2 ? Math.round(engine.lastPower.watts) : engine.target ?? null;
  const summary = `${PHASES[engine.phase] ?? engine.phase} · ${watts == null ? '—' : watts} W · ${DurationFormat.clock(model.ride.elapsed)}`, live = $('#live-summary');
  if (live.textContent !== summary) { live.textContent = summary; live.setAttribute('aria-label', `Live ride. ${summary}`); }
}

// ----- guards for a live ride ----------------------------------------------------------------------------------------------------
let wake = null;
export async function wakeScreen() {
  if (!model.ride.active || wake || !navigator.wakeLock || document.hidden) return;
  try { wake = await navigator.wakeLock.request('screen'); wake.addEventListener('release', () => { wake = null; }); } catch { notify('Keep your screen awake manually during this ride.'); }
}
function releaseWake() { if (!model.ride.active && wake) { void wake.release(); wake = null; } }
function installGuards() {
  const ride = model.ride;
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && !ride.demo && (ride.active || ride.starting)) ride.interrupt('The ride ended because the browser tab became hidden. Keep FTPunk visible for live rides.');
    else if (!document.hidden) void wakeScreen();
  });
  document.addEventListener('freeze', () => ride.interrupt('The browser suspended the workout.'));
  // Space pauses and resumes a workout or free ride, like the Pause button. Not in the FTP test, and not while a control has focus
  // (a focused button handles Space itself).
  document.addEventListener('keydown', event => {
    if (event.key !== ' ' || event.repeat || event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return;
    if (event.target.closest?.('button, a, input, select, textarea, summary, [contenteditable], dialog[open]')) return;
    if (current?.name !== 'ride' || !ride.active || !ride.engine?.session.training || ride.trainingTransition) return;
    event.preventDefault();
    if (ride.engine.phase === 'paused') ride.resumeTraining(); else ride.pauseTraining();
  });
  window.addEventListener('pagehide', () => ride.interrupt('The browser page was closed or navigated away.'));
  window.addEventListener('beforeunload', event => { if (ride.busy) { event.preventDefault(); event.returnValue = ''; } });
}

/** Start the shell: wire the model's callbacks, listen for hash changes and tick once a second. */
export function startShell(appModel) {
  model = appModel;
  model.onNotice = notify; model.onPreferences = () => applyPreferences(model.prefs);
  model.onChange = () => { update(); releaseWake(); };
  let queued = false; model.onInvalidate = () => { if (!queued) { queued = true; queueMicrotask(() => { queued = false; render(); }); } };
  model.hooks.saved.push(session => { for (const spec of routes.values()) spec.onRideSaved?.(model, session); });
  applyPreferences(model.prefs); installDelegation(); installDialogEvents(); installGuards();
  window.addEventListener('hashchange', () => { render(); $('#main').focus({ preventScroll: true }); });
  window.addEventListener('online', () => { void model.intervals.flush().then(() => model.reload()).then(update).catch(fail); });
  render();
  setInterval(() => { update(); if (model.intervals.connection) void model.intervals.flush().catch(fail); }, 1000);
  return { render, navigate };
}
export const currentRoute = () => current;
