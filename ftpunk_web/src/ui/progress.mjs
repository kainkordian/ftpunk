import { esc, $, button, chips, segmented, selectField, switchRow, pill, screenHeader, fmtDate, emptyState, linkButton } from './components.mjs';
import { trendChart, rideCharts, summaryCard } from './charts.mjs';
import { registerRoute, navigate, hashFor, rerender, confirmSheet, notify } from './shell.mjs';
import { exportControls, uploadControls, exportActions, ftpResultCard, calculationNote, riderOf } from './result.mjs';
import { ACTIVITY_FILTERS, TREND_METRICS, activities, activityRow, activityTitle, badgeText, riderGroups, trendSeries, trendSessions } from '../rules/progress.mjs';
import { interruptionSummary, isAdopted, averagePower, DurationFormat } from '../rules/presentation.mjs';
import { PRESETS } from '../domain.mjs';
import { DEVICE_LABELS } from '../bluetooth.mjs';
// Progress: the FTP trend per rider, activity filters, the activity list with delete, and the activity detail (#/activity/<id>).
// The export and upload controls on the detail come from result.mjs (`exportControls`, `uploadControls`): slots of the Intervals.icu / export plan.

const state = { scope: 'current', metric: 'watts', filter: 'all', includeDebug: false };
const BADGE_TONE = { debug: 'warning', interrupted: 'warning', uploadFailed: 'warning', uploaded: 'good', uploadQueued: 'neutral' };
const BADGE_SYMBOL = { debug: '▶', uploaded: '✓', uploadQueued: '↑', uploadFailed: '⚠', interrupted: '⚠' };
const riderID = model => state.scope === 'current' ? model.profile.id : state.scope === 'all' ? null : state.scope;
const scopeTitle = model => state.scope === 'current' ? model.profile.name : state.scope === 'all' ? 'All riders' : model.profiles.find(p => p.id === state.scope)?.name ?? 'Rider';
const isLive = (model, s) => model.ride.active && model.ride.engine?.session.id === s.id;
const jobStatus = (model, s) => model.jobs.find(j => j.sessionID === s.id)?.status ?? null;

function trendSection(model) {
  const sessions = trendSessions(model.history, riderID(model), state.metric, state.includeDebug), metric = TREND_METRICS.find(m => m.id === state.metric);
  const body = sessions.length
    ? `${trendChart(trendSeries(riderGroups(sessions, model.profiles), state.metric, state.includeDebug, model.profiles.map(p => p.id.toLowerCase())), state.metric, { includeDebug: state.includeDebug })}<p class="footnote">Each point is one FTP test. Colour identifies the rider; circles are real results and diamonds are debug results. Compare matching protocols and power sources.</p>`
    : `<p class="muted">${state.metric === 'wattsPerKG' ? 'FTP tests with a result and a saved rider weight' : 'FTP test results'} for ${esc(scopeTitle(model))} will appear here. Debug results are hidden unless you turn them on.</p>`;
  return `<section class="card stack" id="trend"><div class="row spread"><h2>FTP trend · ${esc(scopeTitle(model))}</h2>${segmented(TREND_METRICS.map(m => [m.id, m.title]), state.metric, 'Metric')}</div>${body}</section>`;
}
function activitySection(model) {
  if (!model.history.length) return emptyState('Your first ride starts on Home', 'Finished rides are saved here, with FTP trends for every rider.', linkButton('Go to Home', '#/home', 'tertiary'));
  const list = activities(model.history, riderID(model), state.filter), filter = ACTIVITY_FILTERS.find(f => f.id === state.filter);
  return `<section class="stack"><h2>Activities</h2>${chips(ACTIVITY_FILTERS.map(f => [f.id, f.title]), state.filter, { name: 'Activity type' })}${list.length ? `<ul class="activity-list">${list.map(s => {
    const row = activityRow(s, jobStatus(model, s), state.scope === 'all');
    return `<li class="activity-row"><button type="button" class="activity-open" data-action="open-activity" data-id="${esc(s.id)}" data-testid="activity-${esc(s.id)}"><span class="grow"><strong>${esc(row.title)}</strong><br><span class="muted">${esc(row.subtitle)}</span>${row.badges.length ? `<span class="badges">${row.badges.map(b => pill(badgeText(b), BADGE_TONE[b], BADGE_SYMBOL[b])).join('')}</span>` : ''}</span>${row.value ? `<span class="accent-text num value">${esc(row.value)}</span>` : ''}</button><button type="button" class="icon-btn" data-action="delete-activity" data-id="${esc(s.id)}" aria-label="Delete ${esc(row.title)}" ${isLive(model, s) ? 'disabled' : ''}>🗑</button></li>`;
  }).join('')}</ul>` : `<p class="muted">No ${state.filter === 'all' ? 'activities' : esc(filter.title.toLowerCase())} for ${esc(scopeTitle(model))} yet.</p>`}</section>`;
}
export function confirmDelete(model, session, { then = rerender } = {}) {
  confirmSheet({ title: 'Delete this activity?', text: `Delete ${session.configuration.riderName}’s local recording and its pending upload. Any activity already sent to Intervals.icu remains there. Adopted FTP settings are kept.`, confirm: 'Delete', onConfirm: async () => { await model.deleteSession(session); then(); } });
}
registerRoute('progress', {
  tab: 'progress', documentTitle: () => 'Progress',
  render(model) {
    const others = model.profiles.filter(p => p.id !== model.profile.id);
    if (state.scope !== 'current' && state.scope !== 'all' && !model.profiles.some(p => p.id === state.scope)) state.scope = 'current';
    return `${screenHeader('Progress')}<div class="stack-l"><div class="card row filters">${selectField('Rider', 'pg-scope', [['current', `Current rider · ${model.profile.name}`], ['all', 'All riders'], ...others.map(p => [p.id, p.name])], state.scope)}${switchRow('Show debug results in the trend', 'pg-debug', state.includeDebug)}</div>${trendSection(model)}${activitySection(model)}</div>`;
  },
  actions: model => ({
    'open-activity': el => navigate(hashFor('activity', el.dataset.id)),
    'delete-activity': el => { const s = model.history.find(x => x.id === el.dataset.id); if (s) confirmDelete(model, s); },
  }),
  chips: () => ({ Metric: value => { state.metric = value; rerender(); }, 'Activity type': value => { state.filter = value; rerender(); } }),
  events: () => ({ change: { 'pg-scope': el => { state.scope = el.value; rerender(); }, 'pg-debug': el => { state.includeDebug = el.checked; rerender(); } } }),
});

// ----- one activity ------------------------------------------------------------------------------------------------------------------
function detailHeadline(session) {
  if (session.result && session.training == null) return ftpResultCard(session.result, { showDelta: false });
  if (session.outcome === 'interrupted') { const s = interruptionSummary(session); return `<section class="card warning stack"><h2 class="warn">⚠ ${esc(s.headline)}</h2><p>${esc(s.reason)}</p><p class="muted">${esc(s.saved)}</p></section>`; }
  if (session.training != null) { return `<dl class="kv card"><dt>Time</dt><dd class="num">${DurationFormat.clock(session.endedAtOffset ?? 0)}</dd></dl>`; }
  return '<p class="muted card">No FTP estimate. A valid, continuous 60-second ramp window is required.</p>';
}
function sourcesList(model, session) {
  const c = session.configuration, rows = [['Rider at time of ride', c.riderName], ['Activity', activityTitle(session)], ['Power source', c.powerSource === 'trainer' ? 'Trainer' : 'External power meter'], ['Cadence source', DEVICE_LABELS[c.cadenceSource] ?? 'Unavailable · finish ramp manually'],
    ['FTP at the time', c.priorFTP != null ? `${Math.round(typeof c.priorFTP === 'number' ? c.priorFTP : c.priorFTP.watts)} W` : 'Not provided'], ['Session weight', c.weightKG ? `${c.weightKG} kg` : 'Not provided']];
  if (session.training?.resistance != null) rows.push(['Initial resistance level', (session.training.resistance / 10).toFixed(1)]);
  else if (session.training) for (const step of session.training.steps) rows.push([step.name, `${Math.round(step.seconds)} s · ${step.watts}${step.endWatts == null ? '' : ` → ${step.endWatts}`} W`]);
  else rows.push(['Warm-up', `${c.warmupPower} W`], ['Estimate factor', `${Math.round(c.ftpFactor * 100)} %`]);
  rows.push(['Outcome', session.outcome ? (session.outcome === 'exhaustion' ? 'Ramp complete' : session.outcome) : 'Recording']);
  return `<section class="stack"><h3>This activity</h3><dl class="kv">${rows.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')}</dl>${session.endReason ? `<p class="warn">${esc(session.endReason)}</p>` : ''}</section>`;
}
registerRoute('activity', {
  tab: 'progress', documentTitle: () => 'Activity',
  render(model, [id]) {
    const session = model.history.find(s => s.id === id);
    if (!session) return `${screenHeader('Activity', { back: '#/progress' })}${emptyState('Activity deleted', 'This recording is no longer on this browser.')}`;
    const rider = riderOf(model, session), result = session.result, name = session.configuration.riderName, adopted = result && isAdopted(rider, result, session.startedAt);
    const adoption = result && session.training == null && !session.isDemo ? `<section class="stack">${adopted ? `<p class="accent-text">✓ ${esc(name)}’s FTP was set from this test</p>` : button(`Use ${Math.round(result.estimatedFTP)} W as ${esc(name)}’s FTP`, { kind: 'secondary', action: 'adopt-activity', disabled: model.busy, extra: { 'data-testid': 'detail-adopt', 'data-id': session.id } })}</section>` : '';
    return `${screenHeader(new Date(session.startedAt).toLocaleDateString(undefined, { dateStyle: 'medium' }), { back: '#/progress', right: button('Delete…', { kind: 'danger', small: true, action: 'delete-this', disabled: isLive(model, session), extra: { 'data-id': session.id } }) })}<div class="stack-l">${session.isDemo ? `<p>${pill('Debug · mock sensor data', 'warning', '▶')}</p>` : ''}${detailHeadline(session)}<section class="stack">${rideCharts(session)}${summaryCard(session)}${session.training == null ? calculationNote(session.result) : ''}</section>${adoption}${sourcesList(model, session)}${exportControls(model, session)}${!session.isDemo && session.endedAtOffset != null ? `<section class="stack"><h3>Intervals.icu</h3>${model.jobs.find(j => j.sessionID === session.id) ? `<p>Upload: ${esc(model.jobs.find(j => j.sessionID === session.id).status)}</p>` : ''}${uploadControls(model, session)}</section>` : ''}</div>`;
  },
  actions: model => ({
    ...exportActions(model),
    'delete-this': el => { const s = model.history.find(x => x.id === el.dataset.id); if (s) confirmDelete(model, s, { then: () => navigate('#/progress') }); },
    'adopt-activity': async el => { await model.adopt(model.history.find(s => s.id === el.dataset.id)); rerender(); },
  }),
});
