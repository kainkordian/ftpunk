import { rideTrack } from '../rules/virtual-ride.mjs';
import { esc, $, button, dashBox, profileChart, moveProfileMarker, pill, watts } from './components.mjs';
import { currentRoute } from './shell.mjs';
import { PHASES } from '../domain.mjs';
import { DurationFormat } from '../rules/presentation.mjs';
import { activityTitle } from '../rules/progress.mjs';
import { WorkoutClock } from '../rules/ride-summary.mjs';
import { heartLinePath, targetBoxState, nextStepText, rideFigures, FIGURES } from '../rules/dashboard.mjs';
import { drawChart } from '../scene.mjs';
import { rideVisualState, rideVisualInput } from '../chaindance/state.mjs';
import { coachingText } from '../chaindance/layout.mjs';
// The workout, free ERG and resistance dashboard in the Chaindance (RG/SP) style, without the rider scene. Mirrors App/Features/Ride/WorkoutCockpitView.swift.
// `dashboardHTML` builds the skeleton once per ride screen; `updateDashboard` only sets text, attributes and the heart-rate path, so a tick never rebuilds the header or the boxes.
const clock = DurationFormat.clock;
const kindName = session => session.training.kind === 'workout' ? 'workout' : session.training.resistance != null ? 'resistance' : 'free';
function setText(selector, text) { const el = $(selector); if (el && el.textContent !== text) el.textContent = text; }
function setHidden(selector, hidden) { const el = $(selector); if (el && el.hidden !== hidden) el.hidden = hidden; }
function setAttr(selector, name, value) { const el = $(selector); if (el && el.getAttribute(name) !== value) el.setAttribute(name, value); }
function setDisabled(selector, disabled) { const el = $(selector); if (el && el.disabled !== disabled) el.disabled = disabled; }
let lastHTML = new Map(), figuresCache = null, profileKey = null, actionsSignature = null;
function setHTML(selector, html) { const el = $(selector); if (el && lastHTML.get(selector) !== html) { el.innerHTML = html; lastHTML.set(selector, html); } }

const number = (id, size, unit = '', unitId = '') => `<p class="cd-value"><span class="cd-num ${size}" id="${id}">—</span>${unit || unitId ? `<span class="cd-unit" ${unitId ? `id="${unitId}"` : ''}>${unit}</span>` : ''}</p>`;
const stepButton = (label, action, aria, key) => `<button type="button" class="cd-step-btn" data-action="${action}" id="${action}" aria-label="${aria}" aria-keyshortcuts="${key}">${label}</button>`;

export function dashboardHeader(model, session) {
  const kind = kindName(session);
  return `<header class="cockpit-header cd-header${model.prefs.extraLarge ? " compact" : ""}"><a class="icon-btn" href="#/home" aria-label="Minimise ride" title="Keeps the ride running behind the live-ride bar"><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></a><div class="grow"><p class="cd-title"><span class="cd-badge">${kind === 'workout' ? 'WORKOUT' : kind === 'resistance' ? 'RESISTANCE' : 'FREE RIDE'}</span> <span id="cockpit-title">${esc(activityTitle(session))}</span></p><p class="caption cd-dim" id="cockpit-subtitle">${esc(session.configuration.riderName)}</p></div><div class="clock"><p class="cd-num cd-m" id="cockpit-clock">0:00</p><p class="cd-caption" id="cockpit-clock-label">${kind === 'workout' ? 'WORKOUT TIME' : 'RIDE TIME'}</p></div>${session.isDemo ? button('⋯', { kind: 'secondary', small: true, action: 'debug-controls', extra: { 'aria-label': 'Debug controls' } }) : ''}</header>`;
}
export function dashboardHTML(model, engine) {
  const s = engine.session, kind = kindName(s), workout = kind === 'workout', c = s.configuration, meter = c.powerSource === 'externalPowerMeter';
  const controls = workout ? stepButton('−5 %', 'intensity-minus', 'Lower intensity', 'ArrowDown') + stepButton('+5 %', 'intensity-plus', 'Raise intensity', 'ArrowUp')
    : kind === 'resistance' ? stepButton('− LEVEL', 'res-minus', 'Lower resistance', 'ArrowDown') + stepButton('+ LEVEL', 'res-plus', 'Raise resistance', 'ArrowUp') : stepButton('−10 W', 'erg-minus', 'Lower ERG target', 'ArrowDown') + stepButton('+10 W', 'erg-plus', 'Raise ERG target', 'ArrowUp');
  const actualBody = size => `${number('live-power', size, 'W', 'live-power-unit')}${meter ? '<p class="cd-trainer" id="cd-trainer"><span class="cd-caption">TR</span> <span class="cd-trainer-value" id="live-trainer">—</span></p>' : ''}`;
  const corner = meter ? '' : `${c.powerSource === 'trainer' ? 'Trainer' : 'External meter'} power`;
  const big = workout ? dashBox({ caption: 'Step left', cornerId: 'cd-step-corner', id: 'cd-big', cls: 'cd-bigbox', body: `<div class="cd-bigbody"><p class="cd-num cd-xl" id="cd-step-left" role="timer" aria-label="Step time left">—</p><p class="cd-step-name" id="cd-step-name"></p></div>` })
    : dashBox({ caption: 'Actual', corner, id: 'cd-big', cls: 'cd-bigbox', body: `<div class="cd-bigbody">${actualBody('cd-xl')}</div>` });
  const target = dashBox({ caption: 'Target', captionId: 'cd-target-caption', cornerId: 'cd-intensity-corner', id: 'cd-target-box', tone: 'lime', body: `<div class="cd-bigbody">${number('live-target', 'cd-l', 'W', 'cd-target-unit')}</div><div class="cd-steps">${controls}</div>` });
  const actual = workout ? dashBox({ caption: 'Actual', corner, id: 'cd-actual', body: `<div class="cd-bigbody">${actualBody('cd-l')}</div>` }) : '';
  const profile = workout ? `<div class="cd-profile-block"><div id="cockpit-profile" class="cd-profile">${profileChart(s.training, { intensity: engine.intensity, progressSeconds: 0, height: 'normal', heartPath: '' })}</div>
    <div class="cd-profile-row"><p class="cd-next" id="cd-next"></p><span class="cd-legend" aria-hidden="true"><span class="cd-swatch"></span>Heart rate</span><button type="button" class="cd-outline-btn" id="skip-step" data-action="skip-step" aria-keyshortcuts="Control+ArrowRight Meta+ArrowRight" aria-describedby="skip-hint">⏭ Skip step</button><span class="sr-only" id="skip-hint">Moves on to the next step. The last step can't be skipped; use Stop and save.</span></div></div>` : '';
  const reading = (caption, tone, valueId, unit) => dashBox({ caption, tone, body: `<p class="cd-value"><span class="cd-num cd-m" id="${valueId}">—</span>${unit ? `<span class="cd-unit">${unit}</span>` : ''}</p>` });
  const row = `<section class="cd-readings">${reading('♥ BPM', 'pink', 'live-heart')}${reading('RPM', '', 'live-cadence')}${workout ? reading('Intensity', 'cyan', 'live-intensity', '%') : reading('Work', 'cyan', 'live-kj', 'kJ')}</section>`;
  const figures = `<section class="cd-figures" id="cd-figures" aria-label="Ride figures">${FIGURES.map(f => dashBox({ caption: f.caption, corner: f.note ?? '', id: `fig-${f.id}`, cls: 'cd-fig', body: `<p class="cd-value"><span class="cd-num cd-s" id="${f.id === 'balance' ? 'live-balance' : `fig-${f.id}-value`}">—</span><span class="cd-unit">${f.unit}</span></p>` })).join('')}</section>`;
  lastHTML = new Map(); figuresCache = null; profileKey = null; actionsSignature = null;
  return `<div class="cockpit dash stack" data-kind="${kind}">${dashboardHeader(model, s)}<div id="cockpit-banners" class="stack"></div>
    <section class="cd-main ${workout ? 'is-workout' : 'is-free'}">${big}<div class="cd-pair">${target}${actual}</div></section>${profile}${row}${figures}<p class="cd-dim cd-footer" id="cockpit-notes"></p>
    <section class="cd-chart"><div class="row spread"><h2 class="cd-caption">Power over time</h2><span class="cd-caption">Last 10 minutes</span></div><canvas id="power-chart" role="img" aria-label="Measured power over the last ten minutes; numeric readings are shown above"></canvas></section>
    <div class="cd-actions" id="cockpit-actions"></div></div>`;
}

export function updateDashboard(model) {
  const ride = model.ride, engine = ride.engine; if (!engine || !$('#cd-big')) return;
  const s = engine.session, c = s.configuration, kind = kindName(s), workout = kind === 'workout', elapsed = ride.elapsed, active = engine.active, paused = engine.phase === 'paused', busy = ride.trainingTransition != null;
  const fresh = (reading, age = 2) => reading != null && elapsed - reading.time <= age;
  const power = fresh(engine.lastPower) ? Math.round(engine.lastPower.watts) : null, cadence = fresh(engine.lastCadence) ? Math.trunc(engine.lastCadence.rpm) : null;
  const trainerSample = s.samples.findLast(r => Number.isFinite(r.trainerPower)), trainer = fresh(trainerSample) ? Math.round(trainerSample.trainerPower) : null;
  const hr = s.samples.findLast(r => r.heartRate != null && elapsed - r.time <= 5)?.heartRate;
  const state = paused ? 'Paused' : engine.phase === 'waiting' ? 'Start pedaling' : 'Riding';
  $('.cockpit').classList.toggle('is-paused', paused);
  // header
  setText('#cockpit-clock', clock(workout ? engine.trainingElapsed : elapsed)); setText('#cockpit-subtitle', `${c.riderName} · ${state}`);
  // the big box
  const current = workout ? engine.currentStep : null;
  if (workout) {
    setText('#cd-step-left', current ? clock(Math.ceil(current.remaining)) : engine.phase === 'waiting' ? 'START PEDALING' : '—'); setText('#cd-step-name', current?.step.name ?? '');
    setText('#cd-step-corner', current ? `STEP ${current.index + 1}/${s.training.steps.length}` : '');
    setAttr('#cd-big', 'aria-label', current ? `Step time left ${clock(Math.ceil(current.remaining))}, ${current.step.name}, step ${current.index + 1} of ${s.training.steps.length}` : 'Step time left');
  }
  // target
  const box = targetBoxState({ resistanceLevel: engine.resistanceLevel, paused, target: engine.target, resumeTarget: engine.resumeTarget });
  setText('#cd-target-caption', box.caption); setText('#live-target', box.value ?? '—'); setText('#cd-target-unit', box.value == null ? '' : box.unit); setText('#cd-intensity-corner', workout ? `${engine.intensity} %` : '');
  setAttr('#cd-target-box', 'data-tone', paused ? 'amber' : 'lime');
  setDisabled('#intensity-minus', busy || engine.intensity <= 50); setDisabled('#intensity-plus', busy || engine.intensity >= 150);
  for (const id of ['res-minus', 'res-plus', 'erg-minus', 'erg-plus']) setDisabled(`#${id}`, busy);
  // actual, with the trainer's own watts while a meter is the source
  setText('#live-power', power == null ? '—' : String(power)); setText('#live-power-unit', power == null ? '' : 'W');
  if (c.powerSource === 'externalPowerMeter') { setText('#live-trainer', trainer == null ? '—' : String(trainer)); setAttr('#cd-trainer', 'aria-label', `Trainer power ${trainer == null ? 'not available' : `${trainer} watts`}`); }
  // profile with the heart-rate line, the next step and Skip
  if (workout) {
    const key = `${s.id}/${engine.intensity}`, host = $('#cockpit-profile');
    if (profileKey !== key) { profileKey = key; host.innerHTML = profileChart(s.training, { intensity: engine.intensity, progressSeconds: 0, height: 'normal', heartPath: '' }); }
    moveProfileMarker(host, s.training, engine.trainingElapsed);
    const total = s.training.steps.reduce((n, step) => n + step.seconds, 0), clockOf = WorkoutClock.of(s), path = clockOf ? heartLinePath(clockOf.heartRate(s), total) : '';
    setAttr('#profile-hr', 'd', path);
    const next = nextStepText({ current, steps: s.training.steps, intensity: engine.intensity, waiting: engine.phase === 'waiting' });
    setHTML('#cd-next', `${next.label ? `<span class="cd-dim">${esc(next.label)}</span>` : ''}${esc(next.text)}`);
    setDisabled('#skip-step', !engine.canSkipStep || busy);
  }
  // readings row
  setText('#live-heart', watts(hr)); setText('#live-cadence', cadence == null ? '—' : String(cadence));
  const sampleCount = s.samples.length, second = Math.floor(elapsed);
  if (!figuresCache || figuresCache.session !== s || figuresCache.second !== second || figuresCache.count !== sampleCount) {
    figuresCache = { session: s, second, count: sampleCount, track: rideTrack(s) }; figuresCache.items = rideFigures(s, figuresCache.track);
    for (const f of figuresCache.items) { setText(f.id === 'balance' ? '#live-balance' : `#fig-${f.id}-value`, f.value ?? '—'); setHidden(`#fig-${f.id}`, f.hidden === true); }
  }
  if (workout) setText('#live-intensity', String(engine.intensity)); else setText('#live-kj', figuresCache.track.seconds > 0 ? String(Math.round(figuresCache.track.kilojoules)) : '0');
  // banners and the footer line
  setHTML('#cockpit-banners', `${s.isDemo ? `<p>${pill(ride.mockPaused ? 'Debug · stream paused' : 'Debug · mock sensors', 'warning', '▶')}</p>` : ''}${ride.trainingTransition ? `<p class="warn">${ride.trainingTransition === 'pausing' ? 'Releasing the trainer…' : 'Resuming the trainer…'}</p>` : paused ? '<p class="warn">⏸ Trainer released. Progress is paused. Pedal before resuming.</p>' : ''}${ride.finishing ? '<p class="warn">⏳ Confirming trainer stop…</p>' : ''}${s.endReason ? `<p class="notice error" role="alert">${esc(s.endReason)}</p>` : ''}`);
  setText('#cockpit-notes', kind === 'resistance' ? 'Use your gears and cadence to choose the effort. Levels are trainer-specific, not watts.' : paused ? 'Pedal until fresh power and cadence arrive, then resume.' : coachingText(rideVisualState(rideVisualInput(engine, elapsed, { playbackSpeed: ride.demo ? ride.speed : 1 })), engine.phase));
  // actions: only when what they offer changes
  const sig = `${s.id}/${engine.phase}/${ride.finishing}/${ride.trainingTransition}/${active}`;
  if (sig !== actionsSignature) {
    actionsSignature = sig;
    $('#cockpit-actions').innerHTML = active ? `${button(paused ? '▶ Resume' : '⏸ Pause', { kind: 'primary', action: 'pause-resume', disabled: busy, extra: { 'data-testid': 'pause-resume' } })}${button('Stop &amp; save', { kind: 'secondary', action: 'stop', extra: { 'data-testid': 'stop-save' } })}<span class="cd-dim grow">${s.isDemo ? 'Synthetic recording · never uploads' : 'Keep this tab visible during the ride.'}</span>`
      : `<span class="cd-dim">${ride.finishing ? 'Saving the recording and confirming the trainer stop…' : 'Recording saved.'}</span>`;
  }
  drawChart($('#power-chart'), s.samples, { target: engine.target });
}

/** ↑/↓ change the target (intensity, ERG watts or resistance level) and ⌘/Ctrl+→ skips a step, like native. Space is handled by the shell. */
export function installDashboardKeys(model) {
  document.addEventListener('keydown', event => {
    const ride = model.ride, engine = ride.engine;
    if (event.defaultPrevented || event.altKey || event.shiftKey || currentRoute()?.name !== 'ride' || !ride.active || !engine?.session.training || ride.trainingTransition) return;
    if (event.target.closest?.('button, a, input, select, textarea, summary, [contenteditable], dialog[open]') && !event.target.closest?.('.cd-step-btn')) return;
    const kind = kindName(engine.session), up = event.key === 'ArrowUp', down = event.key === 'ArrowDown';
    if ((up || down) && !event.ctrlKey && !event.metaKey) {
      event.preventDefault(); const sign = up ? 1 : -1;
      if (kind === 'workout') ride.adjustIntensity(5 * sign); else if (kind === 'resistance') ride.adjustResistance(sign); else ride.adjustERG(10 * sign);
    } else if (event.key === 'ArrowRight' && (event.ctrlKey || event.metaKey) && kind === 'workout') { event.preventDefault(); ride.skipStep(); }
  });
}
