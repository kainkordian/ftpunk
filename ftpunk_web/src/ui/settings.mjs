import { esc, $, button, segmented, switchRow, pill, screenHeader, selectField } from './components.mjs';
import { registerRoute, rerender, confirmSheet, openSheet, notify, fail, safely, closeSheet } from './shell.mjs';
import { openInfoSheet } from './sheets.mjs';
import { parseArchive, archiveText, MAX_ARCHIVE_BYTES } from '../archive.mjs';
import { acquireRideLease } from '../storage.mjs';
import { download } from '../export.mjs';
import { DEVICE_LABELS } from '../bluetooth.mjs';
// Settings: riders, devices, ride display, Intervals.icu, backup and transfer, debug (hidden until unlocked from About) and About.
// The Intervals.icu group is the slot of the Intervals.icu plan; other features add controls to "Ride display" with `registerSettingsSlot`.

export const VERSION_LABEL = 'FTPunk for Chrome · v0.2';
export const CREDITS = 'Created by Kordian Gontarska · Developed with OpenAI Codex and Anthropic Claude';
const slots = { rideDisplay: [] };
/** `registerSettingsSlot('rideDisplay', model => html)`: extra rows at the end of a settings group. */
export const registerSettingsSlot = (name, fn) => (slots[name] ??= []).push(fn);
let aboutTaps = 0;

const group = (id, title, body, footer = '') => `<section class="card stack settings-group" id="settings-${id}"><h2>${esc(title)}</h2>${body}${footer ? `<p class="footnote">${esc(footer)}</p>` : ''}</section>`;
const learn = topic => button('ⓘ Learn more', { kind: 'link', action: 'open-info', extra: { 'data-topic': topic } });

function riders(model) {
  return group('riders', 'Riders', `<dl class="kv">${model.profiles.map(r => { const ftp = r.ftpHistory.find(e => e.id === r.currentFTPID); return `<dt>${esc(r.name)}</dt><dd>${ftp ? `FTP ${Math.round(ftp.watts)} W` : 'No FTP yet'}</dd>`; }).join('')}</dl>${button('Manage riders…', { kind: 'secondary', action: 'open-riders' })}${learn('riders')}`, 'Each rider keeps separate FTP, weight and history.');
}
function devices(model) {
  const d = model.devices;
  const rows = model.demoMode ? `<p>${pill('Mock sensor stream · never uploads', 'warning', '▶')}</p>` : Object.keys(DEVICE_LABELS).map(role => { const dev = d.devices[role]; return `<div class="row spread"><span><strong>${esc(DEVICE_LABELS[role])}</strong> ${pill(role === 'trainer' ? 'Required' : 'Optional', role === 'trainer' && !dev ? 'warning' : 'neutral')}<br><span class="muted">${esc(dev ? dev.name + (dev.ready ? (role === 'trainer' ? ' · ERG ready' : '') : ' · connecting…') : role === 'trainer' ? 'Required to ride · not connected' : 'Not connected')}</span></span><span class="light ${dev?.ready ? 'ready' : role === 'trainer' ? 'attention' : ''}" aria-hidden="true">${dev?.ready ? '✓' : '·'}</span></div>`; }).join('');
  return group('devices', 'Devices', `${rows}${button('Measurement & trainer control…', { kind: 'secondary', action: 'open-devices' })}${learn('powerMatching')}`, 'A smart trainer with ERG control is required. A power meter and a heart rate monitor are optional.');
}
function rideDisplay(model) {
  return group('ride-display', 'Ride display', `<div class="field"><span>Theme</span>${segmented([['system', 'System'], ['light', 'Light'], ['dark', 'Dark']], model.prefs.appearance, 'Theme')}</div>${switchRow('Extra-large ride numbers', 'st-extra-large', model.prefs.extraLarge)}${slots.rideDisplay.map(fn => fn(model)).join('')}`, 'Numbers follow your browser text size; extra-large is easier to read from the bike. Reduced motion and increased contrast are supported.');
}
// ---- SLOT (Intervals.icu plan): the whole group below is replaced by the per-rider connection, upload prompt toggle and sync. ----
function intervals(model) {
  const c = model.intervals.connection, jobs = model.jobs;
  const body = c ? `<div class="card accent stack"><strong>${esc(c.name)}</strong><span class="footnote">Account ${esc(c.id)} · connected for this tab</span></div><p class="muted">Every new upload asks you to confirm the rider and destination. Approved queued uploads retry while this tab is connected and online.</p><div class="row">${button('Retry approved uploads', { kind: 'secondary', action: 'retry-uploads' })}${button('Disconnect', { kind: 'danger', action: 'disconnect-intervals' })}</div>`
    : `<p class="muted">Connect with a personal API key from Intervals.icu → Settings → Developer settings. Your key stays in memory for this tab and is never included in a backup.</p><form id="intervals-form" class="stack"><label class="field"><span>Personal API key</span><input type="password" id="api-key" autocomplete="off" required spellcheck="false" placeholder="Your key"></label>${button('Connect account ↗', { kind: 'primary', action: 'connect-intervals' })}</form><a class="btn link" href="https://intervals.icu/settings" target="_blank" rel="noopener noreferrer">Open Intervals.icu settings ↗</a>`;
  return group('intervals', 'Intervals.icu', `${body}${jobs.length ? `<h3>Upload queue</h3>${jobs.map(j => `<p class="row spread"><span>${esc(j.accountName)} · ${esc(j.status)}</span><small class="muted">${esc(j.error ?? '')}</small></p>`).join('')}` : ''}${learn('intervals')}`, 'Rides are saved locally first. Every upload asks you to confirm the rider and account. Debug rides never upload.');
}
function backup(model) {
  return group('backup', 'Backup & transfer', `<p class="muted">Riders and recordings live in this browser. No automatic cloud sync. Use a portable backup to transfer history to a Mac or iPhone. Imports replace matching rider identities after review.</p><div class="row">${button('Export portable backup ↗', { kind: 'secondary', action: 'backup', disabled: model.busy })}${button('Import backup…', { kind: 'secondary', action: 'import', disabled: model.busy })}${button('Download pre-import backup', { kind: 'link', action: 'rollback' })}</div><input type="file" id="archive-file" aria-label="Backup file" accept=".json,application/json" hidden>`);
}
function debug(model) {
  const d = model.devices;
  return group('debug', '▶ Debug', `${switchRow('Mock sensors · no cycling devices', 'st-mock', model.demoMode, { disabled: model.busy })}${button('Hide debug tools', { kind: 'secondary', action: 'hide-debug', disabled: model.busy })}
    <details><summary>Bluetooth diagnostics</summary><div class="stack details-body">${switchRow('Capture Bluetooth packets', 'st-capture', d.captureEnabled, { hint: 'Latest 500 packets, in memory only.' })}${selectField('Trainer resistance field', 'st-resistance-layout', [['standard', 'Standard · 1 byte'], ['legacy', 'Reference layout · 2 bytes']], d.legacyResistance ? 'legacy' : 'standard', { disabled: model.busy })}<p class="footnote">Use the standard layout unless a packet capture confirms the reference layout.</p>${button('Download packet capture ↗', { kind: 'link', action: 'capture' })}</div></details>`, 'Mock rides are marked as debug recordings and never upload. Sensor mode stays fixed while a ride is running.');
}
function about(model) {
  const unlocked = model.prefs.debugUnlocked;
  return group('about', 'About', `<button type="button" class="about-button card accent" data-action="about-tap" aria-label="About FTPunk. ${esc(VERSION_LABEL)}. ${esc(CREDITS)}. ${unlocked ? 'Debug tools are enabled.' : `${10 - aboutTaps} activations remaining to unlock debug tools.`}"><strong>FTPunk</strong><span>${esc(VERSION_LABEL)}</span><span class="footnote">${esc(CREDITS)}</span>${unlocked ? '<span class="footnote">▶ Debug tools enabled</span>' : aboutTaps >= 3 ? `<span class="footnote">${10 - aboutTaps} more taps to enable debug tools</span>` : ''}</button>
    ${['protocols', 'estimate', 'bestMinute'].map(t => button({ protocols: 'ⓘ Ramp protocols and rider guidelines', estimate: '% Understanding the 72–77 % estimate', bestMinute: '⏱ Live max power over 60 seconds' }[t], { kind: 'link', action: 'open-info', extra: { 'data-topic': t } })).join('')}${learn('privacy')}`, 'Local by default: nothing leaves this browser unless you approve an upload.');
}
registerRoute('settings', {
  tab: 'settings', documentTitle: () => 'Settings',
  render(model) { return `${screenHeader('Settings')}<div class="stack-l">${riders(model)}${devices(model)}${rideDisplay(model)}${intervals(model)}${backup(model)}${model.prefs.debugUnlocked ? debug(model) : ''}${about(model)}</div>`; },
  actions: model => ({
    'about-tap': () => { if (model.prefs.debugUnlocked) return; aboutTaps++; if (aboutTaps >= 10) { model.prefs.debugUnlocked = true; if (!model.busy) model.demoMode = true; model.savePrefs(); } rerender(); },
    'hide-debug': () => { if (model.busy) return; model.demoMode = false; model.prefs.debugUnlocked = false; aboutTaps = 0; model.savePrefs(); rerender(); },
    backup: () => model.exportBackup(),
    import: () => { if (!model.busy) $('#archive-file').click(); },
    rollback: async () => { const backups = (await model.store.all('backups')).sort((a, b) => b.createdAt.localeCompare(a.createdAt)); if (!backups.length) throw Error('There is no pre-import backup yet.'); download(archiveText(backups[0].archive), 'ftpunk-before-import.json'); },
    capture: () => download(JSON.stringify(model.devices.captures, null, 2), 'ftpunk-bluetooth-capture.json'),
    'connect-intervals': () => connectIntervals(model),
    'disconnect-intervals': () => { model.intervals.disconnect(); rerender(); notify('Disconnected. Reconnect to retry previously approved queued uploads.'); },
    'retry-uploads': async () => { await model.intervals.flush(true); await model.reload(); rerender(); notify('Approved upload retries finished. See the queue for status.'); },
  }),
  chips: model => ({ Theme: value => { model.prefs.appearance = value; model.savePrefs(); rerender(); } }),
  events: model => ({
    change: {
      'st-extra-large': el => { model.prefs.extraLarge = el.checked; model.savePrefs(); },
      'st-mock': el => { if (model.busy) { el.checked = model.demoMode; return; } model.demoMode = el.checked; model.onChange(); },
      'st-capture': el => { model.devices.captureEnabled = el.checked; }, 'st-resistance-layout': el => { model.devices.legacyResistance = el.value === 'legacy'; },
      'archive-file': async input => { const file = input.files[0]; input.value = ''; if (file) await reviewImport(model, file); },
    },
    submit: { 'intervals-form': () => connectIntervals(model) },
  }),
});
async function connectIntervals(model) {
  const input = $('#api-key'), key = input.value; if (!key.trim()) throw Error('Enter your personal API key.'); input.value = '';
  await model.intervals.connect(key); await model.intervals.flush(); await model.reload(); rerender(); notify('Intervals.icu connected for this tab.');
}
/** Review an imported backup: names the riders and what is replaced, saves a local backup first, then replaces matching riders only. */
async function reviewImport(model, file) {
  if (file.size > MAX_ARCHIVE_BYTES) throw Error('The archive exceeds the 64 MB import limit.');
  const archive = parseArchive(await file.text());
  openSheet({ title: 'Import these riders?', content: `<p><strong>${archive.profiles.map(p => esc(p.name)).join(', ')}</strong></p><p>${archive.activities.length} recordings, ${archive.workouts?.length ?? 0} cached workouts. Local history and workout library for these rider identities will be replaced, not merged. Other riders stay unchanged. A local backup is saved first.</p><p>Credentials and upload approvals are not transferred. Existing remote uploads are not deleted.</p>`,
    actions: '<button type="button" class="btn secondary" data-dialog="cancel">Cancel</button><button type="button" class="btn primary" data-dialog="import">Import and replace matching riders</button>',
    handler: async (action, dialog) => {
      if (action === 'cancel') return dialog.close();
      if (model.busy || model.intervals.busy || model.downloading) throw Error('Wait for the ride or upload to finish before importing.');
      const resume = model.intervals.suspendUploads(); let release;
      try { release = await acquireRideLease(); await model.store.restore(archive); model.ride.engine = null; await model.reload(); model.prefs.selectedRider = model.profile.id; model.savePrefs(); dialog.close(); rerender(); notify('Backup imported. The previous local data is available under Download pre-import backup.'); }
      finally { release?.(); resume(); }
    } });
}
