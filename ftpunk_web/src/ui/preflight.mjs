import { esc, $, screenHeader, checklistRow, checklistCard, pill, numberField, switchRow, profileChart } from './components.mjs';
import { registerRoute, navigate, rerender, wakeScreen } from './shell.mjs';
import { openInfoSheet } from './sheets.mjs';
import { blockerReason, cadenceStatus, devicesLine, DurationFormat } from '../rules/presentation.mjs';
import { intensityLabel } from '../catalog.mjs';
import { PRESETS } from '../domain.mjs';
import { buildConfiguration } from '../rules/preflight.mjs';
// The pre-flight checklist every ride passes through. Start is always visible; when it is disabled the reason sits directly above it.
// Routes: #/preflight/ftpTest, #/preflight/freeERG, #/preflight/resistance, #/preflight/workout/<ref>.

const KINDS = { ftpTest: 'FTP test', freeERG: 'Free ERG ride', resistance: 'Resistance ride' };
const extraRows = [];
/** Other features add checklist rows here: `fn(model, kind) -> [rowHTML...]`. They render below the kind's own rows. */
export const registerPreflightRows = fn => extraRows.push(fn);
let enteredKey = null;
const kindOf = params => params[0] === 'workout' ? 'workout' : params[0] in KINDS ? params[0] : 'ftpTest';
const refOf = params => params.slice(1).join('/');
const workoutOf = (model, params) => kindOf(params) === 'workout' ? model.workoutDetail(refOf(params)) : null;
const titleOf = (model, params) => kindOf(params) === 'workout' ? workoutOf(model, params)?.title ?? 'Workout' : KINDS[kindOf(params)];
const startTitle = (model, kind) => model.ride.starting ? 'Preparing…' : ({ ftpTest: model.demoMode ? 'Start debug test' : 'Start FTP test', freeERG: 'Start free ERG ride', resistance: 'Start resistance ride', workout: 'Start workout' })[kind];
function blockerFor(model, params) {
  const kind = kindOf(params), detail = workoutOf(model, params);
  if (kind === 'workout' && !detail) return { text: 'This workout was removed.', key: 'removed' };
  const key = model.startBlocker(kind, { plan: detail?.plan ?? null, needsFTP: detail?.needsFTP === true });
  return { key, text: blockerReason(key) };
}
function warmupPreview(model) {
  try { const c = buildConfiguration({ draft: model.draft, rider: model.profile, ftp: model.ftp, powerSource: model.powerSource, cadenceSource: 'trainer', powerMatching: false, mock: model.demoMode }); return `${c.warmupPower} W`; } catch { return '—'; }
}
const part = minutes => Number(minutes) === 0 ? 'skip' : `${minutes} min`;
function warmupSummary(model) {
  if (model.demoMode && model.draft.quickDebug) return '10 s · 10 s (debug timing)';
  return `Warm-up ${part(model.draft.warmupMinutes)} at ${warmupPreview(model)} · cool-down ${part(model.draft.cooldownMinutes)}`;
}
function riderSummary(model) {
  const r = model.profile, weight = r.weightKG ? `${Math.round(r.weightKG)} kg` : 'no weight';
  return `${r.name} · ${weight} · ${model.ftp ? `FTP ${Math.round(model.ftp)} W` : 'no FTP'}`;
}
function deviceRowText(model) {
  const d = model.devices;
  if (model.demoMode) return 'Mock sensors';
  return devicesLine({ trainerName: d.devices.trainer?.name ?? null, powerSource: model.powerSource, meterName: d.devices.externalPowerMeter?.name ?? null, heartRateName: d.devices.heartRate?.name ?? null });
}
const stepper = ({ id, title, value, detail, minusAction, plusAction, minusDisabled, plusDisabled, busy }) => `<div class="stepper-row"><div class="grow"><span class="caption">${esc(title)}</span><span class="row-value num" id="${id}">${esc(value)}</span><span class="row-detail">${esc(detail)}</span></div><div class="row nowrap"><button type="button" class="btn secondary" data-action="${minusAction}" aria-label="Decrease ${esc(title.toLowerCase())}" ${minusDisabled || busy ? 'disabled' : ''}>−</button><button type="button" class="btn secondary" data-action="${plusAction}" aria-label="Increase ${esc(title.toLowerCase())}" ${plusDisabled || busy ? 'disabled' : ''}>+</button></div></div>`;

function commonRows(model) {
  const cadence = cadenceStatus(model.cadenceSource(), !!model.devices.devices.trainer);
  return checklistCard([
    checklistRow({ icon: '☺', title: 'Rider', value: riderSummary(model), action: 'open-riders', id: 'row-rider' }),
    checklistRow({ icon: '⌁', title: 'Devices', value: deviceRowText(model), detail: `Cadence: ${cadence.text}`, status: model.devices.devices.trainer && !model.devices.trainerReady && !model.demoMode ? 'attention' : 'normal', action: 'open-devices', id: 'row-devices' }),
  ]);
}
function testRows(model) {
  const d = model.draft, recommended = model.recommendedProtocol, locked = model.busy;
  const rows = [
    checklistRow({ icon: '↗', title: 'Protocol', value: PRESETS[d.preset].title, detail: d.presetChosen ? 'Chosen by you' : `Recommended: ${recommended.reason}`, action: 'open-protocols' }),
    checklistRow({ icon: '%', title: 'Estimate', value: '72 % of your best minute', detail: 'Conservative and fixed. The 72–77 % range is explained in the result.', action: 'info-estimate' }),
    `<details class="warmup-details" ${model.preflightDetailsOpen ? 'open' : ''}><summary>${checklistRow({ icon: '♨', title: 'Warm-up and cool-down', value: warmupSummary(model), detail: 'Adjust', id: 'row-warmup' })}</summary><div class="stack details-body">
      ${model.demoMode && d.quickDebug ? '<p class="muted">10 seconds each · debug override</p>' : `<div class="fields">${numberField('Warm-up · minutes', 'pf-warmup', d.warmupMinutes, { min: 0, max: 60, step: 1, disabled: locked })}${numberField('Cool-down · minutes', 'pf-cooldown', d.cooldownMinutes, { min: 0, max: 60, step: 1, disabled: locked })}</div>`}
      ${switchRow('Use 50% of FTP for the warm-up', 'pf-auto-warmup', d.automaticWarmup, { disabled: locked })}
      ${d.automaticWarmup ? '' : numberField('Warm-up watts', 'pf-manual-warmup', d.manualWarmup, { min: 1, max: 32767, placeholder: '100' })}
      ${!model.ftp && d.automaticWarmup ? '<p class="footnote">No FTP selected: the warm-up uses the protocol’s default target.</p>' : ''}
      <p class="footnote">Set either duration to zero to skip that phase. After automatic exhaustion the trainer releases its load; you can stop and save at any time.</p></div></details>`,
  ];
  return checklistCard(rows, 'Test setup');
}
function ergRows(model) {
  const watts = model.draft.freeWatts;
  return checklistCard([stepper({ id: 'pf-erg-value', title: 'Starting target', value: `${watts} W`, detail: 'Change by 10 W while riding. Stop & save releases the trainer.', minusAction: 'erg-minus', plusAction: 'erg-plus', minusDisabled: watts <= 10, plusDisabled: watts >= 1000, busy: model.busy })], 'Ride setup');
}
function resistanceRows(model) {
  const range = model.resistanceRange;
  if (!range) return checklistCard([checklistRow({ icon: '◔', title: 'Resistance', value: 'Not available', status: 'attention', detail: 'Pair a trainer that advertises resistance control and a supported level range.' })], 'Ride setup');
  const level = range.quantized(model.draft.resistance);
  return checklistCard([stepper({ id: 'pf-res-value', title: 'Starting level', value: (level / 10).toFixed(1), detail: 'Trainer-specific levels, not watts. Use gears and cadence to choose the effort. Power matching is off.', minusAction: 'res-minus', plusAction: 'res-plus', minusDisabled: level <= range.minimum, plusDisabled: level >= range.maximum, busy: model.busy })], 'Ride setup');
}
function workoutRows(model, params) {
  const detail = workoutOf(model, params);
  if (!detail) return '<p class="warn">⌫ This workout was removed.</p>';
  const intensity = model.draft.intensity, used = detail.plan?.ftpWatts, differs = detail.cached && used != null && model.ftp != null && Math.abs(used - model.ftp) > 0.5;
  const ftpText = detail.needsFTP ? 'Needs FTP' : used != null ? `${Math.round(used)} W` : 'Fixed watts';
  return checklistCard([
    `<div class="stack">${checklistRow({ icon: '☰', title: detail.title, value: [detail.categoryTitle, detail.source, DurationFormat.workout(detail.duration)].filter(Boolean).join(' · '), detail: detail.plan ? intensityLabel(detail.plan) : '' })}<div class="profile-wrap">${profileChart(detail.previewPlan, { intensity, height: 'normal' })}</div></div>`,
    checklistRow({ icon: '⚡', title: 'FTP used', value: ftpText, status: detail.needsFTP ? 'attention' : 'normal', detail: differs ? `Saved at ${Math.round(used)} W; your current FTP is ${Math.round(model.ftp)} W. This workout does not rescale.` : '' }),
    stepper({ id: 'pf-intensity', title: 'Intensity', value: `${intensity} %`, detail: 'Scales every target. You can change it by 5 % during the ride.', minusAction: 'intensity-minus', plusAction: 'intensity-plus', minusDisabled: intensity <= 50, plusDisabled: intensity >= 150, busy: model.busy }),
  ], 'Workout');
}
function debugGroup(model, kind) {
  const d = model.draft;
  return checklistCard([`<div class="stack debug-body"><p>${pill('Mock sensors · never uploads', 'warning', '▶')}</p>
    ${kind === 'ftpTest' ? switchRow('Quick warm-up and cool-down · 10 s each', 'pf-quick', d.quickDebug, { disabled: model.busy }) : ''}
    <label class="field"><span>Playback speed</span><select id="pf-speed" ${model.busy ? 'disabled' : ''}>${[1, 4, 12, 60].map(n => `<option value="${n}" ${Number(d.speed) === n ? 'selected' : ''}>${n}×</option>`).join('')}</select></label>
    <label class="field"><span>Signal scenario</span><select id="pf-scenario" ${model.busy ? 'disabled' : ''}>${[['exhaustion', 'Ride to exhaustion'], ['steady', 'Steady rider'], ['powerDropout', 'Power dropout'], ['cadenceDropout', 'Cadence dropout']].map(([v, t]) => `<option value="${v}" ${d.scenario === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label></div>`], 'Debug');
}
function footer(model, params) {
  const c = model.connection, upload = c ? `Saved locally first. You will be asked before anything is uploaded to ${c.name} on Intervals.icu.` : 'Results stay in this browser. Connect Intervals.icu in Settings to upload an activity.';
  return kindOf(params) === 'ftpTest' ? `Stay seated and hold a comfortable, steady cadence. The trainer sets the load. Test limits: 600 W or 30 minutes of ramp. Stop at any time. ${upload}` : upload;
}
function startBar(model, params) {
  const kind = kindOf(params), { key, text } = blockerFor(model, params), removed = key === 'removed', disabled = !!key || model.busy;
  return `<div class="action-bar" id="start-bar"><p class="reason ${text ? '' : 'hidden'}" id="start-reason" role="status" ${text ? '' : 'hidden'}>${esc(text ?? '')}</p><div class="row nowrap"><button type="button" class="btn primary grow" id="start-button" data-action="start" ${disabled ? 'disabled' : ''} ${removed ? 'data-removed' : ''}>▶ ${esc(startTitle(model, kind))}</button>${model.ride.starting ? '<button type="button" class="btn danger" data-action="cancel-start">Cancel start</button>' : ''}</div></div>`;
}
registerRoute('preflight', {
  tab: 'home', documentTitle: (model, params) => titleOf(model, params),
  render(model, params) {
    const kind = kindOf(params), key = params.join('/');
    if (enteredKey !== key) { enteredKey = key; model.draft.intensity = 100; model.applyRecommendation(); }
    const rows = { ftpTest: testRows, freeERG: ergRows, resistance: resistanceRows, workout: workoutRows }[kind](model, params);
    return `${screenHeader(titleOf(model, params), { back: '#/home' })}<div class="stack-l preflight">${model.demoMode ? `<p>${pill('Debug · mock sensors', 'warning', '▶')}</p>` : ''}${commonRows(model)}${rows}${extraRows.flatMap(fn => fn(model, kind) ?? []).join('')}${model.prefs.debugUnlocked && model.demoMode ? debugGroup(model, kind) : ''}<p class="footnote">${esc(footer(model, params))}</p></div>${startBar(model, params)}`;
  },
  update(model, params) {
    const { key, text } = blockerFor(model, params), button = $('#start-button'); if (!button) return;
    button.disabled = !!key || model.busy; const label = `▶ ${startTitle(model, kindOf(params))}`; if (button.textContent !== label) button.textContent = label;
    const reason = $('#start-reason'); reason.hidden = !text; if (reason.textContent !== (text ?? '')) reason.textContent = text ?? '';
    const rider = $('#row-rider'), devices = $('#row-devices'); if (rider && rider.textContent !== riderSummary(model)) rider.textContent = riderSummary(model);
    if (devices && devices.textContent !== deviceRowText(model)) devices.textContent = deviceRowText(model);
    const warm = $('#row-warmup'); if (warm && warm.textContent !== warmupSummary(model)) warm.textContent = warmupSummary(model);
  },
  actions: (model, params) => {
    const bump = (field, delta, min, max) => { model.draft[field] = Math.min(max, Math.max(min, Number(model.draft[field]) + delta)); rerender(); };
    return {
      'info-estimate': () => openInfoSheet('estimate'),
      'erg-minus': () => bump('freeWatts', -10, 10, 1000), 'erg-plus': () => bump('freeWatts', 10, 10, 1000),
      'res-minus': () => { const r = model.resistanceRange; model.draft.resistance = r.quantized(r.quantized(model.draft.resistance) - r.increment); rerender(); },
      'res-plus': () => { const r = model.resistanceRange; model.draft.resistance = r.quantized(r.quantized(model.draft.resistance) + r.increment); rerender(); },
      'intensity-minus': () => bump('intensity', -5, 50, 150), 'intensity-plus': () => bump('intensity', 5, 50, 150),
      'cancel-start': () => model.cancelStart(),
      'start': async () => {
        const kind = kindOf(params);
        const starting = kind === 'ftpTest' ? model.startFTPTest() : kind === 'freeERG' ? model.startFreeRide() : kind === 'resistance' ? model.startResistance() : model.startWorkout(refOf(params));
        rerender(); const started = await starting;
        if (started) { navigate('#/ride'); await wakeScreen(); } else rerender();
      },
    };
  },
  events: model => ({
    input: {
      'pf-warmup': el => { model.draft.warmupMinutes = el.value; model.onChange(); }, 'pf-cooldown': el => { model.draft.cooldownMinutes = el.value; model.onChange(); }, 'pf-manual-warmup': el => { model.draft.manualWarmup = el.value; model.onChange(); },
    },
    change: {
      'pf-auto-warmup': el => { model.draft.automaticWarmup = el.checked; rerender(); }, 'pf-quick': el => { model.draft.quickDebug = el.checked; rerender(); },
      'pf-speed': el => { model.draft.speed = Number(el.value); }, 'pf-scenario': el => { model.draft.scenario = el.value; },
    },
  }),
  bind(root, model) { const details = $('.warmup-details', root); if (details) details.addEventListener('toggle', () => { model.preflightDetailsOpen = details.open; }); },
});
