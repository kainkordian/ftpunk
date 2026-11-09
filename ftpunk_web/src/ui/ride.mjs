import { rideTrack, speedAt, liveBalance } from '../rules/virtual-ride.mjs';
import { esc, $, button, metricTile, phaseTimelineView, applyTimeline, stepRing, holdButton, bindHold, profileChart, moveProfileMarker, pill, watts, switchRow, selectField } from './components.mjs';
import { registerSettingsSlot } from './settings.mjs';
import { registerRoute, openSheet, rerender } from './shell.mjs';
import { PHASES, PRESETS } from '../domain.mjs';
import { CadenceGuard, DurationFormat, phaseTimeline } from '../rules/presentation.mjs';
import { activityTitle } from '../rules/progress.mjs';
import { drawChart } from '../scene.mjs';
import { matchingStatusText } from '../matching.mjs';
import { rideVisualState, rideVisualInput, resolvePlacement, PLACEMENT_KEY, BRAND_NAME } from '../chaindance/state.mjs';
import { cockpitLayout, coachingText, singleColumn } from '../chaindance/layout.mjs';
import { chaindanceHTML, placementMenuHTML, ChaindanceView } from '../chaindance/view.mjs';
// The cockpits: the FTP test, workouts, free ERG and resistance rides. Glanceable numbers, a step countdown, Pause/Resume and Stop & save
// (one tap), and a deliberate hold to finish the ramp. `render` builds the skeleton once; `update` sets text and swaps only the regions that changed.
let signature = null, lastHTML = new Map(), view = null, layoutObserver = null;

const placementOf = model => resolvePlacement(model.prefs[PLACEMENT_KEY]);
const layoutKindOf = kind => kind === 'ftp' ? 'ftpTest' : kind === 'workout' ? 'workout' : 'freeRide';
const kindOf = session => session.training == null ? 'ftp' : session.training.kind === 'workout' ? 'workout' : session.training.resistance != null ? 'resistance' : 'free';
const clock = DurationFormat.clock;
function setText(selector, text) { const el = $(selector); if (el && el.textContent !== text) el.textContent = text; }
function setHTML(selector, html) { const el = $(selector); if (el && lastHTML.get(selector) !== html) { el.innerHTML = html; lastHTML.set(selector, html); } }
const level = tenths => (tenths / 10).toFixed(1);
let trackCache = null;
const extraTiles = rows => `<section id="tiles-more" class="tiles support-tiles ${rows ? 'rows' : ''}" hidden>${metricTile({ title: 'SPEED', value: null, unit: 'km/h', caption: 'Simulated', id: 'live-speed' })}${metricTile({ title: 'DISTANCE', value: null, unit: 'km', caption: 'Simulated', id: 'live-distance' })}${metricTile({ title: 'CALORIES', value: null, unit: 'kcal', caption: 'Estimated', id: 'live-kcal' })}${metricTile({ title: 'AVG POWER', value: null, unit: 'W', id: 'live-average' })}${metricTile({ title: 'BALANCE', value: null, unit: 'L/R', id: 'live-balance' })}</section>`;

function header(model, engine) {
  const s = engine.session, ftp = kindOf(s) === 'ftp';
  return `<header class="cockpit-header${model.prefs.extraLarge ? ' compact' : ''}"><a class="icon-btn" href="#/home" aria-label="Minimise ride" title="Keeps the ride running behind the live-ride bar"><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></a><div class="grow"><p class="cockpit-title accent-text" id="cockpit-title"></p><p class="caption muted" id="cockpit-subtitle">${esc(s.configuration.riderName)} · ${esc(activityTitle(s))}</p></div><div class="clock"><p class="num" id="cockpit-clock">0:00</p><p class="caption muted" id="cockpit-clock-label">${ftp ? 'TOTAL TIME' : s.training?.kind === 'workout' ? 'WORKOUT TIME' : 'RIDE TIME'}</p></div>${placementMenuHTML(placementOf(model))}${s.isDemo ? button('⋯', { kind: 'secondary', small: true, action: 'debug-controls', extra: { 'aria-label': 'Debug controls' } }) : ''}</header>`;
}
registerRoute('ride', {
  tab: 'home', documentTitle: model => model.ride.engine ? PHASES[model.ride.engine.phase] ?? 'Ride' : 'Ride',
  render(model) {
    const engine = model.ride.engine; if (!engine) return '<p class="loading">No ride is running.</p>';
    signature = null; lastHTML = new Map(); const s = engine.session, kind = kindOf(s), c = s.configuration;
    const target = kind === 'resistance' ? 'RESISTANCE' : 'TARGET';
    const layout = cockpitLayout({ phase: engine.phase, accessibilitySize: model.prefs.extraLarge, rideVisual: placementOf(model), kind: layoutKindOf(kind) });
    const blocks = {
      heroTiles: `<section class="tiles two hero-tiles">${metricTile({ title: target, value: null, unit: 'W', tone: 'accent', hero: true, id: 'live-target' })}${metricTile({ title: 'ACTUAL', value: null, unit: 'W', hero: true, id: 'live-power' })}</section>`,
      scene: chaindanceHTML({ hero: true }), strip: chaindanceHTML(),
      progress: kind === 'workout' ? `<div id="cockpit-profile">${profileChart(s.training, { intensity: engine.intensity, progressSeconds: 0, height: 'normal' })}</div><div id="cockpit-step" class="stack"></div>` : kind === 'ftp' ? '<div id="cockpit-progress"></div>' : '',
      tiles: `<div class="dash-bar"><span class="num" id="live-kj">— kJ</span><button type="button" class="dash-toggle" id="dash-toggle" data-action="dash-toggle" data-testid="dashboard-toggle">More readings</button></div><section id="tiles-main" class="tiles support-tiles ${layout.metricRows ? 'rows' : ''}">${metricTile({ title: 'HEART RATE', value: null, unit: 'bpm', tone: 'heart', id: 'live-heart' })}${metricTile({ title: 'CADENCE', value: null, unit: 'rpm', id: 'live-cadence' })}${kind === 'ftp' ? metricTile({ title: 'MAX 60 S', value: null, unit: 'W', id: 'live-best' }) : ''}</section>${extraTiles(layout.metricRows)}<p class="footnote muted" id="cockpit-matching"></p>`,
      controls: '<div id="cockpit-controls"></div>', notes: '<p class="muted" id="cockpit-notes"></p>',
    };
    const block = name => `<div class="blk" id="blk-${name}" data-block="${name}">${blocks[name] ?? ''}</div>`;
    return `<div class="cockpit stack" data-kind="${kind}" data-visual="${layout.visual}">${header(model, engine)}${kind === 'ftp' ? `<div id="cockpit-timeline">${phaseTimelineView(phaseTimeline({ phase: 'waiting', warmup: c.warmupSeconds, cooldown: c.cooldownSeconds, elapsedInPhase: 0 }), 'waiting', { showLabels: layout.showsTimelineLabels })}</div>` : ''}
      <div id="cockpit-banners" class="stack"></div>
      <div class="cockpit-cols" id="cockpit-cols"><div class="col" id="col-main">${singleColumn({ kind: layoutKindOf(kind), visual: layout.visual }).map(block).join('')}</div><div class="col" id="col-side"></div></div>
      <section class="card chart-panel"><div class="row spread"><h2>Power over time</h2><span class="caption muted">Last 10 minutes</span></div><canvas id="power-chart" role="img" aria-label="Measured power over the last ten minutes; numeric readings are shown above"></canvas></section></div>
      <div class="action-bar cockpit-actions" id="cockpit-actions"></div>`;
  },
  bind(root, model) {
    applyTimeline(root);
    view?.stop(); layoutObserver?.disconnect(); view = null; layoutObserver = null;
    const engine = model.ride.engine; if (!engine) return;
    const cockpit = $('.cockpit', root), host = $('#chaindance', root), visual = cockpit.dataset.visual, kind = layoutKindOf(kindOf(engine.session));
    if (host) view = new ChaindanceView(host, () => ({ engine: model.ride.engine, elapsed: model.ride.elapsed, playbackSpeed: model.ride.demo ? model.ride.speed : 1, mockPaused: model.ride.demo && model.ride.mockPaused }), { hero: visual === 'hero' });
    // Wide windows put the Large scene beside the readings: the blocks move between two columns (CockpitLayout); the elements themselves are kept.
    const arrange = () => {
      const layout = cockpitLayout({ phase: model.ride.engine?.phase, accessibilitySize: model.prefs.extraLarge, rideVisual: visual, containerWidth: cockpit.clientWidth, kind }), cols = $('#cockpit-cols', root), key = String(layout.sideBySide);
      if (!cols || cols.dataset.side === key) return; cols.dataset.side = key; cols.classList.toggle('side-by-side', layout.sideBySide);
      const place = (names, column) => { for (const name of names) { const el = $(`#blk-${name}`, root); if (el) column.append(el); } };
      place(layout.sideBySide ? layout.leftColumn : singleColumn({ kind, visual }), $('#col-main', root)); place(layout.sideBySide ? layout.rightColumn : [], $('#col-side', root));
    };
    if (visual === 'hero' && typeof ResizeObserver === 'function') { layoutObserver = new ResizeObserver(arrange); layoutObserver.observe(cockpit); }
    arrange();
  },
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
    const setTarget = text => { setText('#live-target', text); setText('#readout-target', text); }, setActual = text => { setText('#live-power', text); setText('#readout-actual', text); };
    const resistance = engine.resistanceLevel;
    if (resistance != null) { setTarget( level(resistance)); setText('#live-target-caption', paused ? 'Resume level · trainer released' : 'Trainer level · no ERG'); }
    else if (paused) { setTarget( '—'); setText('#live-target-caption', engine.resumeTarget != null ? `Resumes at ${engine.resumeTarget} W` : 'Trainer released'); }
    else if (engine.freewheel) { setTarget( 'EASY'); setText('#live-target-caption', 'Free spin · no ERG target'); }
    else { setTarget( watts(engine.target)); setText('#live-target-caption', engine.target == null ? '' : ride.trainingTransition ? (ride.trainingTransition === 'pausing' ? 'Releasing trainer…' : 'Resuming trainer…') : c.powerMatchingEnabled ? `ERG target · matched command ${watts(ride.lastAcknowledged)} W` : 'ERG target'); }
    setActual( watts(freshPower ? engine.lastPower.watts : null)); setText('#live-power-caption', freshPower ? `${c.powerSource === 'trainer' ? 'Trainer' : 'External meter'} power` : active ? 'Waiting for a fresh reading' : 'Recording finished');
    if ($('#chaindance-readout')) {
      const untilStep = preset.seconds - phaseTime % preset.seconds, current = kind === 'workout' ? engine.currentStep : null;
      const detail = kind === 'ftp' ? ({ ramp: `STEP ${stepNumber} · ${clock(untilStep)}`, warmup: `WARM-UP · ${clock(Math.max(0, c.warmupSeconds - phaseTime))}`, cooldown: `COOL-DOWN · ${clock(Math.max(0, c.cooldownSeconds - phaseTime))}` }[engine.phase] ?? '')
        : current ? `STEP ${current.index + 1}/${s.training.steps.length} · ${clock(current.remaining)}` : '';
      setText('#readout-target-title', resistance != null ? (paused ? 'RESUME LEVEL' : 'RESISTANCE') : paused ? 'PAUSED' : kind === 'ftp' && engine.phase === 'cooldown' && !engine.freewheel ? 'COOL-DOWN' : 'TARGET');
      if (paused && resistance == null) setText('#readout-target', watts(engine.resumeTarget));
      setText('#readout-unit', resistance != null || engine.freewheel ? '' : 'W'); setText('#readout-detail', detail);
      $('#chaindance-readout').setAttribute('aria-label', `${$('#readout-target-title').textContent} ${$('#readout-target').textContent}. Actual ${$('#readout-actual').textContent}${detail ? `. ${detail}` : ''}`);
    }
    setText('#live-heart', watts(hr)); setText('#live-cadence', watts(cadence));
    const guard = CadenceGuard.state(cadence, engine.phase, c.cadenceSource !== 'unavailable');
    $('#live-cadence')?.closest('.tile')?.classList.toggle('warning', guard === 'low'); setText('#live-cadence-caption', guard === 'low' ? CadenceGuard.message : '');
    if (trackCache?.session !== s || trackCache.length !== s.samples.length) trackCache = { session: s, length: s.samples.length, track: rideTrack(s) };
    const track = trackCache.track, ridden = track.seconds > 0, speed = speedAt(track, s.samples.at(-1)?.time ?? 0), left = liveBalance(s.samples), more = model.prefs.dashboardMore === true && guard !== 'low';
    const kmh = (speed * 3.6).toFixed(1), leftPart = left == null ? null : Math.round(left);
    setText('#live-kj', ridden ? `${Math.round(track.kilojoules)} kJ` : '— kJ'); setText('#dash-toggle', model.prefs.dashboardMore === true ? 'Main readings' : 'More readings');
    if ($('#tiles-main')) { $('#tiles-main').hidden = more; $('#tiles-more').hidden = !more; }
    setText('#live-speed', ridden ? kmh : '—'); setText('#live-distance', ridden ? (track.distance / 1000).toFixed(2) : '—'); setText('#live-kcal', ridden ? String(Math.round(track.kilocalories)) : '—');
    setText('#live-average', watts(track.averagePower == null ? null : Math.round(track.averagePower))); setText('#live-balance', leftPart == null ? '—' : `${leftPart} / ${100 - leftPart}`);
    const balanceTile = $('#live-balance')?.closest('.tile'); if (balanceTile) balanceTile.hidden = leftPart == null;
    const chip = $('#readout-speed'); if (chip) { chip.hidden = !ridden; setText('#readout-speed', `${kmh} km/h`); }
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
    const status = ride.matchingStatus, visual = rideVisualState(rideVisualInput(engine, elapsed, { playbackSpeed: ride.demo ? ride.speed : 1 }));
    const showsCoaching = kind !== 'ftp' || cockpitLayout({ phase: engine.phase, accessibilitySize: model.prefs.extraLarge, rideVisual: $('.cockpit').dataset.visual, kind: 'ftpTest' }).showsCoachingLine;
    setText('#cockpit-matching', c.powerMatchingEnabled && active ? `Power matching: ${matchingStatusText(status) || 'waiting for readings'}` : '');
    setText('#cockpit-notes', kind === 'resistance' ? 'Use your gears and cadence to choose the effort. Levels are trainer-specific, not watts.' : paused ? 'Pedal until fresh power and cadence arrive, then resume.' : !showsCoaching ? ''
      : kind === 'ftp' && engine.phase === 'warmup' && c.powerMatchingEnabled && status.kind === 'warming' ? 'Trainer warming up — power matching is settling.' : engine.phase === 'ramp' && kind === 'ftp' ? '' : coachingText(visual, engine.phase));
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
  events: model => ({ change: { 'chaindance-placement': el => { model.prefs[PLACEMENT_KEY] = resolvePlacement(el.value); model.savePrefs(); rerender(); } } }),
  actions: model => {
    const ride = model.ride;
    return {
      stop: () => ride.stop(), 'pause-resume': () => ride.engine.phase === 'paused' ? ride.resumeTraining() : ride.pauseTraining(),
      'intensity-minus': () => ride.adjustIntensity(-5), 'intensity-plus': () => ride.adjustIntensity(5),
      'res-minus': () => ride.adjustResistance(-1), 'res-plus': () => ride.adjustResistance(1), 'erg-minus': () => ride.adjustERG(-10), 'erg-plus': () => ride.adjustERG(10),
      'debug-controls': () => openDebugControls(model),
      'dash-toggle': () => { model.prefs.dashboardMore = model.prefs.dashboardMore !== true; model.savePrefs(); },
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

// Settings → Ride display: the Chaindance switch and layout (the same preference as the cockpit's menu). The settings screen renders the slot; its change events are handled here.
let settingsModel = null;
registerSettingsSlot('rideDisplay', model => {
  settingsModel = model; const placement = placementOf(model);
  return `${switchRow(`Show ${BRAND_NAME} during rides`, 'st-chaindance', placement !== 'off', { hint: 'A neon night-city ride that follows your power. It never controls the trainer.' })}${placement === 'off' ? '' : selectField(`${BRAND_NAME} layout`, 'st-chaindance-layout', [['strip', 'Strip between the readings'], ['hero', 'Large scene with readings on top']], placement)}`;
});
document.addEventListener('change', event => {
  const el = event.target, model = settingsModel; if (!model || !(el?.id === 'st-chaindance' || el?.id === 'st-chaindance-layout')) return;
  const current = placementOf(model);
  model.prefs[PLACEMENT_KEY] = el.id === 'st-chaindance' ? (el.checked ? (current === 'off' ? 'strip' : current) : 'off') : resolvePlacement(el.value);
  model.savePrefs(); rerender();
});
