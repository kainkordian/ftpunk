// The workout text editor's language: a documented subset of the Intervals.icu workout builder syntax. Port of
// Sources/FTPunkDomain/WorkoutText.swift; tests/fixtures/workout-text-cases.json (written by a Swift test) is the truth. Nothing is guessed:
// cadence, heart rate, pace, zones, distance, ranges and free-ride steps are errors that name the line.
//
//     Warm-up
//     - 10m 50%
//     Main set 5x
//     - 3m 115%
//     - 3m 55%
//     Ramp down
//     - 5m ramp 60-40%
//     Sprint
//     - 20s 650w
//
// A line starting with "-" is a step: a duration (30s, 10m, 1h30m, 1m30), a target (80% of FTP, 200w, ramp 60-80%, ramp 100-200w) and optional text,
// which names the step ("- Recovery 30s 50%"). Any other line is a header. A header ending in "Nx" starts a repeat of the steps below it, up to the
// next blank line or header; any other header names the first unnamed step below it.
//
// Blocks are { kind: 'step', step } or { kind: 'repeats', count, steps }; a step is { name, seconds, start, end? } with targets { unit: 'percentFTP' | 'watts', value }.
// The limits and `normalized` live here because both the parser and the custom workout model need them (custom-workouts.mjs re-exports them).

export const LIMITS = Object.freeze({
  stepSeconds: [5, 14400], percent: [0.30, 2.50], watts: [20, 1500], repeats: [1, 100], maximumExpandedSteps: 500, maximumDuration: 86400, maximumPerRider: 200, maximumCharacters: 100000,
});
const within = (value, [low, high]) => value >= low && value <= high;
/** Collapses runs of white space and trims the ends. */
export const normalized = name => name.split(/\s+/).filter(Boolean).join(' ');
const chars = text => [...text].length;
const trimSpaces = line => line.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, '');
const words = text => text.split(/\s+/).filter(Boolean);

export class WorkoutTextError extends Error {
  constructor(line, message) { super(`Line ${line}: ${message}`); this.line = line; this.detail = message; }
}

// ----- tokens ----------------------------------------------------------------------------------------------------------------------
const plainNumber = text => /^\d+(\.\d+)?$/.test(text) ? Number(text) : null;
/** 10m, 30s, 1h, 1h30m, 1m30s and the short 1m30. Null when it is not a duration. */
export function duration(text) {
  let total = 0, digits = '', lastUnit = 3; // h = 0, m = 1, s = 2
  for (const character of text.toLowerCase()) {
    if (/^[0-9]$/.test(character)) { digits += character; continue; }
    if (!digits) return null;
    const unit = { h: 0, m: 1, s: 2 }[character]; if (unit == null) return null;
    if (!(unit > (lastUnit === 3 ? -1 : lastUnit))) return null;
    total += Number(digits) * [3600, 60, 1][unit]; lastUnit = unit; digits = '';
  }
  if (digits) { if (lastUnit !== 1) return null; total += Number(digits); } // a bare trailing number is seconds, and only after minutes ("1m30")
  return lastUnit === 3 ? null : total;
}
const UNSUPPORTED = { hr: 'heart rate targets', lthr: 'heart rate targets', pace: 'pace targets', freeride: 'free-ride steps', rpm: 'cadence targets', press: 'lap-button steps', lap: 'lap-button steps', noshowavg: 'Zwift display flags', '/noshowavg': 'Zwift display flags', ftp: 'the ftp keyword', '%hr': 'heart rate targets' };
const isNumeric = char => /\p{N}/u.test(char);
function token(raw) {
  const text = raw.toLowerCase();
  if (text === '@') return { type: 'at' };
  if (text === 'ramp') return { type: 'ramp' };
  if (Object.hasOwn(UNSUPPORTED, text)) return { type: 'unsupported', raw, why: UNSUPPORTED[text] };
  if (text.endsWith('rpm') && [...text.slice(0, -3)].every(c => isNumeric(c) || c === '-' || c === '.')) return { type: 'unsupported', raw, why: 'cadence targets' };
  const rest = [...text].slice(1);
  if (text[0] === 'z' && rest.length && isNumeric(rest[0]) && rest.every(c => isNumeric(c) || c === '-' || c === 'z')) return { type: 'unsupported', raw, why: 'training zones' };
  for (const suffix of ['km', 'mtr', 'mi', 'yd']) if (text.endsWith(suffix) && plainNumber(text.slice(0, -suffix.length)) != null) return { type: 'unsupported', raw, why: 'distance steps' };
  const seconds = duration(text); if (seconds != null) return { type: 'duration', value: seconds };
  if (text.endsWith('%') && plainNumber(text.slice(0, -1)) != null) return { type: 'percent', value: plainNumber(text.slice(0, -1)) / 100 };
  if (text.endsWith('w') && plainNumber(text.slice(0, -1)) != null) return { type: 'watts', value: plainNumber(text.slice(0, -1)) };
  for (const [suffix, percent] of [['%', true], ['w', false]]) if (text.endsWith(suffix)) {
    const parts = text.slice(0, -1).split('-');
    if (parts.length === 2 && plainNumber(parts[0]) != null && plainNumber(parts[1]) != null) {
      const low = plainNumber(parts[0]), high = plainNumber(parts[1]);
      return percent ? { type: 'rangePercent', low: low / 100, high: high / 100 } : { type: 'rangeWatts', low, high };
    }
  }
  return { type: 'word', raw };
}
/** True when every word of a name reads as plain text (so printing the name and parsing it again gives the same name). */
export function isPlainName(name) {
  const list = words(name), last = list.at(-1);
  if (last && [...last].length >= 2 && /^[0-9]+$/.test(last.slice(0, -1)) && last.at(-1).toLowerCase() === 'x') return false;
  if (name.startsWith('-')) return false;
  return list.every(word => token(word).type === 'word');
}
/** The words of a step line that are text: everything that is not a duration, target, "@", or an "at" right before a target. */
function nameWords(text) {
  const raw = words(text), result = [];
  raw.forEach((word, index) => {
    if (token(word).type !== 'word') return;
    if (word.toLowerCase() === 'at' && index + 1 < raw.length && ['percent', 'watts', 'ramp', 'rangePercent', 'rangeWatts'].includes(token(raw[index + 1]).type)) return;
    result.push(word);
  });
  return result;
}

// ----- parsing ---------------------------------------------------------------------------------------------------------------------
const RAMP_NEEDS = '"ramp" needs two values, like ramp 60-80% or ramp 100-200w.';
function parseStep(text, line) {
  const fail = message => new WorkoutTextError(line, message);
  const tokens = words(text).map(token);
  let seconds = null, target = null, rampNext = false;
  for (const item of tokens) {
    switch (item.type) {
      case 'unsupported': throw fail(`"${item.raw}" is not supported (${item.why}).`);
      case 'word': case 'at': if (rampNext) throw fail(RAMP_NEEDS); break;
      case 'duration': if (rampNext) throw fail(RAMP_NEEDS); if (seconds != null) throw fail('A step has one duration.'); seconds = item.value; break;
      case 'percent': case 'watts':
        if (rampNext) throw fail(RAMP_NEEDS); if (target) throw fail('A step has one target.');
        target = { start: { unit: item.type === 'percent' ? 'percentFTP' : 'watts', value: item.value }, end: null }; break;
      case 'ramp': if (target || rampNext) throw fail('A step has one target.'); rampNext = true; break;
      case 'rangePercent': case 'rangeWatts': {
        if (!rampNext) throw fail('Ranges are not supported. Write ramp followed by the two values to ramp gradually, or use one value.');
        if (target) throw fail('A step has one target.');
        rampNext = false; const unit = item.type === 'rangePercent' ? 'percentFTP' : 'watts';
        target = { start: { unit, value: item.low }, end: { unit, value: item.high } }; break;
      }
    }
  }
  if (rampNext) throw fail(RAMP_NEEDS);
  if (seconds == null) throw fail('This step needs a duration such as 10m, 30s or 1m30.');
  if (!target) throw fail('This step needs a target such as 80%, 200w or ramp 60-80%.');
  if (!within(seconds, LIMITS.stepSeconds)) throw fail('The duration must be between 5 seconds and 4 hours.');
  for (const value of [target.start, target.end].filter(Boolean)) {
    if (value.unit === 'percentFTP') { if (!within(value.value, LIMITS.percent)) throw fail('% FTP must be between 30 and 250.'); }
    else if (!within(value.value, LIMITS.watts)) throw fail('Watts must be between 20 and 1500.');
  }
  const joined = normalized(nameWords(text).join(' '));
  if (chars(joined) > 100) throw fail('The step name can have at most 100 characters.');
  return { name: joined, seconds, start: target.start, ...(target.end ? { end: target.end } : {}) };
}
const countOf = text => /^[+-]?\d+$/.test(text) && text.replace(/^[+-]/, '').length <= 18 ? Number(text) : null;

/** Text -> { blocks, errors: [{ line, message }], isValid }. Every bad line is reported; blocks are empty when there is an error. */
export function parseWorkoutText(text) {
  const errors = [], error = (line, message) => errors.push({ line, message });
  const normalizedText = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  if (chars(normalizedText) > LIMITS.maximumCharacters) return { blocks: [], errors: [{ line: 1, message: 'The text is too long.' }], isValid: false };
  const blocks = []; let header = null, group = null;
  const flush = () => {
    if (group) { if (!group.steps.length) error(group.line, 'This repeat has no steps under it.'); else blocks.push({ kind: 'repeats', count: group.count, steps: group.steps }); }
    group = null;
  };
  normalizedText.split('\n').forEach((rawLine, index) => {
    const number = index + 1, line = trimSpaces(rawLine);
    if (!line) { flush(); header = null; return; }
    if (line.startsWith('-')) {
      try {
        const step = parseStep(line.slice(1), number);
        if (group) group.steps.push(step);
        else { if (!step.name && header != null) step.name = header; header = null; blocks.push({ kind: 'step', step }); }
      } catch (e) { if (e instanceof WorkoutTextError) error(e.line, e.detail); else throw e; }
      return;
    }
    flush();
    const list = words(line), last = list.at(-1), count = last && [...last].length >= 2 && last.at(-1).toLowerCase() === 'x' ? countOf(last.slice(0, -1)) : null;
    if (count != null) {
      if (within(count, LIMITS.repeats)) { group = { count, line: number, steps: [] }; header = null; } else error(number, 'A repeat needs 1 to 100 repeats.');
    } else header = normalized(line);
  });
  flush();
  if (!errors.length && !blocks.length) error(1, 'Add a step such as "- 10m 50%".');
  return { blocks: errors.length ? [] : blocks, errors, isValid: errors.length === 0 };
}

// ----- printing --------------------------------------------------------------------------------------------------------------------
export function durationText(seconds) {
  const total = Math.round(seconds), hours = Math.floor(total / 3600), minutes = Math.floor(total % 3600 / 60), rest = total % 60;
  return (hours > 0 ? `${hours}h` : '') + (minutes > 0 ? `${minutes}m` : '') + (rest > 0 || total === 0 ? `${rest}s` : '');
}
function numberText(value) {
  const rounded = Math.round(value * 100) / 100;
  return Number.isInteger(rounded) ? String(rounded) : String(Number(rounded.toPrecision(6))); // "%g": six significant digits
}
function targetText(start, end) {
  const text = target => numberText(target.unit === 'percentFTP' ? target.value * 100 : target.value), unit = start.unit === 'percentFTP' ? '%' : 'w';
  return end ? `ramp ${text(start)}-${text(end)}${unit}` : text(start) + unit;
}
const stepText = (step, withName) => [...(withName && step.name ? [step.name] : []), durationText(step.seconds), targetText(step.start, step.end)].join(' ');
/** Blocks -> text. Always possible; parsing the result gives the same blocks. */
export function printWorkoutText(blocks) {
  return blocks.map(block => block.kind === 'step'
    ? [...(block.step.name ? [block.step.name] : []), `- ${stepText(block.step, false)}`].join('\n')
    : [`${block.count}x`, ...block.steps.map(step => `- ${stepText(step, true)}`)].join('\n')).join('\n\n');
}
