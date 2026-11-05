import { AppModel } from './app-model.mjs';
import { LocalStore, DB_NAME, loadPreferences } from './storage.mjs';
import { MemoryStore } from './memory-store.mjs';
// Boot only: open storage, build the app model, register the screens, start the shell. Each screen module registers its own route when imported.
import { startShell, navigate, fail } from './ui/shell.mjs';
import { installSheets } from './ui/sheets.mjs';
import './ui/home.mjs';
import './ui/preflight.mjs';
import './ui/ride.mjs';
import './ui/result.mjs';
import './ui/progress.mjs';
import './ui/settings.mjs';
import { openWorkoutDetail } from './ui/library.mjs';
import { applyScenario } from './ui/scenarios.mjs';

const params = new URLSearchParams(location.search), scenario = params.get('scenario'), errors = [];
window.__ftpunkErrors = errors;
window.addEventListener('error', event => errors.push(event.message)); window.addEventListener('unhandledrejection', event => errors.push(String(event.reason?.message ?? event.reason)));
async function boot() {
  const preview = scenario != null;
  let model;
  try {
    // A preview scenario uses an in-memory store and default preferences: it never reads or writes the real database or settings.
    const store = preview ? new MemoryStore() : await LocalStore.open(params.get('db') ?? DB_NAME);
    model = new AppModel({ store, preview, prefs: preview ? loadPreferences({ getItem: () => null }) : loadPreferences(), ...(preview ? { lease: async () => () => {} } : {}) });
    await model.boot();
    installSheets(model);
    let hash = null;
    if (preview) hash = await applyScenario(scenario, model);
    const shell = startShell(model);
    if (hash) history.replaceState(null, '', hash);
    shell.render();
    if (model.pendingDetail) openWorkoutDetail(model, model.pendingDetail);
    if (preview || params.has('test')) window.__ftpunk = { model, ready: true, errors };
    if (!preview && !params.has('nosw') && 'serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(() => model.notify('Offline installation is unavailable. The app still works while this page is online.'));
  } catch (error) {
    document.querySelector('#main').innerHTML = `<section class="card empty"><h1>${preview ? 'This preview could not start.' : 'Your local storage could not open.'}</h1><p class="muted"></p></section>`;
    document.querySelector('#main .muted').textContent = preview ? error.message : 'Enable site storage in Chrome, then reload this page. A recording will not start without working local storage.';
    if (preview || params.has('test')) window.__ftpunk = { error: error.message, ready: true, errors };
    console.error(error);
  }
}
void boot();
