// Pure presentation rules, ported from Sources/FTPunkDomain/PresentationRules.swift (and ResultChartModel.swift).
// No DOM, no storage, no clock: tests mirror Tests/FTPunkTests/PresentationRulesTests.swift.

/** Why Start is disabled, in the order a rider can fix things. */
export const BLOCKER_TEXT = Object.freeze({
  finishing: 'Confirming the trainer stop. Wait a moment before starting.',
  busy: 'Another ride is already in progress.',
  matchingChoice: 'Choose how to use your power meter to start.',
  trainerMissing: 'Connect your trainer to start.',
  trainerControl: 'Enable trainer control to start.',
  powerRange: 'Waiting for the trainer’s power range.',
  resistanceUnsupported: 'This trainer does not advertise resistance control.',
  noPowerTrainer: 'Pedal so the trainer reports power.',
  noPowerMeter: 'Pedal to wake your external power meter.',
  invalidDurations: 'Fix the warm-up and cool-down entries to start.',
  needsFTP: 'Set your FTP so this workout can use your targets.',
  targetsOutOfRange: 'Some targets are outside your trainer’s power range. Lower the intensity.',
  unsupported: 'Live Bluetooth needs Chrome on localhost or HTTPS. Turn on mock sensors in Settings → Debug to try the app.',
});
/** `input` is a readiness object (all fields optional, see `readiness`). Returns a key of BLOCKER_TEXT or null. */
export function startBlocker(input) {
  const r = readiness(input);
  if (r.isFinishing) return 'finishing';
  if (r.isBusy) return 'busy';
  if (r.kind === 'ftpTest' && !r.durationsValid) return 'invalidDurations';
  if (r.needsFTP) return 'needsFTP';
  if (r.isMock) return null;
  if (!r.bluetoothAvailable) return 'unsupported';
  if (r.matchingChoicePending) return 'matchingChoice';
  if (!r.trainerConnected) return 'trainerMissing';
  if (!r.trainerControlReady) return 'trainerControl';
  if (r.kind === 'resistance') { if (!r.supportsResistance) return 'resistanceUnsupported'; }
  else if (!r.powerRangeKnown) return 'powerRange';
  if (!r.targetsInRange) return 'targetsOutOfRange';
  if (!r.freshSelectedPower) return r.powerSource === 'trainer' ? 'noPowerTrainer' : 'noPowerMeter';
  return null;
}
export const readiness = (input = {}) => ({ kind: 'ftpTest', isMock: false, isBusy: false, isFinishing: false, bluetoothAvailable: true, trainerConnected: false, trainerControlReady: false, powerRangeKnown: false, matchingChoicePending: false, powerSource: 'trainer', freshSelectedPower: false, supportsResistance: false, durationsValid: true, needsFTP: false, targetsInRange: true, ...input });
export const blockerReason = key => key ? BLOCKER_TEXT[key] : null;

/** The reference guideline: below 60 kg uses 15 W/min, otherwise 25 W/min. */
export function recommendProtocol(weightKG) {
  if (!Number.isFinite(weightKG) || weightKG <= 0) return { preset: 'standard', reason: '25 W/min is the default. Add your weight for a personal recommendation.' };
  const label = Number.isInteger(weightKG) ? String(weightKG) : weightKG.toFixed(1), preset = weightKG < 60 ? 'gentle' : 'standard';
  return { preset, reason: `${label} kg → ${preset === 'gentle' ? '15' : '25'} W/min` };
}

/** Retest prompts begin after eight weeks. Whole local calendar days, so daylight saving never shifts a week. */
export const RETEST_DUE_AFTER_WEEKS = 8;
const startOfDay = date => { const d = new Date(date); d.setHours(0, 0, 0, 0); return d; };
export function retestAdvice(lastTest, now = new Date()) {
  if (lastTest == null) return { kind: 'never', weeks: null, isDue: false, ageText: null, message: () => null };
  const days = Math.round((startOfDay(now) - startOfDay(lastTest)) / 86400000), weeks = Math.max(0, Math.floor(days / 7)), due = weeks >= RETEST_DUE_AFTER_WEEKS;
  const age = weeks === 0 ? 'this week' : `${weeks} ${weeks === 1 ? 'week' : 'weeks'} ago`;
  return { kind: due ? 'due' : 'recent', weeks, isDue: due, ageText: age, message: (verb = 'Last test') => due ? `${verb} ${weeks} weeks ago, time to retest?` : weeks === 0 ? `${verb} this week` : `${verb} ${age}` };
}
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** "12 Oct": day first, no punctuation, whatever the browser's region setting is. */
export const dayAndMonth = date => { const d = new Date(date); return `${d.getDate()} ${MONTHS[d.getMonth()]}`; };
/** The single status line of Home's FTP card. `date` is null for an FTP entered for one ride. */
export function ftpStatusLine({ date, isRamp, source, now = new Date() }) {
  if (date == null) return { text: source, isRetestPrompt: false };
  const advice = retestAdvice(date, now), parts = [`${isRamp ? 'Tested' : 'Set'} ${dayAndMonth(date)}`];
  if (advice.ageText) parts.push(advice.ageText);
  if (!isRamp) parts.push(source);
  let text = parts.join(' · ');
  if (advice.isDue) text += ' · time to retest?';
  return { text, isRetestPrompt: advice.isDue };
}

/** Change from the current FTP to a new estimate. */
export function resultDelta(newFTP, currentFTP) {
  if (!Number.isFinite(currentFTP) || currentFTP <= 0) return { watts: 0, text: 'First FTP for this rider' };
  const current = Math.round(currentFTP), change = Math.round(newFTP) - current;
  return { watts: change, text: change === 0 ? `Same as your current ${current} W` : `${change > 0 ? '+' : '−'}${Math.abs(change)} W vs ${current} W` };
}

/** Amber warning before the automatic finish at 45 rpm. The finish rule itself is unchanged (RampEngine). */
export const CadenceGuard = Object.freeze({
  warningBelow: 60, finishBelow: 45, message: 'Ramp ends below 45 rpm',
  state(cadence, phase, cadenceAvailable = true) {
    if (phase !== 'ramp' || !cadenceAvailable) return 'ok';
    if (cadence == null) return 'unknown';
    return cadence < this.warningBelow ? 'low' : 'ok';
  },
});

/** Hold-to-confirm gesture arithmetic, shared by the button and its tests. */
export const HOLD_SECONDS = 1.5;
export const holdFraction = seconds => Number.isFinite(seconds) ? Math.min(1, Math.max(0, seconds / HOLD_SECONDS)) : 0;
export const holdComplete = seconds => holdFraction(seconds) >= 1;

/** Fractions of the phase timeline: warm-up, ramp, cool-down. The ramp is open-ended, so it is drawn at a nominal length until known. */
export function phaseTimeline({ phase, warmup, cooldown, nominalRamp = 600, elapsedInPhase, rampElapsed = null }) {
  const ramp = Math.max(nominalRamp, (rampElapsed ?? 0) + 60), total = Math.max(1, warmup + ramp + cooldown), segments = [];
  let cursor = 0;
  for (const [kind, length] of [['warmup', warmup], ['ramp', ramp], ['cooldown', cooldown]]) if (length > 0) { segments.push({ phase: kind, start: cursor / total, end: (cursor + length) / total }); cursor += length; }
  const position = { waiting: 0, warmup: Math.min(elapsedInPhase, warmup), ramp: warmup + Math.min(elapsedInPhase, ramp), cooldown: warmup + ramp + Math.min(elapsedInPhase, cooldown), completed: total, interrupted: total }[phase] ?? 0;
  return { segments, progress: Math.min(1, Math.max(0, position / total)) };
}

/** Device status lights for the Home pill: 'ready' | 'attention' | 'off'. */
export function deviceSummary({ mock, trainerConnected, trainerReady, powerSource, externalMeterConnected, heartRateConnected }) {
  if (mock) return { trainer: 'ready', power: 'ready', heartRate: 'ready', description: 'Mock sensors: trainer, power and heart rate simulated' };
  const trainer = trainerConnected ? (trainerReady ? 'ready' : 'attention') : 'off';
  const power = powerSource === 'trainer' ? trainer : (externalMeterConnected ? 'ready' : 'attention');
  const heartRate = heartRateConnected ? 'ready' : 'off', word = l => l === 'ready' ? 'ready' : l === 'attention' ? 'needs attention' : 'not connected';
  return { trainer, power, heartRate, description: `Trainer ${word(trainer)}. Power from ${powerSource === 'trainer' ? 'trainer' : 'external meter'} ${word(power)}. Heart rate ${word(heartRate)}.` };
}

/** Initials for the rider chip: up to two words. */
export const riderInitials = name => [...String(name).split(/\s+/).filter(Boolean).slice(0, 2)].map(p => [...p][0].toUpperCase()).join('') || '?';
/** Long names are cut so the chip never crowds the toolbar; the full name stays in the accessible label. */
export function riderChipName(name, limit = 14) {
  const trimmed = String(name).trim(), chars = [...trimmed];
  return limit > 1 && chars.length > limit ? chars.slice(0, limit - 1).join('').trimEnd() + '…' : trimmed;
}
/** One-line devices summary for the pre-flight. Every part is labelled so it cannot read as a contradiction. */
export const devicesLine = ({ trainerName, powerSource, meterName, heartRateName }) => `Trainer: ${trainerName ?? 'not connected'} · Power: ${powerSource === 'trainer' ? 'from trainer' : `from ${meterName ?? 'external meter'}`} · Heart rate: ${heartRateName ?? 'none'}`;
/** Cadence row of the pre-flight. It is a problem only once devices are connected and cadence is still missing. */
export function cadenceStatus(source, devicesConnected) {
  if (source === 'trainer') return { text: 'From trainer', isProblem: false };
  if (source === 'externalPowerMeter') return { text: 'From power meter', isProblem: false };
  return devicesConnected ? { text: 'Not available. You will finish the ramp by hand.', isProblem: true } : { text: 'No cadence yet: connect and pedal', isProblem: false };
}

export const DurationFormat = Object.freeze({
  /** "55 min", "1 h 05 min", "45 s". */
  compact(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) return '—';
    const total = Math.round(seconds);
    if (total < 60) return `${total} s`;
    const minutes = Math.floor(total / 60);
    if (minutes < 60) return total % 60 === 0 ? `${minutes} min` : `${minutes} min ${total % 60} s`;
    return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')} min`;
  },
  /** Workout length for cards: minutes below two hours ("60 min", "95 min"), then "2 h 15 min" ("2 h" when exact). */
  workout(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) return '—';
    if (seconds < 60) return this.compact(seconds);
    const minutes = Math.round(seconds / 60);
    if (minutes < 120) return `${minutes} min`;
    return minutes % 60 === 0 ? `${minutes / 60} h` : `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')} min`;
  },
  clock(seconds) { return !Number.isFinite(seconds) || seconds < 0 ? '0:00' : `${Math.floor(seconds / 60)}:${String(Math.floor(seconds) % 60).padStart(2, '0')}`; },
});

/** Whether a ramp result's FTP is already in the rider's history (a "Ramp test" entry made after the session started). */
export const isAdopted = (rider, result, sessionStart) => rider?.ftpHistory?.some(e => e.source === 'Ramp test' && Math.abs(e.watts - result.estimatedFTP) < 0.001 && Date.parse(e.date) >= Date.parse(sessionStart)) === true;

/** Result screen order: the training result, what it means for training, then sharing. */
export function resultSections({ isFTPResult, adopted, canUpload }) {
  const sections = ['headline', 'chart'];
  if (isFTPResult && adopted) sections.push('decision', 'trainingHandoff');
  if (canUpload) sections.push('upload');
  return sections;
}

/** Plain-words account of an ended activity that did not finish normally. */
export function interruptionSummary(session) {
  const length = DurationFormat.compact(session.endedAtOffset ?? session.samples?.at(-1)?.time ?? 0), reason = session.endReason ?? 'The ride stopped unexpectedly.';
  if (session.result != null) return { headline: 'Cool-down interrupted', reason, saved: `Saved on this device: ${length} of recording. Your scored ramp result was kept.`, hasResult: true };
  const what = session.training == null ? 'No FTP estimate, because a complete ramp was not scored.' : 'Your ride up to that point is kept.';
  return { headline: session.training == null ? 'Test interrupted' : 'Ride interrupted', reason, saved: `Saved on this device: ${length} of recording. ${what}`, hasResult: false };
}
/** Time-weighted average of fresh power samples, with gaps over two seconds capped. */
export function averagePower(samples) {
  let energy = 0, seconds = 0;
  for (let i = 0; i + 1 < samples.length; i++) {
    const power = samples[i].power; if (!Number.isFinite(power)) continue;
    const span = Math.min(2, Math.max(0, samples[i + 1].time - samples[i].time)); energy += power * span; seconds += span;
  }
  return seconds > 0 ? energy / seconds : null;
}
/** A ride that ends while the cockpit is minimised brings its result back on screen. */
export const shouldPresentResult = (previous, current, cockpitPresented) => {
  const ended = phase => ['completed', 'interrupted'].includes(phase);
  return !!current && ended(current) && !!previous && !ended(previous) && !cockpitPresented;
};

/** What the result chart draws behind the power line: phase bands and the best-minute window. */
export function resultBands(session) {
  if (session.training != null) return [];
  const end = session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0, bands = [];
  if (session.rampStart != null) {
    if (session.rampStart > 0) bands.push({ title: 'Warm-up', start: 0, end: session.rampStart });
    const rampEnd = session.rampEnd ?? end;
    if (rampEnd > session.rampStart) bands.push({ title: 'Ramp', start: session.rampStart, end: rampEnd });
    const cooldown = session.cooldownStart ?? session.rampEnd;
    if (cooldown != null && end > cooldown) bands.push({ title: 'Cool-down', start: cooldown, end });
  } else if (end > 0) bands.push({ title: 'Warm-up', start: 0, end });
  return bands;
}
export const bestMinuteBand = session => session.result ? { title: `Best minute ${Math.round(session.result.bestMinutePower)} W`, start: session.result.windowStart, end: session.result.windowEnd } : null;
export const ResultChartLayout = Object.freeze({
  /** The forms a label may take, longest first. */
  candidates(title) {
    if (title === 'Warm-up') return ['Warm-up', 'Warm'];
    if (title === 'Cool-down') return ['Cool-down', 'Cool'];
    return title.startsWith('Best minute ') ? [title, 'Best ' + title.slice('Best minute '.length)] : [title];
  },
  estimatedWidth: (text, characterWidth) => [...text].length * Math.max(1, characterWidth),
  /** The longest form of `title` that fits `availableWidth`, or null if none does. */
  fittingLabel(title, availableWidth, characterWidth) {
    return Number.isFinite(availableWidth) ? this.candidates(title).find(t => this.estimatedWidth(t, characterWidth) <= availableWidth) ?? null : null;
  },
  /** Left edge for a label of `width` centred on `centre`, kept inside a plot `plotWidth` wide. */
  clampedLeading: (centre, width, plotWidth) => [plotWidth, width, centre].every(Number.isFinite) ? Math.min(Math.max(0, centre - width / 2), Math.max(0, plotWidth - width)) : 0,
  /** Vertical headroom above the highest power so the two label rows never touch the line. */
  ceiling: peak => Math.max(100, Number.isFinite(peak) ? peak : 0) * 1.32,
});

/** The one line of coaching under the readings. Only the FTP test says "stay seated". (Chaindance's posture rule is added by the ride plan.) */
export const COACHING = Object.freeze({ seated: 'Stay seated. Keep a steady, comfortable cadence.', steady: 'Keep a steady, comfortable cadence.', cooldown: 'Ramp scored. Spin gently to cool down.' });
export const coachingLine = (isFTPTest, phase) => isFTPTest ? (phase === 'cooldown' ? COACHING.cooldown : COACHING.seated) : COACHING.steady;
