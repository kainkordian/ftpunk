import { esc, button, linkButton, screenHeader, riderChip, devicesPill, numberField, field, $ } from './components.mjs';
import { registerRoute, navigate, hashFor, rerender } from './shell.mjs';
import { todaySection, librarySection, upcomingSection, myWorkoutsSection, libraryActions, libraryChips, libraryEvents } from './library.mjs';
import { deviceSummary, ftpStatusLine } from '../rules/presentation.mjs';
// Home: rider chip, Today, the FTP test card with retest advice, quick rides, the library, Upcoming and My workouts.
// The library sections live in library.mjs. Also the first-launch onboarding screen.

export function devicesSummary(model) {
  const d = model.devices;
  return deviceSummary({ mock: model.demoMode, trainerConnected: !!d.devices.trainer, trainerReady: d.trainerReady, powerSource: model.powerSource, externalMeterConnected: !!d.devices.externalPowerMeter?.ready, heartRateConnected: !!d.devices.heartRate?.ready });
}
export function ftpCard(model) {
  const entry = model.ftpEntry, rider = model.profile;
  if (!entry) return `<section class="card accent stack ftp-card"><h2>⚡ No FTP yet</h2><p class="muted">Take an FTP test so workouts fit you.</p>${linkButton('Take an FTP test', hashFor('preflight', 'ftpTest'), 'primary', { 'data-testid': 'ftp-test', 'aria-disabled': model.busy })}</section>`;
  const line = ftpStatusLine({ date: entry.date, isRamp: entry.source === 'Ramp test', source: entry.source }), wkg = rider.weightKG ? entry.watts / rider.weightKG : null;
  return `<section class="card accent stack ftp-card"><p class="label">FTP</p><p class="row ftp-figures"><span class="big num">${Math.round(entry.watts)} W</span>${wkg ? `<span class="muted num">${wkg.toFixed(2)} W/kg</span>` : ''}</p>
    <p class="${line.isRetestPrompt ? 'warn retest' : 'muted'}" id="${line.isRetestPrompt ? 'retest-due' : 'ftp-age'}"><span aria-hidden="true">${line.isRetestPrompt ? '↻' : '▦'}</span> ${esc(line.text)}</p>${linkButton('FTP test', hashFor('preflight', 'ftpTest'), 'secondary', { 'data-testid': 'ftp-test', 'aria-disabled': model.busy })}</section>`;
}
function quickRides(model) {
  const resistanceReason = model.resistanceRange ? null : model.devices.devices.trainer ? 'Trainer doesn’t advertise resistance' : 'Connect your trainer first';
  const tile = (title, symbol, kind, reason) => `<a class="quick-tile ${reason || model.busy ? 'disabled' : ''}" href="${hashFor('preflight', kind)}" ${reason || model.busy ? 'aria-disabled="true"' : ''} ${reason ? `aria-label="${esc(title)}. ${esc(reason)}"` : ''}><span class="symbol" aria-hidden="true">${symbol}</span><strong>${esc(title)}</strong>${reason ? `<small>${esc(reason)}</small>` : ''}</a>`;
  return `<section class="stack" id="quick-rides"><h2>Quick ride</h2><div class="quick-grid">${tile('Free ERG', '⚡', 'freeERG', null)}${tile('Resistance', '◔', 'resistance', resistanceReason)}</div></section>`;
}
registerRoute('home', {
  tab: 'home', documentTitle: () => 'Home',
  render(model) {
    const first = !model.ftpEntry;
    return `${screenHeader('Home', { left: riderChip(model.profile.name), right: devicesPill(devicesSummary(model)) })}<div class="stack-l">${first ? ftpCard(model) : ''}<div id="home-today">${todaySection(model)}</div>${first ? '' : ftpCard(model)}${quickRides(model)}${librarySection(model)}${upcomingSection(model)}${myWorkoutsSection(model)}</div>`;
  },
  bind(root, model) { void model.refreshCalendarIfNeeded(); },
  update(model) {
    const pill = $('.devices-pill'); if (!pill) return; const next = document.createElement('div'); next.innerHTML = devicesPill(devicesSummary(model));
    if (pill.outerHTML !== next.firstElementChild.outerHTML) pill.replaceWith(next.firstElementChild);
  },
  actions: model => ({ ...libraryActions(model) }),
  chips: model => ({ ...libraryChips(model) }),
  events: model => ({ ...libraryEvents(model) }),
});

// ----- first launch ----------------------------------------------------------------------------------------------------------------
registerRoute('onboarding', {
  documentTitle: () => 'Set up',
  render() {
    return `<div class="onboarding stack-l"><header class="stack"><h1>Welcome to FTPunk</h1><p class="muted">A few details make workouts fit you. Everything stays in this browser.</p></header>
      <form id="onboarding-form" class="card stack" novalidate>${field('Your name', 'onboarding-name', '', { maxlength: 80, autocomplete: 'name', required: true })}<div class="fields">${numberField('Weight, kg', 'onboarding-weight', '', { step: '0.1', min: '1', placeholder: 'Optional' })}${numberField('FTP, watts', 'onboarding-ftp', '', { min: '1', max: '32767', placeholder: 'If you know it' })}</div>
      <p class="footnote">Weight gives W/kg and picks the recommended ramp. Not sure of your FTP? The FTP test will find it.</p><p class="notice error" id="onboarding-error" role="alert" hidden></p>
      <div class="stack">${button('Continue →', { kind: 'primary', block: true, action: 'onboarding-continue', extra: { 'data-testid': 'onboarding-continue' } })}${button('Not sure of my FTP: take the FTP test', { kind: 'secondary', block: true, action: 'onboarding-test', extra: { 'data-testid': 'onboarding-take-test' } })}${button('Skip for now', { kind: 'tertiary', block: true, action: 'onboarding-skip', extra: { 'data-testid': 'onboarding-skip' } })}</div></form></div>`;
  },
  actions: model => {
    const values = withFTP => ({ name: $('#onboarding-name').value, weight: $('#onboarding-weight').value, ftp: withFTP ? $('#onboarding-ftp').value : '' });
    const finish = async (withFTP, thenTest) => {
      const result = await model.completeOnboarding(values(withFTP), thenTest), error = $('#onboarding-error');
      if (!result.ok) { error.hidden = false; error.textContent = result.error; return; }
      navigate(thenTest ? hashFor('preflight', 'ftpTest') : '#/home', { replace: false }); rerender();
    };
    return { 'onboarding-continue': () => finish(true, false), 'onboarding-test': () => finish(false, true), 'onboarding-skip': async () => { await model.skipOnboarding(); navigate('#/home'); rerender(); } };
  },
  events: model => ({ submit: { 'onboarding-form': () => $('[data-action="onboarding-continue"]').click() } }),
});
