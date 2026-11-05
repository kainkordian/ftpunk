import { esc, button, chips, workoutCard, profileChart, bindProfileHover, $ } from './components.mjs';
import { openSheet, navigate, hashFor, notify, rerender } from './shell.mjs';
import { CATEGORIES, definitionsIn, mainSetWatts, intensityLabel } from '../catalog.mjs';
import { previewSteps, mainSetText, zoneTitle } from '../rules/preview.mjs';
import { DurationFormat, BLOCKER_TEXT } from '../rules/presentation.mjs';
import { selectToday, upcoming, mine, dateText } from '../rules/home.mjs';
import { exampleWorkout } from '../workouts.mjs';
import { download } from '../export.mjs';
import { ScheduledDate } from '../workouts.mjs';
// The workout library on Home: Today, the classics by category, Upcoming (Intervals.icu cache), My workouts, and the workout detail sheet.
// Called from home.mjs. The "My workouts" section is a marked slot: the workout builder and ZWO import plan replaces `myWorkoutsSection`.

const caption = detail => [DurationFormat.workout(detail.duration), detail.plan && mainSetWatts(detail.plan) != null ? `main ${mainSetWatts(detail.plan)} W` : null].filter(Boolean).join(' · ');
const today = () => ScheduledDate.stringFor(new Date());

export function todaySection(model) {
  const sel = selectToday(model.workouts, model.profile.id, today(), !!model.connection), byID = id => model.workouts.find(w => w.id === id);
  if (sel.kind === 'today') {
    return `<section class="stack"><p class="label">Today · from Intervals.icu</p>${sel.ids.map(byID).filter(Boolean).map(w => `<article class="card accent today-card"><button type="button" class="today-open" data-action="open-workout" data-ref="${esc(`cached:${w.id}`)}" aria-label="${esc(w.plan.name)}, today, ${esc(DurationFormat.workout(w.plan.steps.reduce((n, s) => n + s.seconds, 0)))}. Shows the workout steps"><span class="row spread nowrap"><strong class="title">${esc(w.plan.name)}</strong><span class="muted">${esc(DurationFormat.workout(w.plan.steps.reduce((n, s) => n + s.seconds, 0)))}</span></span>${profileChart(w.plan, { height: 'small' })}</button>${button('▶ Start', { kind: 'primary', block: true, action: 'start-workout', disabled: model.busy, extra: { 'data-ref': `cached:${w.id}` } })}</article>`).join('')}</section>`;
  }
  if (sel.kind === 'nothingToday') {
    const next = sel.next ? byID(sel.next) : null;
    return `<section class="stack"><p class="label">Today · from Intervals.icu</p><h2>Nothing planned today</h2>${next ? `<p class="muted">Next planned</p>${workoutCard({ title: next.plan.name, detail: `${dateText(next.scheduledDate)} · ${DurationFormat.workout(next.plan.steps.reduce((n, s) => n + s.seconds, 0))}`, plan: next.plan, action: 'open-workout', ref: `cached:${next.id}` })}` : ''}${model.calendarMessage ? `<p class="footnote">${esc(model.calendarMessage)}</p>` : ''}</section>`;
  }
  return model.prefs.intervalsHintDismissed ? '' : `<div class="row nowrap hint"><a class="grow btn link" href="#/settings">Connect Intervals.icu in Settings to see planned workouts</a><button type="button" class="icon-btn" data-action="dismiss-hint" aria-label="Dismiss">×</button></div>`;
}

export function librarySection(model) {
  const category = model.libraryCategory, defs = definitionsIn(category);
  return `<section class="stack" id="library"><h2>Workouts</h2>${model.ftp ? '' : '<p class="footnote">ⓘ Needs FTP: take an FTP test or set your FTP to see targets.</p>'}
    ${chips([['all', 'All'], ...CATEGORIES.map(c => [c.id, c.title])], category ?? 'all', { name: 'category' })}
    <div class="grid-cards">${defs.map(def => { const detail = model.workoutDetail(`classic:${def.id}`); return workoutCard({ title: detail.title, detail: caption(detail), plan: detail.previewPlan, badge: detail.needsFTP ? 'Needs FTP' : '', action: 'open-workout', ref: detail.ref }); }).join('')}</div></section>`;
}

export function upcomingSection(model) {
  const list = upcoming(model.workouts, model.profile.id, today());
  if (!model.connection && !list.length) return '';
  return `<section class="stack" id="upcoming"><div class="row spread"><h2>Upcoming</h2>${model.connection ? button(model.downloading ? 'Refreshing…' : '↻ Refresh', { kind: 'link', action: 'refresh-calendar', disabled: model.busy || model.downloading }) : ''}</div>
    <p class="footnote">From Intervals.icu · next 14 days</p>
    ${list.length ? `<div class="grid-cards">${list.map(w => workoutCard({ title: w.plan.name, detail: `${dateText(w.scheduledDate)} · ${DurationFormat.workout(w.plan.steps.reduce((n, s) => n + s.seconds, 0))}`, plan: w.plan, action: 'open-workout', ref: `cached:${w.id}` })).join('')}</div>` : '<p class="muted">Nothing else planned.</p>'}
    ${model.importReport && model.connection ? `<p class="footnote report">${esc(model.importReport)}</p>` : ''}${model.calendarMessage ? `<p class="footnote">${esc(model.calendarMessage)}</p>` : ''}</section>`;
}

// ---- My workouts: marked slot. Today it lists imported JSON files; the builder plan replaces this function and its actions. ----
export function myWorkoutsSection(model) {
  const own = mine(model.workouts, model.profile.id);
  return `<section class="stack" id="my-workouts" data-slot="my-workouts"><h2>My workouts</h2>
    <div class="row">${button('Import file…', { kind: 'tertiary', action: 'import-workout', disabled: model.busy })}<input type="file" id="workout-file" aria-label="Workout file" accept=".json,application/json" hidden></div>
    ${own.length ? `<div class="grid-cards">${own.map(w => workoutCard({ title: w.plan.name, detail: `${DurationFormat.workout(w.plan.steps.reduce((n, s) => n + s.seconds, 0))} · imported`, plan: w.plan, action: 'open-workout', ref: `cached:${w.id}` })).join('')}</div>`
      : `<p class="footnote">Import an FTPunk JSON workout or an Intervals.icu workout event.</p>${button('Get an example JSON file', { kind: 'link', action: 'example-workout' })}`}
    ${model.importReport && !model.connection ? `<p class="footnote report">${esc(model.importReport)}</p>` : ''}</section>`;
}

/** Click, chip and change handlers for everything above; merged into the Home route's own. */
export const libraryActions = model => ({
  'open-workout': el => openWorkoutDetail(model, el.dataset.ref),
  'start-workout': el => navigate(hashFor('preflight', 'workout', el.dataset.ref)),
  'dismiss-hint': () => { model.prefs.intervalsHintDismissed = true; model.savePrefs(); rerender(); },
  'refresh-calendar': () => model.downloadCalendar(),
  'import-workout': () => { if (!model.busy) $('#workout-file').click(); },
  'example-workout': () => download(JSON.stringify(exampleWorkout, null, 2), 'ftpunk-workout-example.json'),
});
export const libraryChips = model => ({ category: value => { model.libraryCategory = value === 'all' ? null : value; rerender(); } });
export const libraryEvents = model => ({ change: { 'workout-file': async input => { const file = input.files[0]; input.value = ''; if (file) await model.importWorkoutFile(file); } } });

/** The detail sheet: profile with hover, step list with % FTP and watts, intensity label and the main set. Start goes to the pre-flight. */
export function openWorkoutDetail(model, ref) {
  const detail = () => model.workoutDetail(ref);
  if (!detail()) return notify('This workout was removed.');
  const content = () => {
    const d = detail(); if (!d) return '<p>This workout was removed.</p>';
    const plan = d.plan ?? d.previewPlan, showValues = !d.needsFTP, steps = previewSteps(plan, 100, showValues), main = d.plan ? mainSetText(d.plan) : null;
    const used = d.plan?.ftpWatts, differs = d.cached && used != null && model.ftp != null && Math.abs(used - model.ftp) > 0.5;
    const ftpNote = d.needsFTP ? '<p class="warn">ⓘ Needs FTP. Take an FTP test or set your FTP to see targets in watts.</p>'
      : used != null ? `<p>${d.cached ? `Targets are fixed in watts (saved at ${Math.round(used)} W FTP).` : `Targets use your FTP of ${Math.round(used)} W.`}</p>${differs ? `<p class="footnote warn">Your current FTP is ${Math.round(model.ftp)} W. This workout does not rescale.</p>` : ''}` : '<p>Targets are fixed in watts.</p>';
    return `<div class="stack"><div><h2>${esc(d.title)}</h2><p class="muted">${esc([d.categoryTitle, d.source, DurationFormat.workout(d.duration)].filter(Boolean).join(' · '))}</p>${d.plan ? `<p><strong>${esc(intensityLabel(d.plan))}</strong></p>` : ''}${main ? `<p class="num">Main set: ${esc(main)}</p>` : ''}</div>
      ${profileChart(d.previewPlan, { height: 'large', interactive: true })}<p class="footnote">The dashed line is 100 % of FTP. Hover or touch the chart to see a step.</p>${ftpNote}
      <ol class="steps" aria-label="Steps">${steps.map(s => `<li data-step-row="${s.index}" tabindex="0"><span class="swatch ${s.zone == null ? 'zone-none' : `zone-${s.zone}`}" aria-hidden="true"></span><span class="grow">${esc(s.name)}${s.zone != null ? `<span class="sr-only"> ${esc(zoneTitle(s.zone))}</span>` : ''}</span><span class="num">${esc(s.durationText)}</span>${showValues ? `<span class="num">${esc(s.percentText ?? '')}</span><span class="num">${esc(s.wattsText)}</span>` : ''}</li>`).join('')}</ol></div>`;
  };
  const actions = () => { const d = detail(); return `${button('▶ Start', { kind: 'primary', extra: { 'data-dialog': 'start' }, disabled: !d || d.needsFTP || model.busy })}${d?.cached ? button('Remove from library', { kind: 'danger', extra: { 'data-dialog': 'remove' }, disabled: model.busy }) : ''}<button type="button" class="btn secondary" data-dialog="close">Close</button>`; };
  const d = detail();
  openSheet({ title: 'Workout', content, actions, onOpen: dialog => bindProfileHover(dialog, d.previewPlan, { showValues: !d.needsFTP }), handler: async (action, dialog) => {
    if (action === 'close') return dialog.close();
    if (action === 'start') { if (d.needsFTP) throw Error(BLOCKER_TEXT.needsFTP); dialog.close(); navigate(hashFor('preflight', 'workout', ref)); return; }
    if (action === 'remove') { await model.deleteCachedWorkout(d.cached.id); dialog.close(); }
  } });
}
