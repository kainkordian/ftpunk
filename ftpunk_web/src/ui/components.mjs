import { riderInitials, riderChipName, holdFraction, holdComplete, HOLD_SECONDS, DurationFormat } from '../rules/presentation.mjs';
import { previewSteps, profileBars, stepAtFraction } from '../rules/preview.mjs';
// Shared view pieces. Each returns an HTML string (escaped by `esc`) or binds behaviour to rendered markup.
// Nothing here knows about routes or storage. No inline styles: the page's Content-Security-Policy may forbid them.

export const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
export const $ = (selector, root = document) => root.querySelector(selector);
export const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
export const watts = n => Number.isFinite(n) ? String(Math.round(n)) : '—';
export const fmtDate = iso => new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
const attrs = (extra = {}) => Object.entries(extra).filter(([, v]) => v !== false && v != null).map(([k, v]) => v === true ? k : `${k}="${esc(v)}"`).join(' ');

/** kind: primary | secondary | tertiary | danger | link. `action` becomes data-action. */
export function button(label, { kind = 'secondary', action, block = false, disabled = false, small = false, extra = {} } = {}) {
  return `<button type="button" class="btn ${kind}${block ? ' block' : ''}${small ? ' small' : ''}" ${attrs({ 'data-action': action, disabled, ...extra })}>${label}</button>`;
}
export const linkButton = (label, href, kind = 'secondary', extra = {}) => `<a class="btn ${kind}" href="${esc(href)}" ${attrs(extra)}>${label}</a>`;
export const pill = (text, tone = 'neutral', symbol = '') => `<span class="pill ${tone}">${symbol ? `<span aria-hidden="true">${symbol}</span>` : ''}${esc(text)}</span>`;
export const field = (label, id, value, extra = {}) => `<label class="field"><span>${esc(label)}</span><input id="${esc(id)}" name="${esc(id)}" value="${esc(value ?? '')}" ${attrs(extra)}></label>`;
export const numberField = (label, id, value, extra = {}) => field(label, id, value, { type: 'number', inputmode: 'decimal', ...extra });
export const switchRow = (label, id, checked, { hint = '', disabled = false } = {}) => `<label class="switch"><span>${esc(label)}${hint ? `<small>${esc(hint)}</small>` : ''}</span><input type="checkbox" id="${esc(id)}" ${attrs({ checked, disabled })}></label>`;
export const selectField = (label, id, options, value, extra = {}) => `<label class="field"><span>${esc(label)}</span><select id="${esc(id)}" ${attrs(extra)}>${options.map(([v, text]) => `<option value="${esc(v)}" ${String(v) === String(value) ? 'selected' : ''}>${esc(text)}</option>`).join('')}</select></label>`;
export const chips = (items, selected, { name = 'chip' } = {}) => `<div class="chips" role="group" aria-label="${esc(name)}">${items.map(([id, title]) => `<button type="button" class="chip" data-chip="${esc(name)}" data-value="${esc(id)}" aria-pressed="${id === selected}">${esc(title)}</button>`).join('')}</div>`;
export const segmented = (items, selected, name) => `<div class="segmented" role="group" aria-label="${esc(name)}">${items.map(([id, title]) => `<button type="button" data-chip="${esc(name)}" data-value="${esc(id)}" aria-pressed="${id === selected}">${esc(title)}</button>`).join('')}</div>`;
/** A screen header: optional back link, title, and right-hand actions. */
export function screenHeader(title, { back = null, left = '', right = '' } = {}) {
  return `<header class="screen-header">${back ? `<a class="icon-btn back" href="${esc(back)}" aria-label="Back">‹</a>` : ''}${left}<h1>${esc(title)}</h1><span class="grow"></span>${right}</header>`;
}
export const riderChip = name => `<button type="button" class="rider-chip" data-action="open-riders" aria-label="Rider: ${esc(name)}. Switch or add riders, and edit weight and FTP."><span class="initials" aria-hidden="true">${esc(riderInitials(name))}</span><span>${esc(riderChipName(name))}</span><span aria-hidden="true" class="caret">▾</span></button>`;
const light = (state, symbol) => `<span class="light ${state}" aria-hidden="true">${state === 'attention' ? '⚠' : symbol}</span>`;
export const devicesPill = summary => `<button type="button" class="devices-pill" data-action="open-devices" aria-label="Devices. ${esc(summary.description)}" title="Connect or manage your trainer, power meter and heart-rate sensor">${light(summary.trainer, 'T')}${light(summary.power, 'P')}${light(summary.heartRate, '♥')}<span>Devices</span></button>`;
/** One line of the pre-flight checklist. `value` and `detail` are plain text. */
export function checklistRow({ icon, title, value, detail = '', status = 'normal', action = '', id = '' }) {
  const body = `<span class="row-icon ${status}" aria-hidden="true">${status === 'attention' ? '⚠' : esc(icon)}</span><span class="row-text"><span class="caption">${esc(title)}</span><span class="row-value" ${id ? `id="${esc(id)}"` : ''}>${esc(value)}</span>${detail ? `<span class="row-detail ${status}" ${id ? `id="${esc(id)}-detail"` : ''}>${esc(detail)}</span>` : ''}</span>${action ? '<span class="chevron" aria-hidden="true">›</span>' : ''}`;
  return action ? `<button type="button" class="check-row" data-action="${esc(action)}" aria-label="${esc(title)}: ${esc(value)}${detail ? '. ' + esc(detail) : ''}">${body}</button>` : `<div class="check-row">${body}</div>`;
}
export const checklistCard = (rows, title = '') => `<section class="check-card">${title ? `<h2 class="card-title">${esc(title)}</h2>` : ''}<div class="card flush">${rows.join('<hr>')}</div></section>`;
export function metricTile({ title, value, unit = '', tone = 'normal', caption = '', hero = false, id = '', placeholder = '—' }) {
  return `<div class="tile ${tone}${hero ? ' hero' : ''}" role="group" aria-label="${esc(title)}"><span class="caption">${esc(title)}</span><span><span class="value" ${id ? `id="${esc(id)}"` : ''}>${esc(value ?? placeholder)}</span>${unit ? `<span class="unit">${esc(unit)}</span>` : ''}</span>${caption || id ? `<span class="caption" ${id ? `id="${esc(id)}-caption"` : ''}>${esc(caption)}</span>` : ''}</div>`;
}
/** Warm-up, ramp and cool-down as one bar with a progress fill. */
export function phaseTimelineView(timeline, current, { showLabels = true } = {}) {
  const label = phase => ({ warmup: 'warm-up', ramp: 'ramp' }[phase] ?? 'cool-down');
  const segments = timeline.segments.map(s => `<span class="segment ${s.phase === current ? 'current' : ''}" data-start="${s.start}" data-end="${s.end}"></span>`).join('');
  return `<div class="timeline" role="img" aria-label="Test progress: ${Math.round(timeline.progress * 100)} percent through the planned test"><div class="track" data-progress="${timeline.progress}">${segments}<span class="fill" data-fill></span></div>${showLabels ? `<div class="timeline-labels">${timeline.segments.map(s => `<span class="${s.phase === current ? 'current' : ''}">${label(s.phase)}</span>`).join('')}</div>` : ''}</div>`;
}
/** Sets the CSS custom properties that position timeline segments (CSP-safe: done through the CSSOM, not style attributes). */
export function applyTimeline(root) {
  for (const track of $$('.timeline .track', root)) {
    for (const s of $$('.segment', track)) { s.style.setProperty('--start', s.dataset.start); s.style.setProperty('--end', s.dataset.end); }
    $('[data-fill]', track)?.style.setProperty('--progress', track.dataset.progress);
  }
}
/** Countdown to the next ramp step: a ring that drains, with the change and time beside it. */
export function stepRing({ fraction, remaining, nextChange }) {
  const circumference = 2 * Math.PI * 22, offset = circumference * (1 - Math.max(0, Math.min(1, fraction)));
  return `<div class="ring-row" role="img" aria-label="Next step: ${esc(nextChange)} in ${remaining} seconds"><svg viewBox="0 0 52 52" width="52" height="52" aria-hidden="true"><circle class="ring-back" cx="26" cy="26" r="22"/><circle class="ring-fill" cx="26" cy="26" r="22" stroke-dasharray="${circumference.toFixed(2)}" stroke-dashoffset="${offset.toFixed(2)}" transform="rotate(-90 26 26)"/><text x="26" y="31" text-anchor="middle">${remaining}</text></svg><span class="ring-text">${esc(nextChange)} in ${remaining} s</span></div>`;
}
/** A deliberate action: press and hold for 1.5 s while a ring fills. Keyboard: hold Space or Enter, or press Shift+Enter. */
export const holdButton = (label, action, { icon = '⚑' } = {}) => `<button type="button" class="btn secondary hold" data-hold="${esc(action)}" aria-label="${esc(label)}. Press and hold for one and a half seconds, or press Shift and Enter."><svg viewBox="0 0 26 26" width="26" height="26" aria-hidden="true"><circle class="ring-back" cx="26" cy="26" r="11" transform="translate(-13 -13)"/><circle class="ring-fill" cx="13" cy="13" r="11" stroke-dasharray="69.115" stroke-dashoffset="69.115" transform="rotate(-90 13 13)"/></svg><span class="hold-label" data-idle="${esc(label)}">${esc(label)}</span></button>`;
export function bindHold(root, handlers, { now = () => performance.now(), reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches } = {}) {
  for (const button of $$('[data-hold]', root)) {
    const ring = $('.ring-fill', button), text = $('.hold-label', button); let start = null, frame = null;
    const paint = fraction => { ring.setAttribute('stroke-dashoffset', (69.115 * (1 - fraction)).toFixed(2)); };
    const stop = () => { start = null; if (frame) cancelAnimationFrame(frame); frame = null; paint(0); text.textContent = text.dataset.idle; };
    const step = () => {
      if (start == null) return;
      const held = (now() - start) / 1000; paint(holdFraction(held)); text.textContent = 'Keep holding…';
      if (holdComplete(held)) { stop(); handlers[button.dataset.hold]?.(); return; }
      frame = requestAnimationFrame(step);
    };
    const begin = () => { if (start != null) return; start = now(); frame = requestAnimationFrame(step); if (reduceMotion()) paint(0.01); };
    button.addEventListener('pointerdown', event => { button.setPointerCapture?.(event.pointerId); begin(); });
    for (const type of ['pointerup', 'pointercancel', 'pointerleave', 'blur']) button.addEventListener(type, stop);
    button.addEventListener('keydown', event => { if (event.key === 'Enter' && event.shiftKey) { event.preventDefault(); handlers[button.dataset.hold]?.(); } else if ((event.key === ' ' || event.key === 'Enter') && !event.repeat) { event.preventDefault(); begin(); } });
    button.addEventListener('keyup', event => { if (event.key === ' ' || event.key === 'Enter') stop(); });
    button.addEventListener('contextmenu', event => event.preventDefault());
  }
}

/** Step profile of a workout: bar height is the target on a fixed 0–130 % of FTP scale, ramps are slanted, bars are coloured by zone.
    Without an FTP the bars are neutral. `progressSeconds` adds a marker (the cockpit moves it through `moveProfileMarker`). */
export function profileChart(plan, { intensity = 100, progressSeconds = null, height = 'normal', interactive = false, id = '' } = {}) {
  const bars = profileBars(plan, intensity), total = Math.max(1, plan.steps.reduce((n, s) => n + s.seconds, 0)), W = 1000, H = 100, hasFTP = plan.ftpWatts > 0;
  const paths = bars.map((bar, i) => {
    const x0 = (bar.start * W).toFixed(1), x1 = Math.max(bar.start * W + 1, bar.end * W - 0.5).toFixed(1), y0 = ((1 - bar.startHeight) * H).toFixed(1), y1 = ((1 - bar.endHeight) * H).toFixed(1);
    return `<path class="bar ${bar.zone == null ? 'zone-none' : `zone-${bar.zone}`}" data-step="${i}" d="M${x0} ${H} L${x0} ${y0} L${x1} ${y1} L${x1} ${H} Z"/>`;
  }).join('');
  const line = hasFTP ? `<line class="ftp-line" x1="0" x2="${W}" y1="${(H * (1 - 100 / 130)).toFixed(1)}" y2="${(H * (1 - 100 / 130)).toFixed(1)}"/>` : '';
  const marker = progressSeconds == null ? '' : `<rect class="marker" id="profile-marker" x="${Math.max(0, Math.min(1, progressSeconds / total)) * W - 3}" y="0" width="6" height="${H}"/>`;
  const peak = Math.max(...plan.steps.map(s => Math.max(s.watts, s.endWatts ?? s.watts))) * intensity / 100;
  const label = `Workout profile: ${plan.steps.length} steps over ${Math.round(total / 60)} minutes, peak target ${Math.round(peak)} watts${hasFTP ? `, ${Math.round(peak / plan.ftpWatts * 100)} percent of FTP` : ''}`;
  return `<div class="profile ${height}${interactive ? ' interactive' : ''}" ${id ? `id="${esc(id)}"` : ''}><svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="${esc(label)}">${line}${paths}${marker}</svg>${interactive ? '<div class="tooltip" role="status" hidden></div>' : ''}</div>`;
}
export function moveProfileMarker(root, plan, seconds) {
  const marker = $('#profile-marker', root), total = Math.max(1, plan.steps.reduce((n, s) => n + s.seconds, 0));
  if (marker) marker.setAttribute('x', (Math.max(0, Math.min(1, seconds / total)) * 1000 - 3).toFixed(1));
  $$('.profile .bar', root).forEach(bar => bar.classList.toggle('done', seconds >= 0 && (() => { let end = 0; for (let i = 0; i <= Number(bar.dataset.step); i++) end += plan.steps[i].seconds; return seconds >= end; })()));
}
/** Hover (or touch-drag) a profile chart or its step list to highlight one step and show its values in a tooltip. */
export function bindProfileHover(root, plan, { intensity = 100, showValues = true } = {}) {
  const chart = $('.profile.interactive', root); if (!chart) return;
  const svg = $('svg', chart), tip = $('.tooltip', chart), steps = previewSteps(plan, intensity, showValues);
  const select = index => {
    $$('.bar', chart).forEach(bar => bar.classList.toggle('selected', Number(bar.dataset.step) === index));
    $$('[data-step-row]', root).forEach(row => row.classList.toggle('selected', Number(row.dataset.stepRow) === index));
    if (index == null) { tip.hidden = true; return; }
    const step = steps[index], bar = profileBars(plan, intensity)[index];
    tip.hidden = false; tip.replaceChildren(); const name = document.createElement('strong'), values = document.createElement('span'); name.textContent = step.name; values.textContent = step.valueText; tip.append(name, values);
    tip.style.setProperty('--x', `${((bar.start + bar.end) / 2 * 100).toFixed(1)}%`);
    tip.classList.toggle('left', bar.start + bar.end < 0.6); tip.classList.toggle('right', bar.start + bar.end > 1.4);
  };
  const at = event => { const box = svg.getBoundingClientRect(); return stepAtFraction(Math.min(1, Math.max(0, (event.clientX - box.left) / Math.max(1, box.width))), plan); };
  svg.addEventListener('pointermove', event => select(at(event))); svg.addEventListener('pointerleave', () => select(null)); svg.addEventListener('pointerdown', event => select(at(event)));
  $$('[data-step-row]', root).forEach(row => { const i = Number(row.dataset.stepRow); row.addEventListener('pointerenter', () => select(i)); row.addEventListener('pointerleave', () => select(null)); row.addEventListener('click', () => select(i)); });
}
/** A library card: title, detail line, a small profile and an optional badge. The whole card is one button. */
export function workoutCard({ title, detail, plan, badge = '', action, ref = '' }) {
  return `<button type="button" class="workout-card" data-action="${esc(action)}" data-ref="${esc(ref)}" aria-label="${esc(title)}. ${esc(detail)}${badge ? '. ' + esc(badge) : ''}"><span class="card-head"><strong>${esc(title)}</strong>${badge ? pill(badge, 'warning') : ''}</span><span class="muted">${esc(detail)}</span>${plan ? profileChart(plan, { height: 'small' }) : ''}</button>`;
}
export const emptyState = (title, text, extra = '') => `<div class="empty card"><h2>${esc(title)}</h2><p class="muted">${esc(text)}</p>${extra}</div>`;
export { DurationFormat };
