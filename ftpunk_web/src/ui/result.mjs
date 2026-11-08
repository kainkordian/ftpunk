import { esc, $, button, linkButton, pill, screenHeader, fmtDate } from './components.mjs';
import { rideCharts, summaryCard } from './charts.mjs';
import { registerRoute, navigate, openSheet, sheetIsOpen, notify, rerender } from './shell.mjs';
import { openInfoSheet } from './sheets.mjs';
import { resultSections, resultDelta, interruptionSummary, isAdopted, averagePower, DurationFormat } from '../rules/presentation.mjs';
import { retargetExample } from '../catalog.mjs';
import { activityTitle, riderIDOf } from '../rules/progress.mjs';
import { download, exportFile, FORMATS, COROS_MINIMUM_BYTES } from '../export.mjs';
import { shouldPromptForUpload } from '../intervals.mjs';
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
    return `<section class="card accent stack"><h2 class="accent-text">✓ ${session.outcome === 'completed' ? 'Ride complete' : 'Ride saved'}</h2><p><strong>${esc(activityTitle(session))}</strong></p><div class="row stats"><div><p class="label">Time</p><p class="num big">${DurationFormat.clock(session.endedAtOffset ?? 0)}</p></div></div><p class="footnote">Saved in this browser.</p></section>`;
  }
  return `<section class="card stack"><h2>${esc(OUTCOMES[session.outcome] ?? 'Ride saved')}</h2><p class="muted">No FTP estimate. A valid, continuous 60-second ramp window is required, and the scored ramp must end by finishing or exhaustion.</p><p class="footnote">The recording is saved in this browser.</p></section>`;
}
export function chartSection(session) {
  return `<section class="stack">${rideCharts(session)}${summaryCard(session)}${session.training == null ? calculationNote(session.result) : ''}${session.endReason && session.outcome !== 'interrupted' ? `<p class="warn">${esc(session.endReason)}</p>` : ''}</section>`;
}
function handoff(model, session) {
  const rider = riderOf(model, session), previous = session.configuration.priorFTP ?? rider?.ftpHistory.find(e => e.id === rider.currentFTPID)?.watts ?? null, r = session.result, example = retargetExample(previous, r.estimatedFTP);
  return `<section class="card stack" id="training-handoff"><p class="label accent-text">WHAT THIS CHANGES</p><h2>Library workouts now use ${Math.round(r.estimatedFTP)} W</h2>${example && example.oldWatts !== example.newWatts ? `<p class="num">${esc(example.text)}</p>` : ''}<p class="footnote">Warm-ups use 50 % of this FTP. Earlier rides keep the FTP they were made with.</p></section>`;
}

// ---- Export and upload controls (plan 9b). Used by the result screen and the activity detail. ----
const FORMAT_ORDER = ['fit', 'tcx', 'csv', 'json'];
/** True where the browser can hand files to the system share sheet (Web Share API level 2). */
export function canShareFiles() {
  try { return typeof navigator.canShare === 'function' && typeof navigator.share === 'function' && navigator.canShare({ files: [new File(['x'], 'a.fit', { type: 'application/octet-stream' })] }); } catch { return false; }
}
export function exportControls(model, session) {
  if (session.endedAtOffset == null || !session.samples.length) return '';
  const share = canShareFiles(), data = { 'data-session': session.id };
  return `<section class="stack export-controls" data-slot="export"><h3>Export</h3>
    <div class="stack">${button('Export FIT file ↗', { kind: 'secondary', action: 'export-fit', extra: { ...data, 'data-testid': 'export-fit' } })}<p class="footnote">For COROS, Garmin, Strava and TrainingPeaks. Upload this file in their web app.</p></div>
    <div class="row">${['tcx', 'csv', 'json'].map(f => button(`${FORMATS[f].title} ↗`, { kind: 'secondary', small: true, action: `export-${f}`, extra: { ...data, 'data-testid': `export-${f}` } })).join('')}</div>
    ${share ? `<div class="row">${button('Share…', { kind: 'link', small: true, action: 'share-fit', extra: { ...data, 'aria-label': 'Share the FIT file' } })}</div>` : ''}</section>`;
}
/** Saves one format through a download link. A FIT file under 20 KB gets a note, because COROS may reject it. */
export function exportSession(session, format) {
  const { name, type, bytes } = exportFile(session, format);
  download(bytes, name, type);
  if (format === 'fit' && bytes.length < COROS_MINIMUM_BYTES) notify('COROS may reject files under 20 KB. If it does, export TCX instead.');
}
/** Hands one format to the system share sheet where the browser supports sharing files. */
export async function shareSession(session, format) {
  const { name, type, bytes } = exportFile(session, format), file = new File([bytes], name, { type });
  if (!canShareFiles() || !navigator.canShare({ files: [file] })) throw Error('This browser cannot share this file. Use the export button instead.');
  try { await navigator.share({ files: [file], title: name }); } catch (error) { if (error?.name !== 'AbortError') throw error; }
}
export function uploadControls(model, session) {
  const connection = model.connectionFor(riderIDOf(session));
  if (!connection) return `<section class="stack" data-slot="upload"><a class="btn link" href="#/settings" data-testid="connect-to-upload">Connect Intervals.icu to upload</a></section>`;
  const job = model.jobs.find(j => j.sessionID === session.id && j.accountID === connection.id);
  return `<section class="stack" data-slot="upload"><button type="button" class="btn link" data-action="request-upload" data-session="${esc(session.id)}" ${job || model.busy ? 'disabled' : ''}>↑ ${job ? `Upload ${esc(job.status)}` : 'Upload to Intervals.icu…'}</button><p class="footnote">You will be asked to confirm the rider and account before anything is sent.</p></section>`;
}
/** The consent dialog: names the rider and the destination account, offers Upload or Keep local, and never uploads by itself. */
export function requestUpload(model, session) {
  const riderName = session.configuration.riderName ?? 'You', connection = model.connectionFor(riderIDOf(session));
  if (!connection) { navigate('#/settings'); notify(`Connect Intervals.icu for ${riderName} (select the rider in Settings), then approve the upload.`); return; }
  openSheet({ title: 'Upload this activity?', content: `<p class="accent-text">✓ Activity saved in this browser</p><dl class="kv"><dt>Rider</dt><dd data-testid="upload-rider">${esc(riderName)}</dd><dt>Activity</dt><dd>${esc(fmtDate(session.startedAt))}</dd><dt>Intervals.icu account</dt><dd data-testid="upload-account">${esc(connection.name)}</dd></dl><p class="footnote">Account ID: ${esc(connection.id)}</p><p class="muted">This sends the activity, including the rider’s name, to this account. Check the destination when sharing FTPunk with another rider. If the connection fails, the approved upload will queue for retry.</p>`,
    actions: '<button type="button" class="btn primary" data-dialog="upload">Upload activity ↗</button><button type="button" class="btn secondary" data-dialog="local">Keep local · not now</button>',
    handler: async (action, dialog) => {
      if (action === 'local') return dialog.close();
      if (model.preview) { dialog.close(); notify('Preview mode: nothing is uploaded.'); return; }
      const approve = dialog.querySelector('[data-dialog="upload"]'); approve.disabled = true;
      try { await model.intervals.approve(session, connection.id); dialog.close(); await model.reload(); model.onChange(); const job = model.jobs.find(j => j.sessionID === session.id && j.accountID === connection.id); notify(job?.status === 'uploaded' ? 'Activity uploaded to Intervals.icu.' : `Upload saved for retry. ${job?.error ?? ''}`); model.onInvalidate(); }
      catch (error) { approve.disabled = false; throw error; }
    } });
}
const sessionFor = (model, el) => model.history.find(s => s.id === el.dataset.session) ?? model.ride.engine?.session;
export const exportActions = model => ({
  ...Object.fromEntries(FORMAT_ORDER.map(f => [`export-${f}`, el => exportSession(sessionFor(model, el), f)])),
  ...Object.fromEntries(FORMAT_ORDER.map(f => [`share-${f}`, el => shareSession(sessionFor(model, el), f)])),
  'request-upload': el => requestUpload(model, model.history.find(s => s.id === el.dataset.session)),
  'info-estimate': () => openInfoSheet('estimate'),
});

registerRoute('result', {
  tab: 'home', documentTitle: () => 'Result',
  render(model) {
    const session = model.resultSession; if (!session) return `${screenHeader('Result', { back: '#/home' })}<p class="muted">Nothing to show.</p>`;
    const rider = riderOf(model, session), result = session.result, isFTP = !!result && session.training == null;
    const adopted = result ? isAdopted(rider, result, session.startedAt) : false, connection = model.connectionFor(riderIDOf(session)), finished = !session.isDemo && session.endedAtOffset != null, canUpload = !!connection && finished;
    const sections = resultSections({ isFTPResult: isFTP, adopted: adopted && !session.isDemo, canUpload });
    const parts = { headline: () => headline(model, session), chart: () => chartSection(session), decision: () => `<p class="accent-text decision" id="ftp-adopted"><strong>✓ ${esc(session.configuration.riderName)}’s FTP is now ${Math.round(result.estimatedFTP)} W</strong></p>`, trainingHandoff: () => handoff(model, session), upload: () => uploadControls(model, session) };
    const canAdopt = isFTP && !session.isDemo && !adopted, current = rider?.ftpHistory.find(e => e.id === rider.currentFTPID)?.watts;
    const finishing = model.ride.finishing;
    return `<div class="stack-l result">${session.isDemo ? `<p>${pill('Debug · mock sensor data · never uploads', 'warning', '▶')}</p>` : ''}<p class="warn" id="result-finishing" ${finishing ? '' : 'hidden'}>⏳ Confirming trainer stop…</p>${sections.map(k => parts[k]()).join('')}${!connection && finished ? uploadControls(model, session) : ''}${exportControls(model, session)}</div>
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
  async onRideSaved(model, session) {
    try { if (!sheetIsOpen() && await shouldPromptForUpload(model, session) && !sheetIsOpen()) requestUpload(model, session); } catch (error) { notify(error?.message ?? String(error), true); }
  },
});
