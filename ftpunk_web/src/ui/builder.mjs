import { esc, button, field, selectField, segmented, screenHeader, profileChart, $, $$ } from './components.mjs';
import { registerRoute, navigate, rerender, notify, confirmSheet } from './shell.mjs';
import { CATEGORIES } from '../catalog.mjs';
import { mainSetText, zoneFor } from '../rules/preview.mjs';
import { DurationFormat } from '../rules/presentation.mjs';
import { LIMITS, isPercent, percent, watts, step as makeStep, stepBlock, repeatBlock, nameIsPlain, tryPlan, needsFTP, totalSeconds, estimatedLoad, parseDuration, durationText, issues } from '../custom-workouts.mjs';
// The workout builder (native App/Features/Builder/BuilderView.swift): name, category, a Blocks / Text toggle whose header stays put, the block editor
// (add step, add repeats, reorder, duplicate, delete; duration, start and end target, unit % FTP or W), the text editor with its error lines, a live profile
// chart with the total duration, and Save / Cancel with a discard confirmation. Everything is plain controls, so it works with the keyboard alone, and the
// layout stacks at phone width. The state lives in `model.builder` (src/my-workouts.mjs); pure rules are in src/builder-state.mjs.
//
// Typing never re-renders the screen (that would drop focus): fields update the state, then only the chart, the summary, the problem list and the Save
// button are repainted. Structural changes (add, delete, move, unit, ramp, mode) re-render and put the focus back on the control that was used.

let activeModel = null, guardInstalled = false;
const state = model => model.builder?.state;
const riderFTP = model => model.ftp;

function ensureBuilder(model, params) {
  if (params[0] === 'new' && model.builder?.key !== 'new') { model.newWorkout(); model.builder.key = 'new'; }
  else if (params[0] === 'edit' && model.builder?.key !== `edit/${params[1]}`) { if (model.editWorkout(params[1])) model.builder.key = `edit/${params[1]}`; }
  return model.builder;
}

// ----- pieces ----------------------------------------------------------------------------------------------------------------------
function equivalent(target, ftp) {
  const per = isPercent(target.start);
  const text = t => per ? (ftp ? `${Math.round(t.value * ftp)} W` : `${Math.round(t.value * 100)} % FTP`) : (ftp ? `${Math.round(t.value / ftp * 100)} % FTP` : `${Math.round(t.value)} W`);
  const range = target.end ? `${text(target.start)} → ${text(target.end)}` : text(target.start);
  return ftp == null && per ? `Needs an FTP for watts. Now ${range}.` : `≈ ${range}` + (ftp ? ` at ${Math.round(ftp)} W FTP` : '');
}
const shown = target => isPercent(target) ? Math.round(target.value * 100) : Math.round(target.value);
const zoneClass = (s, ftp) => { const fraction = isPercent(s.start) ? s.start.value : ftp ? s.start.value / ftp : null; return fraction == null ? 'zone-none' : `zone-${zoneFor(fraction)}`; };
const at = (b, s) => (s == null ? '' : `data-s="${s}" `) + `data-b="${b}"`;

function targetField(label, key, s, b, i, ftp) {
  const target = key === 'end' ? s.end : s.start, per = isPercent(s.start), [low, high] = per ? [30, 250] : LIMITS.watts;
  return `<label class="field target"><span>${esc(label)} <span class="unit">${per ? '% FTP' : 'W'}</span></span><input type="number" inputmode="numeric" step="1" min="${low}" max="${high}" value="${shown(target)}" data-f="${key}" ${at(b, i)} data-key="${b}-${i ?? ''}-${key}"></label>`;
}
function stepEditor(s, b, i, ftp) {
  const per = isPercent(s.start), ramp = s.end != null, key = `${b}-${i ?? ''}`, name = s.name, plain = nameIsPlain(name);
  const unit = (id, text) => `<button type="button" data-action="set-unit" data-unit="${id}" ${at(b, i)} aria-pressed="${id === 'percentFTP' ? per : !per}" data-key="${key}-unit-${id}">${text}</button>`;
  return `<div class="step" data-step ${at(b, i)}>
    <div class="step-top"><span class="swatch ${zoneClass(s, ftp)}" aria-hidden="true"></span>
      <label class="field grow"><span>Step name (optional)</span><input value="${esc(name)}" autocomplete="off" data-f="name" ${at(b, i)} data-key="${key}-name" aria-describedby="name-hint-${key}"></label></div>
    <p class="warn small" id="name-hint-${key}" role="alert" ${plain ? 'hidden' : ''}>The name cannot contain line breaks, '@', or words such as 10m, 80%, 200w, ramp or 5x.</p>
    <div class="step-row"><label class="field duration"><span>Duration <span class="unit">m:ss</span></span><input value="${durationText(s.seconds)}" inputmode="text" autocomplete="off" size="8" data-f="duration" ${at(b, i)} data-key="${key}-duration" aria-describedby="duration-hint-${key}"></label>
      <div class="segmented" role="group" aria-label="Target unit">${unit('percentFTP', '% FTP')}${unit('watts', 'W')}</div></div>
    <p class="warn small" id="duration-hint-${key}" role="alert" hidden>Use m:ss, like 3:30 (5 seconds to 4 hours).</p>
    <div class="step-row">${targetField(ramp ? 'From' : 'Target', 'start', s, b, i, ftp)}<label class="check"><input type="checkbox" data-f="ramp" ${at(b, i)} ${ramp ? 'checked' : ''} data-key="${key}-ramp"><span>Ramp</span></label>${ramp ? targetField('To', 'end', s, b, i, ftp) : ''}</div>
    <p class="footnote" data-equivalent>${esc(equivalent(s, ftp))}</p></div>`;
}
function blockEditor(block, b, count, ftp) {
  const tools = [button('Duplicate', { kind: 'link', small: true, action: 'block-duplicate', extra: { 'data-b': b, 'aria-label': `Duplicate block ${b + 1}`, 'data-key': `${b}-dup` } }),
    button('Delete', { kind: 'link', small: true, action: 'block-delete', extra: { 'data-b': b, 'aria-label': `Delete block ${b + 1}`, 'data-key': `${b}-del` } }),
    b > 0 ? button('Move up', { kind: 'link', small: true, action: 'block-up', extra: { 'data-b': b, 'aria-label': `Move block ${b + 1} up`, 'data-key': `${b}-up` } }) : '',
    b < count - 1 ? button('Move down', { kind: 'link', small: true, action: 'block-down', extra: { 'data-b': b, 'aria-label': `Move block ${b + 1} down`, 'data-key': `${b}-down` } }) : ''].join('');
  if (block.kind === 'step') return `<fieldset class="block card" data-block="${b}"><legend class="sr-only">Block ${b + 1}: step</legend>${stepEditor(block.step, b, null, ftp)}<div class="row block-tools">${tools}</div></fieldset>`;
  const steps = block.steps.map((s, i) => `<div class="repeat-step">${stepEditor(s, b, i, ftp)}<div class="row block-tools">${button('Duplicate step', { kind: 'link', small: true, action: 'step-duplicate', extra: { 'data-b': b, 'data-s': i, 'data-key': `${b}-${i}-dup` } })}${button('Delete step', { kind: 'link', small: true, action: 'step-delete', disabled: block.steps.length <= 1, extra: { 'data-b': b, 'data-s': i, 'data-key': `${b}-${i}-del` } })}</div></div>`).join('');
  return `<fieldset class="block card repeat" data-block="${b}"><legend class="sr-only">Block ${b + 1}: repeat</legend>
    <label class="field repeat-count"><span>Repeat ×</span><input type="number" inputmode="numeric" min="1" max="100" step="1" value="${block.count}" data-f="count" data-b="${b}" data-key="${b}--count"></label>${steps}
    ${button('Add step to repeat', { kind: 'link', small: true, action: 'repeat-add-step', extra: { 'data-b': b, 'data-key': `${b}-add` } })}<div class="row block-tools">${tools}</div></fieldset>`;
}
const blocksEditor = (st, ftp) => `<div id="builder-editor" class="stack" data-mode="blocks"><h2 class="sr-only">Steps</h2>${st.blocks.map((block, b) => blockEditor(block, b, st.blocks.length, ftp)).join('') || '<p class="muted">No steps yet.</p>'}
  <div class="row add-row" role="group" aria-label="Add to the workout">${button('+ Step', { kind: 'secondary', action: 'add-step', extra: { 'data-key': 'add-step' } })}${button('+ Repeat block', { kind: 'secondary', action: 'add-repeat', extra: { 'data-key': 'add-repeat' } })}
    ${button('Warm-up 10 min @ 50 %', { kind: 'tertiary', small: true, action: 'add-preset', extra: { 'data-preset': 'warmup' } })}${button('Cool-down 5 min @ 50 %', { kind: 'tertiary', small: true, action: 'add-preset', extra: { 'data-preset': 'cooldown' } })}${button('Recovery 2 min @ 50 %', { kind: 'tertiary', small: true, action: 'add-preset', extra: { 'data-preset': 'recovery' } })}</div></div>`;
const textEditor = st => `<div id="builder-editor" class="stack" data-mode="text"><label class="field"><span>Workout text</span><textarea id="builder-text" class="mono" rows="14" spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" aria-describedby="builder-status" ${st.parsed.isValid ? '' : 'aria-invalid="true"'}>${esc(st.text)}</textarea></label></div>`;

function previewHTML(model) {
  const st = state(model), ftp = riderFTP(model), draft = { ...st.workout(), name: 'Workout' }, shownBlocks = draft.blocks;
  const plan = shownBlocks.length ? tryPlan(draft, ftp ?? 100) : null;
  if (!plan) return `<div class="profile-empty muted">${shownBlocks.length ? 'Fix the problems below to see the profile' : 'Add a step to see the profile'}</div>`;
  const chartPlan = ftp ? plan : { ...plan, ftpWatts: null }, showValues = ftp != null || !needsFTP(draft), main = mainSetText(plan, 100, showValues), load = estimatedLoad(draft, ftp);
  return `<div class="${st.chartIsStale ? 'stale' : ''}" ${st.chartIsStale ? 'aria-label="Workout profile, from the last text that was valid"' : ''}>${profileChart(chartPlan, { height: 'large' })}</div>
    ${st.chartIsStale ? '<p class="warn small">⚠ Showing the last valid text</p>' : ''}
    <p class="summary"><strong class="num">${esc(DurationFormat.workout(totalSeconds(draft)))}</strong></p>${main ? `<p class="num">Main set: ${esc(main)}</p>` : ''}
    <p class="muted num">${load ? `IF ${load.intensityFactor.toFixed(2)} · TSS ${Math.round(load.tss)} (estimated)` : ftp == null ? 'Set an FTP to see IF and TSS.' : ''}</p>`;
}
function statusHTML(model) {
  const st = state(model);
  if (st.mode === 'blocks') { const reasons = st.saveBlockers; return reasons.length ? `<ul class="blockers">${reasons.map(r => `<li>${esc(r)}</li>`).join('')}</ul>` : ''; }
  const lines = st.parsed.isValid ? '<p class="ok">✓ Text is valid</p>' : `<ul class="blockers">${st.parsed.errors.map(e => `<li>Line ${e.line}: ${esc(e.message)}</li>`).join('')}</ul>`;
  const issue = st.parsed.isValid ? issues(st.workout())[0] : null;
  return `${lines}<p class="footnote">Steps start with “-”: duration (10m, 30s, 1m30), then 80 % or 200w or ramp 60-80%. A line ending in 5x repeats the steps under it. Text before the duration names the step.</p>${issue ? `<p class="warn small">${esc(issue)}</p>` : ''}`;
}

// ----- screen ----------------------------------------------------------------------------------------------------------------------
function render(model, params) {
  const builder = ensureBuilder(model, params);
  if (!builder) return `${screenHeader('Workout', { back: '#/home' })}<section class="card empty"><h2>Nothing to edit</h2><p class="muted">Start from My workouts on Home.</p><a class="btn primary" href="#/home">Back to Home</a></section>`;
  const st = builder.state, ftp = riderFTP(model);
  return `${screenHeader(builder.isNew ? 'New workout' : 'Edit workout', { right: `${button('Cancel', { kind: 'secondary', action: 'builder-cancel' })}${button('Save', { kind: 'primary', action: 'builder-save', disabled: !st.canSave, extra: { id: 'builder-save' } })}` })}
    <div class="builder-layout"><div class="builder-preview-col"><div id="builder-preview" class="stack" aria-label="Workout profile">${previewHTML(model)}</div></div>
    <div class="builder-editor-col stack"><div class="builder-head stack">${field('Workout name', 'builder-name', st.name, { autocomplete: 'off', 'aria-describedby': 'builder-status' })}
      ${selectField('Category', 'builder-category', [['', 'No category'], ...CATEGORIES.map(c => [c.id, c.title])], st.category ?? '')}
      <div><p class="label">Editor</p>${segmented([['blocks', 'Blocks'], ['text', 'Text']], st.mode, 'mode')}</div>
      <p class="warn" id="builder-notice" role="alert" ${st.notice ? '' : 'hidden'}>${esc(st.notice ?? '')}</p></div>
      ${st.mode === 'blocks' ? blocksEditor(st, ftp) : textEditor(st)}
      <div id="builder-status" role="status" aria-live="polite">${statusHTML(model)}</div></div></div>`;
}
/** Repaints what depends on the state without touching the editor (so typing keeps its focus). */
function paint(model) {
  const st = state(model); if (!st) return;
  const preview = $('#builder-preview'); if (preview) preview.innerHTML = previewHTML(model);
  const status = $('#builder-status'); if (status) status.innerHTML = statusHTML(model);
  const save = $('#builder-save'); if (save) save.disabled = !st.canSave;
  const notice = $('#builder-notice'); if (notice) { notice.hidden = !st.notice; notice.textContent = st.notice ?? ''; }
  const text = $('#builder-text'); if (text) text.toggleAttribute('aria-invalid', !st.parsed.isValid);
}
function redraw(focusKey = null) {
  rerender();
  if (focusKey) $(`[data-key="${CSS.escape(focusKey)}"]`)?.focus();
}
const stepOf = (st, el) => { const b = Number(el.dataset.b), block = st.blocks[b]; return block?.kind === 'step' ? block.step : block?.steps[Number(el.dataset.s)]; };
function commit(model, change) { const st = state(model); change(st.blocks); st.setBlocks(st.blocks); }
const defaults = { warmup: () => makeStep('Warm-up', 600, percent(0.5)), cooldown: () => makeStep('Cool-down', 300, percent(0.5)), recovery: () => makeStep('Recovery', 120, percent(0.5)) };

/** Typing in a step field: update the state and the few things that show it. */
function onField(model, event) {
  const el = event.target, f = el.dataset.f; if (!f || event.target.closest('#builder-editor') == null) return;
  const st = state(model), ftp = riderFTP(model), type = event.type;
  if (f === 'count') { const n = Number(el.value); if (type === 'input' && Number.isInteger(n) && n >= 1 && n <= 100) { commit(model, blocks => { blocks[Number(el.dataset.b)].count = n; }); paint(model); } if (type === 'change') { const block = st.blocks[Number(el.dataset.b)]; el.value = block.count; } return; }
  const s = stepOf(st, el); if (!s) return;
  const container = el.closest('[data-step]'), key = el.dataset.key.replace(/-[a-z]+$/, '');
  const refresh = () => { paint(model); if (container) { $('[data-equivalent]', container).textContent = equivalent(s, ftp); $('.swatch', container).className = `swatch ${zoneClass(s, ftp)}`; } };
  if (f === 'name') { if (type !== 'input') return; commit(model, () => { s.name = el.value; }); const hint = $(`#name-hint-${key}`); if (hint) hint.hidden = nameIsPlain(el.value); paint(model); return; }
  if (f === 'duration') {
    const seconds = parseDuration(el.value), ok = seconds != null && seconds >= LIMITS.stepSeconds[0] && seconds <= LIMITS.stepSeconds[1], hint = $(`#duration-hint-${key}`);
    if (type === 'input' && ok) { commit(model, () => { s.seconds = seconds; }); el.removeAttribute('aria-invalid'); if (hint) hint.hidden = true; refresh(); }
    if (type === 'change') { if (ok) { commit(model, () => { s.seconds = seconds; }); el.value = durationText(s.seconds); el.removeAttribute('aria-invalid'); if (hint) hint.hidden = true; refresh(); } else { el.setAttribute('aria-invalid', 'true'); if (hint) hint.hidden = false; } }
    return;
  }
  if (f === 'start' || f === 'end') {
    const target = f === 'end' ? s.end : s.start, number = Number(String(el.value).replace(',', '.'));
    if (type === 'input' && el.value.trim() !== '' && Number.isFinite(number)) { commit(model, () => { target.value = isPercent(s.start) ? number / 100 : number; }); refresh(); }
    if (type === 'change') { el.value = shown(target); }
    return;
  }
  if (f === 'ramp' && type === 'change') { commit(model, () => { if (el.checked) s.end = { ...s.start }; else delete s.end; }); redraw(el.dataset.key); }
}
const unitConvert = (s, toPercent, ftp) => {
  const convert = t => toPercent ? percent(ftp ? Math.min(2.5, Math.max(0.3, t.value / ftp)) : 0.75) : watts(ftp ? Math.min(1500, Math.max(20, Math.round(t.value * ftp))) : 150);
  s.start = convert(s.start); if (s.end) s.end = convert(s.end);
};

registerRoute('builder', {
  tab: 'home', documentTitle: model => model.builder?.isNew ? 'New workout' : 'Edit workout',
  render,
  bind(root, model) {
    activeModel = model;
    if (!guardInstalled) { guardInstalled = true; window.addEventListener('beforeunload', event => { if (location.hash.startsWith('#/builder') && activeModel?.builder?.state.hasUnsavedChanges) { event.preventDefault(); event.returnValue = ''; } }); }
    const editor = $('#builder-editor', root); if (!editor) return;
    for (const type of ['input', 'change']) editor.addEventListener(type, event => onField(model, event));
  },
  chips: model => ({ mode: value => {
    const st = state(model); if (!st) return;
    if (st.switchTo(value)) { model.prefs.builderMode = value; model.savePrefs(); redraw(); $(`[data-chip="mode"][data-value="${value}"]`)?.focus(); }
    else { paint(model); $('#builder-notice')?.scrollIntoView({ block: 'nearest' }); }
  } }),
  events: model => ({
    input: { 'builder-name': el => { state(model).name = el.value; paint(model); }, 'builder-text': el => { state(model).setText(el.value); paint(model); } },
    change: { 'builder-category': el => { state(model).category = el.value || null; paint(model); } },
  }),
  actions: model => ({
    'builder-cancel': () => {
      const leave = () => { model.closeBuilder(); navigate('#/home'); };
      if (state(model)?.hasUnsavedChanges) confirmSheet({ title: 'Discard your changes?', text: 'The workout has changes that are not saved.', confirm: 'Discard changes', cancel: 'Keep editing', onConfirm: leave }); else leave();
    },
    'builder-save': async () => {
      const st = state(model); if (!st?.canSave) return;
      await model.saveCustomWorkout(st.workout()); model.closeBuilder(); notify('Workout saved.'); navigate('#/home');
    },
    'add-step': () => { commit(model, blocks => blocks.push(stepBlock(makeStep('', 300, percent(0.75))))); redraw('add-step'); },
    'add-repeat': () => { commit(model, blocks => blocks.push(repeatBlock(4, [makeStep('Hard', 180, percent(1.1)), makeStep('Easy', 120, percent(0.5))]))); redraw('add-repeat'); },
    'add-preset': el => { commit(model, blocks => blocks.push(stepBlock(defaults[el.dataset.preset]()))); redraw(); $(`[data-preset="${el.dataset.preset}"]`)?.focus(); },
    'block-duplicate': el => { const b = Number(el.dataset.b); commit(model, blocks => blocks.splice(b + 1, 0, structuredClone(blocks[b]))); redraw(`${b + 1}-dup`); },
    'block-delete': el => { const b = Number(el.dataset.b); commit(model, blocks => blocks.splice(b, 1)); redraw(state(model).blocks.length ? `${Math.min(b, state(model).blocks.length - 1)}-del` : 'add-step'); },
    'block-up': el => { const b = Number(el.dataset.b); commit(model, blocks => { [blocks[b - 1], blocks[b]] = [blocks[b], blocks[b - 1]]; }); redraw(b - 1 > 0 ? `${b - 1}-up` : `${b - 1}-down`); },
    'block-down': el => { const b = Number(el.dataset.b); commit(model, blocks => { [blocks[b + 1], blocks[b]] = [blocks[b], blocks[b + 1]]; }); redraw(b + 1 < state(model).blocks.length - 1 ? `${b + 1}-down` : `${b + 1}-up`); },
    'step-duplicate': el => { const b = Number(el.dataset.b), i = Number(el.dataset.s); commit(model, blocks => blocks[b].steps.splice(i + 1, 0, structuredClone(blocks[b].steps[i]))); redraw(`${b}-${i + 1}-dup`); },
    'step-delete': el => { const b = Number(el.dataset.b), i = Number(el.dataset.s); commit(model, blocks => { if (blocks[b].steps.length > 1) blocks[b].steps.splice(i, 1); }); redraw(`${b}-${Math.min(i, state(model).blocks[b].steps.length - 1)}-del`); },
    'repeat-add-step': el => { const b = Number(el.dataset.b); commit(model, blocks => blocks[b].steps.push(makeStep('', 60, percent(0.5)))); redraw(`${b}-add`); },
    'set-unit': el => {
      const st = state(model), s = stepOf(st, el), toPercent = el.dataset.unit === 'percentFTP'; if (!s || isPercent(s.start) === toPercent) return;
      commit(model, () => unitConvert(s, toPercent, riderFTP(model))); redraw(el.dataset.key);
    },
  }),
});
