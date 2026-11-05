import { esc, $, button, metricTile, phaseTimelineView, applyTimeline, stepRing, holdButton, bindHold, profileChart, moveProfileMarker, pill, watts } from './components.mjs';
import { registerRoute, openSheet } from './shell.mjs';
import { PHASES, PRESETS } from '../domain.mjs';
import { CadenceGuard, DurationFormat, phaseTimeline, coachingLine } from '../rules/presentation.mjs';
import { activityTitle } from '../rules/progress.mjs';
import { drawChart } from '../scene.mjs';
// The cockpits: the FTP test, workouts, free ERG and resistance rides. Glanceable numbers, a step countdown, Pause/Resume and Stop & save
// (one tap), and a deliberate hold to finish the ramp. `render` builds the skeleton once; `update` sets text and swaps only the regions that changed.
let signature = null, lastHTML = new Map();

const kindOf = session => session.training == null ? 'ftp' : session.training.kind === 'workout' ? 'workout' : session.training.resistance != null ? 'resistance' : 'free';
const clock = DurationFormat.clock;
function setText(selector, text) { const el = $(selector); if (el && el.textContent !== text) el.textContent = text; }
function setHTML(selector, html) { const el = $(selector); if (el && lastHTML.get(selector) !== html) { el.innerHTML = html; lastHTML.set(selector, html); } }
const level = tenths => (tenths / 10).toFixed(1);

function header(model, engine) {
  const s = engine.session, ftp = kindOf(s) === 'ftp';
  return `<header class="cockpit-header"><a class="icon-btn" href="#/home" aria-label="Minimise ride" title="Keeps the ride running behind the live-ride bar">⌄</a><div class="grow"><p class="cockpit-title accent-text" id="cockpit-title"></p><p class="caption muted" id="cockpit-subtitle">${esc(s.configuration.riderName)} · ${esc(activityTitle(s))}</p></div><div class="clock"><p class="num" id="cockpit-clock">0:00</p><p class="caption muted" id="cockpit-clock-label">${ftp ? 'TOTAL TIME' : s.training?.kind === 'workout' ? 'WORKOUT TIME' : 'RIDE TIME'}</p></div>${s.isDemo ? button('⋯', { kind: 'secondary', small: true, action: 'debug-controls', extra: { 'aria-label': 'Debug controls' } }) : ''}</header>`;
}
registerRoute('ride', {
  tab: 'home', documentTitle: model => model.ride.engine ? PHASES[model.ride.engine.phase] ?? 'Ride' : 'Ride',
  render(model) {
    const engine = model.ride.engine; if (!engine) return '<p class="loading">No ride is running.</p>';
    signature = null; lastHTML = new Map(); const s = engine.session, kind = kindOf(s), c = s.configuration;
    const target = kind === 'resistance' ? 'RESISTANCE' : 'TARGET';
    return `<div class="cockpit stack" data-kind="${kind}">${header(model, engine)}${kind === 'ftp' ? `<div id="cockpit-timeline">${phaseTimelineView(phaseTimeline({ phase: 'waiting', warmup: c.warmupSeconds, cooldown: c.cooldownSeconds, elapsedInPhase: 0 }), 'waiting')}</div>` : ''}
      <div id="cockpit-banners" class="stack"></div>${kind === 'workout' ? `<div id="cockpit-profile">${profileChart(s.training, { intensity: engine.intensity, progressSeconds: 0, height: 'normal' })}</div><div id="cockpit-step" class="stack"></div>` : ''}
      <section class="tiles two hero-tiles">${metricTile({ title: target, value: null, unit: 'W', tone: 'accent', hero: true, id: 'live-target' })}${metricTile({ title: 'ACTUAL', value: null, unit: 'W', hero: true, id: 'live-power' })}</section>
      <div id="cockpit-progress"></div>
      <section class="tiles support-tiles">${metricTile({ title: 'HEART RATE', value: null, unit: 'bpm', tone: 'heart', id: 'live-heart' })}${metricTile({ title: 'CADENCE', value: null, unit: 'rpm', id: 'live-cadence' })}${kind === 'ftp' ? metricTile({ title: 'MAX 60 S', value: null, unit: 'W', id: 'live-best' }) : ''}</section>
      <div id="cockpit-controls"></div><p class="muted" id="cockpit-notes"></p>
      <section class="card chart-panel"><div class="row spread"><h2>Power over time</h2><span class="caption muted">Last 10 minutes</span></div><canvas id="power-chart" role="img" aria-label="Measured power over the last ten minutes; numeric readings are shown above"></canvas></section></div>
      <div class="action-bar cockpit-actions" id="cockpit-actions"></div>`;
  },
  bind(root) { applyTimeline(root); },
  update(model) {
    const ride = model.ride, engine = ride.engine; if (!engine || !$('#cockpit-title')) return;
    const s = engine.session, c = s.configuration, kind = kindOf(s), elapsed = ride.elapsed, active = engine.active, paused = engine.phase === 'paused';
    const phaseTime = Math.max(0, elapsed - engine.phaseStartedAt), preset = PRESETS[c.preset], stepNumber = Math.floor(phaseTime / preset.seconds) + 1;
    const freshPower = engine.lastPower && elapsed - engine.lastPower.time <= 2, cadence = engine.lastCadence && elapsed - engine.lastCadence.time <= 2 ? engine.lastCadence.rpm : null;
    const hr = s.samples.findLast(r => r.heartRate != null && elapsed - r.time <= 5)?.heartRate;
    // header
    setText('#cockpit-title', kind === 'ftp' ? ({ waiting: 'START PEDALING', warmup: 'WARM-UP', ramp: `RAMP · Step ${stepNumber}`, cooldown: engine.freewheel ? 'COOL-DOWN · free spin' : 'COOL-DOWN' }[engine.phase] ?? (PHASES[engine.phase] ?? '').toUpperCase()) : activityTitle(s));
    const ftpClock = { ramp: [phaseTime, 'RAMP TIME'], warmup: [Math.max(0, c.warmupSeconds - phaseTime), 'WARM-UP LEFT'], cooldown: [Math.max(0, c.cooldownSeconds - phaseTime), 'COOL-DOWN LEFT'] }[engine.phase] ?? [elapsed, 'TOTAL TIME'];
    if (kind === 'ftp') { setText('#cockpit-clock', clock(ftpClock[0])); setText('#cockpit-clock-label', ftpClock[1]); } else { setText('#cockpit-clock', clock(kind === 'workout' ? engine.trainingElapsed : elapsed)); setText('#cockpit-subtitle', `${c.riderName} · ${paused ? 'Paused' : engine.phase === 'waiting' ? 'Start pedaling' : 'Riding'}`); }
    // readings
    const resistance = engine.resistanceLevel;
    if (resistance != null) { setText('#live-target', level(resistance)); setText('#live-target-caption', paused ? 'Resume level · trainer released' : 'Trainer level · no ERG'); }
    else if (paused) { setText('#live-target', '—'); setText('#live-target-caption', engine.resumeTarget != null ? `Resumes at ${engine.resumeTarget} W` : 'Trainer released'); }
    else if (engine.freewheel) { setText('#live-target', 'EASY'); setText('#live-target-caption', 'Free spin · no ERG target'); }
    else { setText('#live-target', watts(engine.target)); setText('#live-target-caption', engine.target == null ? '' : ride.trainingTransition ? (ride.trainingTransition === 'pausing' ? 'Releasing trainer…' : 'Resuming trainer…') : c.powerMatchingEnabled ? `ERG target · matched command ${watts(ride.lastAcknowledged)} W` : 'ERG target'); }
    setText('#live-power', watts(freshPower ? engine.lastPower.watts : null)); setText('#live-power-caption', freshPower ? `${c.powerSource === 'trainer' ? 'Trainer' : 'External meter'} power` : active ? 'Waiting for a fresh reading' : 'Recording finished');
    setText('#live-heart', watts(hr)); setText('#live-cadence', watts(cadence));
    const guard = CadenceGuard.state(cadence, engine.phase, c.cadenceSource !== 'unavailable');
    $('#live-cadence')?.closest('.tile')?.classList.toggle('warning', guard === 'low'); setText('#live-cadence-caption', guard === 'low' ? CadenceGuard.message : '');
    if (kind === 'ftp') {
      const best = s.result?.bestMinutePower ?? engine.liveBest;
      if (engine.phase === 'waiting' || engine.phase === 'warmup') { setText('#live-best', engine.phase === 'warmup' ? clock(Math.max(0, c.warmupSeconds - phaseTime)) : 'Pedal'); setText('#live-best-caption', 'Ramp starts in'); const tile = $('#live-best')?.closest('.tile'); if (tile) tile.setAttribute('aria-label', 'Ramp starts in'); }
      else { setText('#live-best', watts(best)); setText('#live-best-caption', 'Best full minute so far'); }
      setHTML('#cockpit-timeline', phaseTimelineView(phaseTimeline({ phase: engine.phase, warmup: c.warmupSeconds, cooldown: c.cooldownSeconds, elapsedInPhase: phaseTime, rampElapsed: engine.phase === 'ramp' ? phaseTime : null }), engine.phase)); applyTimeline($('#cockpit-timeline'));
      const remaining = preset.seconds - phaseTime % preset.seconds;
      setHTML('#cockpit-progress', engine.phase === 'ramp' ? stepRing({ fraction: remaining / preset.seconds, remaining: Math.ceil(remaining), nextChange: `+${preset.step} W` })
        : engine.phase === 'cooldown' ? (s.result ? `<div class="card accent stack"><p class="label accent-text">Provisional result</p><h2>${Math.round(s.result.estimatedFTP)} W estimated FTP</h2><p class="footnote">${Math.round(s.result.factor * 100)} % of your best minute, ${Math.round(s.result.bestMinutePower)} W. The final result appears when you save.</p></div>` : '<p class="muted">ⓘ No FTP estimate from this ramp. You can still save the ride.</p>') : '');
    }
    if (kind === 'workout') {
      moveProfileMarker($('#cockpit-profile'), s.training, engine.trainingElapsed);
      const current = engine.currentStep, steps = s.training.steps, next = current && current.index + 1 < steps.length ? steps[current.index + 1] : null, scaled = w => Math.round(w * engine.intensity / 100);
      setHTML('#cockpit-step', current ? `<div class="row spread nowrap"><strong class="step-name">${esc(current.step.name)}</strong><span class="num big-clock" aria-label="Step time left">${clock(current.remaining)}</span></div><p class="footnote">Step ${current.index + 1} of ${steps.length}</p><p class="muted">${next ? `Next: ${esc(next.name)} · ${DurationFormat.compact(next.seconds)} · ${scaled(next.watts)} W` : 'Last step'}</p>` : engine.phase === 'waiting' ? '<p class="step-name">Start pedaling to begin.</p>' : '');
    }
    // banners
    setHTML('#cockpit-banners', `${s.isDemo ? `<p>${pill(ride.mockPaused ? 'Debug · stream paused' : 'Debug · mock sensors', 'warning', '▶')}</p>` : ''}${ride.trainingTransition ? `<p class="warn">${ride.trainingTransition === 'pausing' ? 'Releasing the trainer…' : 'Resuming the trainer…'}</p>` : paused ? '<p class="warn">⏸ Trainer released. Progress is paused. Pedal before resuming.</p>' : ''}${ride.finishing ? '<p class="warn">⏳ Confirming trainer stop…</p>' : ''}${s.endReason ? `<p class="notice error" role="alert">${esc(s.endReason)}</p>` : ''}${kind === 'ftp' && c.cadenceSource === 'unavailable' && engine.phase === 'ramp' ? '<p class="warn">⚠ No cadence source: hold to finish when you cannot continue.</p>' : ''}`);
    // adjustments and notes
    const busy = ride.trainingTransition != null;
    const adjuster = (title, value, minus, plus, minusOff = false, plusOff = false) => `<div class="adjuster"><button type="button" class="btn secondary" data-action="${minus[1]}" ${minusOff || busy ? 'disabled' : ''}>${minus[0]}</button><div class="adjust-value"><p class="caption muted">${title}</p><p class="num">${value}</p></div><button type="button" class="btn secondary" data-action="${plus[1]}" ${plusOff || busy ? 'disabled' : ''}>${plus[0]}</button></div>`;
    setHTML('#cockpit-controls', !active ? '' : kind === 'workout' ? adjuster('INTENSITY', `${engine.intensity} %`, ['−5 %', 'intensity-minus'], ['+5 %', 'intensity-plus'], engine.intensity <= 50, engine.intensity >= 150)
      : kind === 'resistance' ? adjuster('RESISTANCE', level(resistance ?? 0), ['− level', 'res-minus'], ['+ level', 'res-plus']) : kind === 'free' ? adjuster('ERG TARGET', `${engine.target ?? engine.resumeTarget ?? 0} W`, ['−10 W', 'erg-minus'], ['+10 W', 'erg-plus']) : '');
    setText('#cockpit-notes', kind === 'resistance' ? 'Use your gears and cadence to choose the effort. Levels are trainer-specific, not watts.' : paused ? 'Pedal until fresh power and cadence arrive, then resume.' : kind === 'ftp' && engine.phase === 'warmup' && c.powerMatchingEnabled && ride.matcher?.settledAt > elapsed ? 'Trainer warming up — power matching is settling.' : engine.phase === 'ramp' && kind === 'ftp' ? '' : coachingLine(kind === 'ftp', engine.phase));
    // actions: only when what they offer changes
    const sig = `${s.id}/${engine.phase}/${ride.finishing}/${ride.trainingTransition}/${active}`;
    if (sig !== signature) {
      signature = sig;
      $('#cockpit-actions').innerHTML = active ? `${kind === 'ftp' ? (engine.phase === 'ramp' ? holdButton('Hold to finish', 'finish') : '') : button(paused ? '▶ Resume' : '⏸ Pause', { kind: 'primary', action: 'pause-resume', disabled: busy, extra: { 'data-testid': 'pause-resume' } })}${button('Stop &amp; save', { kind: 'secondary', action: 'stop', extra: { 'data-testid': 'stop-save' } })}<span class="footnote grow">${s.isDemo ? 'Synthetic recording · never uploads' : 'Keep this tab visible during the ride.'}</span>`
        : `<span class="footnote">${ride.finishing ? 'Saving the recording and confirming the trainer stop…' : 'Recording saved.'}</span>`;
      bindHold($('#cockpit-actions'), { finish: () => ride.finishRamp() });
    }
    drawChart($('#power-chart'), s.samples, { target: engine.target });
  },
  actions: model => {
    const ride = model.ride;
    return {
      stop: () => ride.stop(), 'pause-resume': () => ride.engine.phase === 'paused' ? ride.resumeTraining() : ride.pauseTraining(),
      'intensity-minus': () => ride.adjustIntensity(-5), 'intensity-plus': () => ride.adjustIntensity(5),
      'res-minus': () => ride.adjustResistance(-1), 'res-plus': () => ride.adjustResistance(1), 'erg-minus': () => ride.adjustERG(-10), 'erg-plus': () => ride.adjustERG(10),
      'debug-controls': () => openDebugControls(model),
    };
  },
});

/** Mock-ride controls: playback speed, signal scenario, advance, skip the warm-up, simulate a trainer disconnect. Never sends trainer commands. */
function openDebugControls(model) {
  const ride = model.ride;
  openSheet({ title: 'Debug controls', live: true, actions: '<button type="button" class="btn primary" data-dialog="close">Done</button>',
    content: () => `<p>${pill('Mock sensors · never uploads', 'warning', '▶')}</p><div class="fields"><label class="field"><span>Playback speed</span><select id="dbg-speed">${[1, 4, 12, 60].map(n => `<option value="${n}" ${ride.speed === n ? 'selected' : ''}>${n}×</option>`).join('')}</select></label>
      <label class="field"><span>Signal scenario</span><select id="dbg-scenario">${[['exhaustion', 'Ride to exhaustion'], ['steady', 'Steady rider'], ['powerDropout', 'Power dropout'], ['cadenceDropout', 'Cadence dropout']].map(([v, t]) => `<option value="${v}" ${ride.scenario === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label></div>
      <div class="row">${button(ride.mockPaused ? 'Resume stream' : 'Pause stream', { kind: 'secondary', extra: { 'data-dialog': 'toggle' } })}${button('Advance 60 s', { kind: 'secondary', extra: { 'data-dialog': 'advance' } })}${ride.engine?.phase === 'warmup' ? button('Skip warm-up', { kind: 'secondary', extra: { 'data-dialog': 'skip' } }) : ''}${button('Simulate trainer disconnect', { kind: 'danger', extra: { 'data-dialog': 'disconnect' } })}</div>
      <p class="footnote">All sensor values are generated locally. No Bluetooth commands or activity uploads are sent.</p>`,
    onChange: event => { if (event.target.id === 'dbg-speed') ride.speed = Number(event.target.value); if (event.target.id === 'dbg-scenario') ride.scenario = event.target.value; },
    handler: (action, dialog) => {
      if (action === 'close') return dialog.close();
      if (action === 'toggle') ride.mockPaused = !ride.mockPaused;
      if (action === 'advance') ride.advanceMock(60);
      if (action === 'skip') { for (let i = 0; i < 4000 && ride.engine?.phase === 'warmup'; i++) ride.advanceMock(1); }
      if (action === 'disconnect') { ride.interrupt('The trainer disconnected (simulated).'); dialog.close(); }
      model.onChange();
    } });
}
