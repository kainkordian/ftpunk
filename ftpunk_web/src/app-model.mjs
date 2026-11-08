import { uuid, PRESETS } from './domain.mjs';
import { BluetoothDevices } from './bluetooth.mjs';
import { RideController } from './controller.mjs';
import { IntervalsClient, startIntervals, syncAthleteIfNeeded } from './intervals.mjs';
import { LocalStore, acquireRideLease, loadPreferences, savePreferences } from './storage.mjs';
import { freeRide, resistanceRide } from './training.mjs';
import { importWorkout, MAX_WORKOUT_BYTES, ScheduledDate } from './workouts.mjs';
import { definition, planFor, categoryTitle } from './catalog.mjs';
import { download } from './export.mjs';
import { archiveText } from './archive.mjs';
import { startBlocker, recommendProtocol, blockerReason, BLOCKER_TEXT, shouldPresentResult } from './rules/presentation.mjs';
import { currentFTP, parseOnboarding, shouldRefresh, staleEntries, isFromIntervals } from './rules/home.mjs';
import { buildConfiguration, defaultDraft, durationsValid, targetsInRange, powerModeSettings, resolvePowerMode } from './rules/preflight.mjs';

/** The state the screens read and the actions they call. No DOM: the shell wires `onChange`, `onNotice` and `onPreferences`.
    Later features add their own state in their own modules and reach the app through `model` (see `workoutResolvers`, `hooks`). */
export class AppModel {
  constructor({ store, devices = new BluetoothDevices(), prefs = loadPreferences(), preview = false, now = () => performance.now() / 1000, lease = acquireRideLease, rideOptions = {} } = {}) {
    this.lease = lease;
    Object.assign(this, { store, devices, prefs, preview, now });
    this.profiles = []; this.history = []; this.workouts = []; this.jobs = [];
    this.draft = defaultDraft(); this.powerSource = 'trainer'; this.demoMode = false; this.onboardingPending = false;
    this.workoutResolvers = new Map(); // ref prefix ('classic', 'cached', ...) -> (id, model) => detail | null. Plans add their own prefix.
    this.hooks = { saved: [] };        // saved: [(session) => void] run after a recording is saved and history is reloaded
    this.libraryCategory = null; this.downloading = false; this.importReport = null; this.resultSessionID = null; this.lastPhase = null;
    this.onChange = () => {}; this.onInvalidate = () => {}; this.onNotice = () => {}; this.onPreferences = () => {};
    this.intervals = new IntervalsClient(store, { selectedRider: () => this.profile?.id ?? null });
    this.ride = new RideController(devices, store, { now, lease, ...rideOptions });
    this.ride.autoPauseEnabled = this.prefs.autoPause !== false;
    this.ride.onError = error => this.fail(error);
    this.ride.onChange = () => this.onChange();
    this.ride.onSaved = session => { void (async () => { await this.reload(); this.invalidate(); for (const hook of this.hooks.saved) await hook(session); })().catch(error => this.fail(error)); };
    this.devices.onChange = () => this.onChange();
    this.workoutResolvers.set('classic', id => this.classicDetail(id)); this.workoutResolvers.set('cached', id => this.cachedDetail(id));
  }
  /** Something the screen shows has changed (data, not a ride tick): `onChange` updates live numbers, `onInvalidate` re-renders the screen. */
  invalidate() { this.onChange(); this.onInvalidate(); }
  // ----- notices -------------------------------------------------------------------------------------------------------------------
  notify(message, error = false) { this.onNotice(message, error); }
  fail(error) { if (error?.name === 'NotFoundError') return; this.notify(error?.message ?? String(error), true); }
  savePrefs() { this.ride.autoPauseEnabled = this.prefs.autoPause !== false; try { if (!this.preview) savePreferences(this.prefs); } catch { this.notify('Preferences could not be saved. Check browser storage permissions.', true); } this.onPreferences(); this.onChange(); }
  // ----- riders --------------------------------------------------------------------------------------------------------------------
  get profile() { return this.profiles.find(p => p.id === this.prefs.selectedRider) ?? this.profiles[0] ?? null; }
  get ftpEntry() { return currentFTP(this.profile); }
  /** The FTP the library, warm-ups and tests use: the rider's current entry, or null. */
  get ftp() { return this.ftpEntry?.watts ?? null; }
  get busy() { return this.ride.busy; }
  async reload() {
    this.workouts = await this.store.all('workouts'); this.profiles = await this.store.all('profiles'); this.jobs = await this.store.all('jobs');
    this.history = (await this.store.all('sessions')).sort((a, b) => b.startedAt.localeCompare(a.startedAt));
    if (this.profile && this.prefs.selectedRider !== this.profile.id) { this.prefs.selectedRider = this.profile.id; }
  }
  async selectRider(id) { if (this.busy || !this.profiles.some(p => p.id === id)) return; this.prefs.selectedRider = id; this.draft.presetChosen = false; this.applyRecommendation(); this.savePrefs(); this.onInvalidate(); }
  async addRider(name) {
    const clean = String(name).trim();
    if (!clean || [...clean].length > 80) throw Error('Enter a rider name, up to 80 characters.');
    if (this.profiles.some(p => p.name.toLocaleLowerCase() === clean.toLocaleLowerCase())) throw Error('That rider already exists. Choose a distinct name.');
    const rider = { id: uuid(), name: clean, weightKG: null, ftpHistory: [], currentFTPID: null };
    await this.store.put('profiles', rider); await this.reload(); await this.selectRider(rider.id); return rider;
  }
  async saveRiderDetails({ name, weight }) {
    const rider = this.profile, clean = String(name).trim(), kg = String(weight).trim() === '' ? null : Number(String(weight).replace(',', '.'));
    if (!clean || [...clean].length > 80) throw Error('Enter a rider name, up to 80 characters.');
    if (this.profiles.some(p => p.id !== rider.id && p.name.toLocaleLowerCase() === clean.toLocaleLowerCase())) throw Error('That rider already exists. Choose a distinct name.');
    if (kg != null && (!Number.isFinite(kg) || kg <= 0 || kg > 500)) throw Error('Weight must be a positive number in kg.');
    await this.store.put('profiles', { ...rider, name: clean, weightKG: kg }); await this.reload(); this.applyRecommendation(); this.invalidate();
  }
  /** Saving makes this the rider's current FTP. A test result is adopted from the result screen. */
  async setCurrentFTP(value, source = 'Manual') {
    const watts = Number(String(value).replace(',', '.'));
    if (this.busy) throw Error('Finish the current ride before changing FTP.');
    if (!Number.isFinite(watts) || watts <= 0 || watts > 32767) throw Error('FTP must be a positive number, up to 32767 W.');
    const rider = structuredClone(this.profile), entry = { id: uuid(), watts, date: new Date().toISOString(), source };
    rider.ftpHistory.unshift(entry); rider.currentFTPID = entry.id; await this.store.put('profiles', rider); await this.reload(); this.invalidate();
  }
  async chooseFTPEntry(id) {
    if (this.busy) throw Error('Finish the current ride before changing FTP.');
    const rider = structuredClone(this.profile); if (id !== 'none' && !rider.ftpHistory.some(e => e.id === id)) return;
    rider.currentFTPID = id === 'none' ? null : id; await this.store.put('profiles', rider); await this.reload(); this.invalidate();
  }
  /** First launch: a name, optional weight, and FTP if known. Returns the parse result (ok false leaves onboarding open). */
  async completeOnboarding(input, thenTest = false) {
    const parsed = parseOnboarding(input); if (!parsed.ok) return parsed;
    const entry = parsed.ftp ? { id: uuid(), watts: parsed.ftp, date: new Date().toISOString(), source: 'Manual' } : null;
    const rider = { id: uuid(), name: parsed.name, weightKG: parsed.weightKG, ftpHistory: entry ? [entry] : [], currentFTPID: entry?.id ?? null };
    await this.store.put('profiles', rider); await this.reload(); this.prefs.selectedRider = rider.id; this.onboardingPending = false; this.applyRecommendation(); this.savePrefs();
    return { ...parsed, thenTest };
  }
  async skipOnboarding() { if (!this.profiles.length) { await this.store.put('profiles', { id: uuid(), name: 'You', weightKG: null, ftpHistory: [], currentFTPID: null }); await this.reload(); } this.onboardingPending = false; this.savePrefs(); }
  // ----- pre-flight ------------------------------------------------------------------------------------------------------------------
  get recommendedProtocol() { return recommendProtocol(this.profile?.weightKG); }
  applyRecommendation() { if (!this.draft.presetChosen) this.draft.preset = this.recommendedProtocol.preset; }
  choosePreset(preset) { if (PRESETS[preset]) { this.draft.preset = preset; this.draft.presetChosen = true; this.invalidate(); } }
  useRecommendedProtocol() { this.draft.presetChosen = false; this.applyRecommendation(); this.invalidate(); }
  get powerMode() { return resolvePowerMode(this.powerSource, this.prefs.powerMatching, !!this.devices.devices.externalPowerMeter); }
  setPowerMode(mode) { const { powerSource, matching } = powerModeSettings(mode, this.prefs.powerMatching); this.powerSource = powerSource; this.prefs.powerMatching = matching; this.savePrefs(); }
  get powerMatching() { return this.powerSource === 'externalPowerMeter' && this.prefs.powerMatching; }
  cadenceSource() { return this.demoMode ? (this.draft.scenario === 'cadenceDropout' ? 'trainer' : this.powerSource) : this.devices.measurements.cadenceSource(this.powerSource, this.now()); }
  /** The readiness of the rider's setup for a kind of ride ('ftpTest' | 'freeERG' | 'resistance' | 'workout'), as StartReadiness. */
  readiness(kind, { plan = null, needsFTP = false } = {}) {
    const d = this.devices, t = this.now();
    return { kind, isMock: this.demoMode, isBusy: this.ride.starting || this.ride.active, isFinishing: this.ride.finishing, bluetoothAvailable: d.available, trainerConnected: !!d.devices.trainer, trainerControlReady: d.trainerReady,
      powerRangeKnown: !!d.range, powerSource: this.powerSource, freshSelectedPower: d.measurements.fresh(this.powerSource, 'power', t) != null, supportsResistance: !!d.resistanceRange,
      durationsValid: durationsValid(this.draft, { mock: this.demoMode }), needsFTP, targetsInRange: targetsInRange(plan, this.draft.intensity, d.range) };
  }
  startBlocker(kind, options) { return startBlocker(this.readiness(kind, options)); }
  get resistanceRange() { return this.devices.resistanceRange ?? (this.demoMode ? { minimum: 0, maximum: 1000, increment: 10, quantized: n => Math.min(1000, Math.max(0, Math.round(n / 10) * 10)) } : null); }
  testConfiguration(training = null) {
    return buildConfiguration({ draft: this.draft, rider: this.profile, ftp: this.ftp, powerSource: this.powerSource, cadenceSource: this.cadenceSource(), powerMatching: this.powerMatching && !(training?.resistance != null), mock: this.demoMode, training });
  }
  async begin(kind, training = null, intensity = 100) {
    const blocker = this.startBlocker(kind, { plan: training, needsFTP: false });
    if (blocker && blocker !== 'busy') throw Error(blockerReason(blocker));
    if (this.ride.busy) return false;
    const config = this.testConfiguration(training);
    this.resultSessionID = null;
    await this.ride.start(config, { demo: this.demoMode, speed: Number(this.draft.speed), scenario: this.draft.scenario, training, intensity });
    if (this.ride.active) { this.draft.intensity = 100; return true; }
    return false;
  }
  startFTPTest() { return this.begin('ftpTest'); }
  startFreeRide() { return this.begin('freeERG', freeRide(this.draft.freeWatts)); }
  startResistance() {
    const range = this.resistanceRange; if (!range) throw Error(BLOCKER_TEXT.resistanceUnsupported);
    return this.begin('resistance', resistanceRide(range.quantized(this.draft.resistance)));
  }
  async startWorkout(ref) {
    const detail = this.workoutDetail(ref);
    if (!detail) throw Error('This workout was removed.');
    if (detail.needsFTP) throw Error(BLOCKER_TEXT.needsFTP);
    return this.begin('workout', detail.plan, this.draft.intensity);
  }
  cancelStart() { this.ride.stop(); }
  // ----- workouts ----------------------------------------------------------------------------------------------------------------------
  /** `ref` is "classic:<id>", "cached:<id>", or another registered prefix. Returns { ref, title, category, source, duration, plan, previewPlan, needsFTP, cached?, custom? } or null. */
  workoutDetail(ref) { const i = String(ref).indexOf(':'); const resolver = this.workoutResolvers.get(String(ref).slice(0, i)); return resolver ? resolver(String(ref).slice(i + 1), this) : null; }
  classicDetail(id) {
    const def = definition(id); if (!def) return null;
    const ftp = this.ftp, plan = ftp ? planFor(def, ftp) : null;
    // Without an FTP the preview is drawn at a reference level with no FTP, so bars are neutral and no watts are shown.
    const previewPlan = plan ?? { ...planFor(def, 100), ftpWatts: null };
    return { ref: `classic:${id}`, title: def.name, category: def.category, categoryTitle: categoryTitle(def.category), source: null, duration: def.duration, plan, previewPlan, needsFTP: !plan };
  }
  cachedDetail(id) {
    const record = this.workouts.find(w => w.id === id && w.riderID === this.profile?.id); if (!record) return null;
    return { ref: `cached:${id}`, title: record.plan.name, category: null, categoryTitle: null, source: isFromIntervals(record) ? 'Intervals.icu' : 'Imported', duration: record.plan.steps.reduce((n, s) => n + s.seconds, 0), plan: record.plan, previewPlan: record.plan, needsFTP: false, cached: record };
  }
  async importWorkoutFile(file) {
    if (this.busy) return;
    const riderID = this.profile.id;
    if (file.size > MAX_WORKOUT_BYTES) throw Error('Workout files must be under 2 MB.');
    const plan = importWorkout(await file.text(), this.ftp);
    if (this.busy || this.profile.id !== riderID) throw Error('The rider or ride changed. Import again.');
    await this.store.saveWorkouts([{ id: uuid(), riderID, source: 'Imported JSON', savedAt: new Date().toISOString(), plan }]);
    this.importReport = `Saved ${plan.name} for offline riding.`; await this.reload(); this.invalidate();
  }
  async deleteCachedWorkout(id) { if (this.busy) return; await this.store.delete('workouts', id); await this.reload(); this.invalidate(); }
  // ----- Intervals.icu calendar (one connection per rider) -----------------------------------------------------------------------------
  /** The Intervals.icu account usable for a rider: { id, name, remembered } or null. Never exposes the credential. */
  connectionFor(riderID) { return this.intervals.connectionFor(riderID); }
  get connection() { return this.profile ? this.connectionFor(this.profile.id) : null; }
  lastDownload(accountID) { const v = this.prefs[`downloadedAt.${accountID}`]; return typeof v === 'number' ? v : null; }
  shouldRefreshCalendar() { const c = this.connection; return !this.preview && Date.now() - (this.lastCalendarAttempt ?? 0) > 60000 && shouldRefresh({ lastDownload: c ? this.lastDownload(c.id) : null, connected: !!c, rideActive: this.busy, alreadyRunning: this.downloading }); }
  async downloadCalendar({ quiet = false } = {}) {
    if (this.preview) { this.importReport = 'Preview mode: nothing is downloaded.'; this.invalidate(); return; }
    if (this.busy || this.downloading) return;
    const connection = this.connection; if (!connection) throw Error('Connect Intervals.icu in Settings before downloading workouts.');
    const riderID = this.profile.id, ftp = this.ftp, today = new Date(), end = new Date(today); end.setDate(end.getDate() + 14);
    const oldest = ScheduledDate.stringFor(today), newest = ScheduledDate.stringFor(end);
    this.downloading = true; this.invalidate();
    try {
      const result = await this.intervals.workouts(riderID, ftp, oldest, newest);
      if (this.busy || this.profile.id !== riderID) throw Error('The rider or ride changed. Download again.');
      await this.store.saveWorkouts(result.workouts); await this.reload();
      for (const id of staleEntries(this.workouts, riderID, connection.id, new Set(result.workouts.map(w => w.id)), oldest, newest)) await this.store.delete('workouts', id);
      await this.reload(); this.prefs[`downloadedAt.${connection.id}`] = Date.now(); this.savePrefs();
      this.importReport = quiet ? null : `Saved ${result.workouts.length} workouts for offline use.` + (result.skipped.length ? '\nSkipped:\n' + result.skipped.slice(0, 20).join('\n') + (result.skipped.length > 20 ? `\n…and ${result.skipped.length - 20} more.` : '') : '');
    } finally { this.downloading = false; this.invalidate(); }
  }
  async refreshCalendarIfNeeded() { await syncAthleteIfNeeded(this).catch(() => {}); if (this.shouldRefreshCalendar()) { this.lastCalendarAttempt = Date.now(); await this.downloadCalendar({ quiet: true }).catch(error => { this.calendarMessage = `Calendar not refreshed: ${error.message}`; this.invalidate(); }); } }
  // ----- recordings -------------------------------------------------------------------------------------------------------------------
  get resultSession() { const engine = this.ride.engine; if (engine && this.resultSessionID == null) return engine.session; return this.history.find(s => s.id === this.resultSessionID) ?? engine?.session ?? null; }
  /** Use a ramp result as the rider's current FTP. The result's own rider is updated, whoever is selected. */
  async adopt(session) {
    if (this.busy) throw Error('Finish the current ride before changing FTP.');
    const rider = this.profiles.find(p => p.id === session.configuration.riderID); if (!rider) throw Error('The original rider could not be found.');
    if (!session.result || session.isDemo) return;
    const next = structuredClone(rider), entry = { id: uuid(), watts: session.result.estimatedFTP, date: new Date().toISOString(), source: 'Ramp test', sessionID: session.id };
    next.ftpHistory.unshift(entry); next.currentFTPID = entry.id; await this.store.put('profiles', next); await this.reload(); this.notify(`Current FTP updated for ${next.name}.`); this.invalidate();
  }
  async deleteSession(session) {
    if (this.ride.active && this.ride.engine?.session.id === session.id) throw Error('Stop the ride before deleting it.');
    await this.store.delete('sessions', session.id);
    // Adopted FTP settings are kept (as native): deleting a recording never changes a rider's FTP history.
    for (const job of (await this.store.all('jobs')).filter(j => j.sessionID === session.id)) await this.store.delete('jobs', job.id);
    if (this.ride.engine?.session.id === session.id && !this.ride.busy) this.ride.engine = null;
    await this.reload(); this.invalidate();
  }
  closeResult() { if (!this.ride.busy) this.ride.engine = null; this.resultSessionID = null; this.onChange(); }
  async exportBackup() { if (this.busy) throw Error('Finish the ride before exporting a backup.'); const release = await this.lease(); try { download(archiveText(await this.store.backup()), `ftpunk-backup-${new Date().toISOString().slice(0, 10)}.json`); } finally { release(); } }
  /** Run on every state change: returns 'present' once when a ride has just ended, so the shell can show its result. */
  phaseChange() {
    const phase = this.ride.engine?.phase ?? null, previous = this.lastPhase; this.lastPhase = phase;
    return { previous, phase, present: shouldPresentResult(previous, phase, false) };
  }
  async boot() {
    try { const release = await this.lease(); try { await this.store.recover(); } finally { release(); } } catch (error) { this.notify(error.message); }
    await this.reload(); await startIntervals(this);
    this.onboardingPending = !this.profiles.length;
    this.applyRecommendation();
  }
}
export { LocalStore };
