import { esc, numberField, field, selectField, button, pill } from './components.mjs';
import { openSheet, closeSheet, registerGlobalAction, safely, fail, notify, refreshSheet } from './shell.mjs';
import { riderInitials } from '../rules/presentation.mjs';
import { POWER_MODES } from '../rules/preflight.mjs';
import { PRESETS } from '../domain.mjs';
import { DEVICE_LABELS } from '../bluetooth.mjs';
// Sheets shared by several screens: the rider sheet, the devices sheet, the ramp protocol chooser and the explanations.
// Owned by the foundation plan. Screens open them through global actions (open-riders, open-devices) or the functions below.

const done = '<button type="button" class="btn primary" data-dialog="close">Done</button>';
const close = (action, dialog) => dialog.close();

export function openRiderSheet(model) {
  const fromIntervals = false; // the Intervals.icu plan sets this when FTP and weight follow a linked account
  const content = () => {
    const rider = model.profile, busy = model.busy;
    const list = model.profiles.map(r => {
      const ftp = r.ftpHistory.find(e => e.id === r.currentFTPID);
      return `<button type="button" class="select-row" data-dialog="select:${esc(r.id)}" ${busy ? 'disabled' : ''} aria-pressed="${r.id === rider.id}"><span class="initials" aria-hidden="true">${esc(riderInitials(r.name))}</span><span class="grow"><strong>${esc(r.name)}</strong><br><span class="muted">${ftp ? `FTP ${Math.round(ftp.watts)} W` : 'No FTP yet'}</span></span>${r.id === rider.id ? '<span class="accent-text" aria-label="Selected">✓</span>' : ''}</button>`;
    }).join('');
    const history = rider.ftpHistory.length > 1 || rider.currentFTPID == null && rider.ftpHistory.length ? selectField('FTP used', 'sheet-ftp-used', [['none', 'No FTP'], ...rider.ftpHistory.map(e => [e.id, `${Math.round(e.watts)} W · ${new Date(e.date).toLocaleDateString(undefined, { dateStyle: 'medium' })}`])], rider.currentFTPID ?? 'none', { disabled: busy }) : '';
    return `<section class="stack"><h3>Riders</h3><div class="stack">${list}</div>
      <form class="row nowrap" id="add-rider-form"><label class="field grow"><span>New rider’s name</span><input id="sheet-new-name" maxlength="80" autocomplete="off"></label><button type="button" class="btn secondary" data-dialog="add" ${busy ? 'disabled' : ''}>Add</button></form></section>
      <section class="stack"><h3>Details</h3><div class="fields">${field('Name', 'sheet-name', rider.name, { maxlength: 80 })}${numberField('Weight, kg', 'sheet-weight', rider.weightKG ?? '', { step: '0.1', min: '1', placeholder: 'Optional' })}</div>
      <p class="footnote">Weight gives W/kg and picks the recommended ramp. Each rider keeps separate FTP and history.${fromIntervals ? ' From Intervals.icu · edit to override.' : ''}</p>${button('Save details', { kind: 'secondary', extra: { 'data-dialog': 'details' }, disabled: busy })}</section>
      <section class="stack"><h3>FTP</h3><dl class="kv"><dt>Current FTP</dt><dd>${model.ftp ? `${Math.round(model.ftp)} W` : 'Not set'}</dd></dl>${history}
      <div class="row nowrap">${numberField('New FTP, W', 'sheet-new-ftp', '', { min: '1', max: '32767', placeholder: 'Watts' })}<button type="button" class="btn secondary" data-dialog="ftp" ${busy ? 'disabled' : ''}>Save</button></div>
      <p class="footnote">Saving makes this the rider’s current FTP. Workouts and warm-ups use it. A test result is adopted from the result screen.</p></section>`;
  };
  const input = id => document.getElementById(id);
  openSheet({ title: 'Rider', content, actions: done, live: true, onChange: (event) => { if (event.target.id === 'sheet-ftp-used') void safely(() => model.chooseFTPEntry(event.target.value))(); },
    handler: async (action) => {
      if (action === 'close') return closeSheet();
      if (action.startsWith('select:')) { await model.selectRider(action.slice(7)); refreshSheet(); return; }
      if (action === 'add') { await model.addRider(input('sheet-new-name').value); refreshSheet(); return; }
      if (action === 'details') { await model.saveRiderDetails({ name: input('sheet-name').value, weight: input('sheet-weight').value }); notify('Rider details saved.'); refreshSheet(); return; }
      if (action === 'ftp') { await model.setCurrentFTP(input('sheet-new-ftp').value); input('sheet-new-ftp').value = ''; refreshSheet(); }
    } });
}

const SYMBOL = { trainer: 'T', externalPowerMeter: 'P', heartRate: '♥' };
const SUBTITLE = { trainer: 'Required to ride · connect to pick your trainer', externalPowerMeter: 'For power matching, or as the power source', heartRate: 'Heart rate on screen and in the file' };
const BADGE = { trainer: 'Required', externalPowerMeter: 'Optional', heartRate: 'Optional' };
/** One shared place for trainer, power meter and heart-rate connections (Home pill, pre-flight, Settings). */
export function openDevicesSheet(model) {
  const d = model.devices;
  const content = () => {
    if (model.demoMode) return `<div class="stack"><p>${pill('Mock sensor stream · never uploads', 'warning', '▶')}</p><p class="footnote">Mock sensors simulate a trainer, power, cadence and heart rate. No Bluetooth commands are sent. Turn them off in Settings → Debug.</p></div>`;
    const t = model.now(), rows = Object.keys(DEVICE_LABELS).map(role => {
      const device = d.devices[role], reading = d.measurements.fresh(role, role === 'heartRate' ? 'heartRate' : 'power', t, role === 'heartRate' ? 5 : 2);
      const status = device ? device.name + (device.ready ? (reading != null ? ` · ${Math.round(reading)} ${role === 'heartRate' ? 'bpm' : 'W'}` : ' · waiting for readings') : ' · connecting…') : SUBTITLE[role];
      return `<div class="device-row"><span class="initials ${device?.ready ? 'on' : ''}" aria-hidden="true">${SYMBOL[role]}</span><span class="grow"><strong>${esc(DEVICE_LABELS[role])}</strong> ${pill(BADGE[role], role === 'trainer' && !device ? 'warning' : 'neutral')}<br><span class="muted">${esc(status)}</span>${device?.notice ? `<br><span class="footnote warn">${esc(device.notice)}</span>` : ''}</span>${button(device ? 'Disconnect' : 'Connect', { kind: 'secondary', small: true, extra: { 'data-dialog': `${device ? 'disconnect' : 'connect'}:${role}` }, disabled: model.busy })}</div>`;
    }).join('');
    const meter = !!d.devices.externalPowerMeter;
    const power = meter ? selectField('Power source', 'sheet-power-mode', POWER_MODES, model.powerMode, { disabled: model.busy }) : '<p>Power: measured by the trainer</p>';
    return `<section class="stack"><h3>Connections</h3>${rows}${d.available ? '' : '<p class="notice">Live Bluetooth needs Chrome on localhost or HTTPS.</p>'}</section>
      <section class="stack"><h3>Measurement</h3>${power}<p class="footnote">Fixed when a ride starts. With an external meter, power matching makes the meter read the workout target; without one the trainer uses its own reading.</p>${button('About power matching', { kind: 'link', extra: { 'data-dialog': 'matching-info' } })}</section>
      <section class="stack"><h3>Trainer control</h3><p class="footnote">${d.trainerReady ? 'ERG control confirmed.' : d.devices.trainer ? 'Enabling trainer control…' : 'Connect a trainer to control it.'}</p>${d.range ? `<p class="footnote">Trainer: ${d.range.minimum}–${d.range.maximum} W · ${d.range.increment} W increments</p>` : ''}${d.resistanceRange ? `<p class="footnote">Resistance levels ${d.resistanceRange.minimum / 10}–${d.resistanceRange.maximum / 10}</p>` : ''}<p class="footnote">Keep this tab visible during a live ride. FTPunk releases trainer control if you leave the tab.</p></section>`;
  };
  openSheet({ title: 'Devices', content, actions: done, live: true,
    onChange: event => { if (event.target.id === 'sheet-power-mode') model.setPowerMode(event.target.value); },
    handler: (action) => {
      if (action === 'close') return closeSheet();
      if (action === 'matching-info') return openInfoSheet('powerMatching');
      const [verb, role] = action.split(':');
      if (verb === 'disconnect') { d.disconnect(role); if (role === 'externalPowerMeter') model.powerSource = 'trainer'; model.onChange(); return; }
      if (verb === 'connect') {
        // connect() must request the chooser synchronously inside this click, before its first await.
        const pairing = d.connect(role); model.onChange();
        return pairing.then(() => { refreshSheet(); model.onChange(); }, error => { model.onChange(); throw error; });
      }
    } });
}
/** The "Use power matching?" prompt after a power meter has paired. */
export function installMeterPrompt(model) {
  model.devices.onMeterReady = name => {
    if (model.busy) return;
    model.powerSource = 'externalPowerMeter';
    openSheet({ title: 'Use power matching?', content: `<p><strong>${esc(name)}</strong> is connected.</p><p>Power matching adjusts trainer resistance until this meter reads the workout target, or you can use the meter for recording only.</p><p class="footnote">Your choice is saved in Settings → Devices → Power source.</p>`,
      actions: '<button type="button" class="btn primary" data-dialog="yes">Use power matching</button><button type="button" class="btn secondary" data-dialog="no">Use meter for recording only</button>',
      handler: (choice, dialog) => { model.prefs.powerMatching = choice === 'yes'; model.savePrefs(); dialog.close(); } });
  };
}

export function openProtocolSheet(model) {
  const content = () => `<p class="muted">Recommended: ${esc(model.recommendedProtocol.reason)}</p><div class="stack">${Object.entries(PRESETS).sort(([a], [b]) => ['gentle', 'standard', 'zwift'].indexOf(a) - ['gentle', 'standard', 'zwift'].indexOf(b)).map(([key, p]) => `<button type="button" class="select-row" data-dialog="choose:${key}" aria-pressed="${model.draft.preset === key}"><span aria-hidden="true">${model.draft.preset === key ? '●' : '○'}</span><span class="grow"><strong>${esc(p.title)}</strong><br>Start at ${p.start} W · +${p.step} W every ${p.seconds} s<br><span class="muted">${esc(p.audience)}</span></span></button>`).join('')}</div>
    ${button('Which protocol, and why?', { kind: 'link', extra: { 'data-dialog': 'info' } })}${model.draft.presetChosen ? button('Use the recommendation', { kind: 'secondary', extra: { 'data-dialog': 'recommend' } }) : ''}`;
  openSheet({ title: 'Protocol', content, actions: done, live: true, handler: (action, dialog) => {
    if (action === 'close') return dialog.close();
    if (action === 'info') return openInfoSheet('protocols');
    if (action === 'recommend') { model.useRecommendedProtocol(); return dialog.close(); }
    if (action.startsWith('choose:')) { model.choosePreset(action.slice(7)); dialog.close(); }
  } });
}

const SOURCE = 'https://www.cyclecoach.com/blog/2020/2/2/is-the-map-ramp-test-a-valid-estimator-of-ftp';
const INFO = {
  protocols: { title: 'Ramp protocols', sections: [
    ['Which ramp should I choose?', ['15 W/min: a gentler ramp for lighter riders. The reference project’s weight guideline is below 60 kg. Start at 50 W and add 5 W every 20 seconds.', '25 W/min: the reference option for heavier riders (60 kg and above). Start at 100 W and add 5 W every 12 seconds.', '20 W/min · Zwift-style: the legacy option used by apps such as Zwift. Start at 100 W and add 20 W every 60 seconds. FTPunk keeps your chosen warm-up and its 72% estimate; this is not a reproduction of the entire Zwift workout.']],
    ['Why the 15 and 25 W protocols?', ['The reference follows coach Richard Stern’s MAP method. He recommended different ramp rates and the smallest practical increments, rather than one universal ramp. He argues that changing the protocol changes the MAP result and therefore the FTP estimate.', 'His original guidance distinguishes non-elite men (25 W/min), elite men (20 W/min), and women (15 W/min). The 60 kg light/heavy shortcut comes from this reference project. It is a practical guideline, not a universal physiological boundary. Choose manually and use the same protocol for comparisons.']],
    ['Warm-up', ['With an existing FTP, the default warm-up target is 50% of that value. Without one, the reference uses 75 W for the lighter protocol and 100 W for the heavier protocol. You can override the target.']]], link: [SOURCE, 'Richard Stern · MAP protocol and FTP'] },
  bestMinute: { title: 'Max power · 60 s', sections: [['Current max power over 60 seconds', ['The dashboard shows the highest time-weighted average from a complete, fresh 60-second power window during this ramp so far. Warm-up and cool-down never contribute.', 'No number is shown until a full minute of valid ramp data exists. Zeros count as real power; missing or stale readings do not. An earlier best minute stays on the dashboard even after power falls.', 'This is measured average power, not FTP. It is provisional during the ramp: the final calculation rechecks the scored window and excludes any low-cadence exhaustion confirmation period.']]] },
  estimate: { title: 'Why 72–77%?', sections: [
    ['An estimate, with a range', ['FTPunk takes the best continuous 60 seconds from your selected power source during the scored ramp as its MAP proxy. Warm-up, cooldown and any low-cadence confirmation period are excluded.', 'Stern reports that roughly one-hour power commonly fell between 72% and 77% of MAP in the riders he studied. This is a guideline range, not a personal confidence interval or a guarantee.', '75% became a common single-number estimate in training apps. Stern recommends 72% as a conservative starting point when a longer test is unavailable. Underestimating FTP is less harmful than overestimating it, so FTPunk always uses 72% for new tests and shows the 72–77% range. Recordings made with 75% in earlier versions keep and show their original factor.']],
    ['Example', ['A best minute of 300 W gives a range of 216–231 W. The 72% estimate is 216 W, the figure FTPunk reports. W/kg divides that estimate by the weight saved with that test.']],
    ['Use the result', ['Anaerobic contribution and endurance vary between riders. Check whether the estimate fits sustainable training efforts or compare it with a longer test. Keep the protocol and factor consistent when reviewing progress.']]], link: [SOURCE, 'Read Stern’s explanation'] },
  riders: { title: 'Riders', sections: [['', ['Each rider has their own FTP history, weight and recordings. Choose the rider from the chip on Home; the rider sheet manages the others.', 'An adopted test result updates the rider who took the test, even when someone else is selected.']]] },
  powerMatching: { title: 'Power matching', sections: [['', ['With an external power meter, power matching makes the meter read the workout target. A trainer’s own reading depends on when it was last calibrated, the room temperature and how warm it is, so FTPunk compares the trainer with your pedals during the ride.', 'It never makes a ramp harder when you fade. The choice is fixed when a ride starts, and without an external meter the trainer controls power using its own measurement.', 'For the best starting point, calibrate the trainer (spin-down in its own app) after about 10 minutes of riding. Validate the response at a low load before a maximal test.']]] },
  intervals: { title: 'Intervals.icu', sections: [['', ['Connecting lets FTPunk download your planned workouts for the next 14 days and, only after you confirm each time, upload a finished ride. The confirmation names the rider and the Intervals.icu account.', 'Your key stays in memory for this tab and is never included in a backup. Uploads never change your FTP, weight or wellness settings on Intervals.icu.']]] },
  privacy: { title: 'Your data', sections: [['', ['Riders, recordings and FTP history stay in this browser unless you approve an upload. Web, iPhone and Mac history are independent; backups move them by hand.', 'This is a hardware prototype: validate trainer control and Stop at a low load before a maximal test.']]] },
};
export function openInfoSheet(topic) {
  const info = INFO[topic]; if (!info) return;
  openSheet({ title: info.title, content: `${info.sections.map(([heading, paragraphs]) => `<section class="stack">${heading ? `<h3>${esc(heading)}</h3>` : ''}${paragraphs.map(p => `<p>${esc(p)}</p>`).join('')}</section>`).join('')}${info.link ? `<a href="${esc(info.link[0])}" target="_blank" rel="noopener noreferrer">${esc(info.link[1])} ↗</a>` : ''}`, actions: done, handler: close });
}
export const INFO_TOPICS = Object.keys(INFO);
let installed = null;
/** Registers the global actions every screen can use. Called once at start. */
export function installSheets(model) {
  if (installed === model) return; installed = model;
  registerGlobalAction('open-riders', () => openRiderSheet(model));
  registerGlobalAction('open-devices', () => openDevicesSheet(model));
  registerGlobalAction('open-info', el => openInfoSheet(el.dataset.topic));
  registerGlobalAction('open-protocols', () => openProtocolSheet(model));
  installMeterPrompt(model);
}
