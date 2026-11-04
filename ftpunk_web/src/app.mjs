import { CITY_BEATS, cityScene, rideRewards } from './city.mjs';
import { importWorkout, MAX_WORKOUT_BYTES, exampleWorkout } from './workouts.mjs';
import { starterPlans, freeRide, resistanceRide, progressMilliseconds, LAST_LIGHT_MS } from './training.mjs';
import { parseArchive, archiveText, MAX_ARCHIVE_BYTES } from './archive.mjs';
import { configuration, PRESETS, PHASES, OUTCOMES, uuid } from './domain.mjs';
import { BluetoothDevices, DEVICE_LABELS } from './bluetooth.mjs';
import { LocalStore, acquireRideLease, loadPreferences, savePreferences } from './storage.mjs';
import { RideController } from './controller.mjs';
import { IntervalsClient } from './intervals.mjs';
import { csv, tcx, download } from './export.mjs';
import { drawScene, drawChart } from './scene.mjs';

const $ = selector => document.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const time = seconds => `${Math.floor(Math.max(0, seconds) / 60).toString().padStart(2, '0')}:${Math.floor(Math.max(0, seconds) % 60).toString().padStart(2, '0')}`;
const watts = n => Number.isFinite(n) ? Math.round(n) : '—';
const date = iso => new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
const blank = n => n == null ? '' : n;
const prefs = loadPreferences();
const devices = new BluetoothDevices();
const state = { freeWatts: 100, resistance: 0, workouts: [], downloading: false, importReport: null, tab: 'train', profiles: [], history: [], jobs: [], busyRole: null, notice: null, historyRider: 'all', showDemos: true, lastPhase: null, wake: null, lastViewPhase: null, dialogAction: null };
const draft = { preset: 'standard', priorFTP: '', weightKG: '', warmupMinutes: '10', cooldownMinutes: '3', manualWarmupPower: '', ftpFactor: '0.72', powerSource: 'trainer', demo: false, quickDemo: true, speed: '12', scenario: 'exhaustion' };
let store, ride, intervals;
function currentProfile() { return state.profiles.find(p => p.id === prefs.selectedRider) ?? state.profiles[0]; }
function profileFields() { const p = currentProfile(); if (!p) return; draft.weightKG = p.weightKG ?? ''; draft.priorFTP = p.ftpHistory.find(e => e.id === p.currentFTPID)?.watts ?? ''; }
function notify(message, error = false) { state.notice = message; const box = $('#notice'); box.hidden = !message; box.className = error ? 'notice error' : 'notice'; box.replaceChildren(); if (message) { const text = document.createElement('span'); text.textContent = message; const button = document.createElement('button'); button.type = 'button'; button.textContent = 'Dismiss'; button.onclick = () => notify(null); box.append(text, button); } }
function fail(error) { if (error?.name === 'NotFoundError') return; notify(error.message ?? String(error), true); }
function safely(action) { return async event => { try { await action(event); } catch (error) { fail(error); } }; }
function applyPreferences() { document.documentElement.dataset.appearance = prefs.appearance; document.documentElement.classList.toggle('large-numbers', prefs.extraLarge); try { savePreferences(prefs); } catch { notify('Preferences could not be saved. Check browser storage permissions.', true); } }
function modal(title, content, actions, handler) {
  const dialog = $('#dialog'); if (dialog.open) dialog.close();
  dialog.innerHTML = `<div class="dialog-head"><h2 id="dialog-title">${esc(title)}</h2><button type="button" class="icon-button" data-close aria-label="Close dialog">×</button></div><div class="dialog-content">${content}</div><div class="dialog-actions">${actions}</div>`;
  dialog.querySelector('[data-close]').onclick = () => dialog.close();
  dialog.querySelectorAll('[data-dialog]').forEach(button => button.onclick = async () => {
    try { await handler?.(button.dataset.dialog, dialog); }
    catch (error) {
      let message = dialog.querySelector('.dialog-error');
      if (!message) { message = document.createElement('p'); message.className = 'notice error dialog-error'; message.setAttribute('role', 'alert'); dialog.querySelector('.dialog-content').append(message); }
      message.textContent = error.message; message.scrollIntoView({ block: 'nearest' });
    }
  });
  const form = dialog.querySelector('form');
  if (form) form.onsubmit = event => { event.preventDefault(); dialog.querySelector('[data-dialog]')?.click(); };
  dialog.showModal();
}
function heading(kicker, title, subtitle, extra = '') { return `<div class="page-heading"><div><p class="eyebrow">${kicker}</p><h1>${title}</h1><p class="subtitle">${subtitle}</p></div>${extra}</div>`; }
function field(label, id, value, extra = '') { return `<label class="field"><span>${label}</span><input id="${id}" name="${id}" type="number" value="${esc(blank(value))}" ${extra}></label>`; }
function getConfiguration(training = null) {
  const p = currentProfile(), now = performance.now() / 1000;
  const num = value => value === '' ? null : Number(value);
  return configuration({ preset: draft.preset, priorFTP: num(draft.priorFTP), weightKG: num(draft.weightKG), warmupSeconds: training ? 0 : draft.demo && draft.quickDemo ? 10 : Number(draft.warmupMinutes) * 60, cooldownSeconds: training ? 0 : draft.demo && draft.quickDemo ? 10 : Number(draft.cooldownMinutes) * 60, manualWarmupPower: training?.steps[0].watts ?? num(draft.manualWarmupPower), ftpFactor: Number(draft.ftpFactor), powerSource: draft.powerSource, cadenceSource: draft.demo ? (draft.scenario === 'cadenceDropout' ? 'trainer' : draft.powerSource) : devices.measurements.cadenceSource(draft.powerSource, now), powerMatchingEnabled: prefs.powerMatching, riderID: p.id, riderName: p.name });
}
function connectionsView(locked) { return `<section class="panel devices-panel"><div class="section-heading"><div><p class="eyebrow">YOUR CONNECTIONS</p><h2>Ready to roll.</h2></div><span class="status-dot" id="device-dot"></span></div>
        <p class="muted compact">Connect the trainer first. A separate power meter and heart-rate sensor are optional.</p>
        <div class="device-list">${Object.entries(DEVICE_LABELS).map(([role, label]) => `<div class="device-row"><div class="device-icon" aria-hidden="true">${role === 'trainer' ? 'ϟ' : role === 'externalPowerMeter' ? '◎' : '♡'}</div><div class="device-copy"><strong>${label}</strong><span id="device-${role}">${esc(devices.devices[role]?.name ?? 'Not connected')}</span><small id="reading-${role}"></small></div><button class="small-button" data-connect="${role}" ${locked || state.busyRole ? 'disabled' : ''}>${state.busyRole === role ? 'Pairing…' : devices.devices[role] ? 'Disconnect' : 'Connect'}</button></div>`).join('')}</div>
        <label class="field power-source"><span>Measure power with</span><select id="powerSource" ${locked ? 'disabled' : ''}><option value="trainer" ${draft.powerSource === 'trainer' ? 'selected' : ''}>Trainer</option><option value="externalPowerMeter" ${draft.powerSource === 'externalPowerMeter' ? 'selected' : ''}>External power meter</option></select></label>
        <div class="matching-note"><span aria-hidden="true">⇄</span><div><strong id="matching-status">Power matching on</strong><p id="matching-copy">External meter controls trainer power.</p><a href="#settings">Manage in settings →</a></div></div>
        <p class="browser-help" id="browser-support">Keep this tab visible during a live test. FTPunk releases trainer control if you leave the tab.</p>
      </section>`; }
function setupView() {
  const p = currentProfile(), locked = ride.busy;
  return `${heading('A LITTLE STRUCTURE. A LOT OF GRIT.', 'Find your next gear.', 'A progressive ramp. One honest effort. Your next FTP benchmark.', '<span class="outline-badge">FTP RAMP TEST</span>')}
    <div class="step-strip" aria-label="Test sequence"><span class="current"><b>01</b> Set your test</span><span><b>02</b> Ride the ramp</span><span><b>03</b> Meet your numbers</span></div>
    <div class="setup-grid"><div class="stack">
      <section class="panel"><div class="section-heading"><div><p class="eyebrow">THE RIDER</p><h2>Make it yours.</h2></div><button class="text-button" data-action="add-rider" ${locked ? 'disabled' : ''}>＋ Add rider</button></div>
        <div class="fields rider-fields"><label class="field"><span>Rider</span><select id="rider" ${locked ? 'disabled' : ''}>${state.profiles.map(r => `<option value="${r.id}" ${r.id === p.id ? 'selected' : ''}>${esc(r.name)}</option>`).join('')}</select></label>${field('Current FTP · W', 'priorFTP', draft.priorFTP, 'min="1" max="32767" placeholder="Optional"')}${field('Weight · kg', 'weightKG', draft.weightKG, 'min="1" step="0.1" placeholder="Optional"')}</div>
      </section>
      <section class="panel"><div class="section-heading"><div><p class="eyebrow">THE PROTOCOL</p><h2>Choose your climb.</h2></div><button class="text-button" data-action="protocol-info">How it works ↗</button></div>
        <fieldset class="protocols" ${locked ? 'disabled' : ''}><legend class="sr-only">Ramp protocol</legend>${Object.entries(PRESETS).map(([key, r]) => `<label class="protocol-card ${draft.preset === key ? 'selected' : ''}"><input type="radio" name="preset" value="${key}" ${draft.preset === key ? 'checked' : ''}><span class="protocol-top"><span>${key === 'gentle' ? 'GENTLE' : key === 'zwift' ? 'CLASSIC' : 'STANDARD'}</span><span class="radio-mark"></span></span><strong>${r.title}</strong><small>Start ${r.start} W<br>+${r.step} W every ${r.seconds} sec</small></label>`).join('')}</fieldset>
        <div class="fields duration-fields">${field('Warm-up · minutes', 'warmupMinutes', draft.warmupMinutes, 'min="0" max="60" step="1"')}${field('Cooldown · minutes', 'cooldownMinutes', draft.cooldownMinutes, 'min="0" max="60" step="1"')}<label class="field"><span>FTP estimate</span><select id="ftpFactor"><option value="0.72" ${draft.ftpFactor === '0.72' ? 'selected' : ''}>72% · conservative</option><option value="0.75" ${draft.ftpFactor === '0.75' ? 'selected' : ''}>75% · classic</option></select></label></div>
        <details class="advanced"><summary>Warm-up power & test limits</summary><div class="fields">${field('Manual warm-up · W', 'manualWarmupPower', draft.manualWarmupPower, 'min="1" max="32767" placeholder="Automatic"')}<p class="muted">Automatic warm-up uses 50% of your current FTP, or the protocol default. Ramp limits: 600 W / 30 minutes, capped by trainer capability.</p></div></details>
        <div class="plan-preview"><div><span class="tiny-label">WARM UP</span><strong id="warmup-preview">—</strong></div><span class="plan-line"></span><div><span class="tiny-label">BUILD IT UP</span><strong id="ramp-preview">—</strong></div><span class="plan-line"></span><div><span class="tiny-label">EASE IT DOWN</span><strong id="cooldown-preview">—</strong></div></div>
      </section>
      <section class="start-panel"><div><span class="eyebrow" id="start-mode">YOUR NEXT BENCHMARK</span><p id="readiness">Connect your trainer to get rolling.</p></div><button class="primary" id="start-test" data-action="start" ${locked ? 'disabled' : ''}>${ride.starting ? 'Starting…' : 'Start ramp test'} <span aria-hidden="true">↗</span></button>${ride.starting ? '<button class="danger-button" data-action="cancel-start">Cancel start</button>' : ''}</section>
      ${locked ? '<a class="return-ride" href="#ride">A test is running. Return to the live ride →</a>' : ''}
    </div><div class="stack">
      ${connectionsView(locked)}
      <section class="panorama-card"><canvas id="setup-scene" aria-label="A pixel cyclist riding an alpine road" role="img"></canvas><div><span class="eyebrow">THE ROAD IS YOURS.</span><p>No subscriptions.<br>No leaderboard pressure.<br>Just you, getting stronger.</p></div></section>
      <button class="demo-link" data-action="demo" ${locked ? 'disabled' : ''}>${draft.demo ? '✓ Mock ride selected · switch to real sensors' : 'No trainer nearby? Try a mock ride'} <span>→</span></button>
      ${draft.demo ? `<section class="panel demo-options"><span class="outline-badge">MOCK SENSORS · NEVER UPLOADS</span><label class="switch-row"><span>Quick warm-up & cooldown <small>10 seconds each</small></span><input type="checkbox" id="quickDemo" ${draft.quickDemo ? 'checked' : ''} ${locked ? 'disabled' : ''}></label><div class="fields"><label class="field"><span>Simulation speed</span><select id="speed">${[1, 12, 60].map(n => `<option value="${n}" ${draft.speed === String(n) ? 'selected' : ''}>${n}×</option>`).join('')}</select></label><label class="field"><span>Scenario</span><select id="scenario">${[['exhaustion', 'Ride to exhaustion'], ['steady', 'Steady rider'], ['powerDropout', 'Power dropout'], ['cadenceDropout', 'Cadence dropout']].map(([v, label]) => `<option value="${v}" ${draft.scenario === v ? 'selected' : ''}>${label}</option>`).join('')}</select></label></div></section>` : ''}
    </div></div>`;
}
function libraryView(locked) {
  const p = currentProfile();
  return `<section class="panel"><h2>Your workout library</h2><p class="muted">Import FTPunk JSON with timed watts, ramps and repeats, or an Intervals.icu cycling event. Cached targets stay fixed in watts.</p><div class="button-row"><button class="secondary" data-action="import-workout" ${locked ? 'disabled' : ''}>Import workout JSON…</button><button class="text-button" data-action="example-workout">Download example</button></div><input type="file" id="workout-file" accept=".json,application/json" hidden>
    ${intervals.connection ? `<p>Intervals.icu · ${esc(intervals.connection.name)}</p><button class="secondary" data-action="download-workouts" ${locked || state.downloading ? 'disabled' : ''}>${state.downloading ? 'Downloading…' : 'Download next 14 days'}</button>` : '<a href="#settings">Connect Intervals.icu in Settings →</a>'}
    ${state.importReport ? `<p class="import-report" role="status">${esc(state.importReport)}</p>` : ''}
    ${state.workouts.filter(w => w.riderID === p.id).map(w => `<details><summary>${esc(w.plan.name)}</summary><p>${esc(w.source)} · ${time(w.plan.steps.reduce((n, s) => n + s.seconds, 0))}${w.plan.ftpWatts ? ` · saved FTP ${watts(w.plan.ftpWatts)} W` : ''}</p><ol>${w.plan.steps.map(step => `<li>${esc(step.name)} · ${step.seconds} s · ${step.watts}${step.endWatts == null ? '' : ` → ${step.endWatts}`} W</li>`).join('')}</ol><button class="primary" data-cached="${esc(w.id)}" ${locked ? 'disabled' : ''}>Start cached workout</button><button class="text-button" data-delete-workout="${esc(w.id)}" ${locked ? 'disabled' : ''}>Remove from library</button></details>`).join('')}</section>`;
}
function resistanceView(locked) {
  const range = devices.resistanceRange ?? (draft.demo ? { minimum: 0, maximum: 1000, increment: 10, quantized: n => Math.min(1000, Math.max(0, n)) } : null);
  if (!range) return '<section class="panel"><h2>Resistance ride</h2><p class="muted">Pair a trainer that advertises resistance control and a supported level range.</p></section>';
  state.resistance = range.quantized(state.resistance);
  return `<section class="panel"><h2>Resistance ride</h2><p>Choose effort with your gears and cadence. These are trainer-specific levels, not watts or percent. Power matching is off.</p>${field('Starting resistance level', 'resistance-level', state.resistance / 10, `min="${range.minimum / 10}" max="${range.maximum / 10}" step="${range.increment / 10}"`)}<button class="primary" data-action="resistance-ride" ${locked ? 'disabled' : ''}>Start resistance ride</button></section>`;
}
function rewardsView(session) {
  if (!session.adventureEnabled) return '';
  const rewards = rideRewards(session);
  return `<section class="panel rewards"><h2>${session.isDemo ? 'Cyclepunk preview · no rewards' : 'Cyclepunk · this ride'}</h2>${session.isDemo ? '' : `<p><strong>${rewards.xp} XP</strong> · ${Math.floor(rewards.milliseconds / 1000)} valid riding seconds</p>${rewards.partial ? '<p class="muted">Partial XP carries into your next ride.</p>' : ''}${rewards.unlocked.map(b => `<h3>Unlocked: ${esc(b.title)}</h3><p>${esc(b.speaker)}: ${esc(b.message)}</p>`).join('')}${rewards.unlocked.some(b => b.id === 'last-light-radio') ? '<strong>✦ Last Light patch earned</strong>' : ''}`}</section>`;
}
function trainView() {
  const p = currentProfile(), locked = ride.busy;
  let plans = []; try { plans = starterPlans(Number(draft.priorFTP)); } catch { /* FTP is optional for a free ride. */ }
  return `${heading('YOUR TRAINING SPACE', 'Make time to ride.', 'Offline workouts, free ERG riding, and a city that grows with you.')}
    <div class="setup-grid"><div class="stack">
      <section class="panel"><h2>The rider</h2><label class="field"><span>Rider</span><select id="rider" ${locked ? 'disabled' : ''}>${state.profiles.map(r => `<option value="${r.id}" ${r.id === p.id ? 'selected' : ''}>${esc(r.name)}</option>`).join('')}</select></label>${field('Current FTP · W', 'priorFTP', draft.priorFTP, 'min="1" max="32767" placeholder="Set FTP for workouts"')}<button class="text-button" data-action="add-rider" ${locked ? 'disabled' : ''}>Add rider</button></section>
      <section class="panel"><h2>Free ERG ride</h2><p>Choose your starting watts. Adjust the target while riding. Stop & save releases the trainer and keeps your recording.</p>${field('Starting target · W', 'free-watts', state.freeWatts, 'min="1" max="32767" step="1"')}<button class="primary" data-action="free-ride" ${locked ? 'disabled' : ''}>Start free ERG ride</button></section>
      ${resistanceView(locked)}
      ${libraryView(locked)}
      <section class="panel"><h2>Offline workouts</h2><p class="muted">${plans.length ? `Targets based on ${esc(draft.priorFTP)} W FTP. Targets use this FTP snapshot. Trainer commands are rounded to its supported increment.` : 'Set your current FTP above to see workout targets.'}</p>${plans.map((plan, i) => `<details><summary>${esc(plan.name)}</summary><ol>${plan.steps.map(step => `<li>${esc(step.name)} · ${step.seconds / 60} min · ${step.watts} W</li>`).join('')}</ol><button class="primary" data-workout="${i}" ${locked ? 'disabled' : ''}>Start workout</button></details>`).join('')}</section>
      <section class="panel"><h2>Cyclepunk</h2><label class="switch-row"><span>Adventure progress<small>10 XP per minute of fresh, positive power. Easy riding counts equally.</small></span><input id="adventure" type="checkbox" ${prefs.adventure ? 'checked' : ''} ${locked ? 'disabled' : ''}></label><a href="#city">Visit the city →</a></section>
    </div><div class="stack">${connectionsView(locked)}<button class="demo-link" data-action="demo" ${locked ? 'disabled' : ''}>${draft.demo ? 'Mock sensors selected · switch to real sensors' : 'Try mock sensors'}</button><p class="footnote">${draft.demo ? 'Mock rides run at the selected preview speed and earn no real XP.' : 'Keep this tab visible for trainer control.'}</p>${ride.starting ? '<button class="danger-button" data-action="cancel-start">Cancel start</button>' : ''}</div></div>`;
}
function cityView() {
  const p = currentProfile(), ms = progressMilliseconds(p.cycleProgress), restored = ms >= LAST_LIGHT_MS;
  return `${heading('CYCLEPUNK · GHOST CIRCUIT', 'Last Light', `${esc(p.name)} · ${Math.floor(ms / 6000)} XP`)}
    ${cityScene(ms)}<section class="panel"><h2>${restored ? 'Lowline radio restored' : 'A signal in the static'}</h2><progress aria-label="Last Light chapter progress" max="${LAST_LIGHT_MS}" value="${Math.min(ms, LAST_LIGHT_MS)}"></progress><p>${restored ? '✦ Last Light patch earned' : `${Math.ceil((LAST_LIGHT_MS - ms) / 60000)} riding minutes to restore the radio.`}</p></section>
    <section class="panel transmissions"><h2>Transmissions</h2>${CITY_BEATS.map(b => ms >= b.milliseconds ? `<article><p class="eyebrow">${esc(b.speaker)}</p><h3>${esc(b.title)}</h3><p>${esc(b.message)}</p></article>` : `<p class="muted">🔒 ${esc(b.title)} · ${b.milliseconds / 60000} riding minutes</p>`).join('')}</section>
    <section class="panel"><label class="switch-row"><span>Progress on future rides<small>Progress spans rides and stays with this rider. Mock rides earn no real XP. Portable backups include your progress.</small></span><input id="adventure" type="checkbox" ${prefs.adventure ? 'checked' : ''} ${ride.busy ? 'disabled' : ''}></label><a class="primary" href="#train">Go to Train →</a></section>`;
}
async function startRide(training = null) {
  if (ride.busy || state.busyRole || $('#dialog').open) return;
  const config = getConfiguration(training), p = currentProfile(); p.weightKG = config.weightKG;
  if (config.priorFTP != null && p.ftpHistory.find(e => e.id === p.currentFTPID)?.watts !== config.priorFTP) {
    const entry = { id: uuid(), watts: config.priorFTP, date: new Date().toISOString(), source: 'Manual' }; p.ftpHistory.unshift(entry); p.currentFTPID = entry.id;
  }
  await store.put('profiles', p);
  const starting = ride.start(config, { demo: draft.demo, speed: Number(draft.speed), scenario: draft.scenario, training, adventure: prefs.adventure });
  render(); await starting;
  if (ride.active) { location.hash = 'ride'; await wakeScreen(); } else render();
}
function rideView() {
  const e = ride.engine;
  if (!e) return `${heading('YOUR LIVE DASHBOARD', 'The road is waiting.', 'Start a ramp test to see your effort in real time.')}<section class="empty panel"><span class="empty-symbol">ϟ</span><h2>Clip in. Find your rhythm.</h2><p>Pair your trainer or try a mock ride first.</p><a class="primary" href="#setup">Set up a test ↗</a></section>`;
  const s = e.session, c = s.configuration;
  return `${heading(s.isDemo ? `MOCK RIDE · ${ride.speed}× SPEED · NEVER UPLOADS` : 'LIVE FROM YOUR TRAINER', `<span id="ride-title">${PHASES[e.phase]}</span>`, `${esc(c.riderName)} <span class="separator">/</span> ${esc(s.training?.name ?? PRESETS[c.preset].title)} <span class="separator">/</span> ${c.powerSource === 'trainer' ? 'Trainer power' : 'External meter'}${c.powerMatchingEnabled ? ' · power matching' : ''}`, '<span class="outline-badge" id="ride-time">00:00</span>')}
    <div id="ride-message" class="ride-message" role="status"></div>
    <section class="ride-metrics"><div class="metric primary-metric"><span class="tiny-label">YOUR POWER</span><div><strong id="live-power">—</strong><span>W</span></div><small id="power-freshness">Waiting for power</small></div><div class="metric"><span class="tiny-label">${s.training?.resistance != null ? "RESISTANCE LEVEL" : "WORKOUT TARGET"}</span><div><strong id="live-target">—</strong><span>${s.training?.resistance != null ? "" : "W"}</span></div><small id="trainer-command">ERG control</small></div><div class="metric"><span class="tiny-label">${s.training ? "RIDING TIME" : "BEST 60 SECONDS"}</span><div><strong id="live-best">—</strong><span>${s.training ? "" : "W"}</span></div><small>${s.training ? "Recorded session time" : "Time-weighted · ramp only"}</small></div></section>
    <div class="ride-grid"><section class="panel scene-panel"><canvas id="ride-scene" role="img" aria-label="Pixel cyclist on an alpine climb"></canvas><div class="ride-strip"><div><span class="tiny-label">CADENCE</span><strong id="live-cadence">—</strong><small>rpm</small></div><div><span class="tiny-label">HEART RATE</span><strong id="live-heart">—</strong><small>bpm</small></div><div><span class="tiny-label">${s.training ? "WORKOUT TIME" : "PHASE TIME"}</span><strong id="phase-time">00:00</strong></div></div></section><section class="panel effort-panel"><p class="eyebrow">THE EFFORT</p><h2>One step at a time.</h2><p id="phase-guidance"></p><div class="phase-track"><span data-phase="warmup">01 Warm up</span><span data-phase="ramp">02 Ramp</span><span data-phase="cooldown">03 Recover</span></div><p class="muted" id="next-step"></p></section></div>
    <section class="panel chart-panel"><div class="section-heading"><div><p class="eyebrow">EVERY WATT COUNTS</p><h2>Power over time.</h2></div><span class="chart-key"><i></i> Power <i class="target"></i> Target</span></div><canvas id="power-chart" role="img" aria-label="Measured power over the last ten minutes; numeric readings are shown above"></canvas><div class="chart-axis"><span>Last 10 minutes</span><span id="chart-end">00:00</span></div></section>
    <div class="ride-actions" id="ride-actions"></div><div id="ride-result"></div>`;
}
function historyView() {
  const visible = state.history.filter(s => (state.historyRider === 'all' || s.configuration.riderID === state.historyRider) && (state.showDemos || !s.isDemo));
  const realResults = visible.filter(s => !s.isDemo && s.result), latest = realResults[0]?.result;
  return `${heading('KEEP SHOWING UP.', 'Your work, recorded.', 'A local record of the effort. A clearer picture of your progress.', '<button class="secondary" data-action="backup">Export backup ↗</button>')}
    <div class="history-stats"><div><span class="tiny-label">RECORDED RIDES</span><strong>${visible.length.toString().padStart(2, '0')}</strong></div><div><span class="tiny-label">LATEST ESTIMATED FTP</span><strong>${watts(latest?.estimatedFTP)} <small>W</small></strong></div><div><span class="tiny-label">BEST ESTIMATED FTP</span><strong>${watts(realResults.length ? Math.max(...realResults.map(s => s.result.estimatedFTP)) : null)} <small>W</small></strong></div></div>
    <section class="panel"><div class="section-heading history-filters"><h2>Ride history</h2><div><label class="sr-only" for="history-rider">Filter by rider</label><select id="history-rider"><option value="all">All riders</option>${state.profiles.map(p => `<option value="${p.id}" ${p.id === state.historyRider ? 'selected' : ''}>${esc(p.name)}</option>`).join('')}</select><label class="inline-check"><input type="checkbox" id="show-demos" ${state.showDemos ? 'checked' : ''}> Include mock rides</label></div></div>
    ${visible.length ? `<div class="history-list">${visible.map(s => `<button class="history-row" data-session="${s.id}"><span class="history-icon">${s.isDemo ? '◌' : '↗'}</span><span><strong>${esc(s.configuration.riderName)} <small>${s.isDemo ? 'MOCK' : OUTCOMES[s.outcome] ?? 'Recording'}</small></strong><span>${date(s.startedAt)} · ${esc(s.training?.name ?? PRESETS[s.configuration.preset].title)}</span></span><span class="history-result">${s.training ? time(s.endedAtOffset ?? 0) + ' <small>riding time</small>' : watts(s.result?.estimatedFTP) + ' <small>W FTP</small>'}<b aria-hidden="true">→</b></span></button>`).join('')}</div>` : '<div class="empty"><span class="empty-symbol">↗</span><h2>Your first benchmark starts here.</h2><p>Finished tests and interrupted recordings will appear here.</p><a class="text-button" href="#setup">Set up a test →</a></div>'}</section>
    <p class="footnote">History is stored in this browser on this device. Export a backup before clearing browser data. Mock rides do not count toward real FTP progress.</p>`;
}
function settingsView() {
  const locked = ride.busy, connection = intervals.connection;
  return `${heading('YOUR RIDE. YOUR RULES.', 'Fine-tune your space.', 'Simple preferences. Clear control. Everything local until you choose to share.')}
    <div class="settings-grid"><div class="stack"><section class="panel"><p class="eyebrow">TRAINER CONTROL</p><h2>Make the watts match.</h2><label class="switch-row"><span>Power matching<small>Use your external meter to control the workout effort.</small></span><input type="checkbox" id="power-matching" ${prefs.powerMatching ? 'checked' : ''} ${locked ? 'disabled' : ''}></label><p class="muted">When an external meter is selected, FTPunk gradually adjusts the trainer target until that meter reads the requested watts. Trainer-only rides use the trainer’s own power. Changes apply to the next test.</p></section>
      <section class="panel"><p class="eyebrow">MAKE IT READABLE</p><h2>A view that works for you.</h2><label class="field"><span>Appearance</span><select id="appearance">${['system', 'light', 'dark'].map(v => `<option value="${v}" ${prefs.appearance === v ? 'selected' : ''}>${v[0].toUpperCase() + v.slice(1)}</option>`).join('')}</select></label><label class="switch-row"><span>Extra-large ride numbers<small>For a dashboard you can read from the bike.</small></span><input type="checkbox" id="extra-large" ${prefs.extraLarge ? 'checked' : ''}></label><p class="muted">Supports keyboard navigation, system reduced motion, and screen readers. Values always include names and units.</p></section>
      <section class="panel"><p class="eyebrow">THE TEST, EXPLAINED</p><h2>Know your numbers.</h2><p class="muted">The estimate is ${Math.round(Number(draft.ftpFactor) * 100)}% of your best complete 60 seconds during the ramp. The reference range is 72–77%; use the result as a training estimate.</p><button class="text-button" data-action="protocol-info">Protocols & rider guidelines ↗</button></section>
    </div><div class="stack"><section class="panel"><p class="eyebrow">OPTIONAL CONNECTION</p><h2>Intervals.icu</h2>
      ${connection ? `<div class="account-card"><span class="local-dot"></span><strong>${esc(connection.name)}</strong><small>Account ${esc(connection.id)} · connected for this tab</small></div><p class="muted">Every new upload asks you to confirm the rider and destination. Approved queued uploads retry while this tab is connected and online.</p><div class="button-row"><button class="secondary" data-action="retry-uploads">Retry approved uploads</button><button class="text-button" data-action="disconnect-intervals">Disconnect</button></div>` : `<p class="muted">Connect with a personal API key from Intervals.icu → Settings → Developer settings. Your key stays in memory for this tab and is never included in a backup.</p><form id="intervals-form"><label class="field"><span>Personal API key</span><input type="password" id="api-key" autocomplete="off" required spellcheck="false" placeholder="Your key"></label><button class="secondary" type="submit">Connect account ↗</button></form><a class="text-button external-link" href="https://intervals.icu/settings" target="_blank" rel="noopener noreferrer">Open Intervals.icu settings ↗</a>`}
      <div id="upload-jobs">${state.jobs.length ? `<h3>Upload queue</h3>${state.jobs.map(j => `<p class="job-row"><span>${esc(j.accountName)} · ${esc(j.status)}</span><small>${esc(j.error ?? '')}</small></p>`).join('')}` : ''}</div></section>
      <section class="panel"><p class="eyebrow">LOCAL BY DEFAULT</p><h2>Your data stays yours.</h2><p class="muted">Riders and recordings live in this browser. No automatic cloud sync. Use a portable backup to transfer history to Mac or iPhone. Imports replace matching rider identities after review.</p><div class="button-row"><button class="secondary" data-action="backup" ${locked ? 'disabled' : ''}>Export portable backup ↗</button><button class="secondary" data-action="import" ${locked ? 'disabled' : ''}>Import backup…</button><button class="text-button" data-action="rollback">Download pre-import backup</button></div><input type="file" id="archive-file" accept=".json,application/json" hidden></section>
      <section class="panel"><p class="eyebrow">BLUETOOTH DIAGNOSTICS</p><details><summary>Advanced options</summary><label class="switch-row"><span>Capture Bluetooth packets<small>Latest 500 packets, in memory only.</small></span><input type="checkbox" id="capture" ${devices.captureEnabled ? 'checked' : ''}></label><label class="field"><span>Trainer resistance field</span><select id="resistance-layout" ${locked ? 'disabled' : ''}><option value="standard" ${!devices.legacyResistance ? 'selected' : ''}>Standard · 1 byte</option><option value="legacy" ${devices.legacyResistance ? 'selected' : ''}>Reference layout · 2 bytes</option></select></label><button class="text-button" data-action="capture">Download packet capture ↗</button></details></section>
    </div></div>`;
}
function render() {
  if (!ride) return;
  state.tab = ['train', 'setup', 'ride', 'city', 'history', 'settings'].includes(location.hash.slice(1)) ? location.hash.slice(1) : 'train';
  document.querySelectorAll('[data-tab]').forEach(a => { a.toggleAttribute('aria-current', a.dataset.tab === state.tab); if (a.dataset.tab === state.tab) a.setAttribute('aria-current', 'page'); });
  $('#breadcrumb').textContent = `TRAINING / ${{ train: 'TRAIN', city: 'CITY', setup: 'FTP TEST', ride: 'LIVE RIDE', history: 'HISTORY', settings: 'SETTINGS' }[state.tab]}`;
  state.lastViewPhase = null;
  $('#main').innerHTML = ({ train: trainView, city: cityView, setup: setupView, ride: rideView, history: historyView, settings: settingsView })[state.tab]();
  bind(); update();
}
function bind() {
  if ($('#resistance-level')) { $('#resistance-level').disabled = ride.busy; $('#resistance-level').oninput = e => { state.resistance = Math.round(Number(e.target.value) * 10); }; }
  document.querySelectorAll('[data-cached]').forEach(b => b.onclick = safely(() => startRide(state.workouts.find(w => w.id === b.dataset.cached).plan)));
  document.querySelectorAll('[data-delete-workout]').forEach(b => b.onclick = safely(async () => { if (ride.busy) return; await store.delete('workouts', b.dataset.deleteWorkout); await reload(); render(); }));
  if ($('#workout-file')) $('#workout-file').onchange = safely(async e => {
    const file = e.target.files[0]; e.target.value = ''; if (!file || ride.busy) return;
    const riderID = currentProfile().id;
    if (file.size > MAX_WORKOUT_BYTES) throw Error('Workout files must be under 2 MB.');
    const plan = importWorkout(await file.text(), Number(draft.priorFTP) || null);
    if (ride.busy || currentProfile().id !== riderID) throw Error('The rider or ride changed. Import again.');
    await store.saveWorkouts([{ id: uuid(), riderID, source: 'Imported JSON', savedAt: new Date().toISOString(), plan }]);
    state.importReport = `Saved ${plan.name} for offline riding.`; await reload(); render();
  });

  if ($('#free-watts')) { $('#free-watts').disabled = ride.busy; $('#free-watts').oninput = e => { state.freeWatts = Number(e.target.value); }; }
  if ($('#adventure')) $('#adventure').onchange = e => { prefs.adventure = e.target.checked; applyPreferences(); };
  document.querySelectorAll('[data-workout]').forEach(b => b.onclick = safely(() => startRide(starterPlans(Number(draft.priorFTP))[Number(b.dataset.workout)])));

  if ($('#archive-file')) $('#archive-file').onchange = safely(async event => {
    const file = event.target.files[0]; event.target.value = ''; if (!file) return;
    if (file.size > MAX_ARCHIVE_BYTES) throw Error('The archive exceeds the 64 MB import limit.');
    const archive = parseArchive(await file.text());
    modal('Import these riders?', `<p><strong>${archive.profiles.map(p => esc(p.name)).join(', ')}</strong></p><p>${archive.activities.length} recordings, ${archive.workouts?.length ?? 0} cached workouts. Local history, workout library and Cyclepunk progress for these rider identities will be replaced, not merged. Other riders stay unchanged. A local backup is saved first.</p><p>Credentials and upload approvals are not transferred. Existing remote uploads are not deleted.</p>`, '<button class="secondary" data-dialog="cancel">Cancel</button><button class="primary" data-dialog="import">Import and replace matching riders</button>', async (action, dialog) => {
      if (action === 'cancel') { dialog.close(); return; }
      if (ride.busy || intervals.busy || state.downloading) throw Error('Wait for the ride or upload to finish before importing.');
      const resumeUploads = intervals.suspendUploads(); let release;
      try {
        release = await acquireRideLease();
        await store.restore(archive); ride.engine = null;
        await reload(); prefs.selectedRider = currentProfile().id; profileFields(); applyPreferences();
        dialog.close(); render(); notify('Backup imported. The previous local data is available under Download pre-import backup.');
      } finally { release?.(); resumeUploads(); }
    });
  });
  document.querySelectorAll('[data-action]').forEach(b => b.onclick = safely(() => actions[b.dataset.action]?.()));
  document.querySelectorAll('[data-connect]').forEach(b => b.onclick = safely(async () => {
    if (ride.busy || state.busyRole) return;
    const role = b.dataset.connect;
    if (devices.devices[role]) { devices.disconnect(role); if (role === 'externalPowerMeter') draft.powerSource = 'trainer'; render(); return; }
    state.busyRole = role;
    // connect() requests the chooser synchronously before its first await.
    const pairing = devices.connect(role); render();
    try { await pairing; } finally { state.busyRole = null; render(); }
  }));
  document.querySelectorAll('[data-session]').forEach(b => b.onclick = () => showSession(state.history.find(s => s.id === b.dataset.session)));
  for (const key of Object.keys(draft)) {
    const input = $(`#${key}`); if (!input) continue;
    if (ride.busy) input.disabled = true;
    input.oninput = () => { draft[key] = input.type === 'checkbox' ? input.checked : input.value; updateSetup(); };
  }
  if (state.tab === 'train' && $('#priorFTP')) $('#priorFTP').onchange = render;
  document.querySelectorAll('[name="preset"]').forEach(r => r.onchange = () => { draft.preset = r.value; render(); });
  if ($('#rider')) $('#rider').onchange = () => { prefs.selectedRider = $('#rider').value; profileFields(); applyPreferences(); render(); };
  if ($('#power-matching')) $('#power-matching').onchange = () => { prefs.powerMatching = $('#power-matching').checked; applyPreferences(); };
  if ($('#appearance')) $('#appearance').onchange = () => { prefs.appearance = $('#appearance').value; applyPreferences(); };
  if ($('#extra-large')) $('#extra-large').onchange = () => { prefs.extraLarge = $('#extra-large').checked; applyPreferences(); };
  if ($('#capture')) $('#capture').onchange = () => { devices.captureEnabled = $('#capture').checked; };
  if ($('#resistance-layout')) $('#resistance-layout').onchange = () => { devices.legacyResistance = $('#resistance-layout').value === 'legacy'; };
  if ($('#history-rider')) $('#history-rider').onchange = () => { state.historyRider = $('#history-rider').value; render(); };
  if ($('#show-demos')) $('#show-demos').onchange = () => { state.showDemos = $('#show-demos').checked; render(); };
  if ($('#intervals-form')) $('#intervals-form').onsubmit = safely(async event => {
    event.preventDefault(); const button = event.target.querySelector('button'); button.disabled = true; button.textContent = 'Connecting…';
    const input = $('#api-key'), key = input.value; input.value = '';
    try { await intervals.connect(key); await intervals.flush(); await reload(); render(); notify('Intervals.icu connected for this tab.'); }
    catch (error) { button.disabled = false; button.textContent = 'Connect account ↗'; throw error; }
  });
}
function updateSetup() {
  if (!$('#start-test')) return;
  let c, invalid;
  try { c = getConfiguration(); } catch (error) { invalid = error.message; }
  if (c) {
    const p = PRESETS[c.preset];
    $('#warmup-preview').textContent = `${c.warmupSeconds / 60 < 1 ? `${c.warmupSeconds}s` : `${c.warmupSeconds / 60} min`} · ${c.warmupPower} W`;
    $('#ramp-preview').textContent = `${p.start} W → +${p.step} W`;
    $('#cooldown-preview').textContent = `${c.cooldownSeconds < 60 ? `${c.cooldownSeconds}s` : `${c.cooldownSeconds / 60} min`} · easy spin`;
  }
  const liveReady = devices.trainerReady && !!devices.range && devices.measurements.fresh(draft.powerSource, 'power', performance.now() / 1000) != null;
  const ready = c && (draft.demo || liveReady) && !state.busyRole && !ride.busy && !$('#dialog').open;
  $('#start-test').disabled = !ready;
  $('#start-mode').textContent = draft.demo ? 'MOCK RIDE · SYNTHETIC DATA' : 'YOUR NEXT BENCHMARK';
  $('#readiness').textContent = invalid ?? (ride.busy ? 'Your test is already running.' : draft.demo ? 'Ready to try the full workflow, without sensors.' : !devices.available ? 'Live Bluetooth requires Chrome on localhost or HTTPS. Mock rides are available.' : !devices.trainerReady ? 'Connect your smart trainer to get rolling.' : !liveReady ? 'Pedal to wake the selected power source.' : c.cadenceSource === 'unavailable' ? 'Ready. No cadence signal: finish the ramp manually.' : 'All set. Clip in and find your rhythm.');
  updateConnections();
  drawScene($('#setup-scene'), { phase: 'waiting', dark: isDark() });
}
function updateConnections() {
  if (!$('#matching-status')) return;
  const liveReady = devices.trainerReady && devices.measurements.fresh(draft.powerSource, 'power', performance.now() / 1000) != null;
  $('#matching-status').textContent = prefs.powerMatching ? 'Power matching on' : 'Power matching off';
  $('#matching-copy').textContent = draft.powerSource === 'trainer' ? 'Trainer power selected. Matching applies when you use an external meter.' : prefs.powerMatching ? 'External meter controls trainer power.' : 'External meter records power; trainer uses its own measurement.';
  $('#device-dot').classList.toggle('connected', liveReady);
  for (const role of Object.keys(DEVICE_LABELS)) {
    const device = devices.devices[role], value = devices.measurements.fresh(role, role === 'heartRate' ? 'heartRate' : 'power', performance.now() / 1000, role === 'heartRate' ? 5 : 2);
    $(`#device-${role}`).textContent = device ? device.name + (device.ready ? '' : ' · connecting…') : 'Not connected';
    $(`#reading-${role}`).textContent = value != null ? `${Math.round(value)} ${role === 'heartRate' ? 'bpm' : 'W'} · live` : device?.ready ? 'Connected · waiting for readings' : '';
  }
}
function isDark() { return prefs.appearance === 'dark' || prefs.appearance === 'system' && matchMedia('(prefers-color-scheme: dark)').matches; }
function updateRide() {
  if (!$('#ride-time') || !ride.engine) return;
  const e = ride.engine, s = e.session, c = s.configuration, elapsed = ride.elapsed, active = e.active;
  $('#ride-title').textContent = PHASES[e.phase]; $('#ride-time').textContent = time(elapsed);
  const freshPower = e.lastPower && elapsed - e.lastPower.time <= 2;
  $('#live-power').textContent = watts(freshPower ? e.lastPower.watts : null); $('#power-freshness').textContent = freshPower ? 'Measured from your selected source' : active ? 'Waiting for a fresh reading' : 'Recording finished';
  $('#live-target').textContent = e.resistanceLevel != null ? (e.resistanceLevel / 10).toFixed(1) : watts(e.target); $('#live-best').textContent = s.training ? time(elapsed) : watts(e.liveBest);
  $('#trainer-command').textContent = ride.trainingTransition ? (ride.trainingTransition === 'pausing' ? 'Releasing trainer…' : 'Resuming trainer…') : e.phase === 'paused' ? `Trainer released · resume at ${e.resistanceLevel != null ? (e.resistanceLevel / 10).toFixed(1) + ' level' : e.resumeTarget + ' W'}` : e.resistanceLevel != null ? 'Resistance control · matching off' : e.freewheel ? 'ERG released · free spin' : c.powerMatchingEnabled ? `Matched command: ${watts(ride.lastAcknowledged)} W` : 'ERG target';
  $('#live-cadence').textContent = watts(e.lastCadence && elapsed - e.lastCadence.time <= 2 ? e.lastCadence.rpm : null);
  const hr = s.samples.findLast(r => r.heartRate != null && elapsed - r.time <= 5)?.heartRate;
  $('#live-heart').textContent = watts(hr); $('#phase-time').textContent = time(s.training ? e.trainingElapsed : elapsed - e.phaseStartedAt); $('#chart-end').textContent = time(elapsed);
  const guidance = { paused: 'Workout progress and XP are paused. Pedal until fresh readings arrive, then resume.', riding: 'Stay comfortable. Follow the target; Stop & save is always available.', waiting: 'Start pedaling. The test begins once fresh power and movement arrive.', warmup: 'Settle into a comfortable cadence. Let your legs come to the effort.', ramp: 'Stay seated and hold a steady cadence. Keep going until you cannot maintain it.', cooldown: e.freewheel ? 'The ramp is done. Resistance is released: spin freely and recover.' : 'Take it easy. Your recording continues through the cooldown.', completed: 'Your effort is saved on this browser. Take a breath. You earned it.', interrupted: 'Your recording has been saved up to the interruption. Check the reason before starting again.' };
  $('#phase-guidance').textContent = guidance[e.phase];
  const p = PRESETS[c.preset];
  $('#next-step').textContent = e.phase === 'ramp' ? `Next step in ${Math.ceil(p.seconds - (elapsed - e.phaseStartedAt) % p.seconds)} sec · +${p.step} W${c.cadenceSource === 'unavailable' ? '. No cadence signal: use Finish ramp.' : ''}` : e.phase === 'warmup' ? `${time(Math.max(0, c.warmupSeconds - (elapsed - e.phaseStartedAt)))} until the ramp` : e.phase === 'cooldown' ? `${time(Math.max(0, c.cooldownSeconds - (elapsed - e.phaseStartedAt)))} of recovery remaining` : '';
  if (s.training) {
    $('#next-step').textContent = e.currentStep ? `${e.currentStep.step.name}${s.training.kind === 'workout' ? ` · ${e.intensity}% intensity` : ''} · ${s.training.kind === 'workout' ? time(e.currentStep.remaining) + ' remaining' : e.resistanceLevel != null ? 'Adjust your resistance below' : 'Adjust your watts below'}` : '';
    document.querySelector('.phase-track').hidden = true;
  }
  if (s.adventureEnabled) $('#phase-guidance').textContent += s.isDemo ? ' Preview · no Cyclepunk rewards.' : ` Cyclepunk: ${Math.floor(s.eligibleMilliseconds / 6000)} XP this ride.`;
  document.querySelectorAll('[data-phase]').forEach(span => span.classList.toggle('current', span.dataset.phase === e.phase));
  const message = $('#ride-message'); message.hidden = !s.endReason; message.textContent = s.endReason ?? '';
  if (state.lastViewPhase !== `${s.id}/${e.phase}/${ride.finishing}/${ride.trainingTransition}`) {
    state.lastViewPhase = `${s.id}/${e.phase}/${ride.finishing}/${ride.trainingTransition}`;
    $('#ride-actions').innerHTML = active ? `${s.training ? `<button class="primary" data-live="pause" ${ride.trainingTransition ? 'disabled' : ''}>${e.phase === 'paused' ? 'Resume' : 'Pause'}</button>` : ''}${s.training?.kind === 'workout' ? '<button class="secondary" data-live="easier">−5%</button><button class="secondary" data-live="harder">+5%</button>' : ''}${e.resistanceLevel != null ? '<button class="secondary" data-live="less-resistance">− level</button><button class="secondary" data-live="more-resistance">+ level</button>' : s.training?.kind === 'freeRide' ? '<button class="secondary" data-live="lower">−10 W</button><button class="secondary" data-live="higher">+10 W</button>' : ''}${e.phase === 'ramp' ? '<button class="primary" data-live="finish">Finish ramp ↗</button>' : ''}<button class="danger-button" data-live="stop">${e.phase === 'cooldown' ? 'End cooldown & save' : 'Stop & save'}</button><span class="footnote">${s.isDemo ? 'Synthetic recording · never uploads' : 'Keep this tab visible during the test.'}</span>` : `<button class="secondary" data-live="details">Review recording ↗</button><a class="primary" href="#train">Back to Train ↗</a><button class="text-button" data-live="json">Download JSON</button>${ride.finishing ? '<span class="footnote">Saving recording and confirming trainer stop…</span>' : ''}`;
    document.querySelectorAll('[data-live]').forEach(b => b.onclick = safely(() => ({ easier: () => ride.adjustIntensity(-5), harder: () => ride.adjustIntensity(5), 'less-resistance': () => ride.adjustResistance(-1), 'more-resistance': () => ride.adjustResistance(1), pause: () => e.phase === 'paused' ? ride.resumeTraining() : ride.pauseTraining(), lower: () => ride.adjustERG(-10), higher: () => ride.adjustERG(10), finish: () => ride.finishRamp(), stop: () => ride.stop(), details: () => showSession(s), json: () => exportSession(s, 'json') })[b.dataset.live]()));
    if (ride.trainingTransition) document.querySelectorAll('[data-live="lower"], [data-live="higher"], [data-live="easier"], [data-live="harder"], [data-live="less-resistance"], [data-live="more-resistance"]').forEach(b => { b.disabled = true; });
    $('#ride-result').innerHTML = s.result ? `<section class="result-banner"><span class="eyebrow">${s.isDemo ? 'MOCK RESULT' : 'YOUR ESTIMATED FTP'}</span><strong>${Math.round(s.result.estimatedFTP)} <small>W</small></strong><p>${Math.round(s.result.bestMinutePower)} W best minute × ${Math.round(s.result.factor * 100)}% · Reference range ${Math.round(s.result.lowerFTP)}–${Math.round(s.result.upperFTP)} W</p></section>` : '';
    if (!active) $('#ride-result').innerHTML += rewardsView(s);
  }
  drawScene($('#ride-scene'), { time: elapsed, phase: e.phase, pedaling: active && e.phase !== 'paused' && (e.lastCadence?.rpm ?? 0) >= 20, dark: isDark(), reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches });
  drawChart($('#power-chart'), s.samples, { target: e.target });
}
function update() {
  $('#ride-dot').hidden = !ride.active;
  if (state.tab === 'setup') updateSetup();
  if (state.tab === 'train') updateConnections();
  $('#live-link').hidden = !ride.engine;
  $('#quick-stop').hidden = !ride.active;
  if (state.tab === 'ride') updateRide();
  const phase = ride.engine?.phase;
  if (phase && state.lastPhase !== phase) { state.lastPhase = phase; $('#announce').textContent = PHASES[phase]; }
}
async function reload() { state.workouts = await store.all('workouts'); state.profiles = await store.all('profiles'); state.history = (await store.all('sessions')).sort((a, b) => b.startedAt.localeCompare(a.startedAt)); state.jobs = await store.all('jobs'); }
function exportSession(s, format) { const content = format === 'csv' ? csv(s) : format === 'tcx' ? tcx(s) : JSON.stringify(s, null, 2); download(content, `ftpunk-${s.isDemo ? 'mock-' : ''}${s.id}.${format}`, format === 'csv' ? 'text/csv' : format === 'tcx' ? 'application/vnd.garmin.tcx+xml' : 'application/json'); }
function showSession(s) {
  if (!s) return;
  const c = s.configuration, result = s.result;
  modal(s.isDemo ? 'Mock ride recording' : 'Your ride, recorded.', `<p class="eyebrow">${esc(c.riderName)} · ${date(s.startedAt)}</p>${result ? `<div class="dialog-result"><strong>${Math.round(result.estimatedFTP)} <small>W FTP</small></strong><p>Best 60 seconds: ${Math.round(result.bestMinutePower)} W · ${Math.round(result.factor * 100)}% factor</p><p>Reference range: ${Math.round(result.lowerFTP)}–${Math.round(result.upperFTP)} W${result.wattsPerKG ? ` · ${result.wattsPerKG.toFixed(2)} W/kg` : ''}</p></div>` : s.training ? `<p>${esc(s.training.name)} · ${Math.floor((s.eligibleMilliseconds ?? 0) / 6000)} XP recorded</p>` : '<p>No FTP estimate: this recording has no scored, complete 60-second ramp window.</p>'}<dl class="session-details"><dt>Outcome</dt><dd>${OUTCOMES[s.outcome] ?? 'Recording'}</dd><dt>Protocol</dt><dd>${esc(s.training?.name ?? PRESETS[c.preset].title)}</dd><dt>Duration</dt><dd>${time(s.endedAtOffset ?? 0)}</dd><dt>Power source</dt><dd>${esc(DEVICE_LABELS[c.powerSource])}</dd><dt>Cadence source</dt><dd>${esc(DEVICE_LABELS[c.cadenceSource] ?? 'Unavailable · manual finish')}</dd><dt>Power matching</dt><dd>${c.powerMatchingEnabled ? 'On' : 'Off'}</dd></dl>${s.endReason ? `<p class="notice error">${esc(s.endReason)}</p>` : ''}${s.isDemo ? '<p class="muted">Synthetic data. This ride cannot upload or become your real FTP.</p>' : ''}<div class="button-row"><button class="secondary" data-dialog="json">JSON ↗</button><button class="secondary" data-dialog="csv">CSV ↗</button><button class="secondary" data-dialog="tcx" ${!s.samples.length ? 'disabled' : ''}>TCX ↗</button></div>${rewardsView(s)}<details><summary>Session events</summary><ul class="event-list">${s.events.map(e => `<li><time>${time(e.time)}</time> ${esc(e.message)}</li>`).join('')}</ul></details>`, `${result && !s.isDemo ? '<button class="secondary" data-dialog="adopt">Use as current FTP</button>' : ''}${!s.isDemo && s.samples.length ? '<button class="primary" data-dialog="upload">Upload to Intervals.icu ↗</button>' : ''}<button class="text-button danger-text" data-dialog="delete" ${ride.busy ? 'disabled' : ''}>Delete recording</button>`, async (action, dialog) => {
    if (['json', 'csv', 'tcx'].includes(action)) return exportSession(s, action);
    if (action === 'upload') { dialog.close(); return reviewUpload(s); }
    if (action === 'adopt') {
      if (ride.busy) throw Error('Finish the current ride before changing FTP.');
      const p = state.profiles.find(p => p.id === c.riderID); if (!p) throw Error('The original rider could not be found.');
      const entry = { id: uuid(), watts: result.estimatedFTP, date: s.startedAt, source: 'Ramp test', sessionID: s.id }; p.ftpHistory.unshift(entry); p.currentFTPID = entry.id; await store.put('profiles', p); profileFields(); dialog.close(); notify(`Current FTP updated for ${p.name}.`); render();
    }
    if (action === 'delete') { dialog.close(); modal('Delete this recording?', `<p>This removes ${esc(c.riderName)}’s recording from this browser. Export it first if you want to keep a copy. Uploaded activities stay on Intervals.icu.</p>`, '<button class="danger-button" data-dialog="confirm">Delete recording</button><button class="secondary" data-dialog="cancel">Keep recording</button>', async (choice, d) => { if (choice === 'confirm') { await store.delete('sessions', s.id); for (const p of state.profiles) { const removed = p.ftpHistory.filter(e => e.sessionID === s.id).map(e => e.id); p.ftpHistory = p.ftpHistory.filter(e => e.sessionID !== s.id); if (removed.includes(p.currentFTPID)) p.currentFTPID = null; await store.put('profiles', p); } profileFields(); const jobs = await store.all('jobs'); for (const job of jobs.filter(j => j.sessionID === s.id)) await store.delete('jobs', job.id); await reload(); render(); } d.close(); }); }
  });
}
function reviewUpload(session) {
  if (!intervals.connection) { location.hash = 'settings'; notify('Connect Intervals.icu, then open the recording in Progress to approve its upload.'); return; }
  const connection = { ...intervals.connection };
  modal('Upload this test?', `<p>Your test is already saved locally.</p><dl class="session-details"><dt>Rider</dt><dd>${esc(session.configuration.riderName)}</dd><dt>Destination</dt><dd>${esc(connection.name)} · ${esc(connection.id)}</dd><dt>Recording</dt><dd>${date(session.startedAt)}</dd></dl><p class="muted">This sends the activity, including the rider’s name, to this account. If the connection fails, the approved upload will queue for retry.</p>`, '<button class="primary" data-dialog="upload">Approve & upload ↗</button><button class="secondary" data-dialog="local">Keep local</button>', async (action, dialog) => {
    if (action === 'local') { dialog.close(); return; }
    dialog.querySelector('[data-dialog="upload"]').disabled = true;
    try { await intervals.approve(session, connection.id); dialog.close(); await reload(); render(); const job = state.jobs.find(j => j.sessionID === session.id && j.accountID === connection.id); notify(job?.status === 'uploaded' ? 'Activity uploaded to Intervals.icu.' : `Upload saved for retry. ${job?.error ?? ''}`); } catch (error) { dialog.querySelector('[data-dialog="upload"]').disabled = false; throw error; }
  });
}
const actions = {
  'import-workout': () => { if (!ride.busy) $('#workout-file').click(); },
  'example-workout': () => download(JSON.stringify(exampleWorkout, null, 2), 'ftpunk-workout-example.json'),
  'resistance-ride': () => startRide(resistanceRide(state.resistance)),
  'download-workouts': async () => {
    if (ride.busy || state.downloading) return;
    const riderID = currentProfile().id, ftp = Number(draft.priorFTP) || null;
    const dateOnly = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    const today = new Date(), end = new Date(today); end.setDate(end.getDate() + 14);
    state.downloading = true; render();
    try {
      const result = await intervals.workouts(riderID, ftp, dateOnly(today), dateOnly(end));
      if (ride.busy || currentProfile().id !== riderID) throw Error('The rider or ride changed. Download again.');
      await store.saveWorkouts(result.workouts); await reload();
      state.importReport = `Saved ${result.workouts.length} workouts for offline use.` + (result.skipped.length ? '\nSkipped:\n' + result.skipped.slice(0, 20).join('\n') + (result.skipped.length > 20 ? `\n…and ${result.skipped.length - 20} more.` : '') : '');
    } finally { state.downloading = false; render(); }
  },
  'cancel-start': () => ride.stop(),
  'start': () => startRide(),
  'free-ride': () => startRide(freeRide(state.freeWatts)),
  'demo': () => { draft.demo = !draft.demo; render(); },
  'add-rider': () => modal('Who’s riding?', '<form id="rider-form"><label class="field"><span>Rider name</span><input id="new-rider-name" maxlength="80" placeholder="Your name" required autocomplete="name"></label><p class="muted">Each rider has a separate FTP history and recordings.</p></form>', '<button class="primary" data-dialog="save">Add rider ↗</button>', async (_, dialog) => {
    const name = $('#new-rider-name').value.trim(); if (!name || name.length > 80) throw Error('Enter a rider name, up to 80 characters.'); if (state.profiles.some(p => p.name.toLocaleLowerCase() === name.toLocaleLowerCase())) throw Error('That rider already exists. Choose a distinct name.');
    const p = { id: uuid(), name, weightKG: null, ftpHistory: [], currentFTPID: null }; await store.put('profiles', p); prefs.selectedRider = p.id; await reload(); profileFields(); applyPreferences(); dialog.close(); render();
  }),
  'protocol-info': () => modal('The ramp, explained.', `<p>Start with a warm-up, then follow a progressively higher ERG target while staying seated at a steady cadence.</p>${Object.entries(PRESETS).map(([key, p]) => `<h3>${p.title}${key === 'zwift' ? ' · Zwift-style' : ''}</h3><p>${p.audience}. Start ${p.start} W, add ${p.step} W every ${p.seconds} seconds.</p>`).join('')}<h3>Finishing the ramp</h3><p>After the first 10 seconds of the ramp, cadence below 45 rpm for 5 seconds ends the effort. The scored ramp ends at the start of that low-cadence period. You can also use Finish ramp. Without a cadence signal, finish manually.</p><h3>The FTP estimate</h3><p>The best complete 60-second power window is weighted by time. Zeros count; gaps do not get filled. Your selected factor is 72% or 75%. The 72–77% range is an estimate, not a laboratory measurement.</p><h3>Recovery</h3><p>After automatic exhaustion, ERG resistance is released for free spinning. A manual finish uses the protocol’s easy cooldown target.</p>`, '<button class="primary" data-dialog="close">Got it</button>', (_, dialog) => dialog.close()),
  'backup': async () => {
    if (ride.busy) throw Error('Finish the ride before exporting a backup.');
    const release = await acquireRideLease();
    try { download(archiveText(await store.backup()), `ftpunk-backup-${new Date().toISOString().slice(0, 10)}.json`); }
    finally { release(); }
  },
  'import': () => { if (!ride.busy) $('#archive-file').click(); },
  'rollback': async () => {
    const backups = (await store.all('backups')).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    if (!backups.length) throw Error('There is no pre-import backup yet.');
    download(archiveText(backups[0].archive), 'ftpunk-before-import.json');
  },
  'capture': () => download(JSON.stringify(devices.captures, null, 2), 'ftpunk-bluetooth-capture.json'),
  'disconnect-intervals': () => { intervals.disconnect(); render(); notify('Disconnected. Reconnect to retry previously approved queued uploads.'); },
  'retry-uploads': async () => { await intervals.flush(true); await reload(); render(); notify('Approved upload retries finished. See the queue for status.'); },
};
async function wakeScreen() { if (!ride.active || state.wake || !navigator.wakeLock || document.hidden) return; try { state.wake = await navigator.wakeLock.request('screen'); state.wake.addEventListener('release', () => { state.wake = null; }); } catch { notify('Keep your screen awake manually during this test.'); } }
async function boot() {
  try {
    applyPreferences(); store = await LocalStore.open();
    try { const release = await acquireRideLease(); try { await store.recover(); } finally { release(); } } catch (error) { notify(error.message); }
    await reload();
    if (!state.profiles.length) { const p = { id: uuid(), name: 'You', weightKG: null, ftpHistory: [], currentFTPID: null }; await store.put('profiles', p); state.profiles = [p]; }
    prefs.selectedRider = currentProfile().id; profileFields();
    intervals = new IntervalsClient(store); ride = new RideController(devices, store);
    ride.onChange = () => { update(); if (!ride.active && state.wake) { void state.wake.release(); state.wake = null; } };
    ride.onError = fail;
    $('#quick-stop').onclick = () => ride.stop();
    ride.onSaved = session => { void (async () => { await reload(); if (['history', 'city', 'train'].includes(state.tab)) render(); if (!session.isDemo && (session.result || session.training) && intervals.connection && !$('#dialog').open) reviewUpload(session); })().catch(fail); };
    devices.onChange = update;
    devices.onMeterReady = name => {
      if (ride.busy) return;
      draft.powerSource = 'externalPowerMeter';
      modal('Use power matching?', `<p><strong>${esc(name)}</strong> is connected.</p><p>Adjust trainer resistance until this meter reads the workout target, or use the meter for recording only.</p><p class="muted">Your preference is saved in Settings → Trainer control.</p>`, '<button class="primary" data-dialog="yes">Use power matching</button><button class="secondary" data-dialog="no">Recording only</button>', (choice, dialog) => { prefs.powerMatching = choice === 'yes'; applyPreferences(); dialog.close(); render(); });
    };
    $('#dialog').addEventListener('close', update);
    window.addEventListener('hashchange', () => { render(); $('#main').focus({ preventScroll: true }); });
    window.addEventListener('resize', update);
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && !ride.demo && (ride.active || ride.starting)) ride.interrupt('The test ended because the browser tab became hidden. Keep FTPunk visible for live rides.');
      else if (!document.hidden) void wakeScreen();
    });
    document.addEventListener('freeze', () => ride.interrupt('The browser suspended the workout.'));
    window.addEventListener('pagehide', () => ride.interrupt('The browser page was closed or navigated away.'));
    window.addEventListener('beforeunload', event => { if (ride.busy) { event.preventDefault(); event.returnValue = ''; } });
    window.addEventListener('online', safely(async () => { await intervals.flush(); await reload(); if (state.tab === 'settings') render(); }));
    setInterval(() => { update(); if (intervals.connection) void intervals.flush().catch(fail); }, 1000);
    render();
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(() => notify('Offline installation is unavailable. The app still works while this page is online.'));
  } catch (error) { fail(error); $('#main').innerHTML = '<section class="panel empty"><h1>Your local storage could not open.</h1><p>Enable site storage in Chrome, then reload this page. A recording will not start without working local storage.</p></section>'; }
}
void boot();
