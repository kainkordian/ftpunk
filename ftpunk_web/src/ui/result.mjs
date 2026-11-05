import { esc, $, button, linkButton, pill, screenHeader, fmtDate } from './components.mjs';
import { powerChart } from './charts.mjs';
import { registerRoute, navigate, openSheet, sheetIsOpen, notify, rerender } from './shell.mjs';
import { openInfoSheet } from './sheets.mjs';
import { resultSections, resultDelta, interruptionSummary, isAdopted, averagePower, DurationFormat } from '../rules/presentation.mjs';
import { retargetExample } from '../catalog.mjs';
import { activityTitle } from '../rules/progress.mjs';
import { csv, tcx, download } from '../export.mjs';
import { OUTCOMES } from '../domain.mjs';
// The result screen: the training result first, then what it means for training, then sharing. Debug and interrupted rides use the same layout.
// Two marked slots are used by the Intervals.icu / export plan: `exportControls` and `uploadControls` (also used by the activity detail).

export const riderOf = (model, session) => model.profiles.find(p => p.id === session.configuration.riderID) ?? null;

/** The estimate with its change from the current FTP. The stored factor is shown, so recordings made with the older 75 % option keep their figures. */
export function ftpResultCard(result, { currentFTP = null, showDelta = true } = {}) {
  const delta = resultDelta(result.estimatedFTP, currentFTP);
  return `<section class="card accent stack result-card" aria-label="Estimated FTP"><p class="label accent-text">ESTIMATED FTP</p><p class="row result-figures"><span class="hero-number num" id="result-ftp">${Math.round(result.estimatedFTP)} W</span>${result.wattsPerKG ? `<span class="muted num">${result.wattsPerKG.toFixed(2)} W/kg</span>` : ''}</p>${showDelta ? `<p class="${delta.watts < 0 ? 'warn' : ''}"><strong>${esc(delta.text)}</strong></p>` : ''}<p class="muted">${Math.round(result.factor * 100)} % of your best minute, ${Math.round(result.bestMinutePower)} W</p></section>`;
}
/** "How this is calculated": the shaded minute, the factor and the 72–77 % range. */
export function calculationNote(result) {
  if (!result) return button('ⓘ How an estimate is calculated', { kind: 'link', action: 'info-estimate' });
  return `<details class="calc"><summary>How this is calculated</summary><div class="stack"><p>FTPunk takes the best continuous 60 seconds of the scored ramp, shaded above, and uses ${Math.round(result.factor * 100)} % of it. Warm-up, cool-down and the low-cadence confirmation period never count.</p><p>Research reports one-hour power commonly between 72 % and 77 % of that minute: ${Math.round(result.lowerFTP)}–${Math.round(result.upperFTP)} W here. New tests report the conservative 72 %, because underestimating FTP is less harmful than overestimating it.</p>${button('ⓘ Why 72–77 %?', { kind: 'link', action: 'info-estimate' })}</div></details>`;
}
export function headline(model, session) {
  const rider = riderOf(model, session), current = rider?.ftpHistory.find(e => e.id === rider.currentFTPID)?.watts ?? null;
  if (session.outcome === 'interrupted') {
    const summary = interruptionSummary(session);
    return `<section class="card warning stack"><h2 class="warn">⚠ ${esc(summary.headline)}</h2><p>${esc(summary.reason)}</p><p class="muted">${esc(summary.saved)}</p>${session.result ? ftpResultCard(session.result, { currentFTP: current, showDelta: !session.isDemo }) : ''}</section>`;
  }
  if (session.result && session.training == null) return ftpResultCard(session.result, { currentFTP: current, showDelta: !session.isDemo });
  if (session.training != null) {
    const average = session.training.resistance == null ? averagePower(session.samples) : null;
    return `<section class="card accent stack"><h2 class="accent-text">✓ ${session.outcome === 'completed' ? 'Ride complete' : 'Ride saved'}</h2><p><strong>${esc(activityTitle(session))}</strong></p><div class="row stats"><div><p class="label">Time</p><p class="num big">${DurationFormat.clock(session.endedAtOffset ?? 0)}</p></div>${average != null ? `<div><p class="label">Average power</p><p class="num big">${Math.round(average)} W</p></div>` : ''}</div><p class="footnote">Saved in this browser.</p></section>`;
  }
  return `<section class="card stack"><h2>${esc(OUTCOMES[session.outcome] ?? 'Ride saved')}</h2><p class="muted">No FTP estimate. A valid, continuous 60-second ramp window is required, and the scored ramp must end by finishing or exhaustion.</p><p class="footnote">The recording is saved in this browser.</p></section>`;
}
export function chartSection(session) {
  return `<section class="stack">${powerChart(session)}${session.training == null ? calculationNote(session.result) : ''}${session.endReason && session.outcome !== 'interrupted' ? `<p class="warn">${esc(session.endReason)}</p>` : ''}</section>`;
}
function handoff(model, session) {
  const rider = riderOf(model, session), previous = session.configuration.priorFTP ?? rider?.ftpHistory.find(e => e.id === rider.currentFTPID)?.watts ?? null, r = session.result, example = retargetExample(previous, r.estimatedFTP);
  return `<section class="card stack" id="training-handoff"><p class="label accent-text">WHAT THIS CHANGES</p><h2>Library workouts now use ${Math.round(r.estimatedFTP)} W</h2>${example && example.oldWatts !== example.newWatts ? `<p class="num">${esc(example.text)}</p>` : ''}<p class="footnote">Warm-ups use 50 % of this FTP. Earlier rides keep the FTP they were made with.</p></section>`;
}

// ---- SLOT (export/upload plan): export controls and upload controls. Used by the result screen and the activity detail. ----
export function exportControls(model, session) {
  if (session.endedAtOffset == null || !session.samples.length) return '';
  return `<section class="stack" data-slot="export"><h3>Export</h3><div class="row">${['json', 'csv', 'tcx'].map(f => button(`${f.toUpperCase()} ↗`, { kind: 'secondary', small: true, action: `export-${f}`, extra: { 'data-session': session.id } })).join('')}</div></section>`;
}
export function exportSession(session, format) {
  const content = format === 'csv' ? csv(session) : format === 'tcx' ? tcx(session) : JSON.stringify(session, null, 2);
  download(content, `ftpunk-${session.isDemo ? 'debug-' : ''}${session.id}.${format}`, format === 'csv' ? 'text/csv' : format === 'tcx' ? 'application/vnd.garmin.tcx+xml' : 'application/json');
}
export function uploadControls(model, session) {
  const job = model.jobs.find(j => j.sessionID === session.id && j.accountID === model.connection?.id);
  return `<section class="stack" data-slot="upload"><button type="button" class="btn link" data-action="request-upload" data-session="${esc(session.id)}" ${job || model.busy ? 'disabled' : ''}>↑ ${job ? `Upload ${esc(job.status)}` : 'Upload to Intervals.icu…'}</button><p class="footnote">You will be asked to confirm the rider and account before anything is sent.</p></section>`;
}
export function requestUpload(model, session) {
  if (!model.connection) { navigate('#/settings'); notify('Connect Intervals.icu, then open the recording in Progress to approve its upload.'); return; }
  const connection = { ...model.connection };
  openSheet({ title: 'Upload this activity?', content: `<p>Your activity is already saved in this browser.</p><dl class="kv"><dt>Rider</dt><dd>${esc(session.configuration.riderName)}</dd><dt>Destination</dt><dd>${esc(connection.name)} · ${esc(connection.id)}</dd><dt>Recording</dt><dd>${esc(fmtDate(session.startedAt))}</dd></dl><p class="muted">This sends the activity, including the rider’s name, to this account. If the connection fails, the approved upload will queue for retry.</p>`,
    actions: '<button type="button" class="btn primary" data-dialog="upload">Approve &amp; upload ↗</button><button type="button" class="btn secondary" data-dialog="local">Keep local</button>',
    handler: async (action, dialog) => {
      if (action === 'local') return dialog.close();
      const approve = dialog.querySelector('[data-dialog="upload"]'); approve.disabled = true;
      try { await model.intervals.approve(session, connection.id); dialog.close(); await model.reload(); model.onChange(); const job = model.jobs.find(j => j.sessionID === session.id && j.accountID === connection.id); notify(job?.status === 'uploaded' ? 'Activity uploaded to Intervals.icu.' : `Upload saved for retry. ${job?.error ?? ''}`); }
      catch (error) { approve.disabled = false; throw error; }
    } });
}
export const exportActions = model => ({
  'export-json': el => exportSession(model.history.find(s => s.id === el.dataset.session) ?? model.ride.engine?.session, 'json'),
  'export-csv': el => exportSession(model.history.find(s => s.id === el.dataset.session) ?? model.ride.engine?.session, 'csv'),
  'export-tcx': el => exportSession(model.history.find(s => s.id === el.dataset.session) ?? model.ride.engine?.session, 'tcx'),
  'request-upload': el => requestUpload(model, model.history.find(s => s.id === el.dataset.session)),
  'info-estimate': () => openInfoSheet('estimate'),
});

registerRoute('result', {
  tab: 'home', documentTitle: () => 'Result',
  render(model) {
    const session = model.resultSession; if (!session) return `${screenHeader('Result', { back: '#/home' })}<p class="muted">Nothing to show.</p>`;
    const rider = riderOf(model, session), result = session.result, isFTP = !!result && session.training == null;
    const adopted = result ? isAdopted(rider, result, session.startedAt) : false, canUpload = !!model.connection && !session.isDemo && session.endedAtOffset != null;
    const sections = resultSections({ isFTPResult: isFTP, adopted: adopted && !session.isDemo, canUpload });
    const parts = { headline: () => headline(model, session), chart: () => chartSection(session), decision: () => `<p class="accent-text decision" id="ftp-adopted"><strong>✓ ${esc(session.configuration.riderName)}’s FTP is now ${Math.round(result.estimatedFTP)} W</strong></p>`, trainingHandoff: () => handoff(model, session), upload: () => uploadControls(model, session) };
    const canAdopt = isFTP && !session.isDemo && !adopted, current = rider?.ftpHistory.find(e => e.id === rider.currentFTPID)?.watts;
    const finishing = model.ride.finishing;
    return `<div class="stack-l result">${session.isDemo ? `<p>${pill('Debug · mock sensor data · never uploads', 'warning', '▶')}</p>` : ''}<p class="warn" id="result-finishing" ${finishing ? '' : 'hidden'}>⏳ Confirming trainer stop…</p>${sections.map(k => parts[k]()).join('')}${exportControls(model, session)}</div>
      <div class="action-bar result-actions">${canAdopt ? `${button(`Use ${Math.round(result.estimatedFTP)} W as ${esc(session.configuration.riderName)}’s FTP`, { kind: 'primary', block: true, action: 'adopt', disabled: model.busy || finishing, extra: { 'data-testid': 'adopt' } })}${button(current ? `Keep ${Math.round(current)} W` : 'Not now', { kind: 'secondary', block: true, action: 'done', disabled: finishing, extra: { 'data-testid': 'keep-ftp' } })}`
        : button(adopted && !session.isDemo ? 'Back to Home' : 'Done', { kind: 'primary', block: true, action: 'done', disabled: finishing, extra: { 'data-testid': 'done' } })}</div>`;
  },
  update(model) { const note = $('#result-finishing'); if (note) note.hidden = !model.ride.finishing; document.querySelectorAll('.result-actions button').forEach(b => { b.disabled = model.ride.finishing || (b.dataset.action === 'adopt' && model.busy); }); },
  actions: model => ({
    ...exportActions(model),
    adopt: async () => { const session = model.resultSession; await model.adopt(session); rerender(); },
    done: () => { model.closeResult(); navigate('#/home'); },
  }),
  /** After every finished ride that has a result or a workout: ask whether to upload it (never silent). */
  onRideSaved(model, session) { if (!session.isDemo && (session.result || session.training) && model.connection && !sheetIsOpen()) requestUpload(model, session); },
});
