import { validatePlan, supportsIntensity } from './training.mjs';
import { RampEngine, configuration, PRESETS, mockSample } from './domain.mjs';
import { PowerMatcher, TrainerWarmth } from './matching.mjs';
import { route } from './protocol.mjs';
import { acquireRideLease } from './storage.mjs';
import { AutoPause } from './rules/ride-summary.mjs';
/** Work the trainer has done since the app connected to it. It lives with the Bluetooth trainer connection (one record per connected trainer, so a reconnect starts cold
 *  and a second ride on the same connection starts warm); rides without a trainer connection (mock sensors) get a fresh one per ride. */
const warmthByConnection = new WeakMap();
export function warmthFor(entry) {
  if (!entry) return new TrainerWarmth();
  let warmth = warmthByConnection.get(entry); if (!warmth) warmthByConnection.set(entry, warmth = new TrainerWarmth());
  return warmth;
}
export class RideController {
  constructor(devices, store, { now = () => performance.now() / 1000, lease = acquireRideLease } = {}) {
    Object.assign(this, { devices, store, now, lease });
    this.engine = null; this.matcher = null; this.warmth = null; this.warmthConnection = null; this.lastTrainerPower = null; this.matchLogPhase = null; this.matchLogTime = 0; this.elapsed = 0; this.starting = false; this.finishing = false; this.pending = null; this.trainingTransition = null; this.trainingCommand = null; this.saveQueue = Promise.resolve(); this.onChange = () => {}; this.onError = () => {}; this.onSaved = () => {}; this.speed = 12; this.scenario = 'exhaustion'; this.autoPause = new AutoPause(); /** Set by the app from the rider's preference. Workouts and free rides only, never the FTP test. */ this.autoPauseEnabled = true;
    devices.onReading = reading => {
      if (this.active && !this.demo) {
        const sample = route(reading, this.engine.session.configuration, this.origin);
        if (sample) { this.engine.receive(sample); if (Number.isFinite(sample.trainerPower) && !(sample.time <= (this.lastTrainerPower?.time ?? -Infinity))) this.lastTrainerPower = { time: sample.time, watts: sample.trainerPower }; }
      }
    };
    devices.onFailure = (role, reason) => {
      const c = this.preparingConfiguration ?? this.engine?.session.configuration;
      if (!this.demo && (this.starting || this.active) && c && (role === 'trainer' || role === c.powerSource || role === c.cadenceSource)) this.interrupt(reason);
    };
  }
  get active() { return this.engine?.active === true; }
  get busy() { return this.starting || this.finishing || this.active; }
  async start(input, { demo = false, speed = 12, scenario = 'exhaustion', training = null, intensity = 100 } = {}) {
    if (this.busy) return;
    this.demo = demo; this.starting = true; this.cancelStart = null; this.onChange();
    let startedHardware = false;
    try {
      this.release = await this.lease();
      if (this.cancelStart) throw Error(this.cancelStart);
      if (training) training = validatePlan(training);
      let config = configuration({ ...input, ...(training?.resistance == null ? {} : { powerMatchingEnabled: false }) }); this.preparingConfiguration = config;
      if (this.cancelStart) throw Error(this.cancelStart);
      if (!demo) {
        if (!this.devices.trainerReady || this.devices.measurements.fresh(config.powerSource, 'power', this.now()) == null) throw Error('Connect the trainer and pedal until the selected power source is receiving fresh data.');
        const range = this.devices.range, p = PRESETS[config.preset];
        if (training?.resistance != null) {
          const resistance = this.devices.resistanceRange;
          if (!resistance || resistance.quantized(training.resistance) !== training.resistance) throw Error('Resistance control or this level is not supported.');
          startedHardware = true; await this.devices.startResistance(training.resistance);
        } else {
          if (!range) throw Error('This trainer does not expose ERG power control.');
          if (training) {
            if (!supportsIntensity(training, 100, range.minimum, range.maximum) || !supportsIntensity(training, intensity, range.minimum, range.maximum) || !training.steps.every(s => range.quantized(s.watts) > 0 && range.quantized(s.endWatts ?? s.watts) > 0)) throw Error('The workout exceeds the trainer’s supported power range.');
          } else if (![config.warmupPower, p.start, p.cooldown].every(w => range.quantized(w) === w) || p.step % range.increment !== 0) throw Error('This protocol’s targets do not fit the trainer’s supported range or power increment.');
          if (!training) config = configuration({ ...config, maximumPower: Math.min(config.maximumPower, range.maximum) });
          startedHardware = true; await this.devices.start(range.quantized(Math.round((training?.steps[0].watts ?? config.warmupPower) * (training ? intensity / 100 : 1))));
        }
      }
      if (this.cancelStart) throw Error(this.cancelStart);
      this.demo = demo; this.speed = speed; this.scenario = scenario; this.mockPaused = false; this.elapsed = 0; this.origin = this.now(); this.lastWall = this.origin;
      this.lastCheckpoint = -Infinity; this.lastAcknowledged = demo ? null : this.devices.range?.quantized(Math.round((training?.steps[0].watts ?? config.warmupPower) * (training ? intensity / 100 : 1))); this.lastResistance = training?.resistance ?? null; this.matcher = new PowerMatcher(); this.lastTrainerPower = null; this.matchLogPhase = null; this.matchLogTime = 0; this.warmthConnection = demo ? null : this.devices.devices?.trainer ?? null; this.warmth = warmthFor(this.warmthConnection); this.warmth.beginSession(); this.released = false; this.finalized = null;
      this.autoPause.reset();
      this.engine = new RampEngine(config, { demo, devices: demo ? [] : this.devices.snapshots, training });
      if (training?.kind === 'workout' && intensity !== 100) { if (!this.engine.setIntensity(intensity, 0)) throw Error('Choose 50–150% intensity within the trainer’s supported power range.'); }
      await this.checkpoint(true);
      if (this.cancelStart) throw Error(this.cancelStart);
      if (!this.engine.active) throw Error('The recording could not be started.');
      this.timer = setInterval(() => this.tick(), demo ? 100 : 250);
    } catch (error) {
      if (this.engine?.active) {
        this.engine.interrupt(this.elapsed, error.message);
        // Persist an interrupted preparation without preventing the release attempt.
        void this.checkpoint(true).catch(saveError => this.onError(saveError));
      }
      if (startedHardware) { try { await this.devices.stop(); } catch (stopError) { this.onError(stopError); } }
      this.release?.(); this.release = null;
      this.onError(error);
    } finally { this.starting = false; this.preparingConfiguration = null; this.onChange(); }
  }
  tick() {
    if (!this.active) return;
    const now = this.now(), delta = Math.max(0, now - this.lastWall); this.lastWall = now;
    if (this.demo) { if (!this.mockPaused) this.advanceMock(Math.min(delta, 0.5) * this.speed); }
    else {
      this.elapsed = now - this.origin; this.engine.tick(this.elapsed);
      if (this.autoPauseEnabled && this.engine.session.training) {
        const power = this.engine.lastPower && this.elapsed - this.engine.lastPower.time <= 2 ? this.engine.lastPower.watts : null;
        const action = this.autoPause.update({ time: this.elapsed, phase: this.engine.phase, power, canResume: this.engine.canResume(this.elapsed) });
        if (action === 'pause') this.pauseTraining(); else if (action === 'resume') this.resumeTraining();
      }
      if (this.lastTrainerPower) this.warmth.add(this.lastTrainerPower);
      if (this.active && !this.pending) {
        if (this.engine.freewheel && !this.released) this.send(() => this.devices.stop(), () => { this.released = true; this.engine.event(this.elapsed, 'Trainer released for free-spin cooldown'); });
        else if (this.engine.targetResistance != null) {
          const level = this.engine.targetResistance;
          if (level !== this.lastResistance) this.send(() => this.devices.setResistance(level), () => { this.lastResistance = level; this.engine.event(this.elapsed, `Trainer confirmed resistance ${level / 10}`); });
        }
        else if (this.engine.target != null) {
          const c = this.engine.session.configuration;
          const cadence = this.engine.lastCadence && this.elapsed - this.engine.lastCadence.time <= 2 ? this.engine.lastCadence.rpm : null;
          const watts = c.powerMatchingEnabled ? this.matcher.command(this.engine.target, this.engine.lastPower, this.lastTrainerPower, cadence, this.elapsed, this.devices.range, this.warmth) : this.devices.range.quantized(this.engine.target);
          if (watts !== this.lastAcknowledged) this.send(() => this.devices.setTarget(watts), () => { this.lastAcknowledged = watts; this.engine.event(this.elapsed, `Trainer confirmed ${watts} W (workout target ${this.engine.target} W)`); });
        }
      }
    }
    this.logPowerMatching();
    this.checkpoint().catch(error => this.storageFailed(error));
    if (!this.active) void this.finalize();
    this.onChange();
  }
  /** Pause, resume, an intensity or ERG change: forget the smoothed readings and wait for the trainer to settle. The gain and offset estimate and the trainer's warmth are kept
   *  (as native); the last command's correction is cleared because the next command is a fresh feed-forward. */
  restartMatching() { if (!this.matcher) return; this.matcher.restartSettle(this.elapsed); this.matcher.correction = 0; }
  /** What the matcher is doing, for the cockpit: `{ kind: 'off' | 'warming' | 'matching' | 'fadeHold', ... }`. Off unless this ride uses power matching. */
  get matchingStatus() { return this.active && this.engine.session.configuration.powerMatchingEnabled && this.matcher ? this.matcher.status : { kind: 'off' }; }
  /** What the matcher did, for the owner to read in the ride's events: at ramp start, every 2 minutes of ramp and at ramp end. */
  logPowerMatching() {
    const engine = this.engine; if (!engine || !engine.session.configuration.powerMatchingEnabled) return;
    const phase = engine.phase, previous = this.matchLogPhase; this.matchLogPhase = phase;
    const rampStarted = phase === 'ramp' && previous !== 'ramp', periodic = phase === 'ramp' && this.elapsed - this.matchLogTime >= 120, rampEnded = previous === 'ramp' && phase !== 'ramp';
    if (!(rampStarted || periodic || rampEnded)) return;
    this.matchLogTime = this.elapsed;
    const m = this.matcher, signed = `${m.offset >= 0 ? '+' : '-'}${Math.abs(m.offset).toFixed(1)}`;
    engine.event(this.elapsed, `Power matching (${rampStarted ? 'ramp start' : rampEnded ? 'ramp end' : 'ramp'}): gain ${m.gain.toFixed(3)}, offset ${signed} W, trainer warmth ${this.warmth.kilojoules.toFixed(0)} kJ, fade guard ${m.fadeSeconds.toFixed(0)} s, ${m.measurementCount} measurements`);
  }
  /** Mock rides only: run the simulated sensors forward by `seconds` of ride time (also used by preview scenarios and the debug controls). */
  advanceMock(seconds) {
    if (!this.demo || !this.active) return;
    const end = this.elapsed + seconds;
    while (this.elapsed < end && this.active) {
      this.elapsed = Math.min(end, this.elapsed + 0.5);
      this.engine.receive(mockSample(this.elapsed, this.engine.target ?? (this.engine.freewheel ? 0 : this.engine.session.configuration.warmupPower), this.engine.phase, this.scenario));
      this.engine.tick(this.elapsed);
    }
    if (!this.active) void this.finalize();
    this.onChange();
  }
  send(action, acknowledged) {
    const id = this.engine.session.id;
    const owned = () => this.engine?.session.id === id && this.active;
    const current = () => owned() && this.engine.phase !== 'paused';
    const pending = Promise.resolve().then(() => { if (current()) return action(); }).then(() => {
      if (current()) acknowledged();
    }).catch(error => { if (owned()) this.interrupt(error.message); }).finally(() => {
      if (this.pending === pending) this.pending = null;
    });
    this.pending = pending;
  }
  checkpoint(force = false) {
    if (!this.engine || !force && this.elapsed - this.lastCheckpoint < 1) return Promise.resolve();
    this.lastCheckpoint = this.elapsed;
    const snapshot = structuredClone(this.engine.session);
    this.saveQueue = this.saveQueue.catch(() => {}).then(() => this.store.saveSession ? this.store.saveSession(snapshot) : this.store.put('sessions', snapshot)); return this.saveQueue;
  }
  storageFailed(error) { this.onError(Error(`Recording could not be saved: ${error.message}`)); this.interrupt('Local storage failed.'); }
  adjustERG(delta) {
    if (!this.active || this.trainingTransition || this.engine.resistanceLevel != null || this.engine.session.training?.kind !== 'freeRide') return;
    const requested = (this.engine.target ?? this.engine.freeRideTarget) + delta;
    const target = this.demo ? Math.min(1000, Math.max(1, requested)) : this.devices.range.quantized(requested);
    this.engine.adjustERG(target, this.elapsed); this.restartMatching(); this.onChange();
  }
  adjustIntensity(delta) {
    if (!this.active || this.trainingTransition || this.engine.session.training?.kind !== 'workout') return;
    const range = this.demo ? { minimum: 1, maximum: 32767 } : this.devices.range;
    const percent = this.engine.intensity + delta;
    if (!this.demo && range && !this.engine.session.training.steps.every(s => [s.watts, s.endWatts ?? s.watts].every(w => range.quantized(Math.round(w * percent / 100)) > 0))) { this.onError(Error('The adjusted target rounds to zero on this trainer.')); return; }
    if (!range || !this.engine.setIntensity(this.engine.intensity + delta, this.elapsed, range.minimum, range.maximum)) { this.onError(Error('Choose 50–150% intensity within the trainer’s supported power range.')); return; }
    this.restartMatching(); this.checkpoint(true).catch(e => this.storageFailed(e)); this.onChange();
  }
  /** Moves a workout on to its next step; the target goes out through the next tick, and power matching restarts its settle (native AppModel.skipStep). */
  skipStep() {
    if (!this.active || this.trainingTransition) return;
    if (!this.demo) this.elapsed = Math.max(this.elapsed, this.now() - this.origin);
    if (!this.engine.skipStep(this.elapsed)) return;
    this.restartMatching(); this.checkpoint(true).catch(e => this.storageFailed(e)); this.onChange();
  }
  adjustResistance(steps) {
    if (!this.active || this.trainingTransition || this.engine.resistanceLevel == null) return;
    const range = this.devices.resistanceRange ?? (this.demo ? { increment: 10, quantized: n => Math.max(0, Math.min(1000, n)) } : null);
    if (!range) return;
    this.engine.adjustResistance(range.quantized(this.engine.resistanceLevel + steps * range.increment), this.elapsed); this.onChange();
  }
  pauseTraining() {
    if (!this.active || this.trainingTransition || !this.engine.session.training) return;
    if (!this.demo) this.elapsed = Math.max(this.elapsed, this.now() - this.origin);
    if (!this.engine.pause(this.elapsed)) { if (!this.active) void this.finalize(); this.onChange(); return; }
    this.restartMatching();
    if (this.demo) this.released = true;
    else {
      const pending = this.pending;
      this.changeTrainingState('pausing', async current => {
        await pending; if (!current()) return;
        await this.devices.stop();
        if (current()) { this.released = true; this.lastAcknowledged = null; this.engine.event(this.elapsed, 'Trainer release confirmed for pause'); }
      });
    }
    this.checkpoint(true).catch(error => this.storageFailed(error)); this.onChange();
  }
  resumeTraining() {
    if (this.engine?.phase !== 'paused' || this.trainingTransition || !this.released) return;
    if (!this.demo) this.elapsed = Math.max(this.elapsed, this.now() - this.origin);
    if (!this.engine.canResume(this.elapsed)) { this.onError(Error('Pedal until fresh power and cadence arrive, then resume.')); return; }
    const target = this.engine.resistanceLevel ?? this.engine.resumeTarget;
    if (this.demo) { this.engine.resume(this.elapsed); this.released = false; this.restartMatching(); this.onChange(); return; }
    this.released = false; // Any attempted restart must be followed by Stop if cancelled.
    this.changeTrainingState('resuming', async current => {
      if (!current()) return;
      if (this.engine.resistanceLevel != null) await this.devices.startResistance(target);
      else await this.devices.start(this.devices.range.quantized(target));
      if (!current()) return;
      this.elapsed = Math.max(this.elapsed, this.now() - this.origin);
      if (!this.engine.resume(this.elapsed)) throw Error('Fresh movement was lost while resuming. The ride has been interrupted.');
      this.restartMatching(); this.lastAcknowledged = this.devices.range?.quantized(target); this.lastResistance = this.engine.resistanceLevel;
      this.checkpoint(true).catch(error => this.storageFailed(error));
    });
  }
  changeTrainingState(state, action) {
    const id = this.engine.session.id;
    const owned = () => this.engine?.session.id === id && this.active;
    const current = () => owned() && this.engine.phase === 'paused';
    this.trainingTransition = state;
    const work = Promise.resolve().then(() => action(current)).catch(error => { if (owned()) this.interrupt(error.message); }).finally(() => {
      if (this.trainingCommand === work) { this.trainingCommand = null; this.trainingTransition = null; }
      this.onChange();
    });
    this.trainingCommand = work; this.onChange(); return work;
  }
  finishRamp() { this.engine?.finishRamp(this.elapsed); this.onChange(); if (!this.active) void this.finalize(); }
  stop() { if (this.starting) { this.cancelStart = 'Starting the test was cancelled.'; return; } this.engine?.end(this.elapsed); void this.finalize(); this.onChange(); }
  interrupt(reason) {
    if (this.starting) this.cancelStart = reason;
    if (!this.active) return;
    this.engine.interrupt(this.demo ? this.elapsed : Math.max(this.elapsed, this.now() - this.origin), reason);
    void this.finalize(); this.onChange();
  }
  async finalize() {
    if (!this.engine || this.active || this.finalized === this.engine.session.id) return;
    this.finalized = this.engine.session.id; this.finishing = true; clearInterval(this.timer); this.onChange();
    const session = this.engine.session;
    // Begin release now. A slow IndexedDB transaction must not hold the trainer target.
    const releasing = (async () => {
      try {
        if (!this.demo) {
          await this.pending; await this.trainingCommand;
          if (!this.released) { await this.devices.stop(); this.released = true; }
        }
      } catch (error) { this.onError(Error(`Trainer stop was not confirmed. ${error.message}`)); }
    })();
    let saved = false;
    try { await this.checkpoint(true); saved = true; }
    catch (error) { this.onError(Error(`The final recording could not be saved. Download JSON now. ${error.message}`)); }
    await releasing;
    this.release?.(); this.release = null; this.finishing = false; this.onChange();
    if (saved) this.onSaved(session);
  }
}
