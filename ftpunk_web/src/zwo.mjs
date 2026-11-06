import { validatePlan } from './training.mjs';
// Zwift workout files (.zwo). Port of Sources/FTPunkDomain/ZWOImport.swift and ZWOExport.swift; contracts/README.md has the rules and
// tests/fixtures/zwo-cases.json (written by a Swift test) is the truth. Powers are fractions of FTP, so an import needs the rider's FTP and
// resolves to whole watts once. Only timed power steps are supported: a step that would need guessed watts rejects the file.
const MAX_BYTES = 2 * 1024 * 1024, MAX_STEPS = 500, MAX_SECONDS = 86400;
const NOT_ZWO = 'This is not a valid ZWO workout file.', NEEDS_FTP = 'Set an FTP first: ZWO powers are fractions of FTP.';
const FREE = 'This workout has a free-ride or maximal-effort step, which has no power target. Those are unsupported.';
const DECIMAL = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;

/** A file's text is ZWO when its first visible character is "<" (the JSON formats start with "{"). */
export const looksLikeZWO = text => text.replace(/^[﻿\s]+/, '').startsWith('<');

function number(element, key) {
  const raw = element.getAttribute(key)?.replace(/^[ \t]+|[ \t]+$/g, '');
  if (raw == null || !DECIMAL.test(raw)) return null;
  const value = Number(raw); return Number.isFinite(value) ? value : null;
}
const cut = (text, limit) => { let out = ''; for (const char of text) { if (out.length + char.length > limit) break; out += char; } return out; };

/** Parses ZWO text into a resolved plan at `ftp`. Throws Error(message) with the same words as the native app. */
export function parseZWO(text, ftp) {
  if (new TextEncoder().encode(text).length > MAX_BYTES) throw Error('Workout files must be under 2 MB.');
  // A workout file has no use for a DTD; refusing it closes the door on entity tricks.
  const head = text.slice(0, 4096).toLowerCase();
  if (head.includes('<!doctype') || head.includes('<!entity')) throw Error(NOT_ZWO);
  const doc = new DOMParser().parseFromString(text, 'application/xml'), root = doc.documentElement;
  if (!root || doc.querySelector('parsererror') || root.nodeName !== 'workout_file') throw Error(NOT_ZWO);
  const blocks = []; let name = '', expanded = 0, seconds = 0;
  const fail = message => { throw Error(message); };
  const fraction = (el, key) => { const v = number(el, key); if (v == null || !(v > 0) || v > 5) fail('ZWO powers are fractions of FTP (for example 0.75), and every step needs one.'); return v; };
  const duration = (el, key) => { const v = number(el, key); if (v == null || !(v > 0) || v > MAX_SECONDS) fail('Every step must have a timed power target; free, distance and lap steps are unsupported.'); return v; };
  const count = (more, added) => { expanded += more; seconds += added; if (expanded > MAX_STEPS || seconds > MAX_SECONDS) fail('Workout repeats are too deeply nested or too large.'); };
  // Document order matters: the first problem found is the one reported, exactly as the native streaming parser does.
  for (const child of root.children) {
    if (child.nodeName === 'name') name = child.textContent;
    else if (child.nodeName === 'sportType') { const sport = child.textContent.trim().toLowerCase(); if (sport && sport !== 'bike') fail('Only cycling (bike) workouts are supported.'); }
    else if (child.nodeName === 'workout') for (const el of child.children) readStep(el);
  }
  function readStep(el) {
    switch (el.nodeName) {
      case 'SteadyState': { const length = duration(el, 'Duration'), power = fraction(el, 'Power'); count(1, length); blocks.push({ kind: 'steady', seconds: length, power }); break; }
      case 'Warmup': case 'Cooldown': case 'Ramp': {
        // PowerLow is where the step starts and PowerHigh where it ends, even when a cool-down falls.
        const length = duration(el, 'Duration'), low = fraction(el, 'PowerLow'), high = fraction(el, 'PowerHigh'); count(1, length);
        blocks.push({ kind: 'ramp', name: el.nodeName === 'Warmup' ? 'Warm-up' : el.nodeName === 'Cooldown' ? 'Cool-down' : 'Ramp', seconds: length, from: low, to: high }); break;
      }
      case 'IntervalsT': {
        const repeats = number(el, 'Repeat'); if (repeats == null || repeats < 1 || repeats > 100 || Math.round(repeats) !== repeats) fail('Invalid repeat count.');
        const on = duration(el, 'OnDuration'), off = duration(el, 'OffDuration');
        const power = (single, low, high) => el.hasAttribute(low) || el.hasAttribute(high) ? { from: fraction(el, low), to: fraction(el, high) } : { from: fraction(el, single), to: null };
        const onPower = power('OnPower', 'PowerOnLow', 'PowerOnHigh'), offPower = power('OffPower', 'PowerOffLow', 'PowerOffHigh');
        count(repeats * 2, repeats * (on + off)); blocks.push({ kind: 'intervals', repeats, on, off, onPower, offPower }); break;
      }
      case 'SolidState':
        if (el.hasAttribute('Power') || el.hasAttribute('PowerLow')) {
          const length = duration(el, 'Duration');
          if (el.hasAttribute('PowerLow')) { const low = fraction(el, 'PowerLow'), high = fraction(el, 'PowerHigh'); count(1, length); blocks.push({ kind: 'ramp', name: 'Ramp', seconds: length, from: low, to: high }); }
          else { const power = fraction(el, 'Power'); count(1, length); blocks.push({ kind: 'steady', seconds: length, power }); }
        } else fail(FREE);
        break;
      case 'FreeRide': case 'MaxEffort': fail(FREE); break;
      default: break; // textevent, Cadence, pace and other metadata do not change the power plan
    }
  }
  if (!(Number.isFinite(ftp) && ftp > 0 && ftp <= 32767)) throw Error(NEEDS_FTP);
  const steps = [];
  const watts = f => { const value = Math.round(f * ftp); if (!(value >= 1 && value <= 32767)) throw Error('Power targets must be positive watts within the supported file range.'); return value; };
  const add = (stepName, length, from, to) => {
    if (steps.length >= MAX_STEPS) throw Error('Workout repeats are too deeply nested or too large.');
    const start = watts(from), end = to == null ? null : watts(to);
    steps.push({ name: stepName, seconds: length, watts: start, ...(end == null ? {} : { endWatts: end }) });
  };
  for (const block of blocks) {
    if (block.kind === 'steady') add('Steady', block.seconds, block.power, null);
    else if (block.kind === 'ramp') add(block.name, block.seconds, block.from, block.to);
    else for (let n = 0; n < block.repeats; n++) { add('On', block.on, block.onPower.from, block.onPower.to); add('Off', block.off, block.offPower.from, block.offPower.to); }
  }
  if (!steps.length) throw Error('The workout contains no steps.');
  const title = cut(name.trim(), 100);
  return validatePlan({ version: steps.some(s => s.endWatts != null) ? 2 : 1, kind: 'workout', name: title || 'Imported workout', ftpWatts: ftp, steps });
}

const escapeXML = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
/** Any workout plan as a Zwift .zwo file: a step with an end power becomes a Ramp, every other step a SteadyState. Powers are fractions of the
    plan's own FTP snapshot, else the rider's. Names of steps are not part of the format; repeats are not folded back into IntervalsT. */
export function exportZWO(plan, riderFTP = null) {
  const ftp = plan.ftpWatts ?? riderFTP;
  if (!(Number.isFinite(ftp) && ftp > 0)) throw Error(NEEDS_FTP);
  if (plan.kind !== 'workout' || plan.resistance != null) throw Error('Only timed power workouts can be exported as ZWO.');
  const fraction = w => (Math.round(w / ftp * 1000) / 1000).toFixed(3);
  const lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<workout_file>', '    <author>FTPunk</author>', `    <name>${escapeXML(plan.name)}</name>`, '    <description></description>', '    <sportType>bike</sportType>', '    <tags/>', '    <workout>'];
  for (const step of plan.steps) {
    const length = Math.max(1, Math.round(step.seconds));
    lines.push(step.endWatts != null ? `        <Ramp Duration="${length}" PowerLow="${fraction(step.watts)}" PowerHigh="${fraction(step.endWatts)}"/>` : `        <SteadyState Duration="${length}" Power="${fraction(step.watts)}"/>`);
  }
  lines.push('    </workout>', '</workout_file>', '');
  return lines.join('\n');
}
/** `FTPunk-<workout name>.zwo`, reduced to letters, digits and hyphens. */
export function zwoFileName(plan) {
  let title = '', last = '';
  for (const { segment } of new Intl.Segmenter().segment(plan.name)) { if (/^[A-Za-z0-9]$/.test(segment)) { title += segment; last = segment; } else if (last !== '-') { title += '-'; last = '-'; } }
  title = title.replace(/^-+|-+$/g, '');
  return `FTPunk-${title || 'Workout'}.zwo`;
}
