// Cockpit layout and the coaching line, ported from CockpitLayout and CoachingText in Sources/FTPunkDomain/PresentationRules.swift. Pure.
import { Posture } from './state.mjs';

export const SIDE_BY_SIDE_MINIMUM_WIDTH = 900;
/**
 * What the cockpit shows at the current phase and width. `kind`: 'ftpTest' | 'workout' | 'freeRide'. `visual` is the placement ('off' | 'strip' | 'hero');
 * 'hero' falls back to 'strip' at accessibility text sizes, so the numbers stay first. `sideBySide`: the Large scene on the left and the readings in a right column
 * (wide windows). The blocks are 'scene', 'progress', 'tiles', 'controls' and 'notes'.
 */
export function cockpitLayout({ phase, accessibilitySize = false, rideVisual = 'off', containerWidth = 0, regularWidthClass = true, kind = 'ftpTest' }) {
  const visual = rideVisual === 'hero' && accessibilitySize ? 'strip' : rideVisual;
  const sideBySide = visual === 'hero' && regularWidthClass && containerWidth >= SIDE_BY_SIDE_MINIMUM_WIDTH;
  let leftColumn = [], rightColumn = [];
  if (sideBySide) {
    if (kind === 'ftpTest') [leftColumn, rightColumn] = [['scene', 'progress'], ['tiles', 'notes']];
    else if (kind === 'workout') [leftColumn, rightColumn] = [['scene', 'progress'], ['tiles', 'controls', 'notes']];
    else [leftColumn, rightColumn] = [['scene', 'controls'], ['tiles', 'notes']];
  }
  return { compactHeader: accessibilitySize, showsHeaderSubtitle: !accessibilitySize, showsTimelineLabels: !accessibilitySize, metricRows: accessibilitySize,
    // The coaching line is dropped mid-ramp (the bottom bar would clip it), at large text sizes and while the strip takes its place.
    showsCoachingLine: phase !== 'ramp' && !accessibilitySize && visual === 'off', visual, sideBySide, leftColumn, rightColumn, maximumContentWidth: visual === 'hero' ? 1400 : 760 };
}
/** The blocks of the single-column cockpit, top to bottom (the web's reading of the native cockpits' body). `heroTiles` is the big target and actual pair; the Large scene
 *  carries them in its readout instead. `visual`: 'off' | 'strip' | 'hero'. */
export function singleColumn({ kind, visual }) {
  const head = visual === 'hero' ? 'scene' : 'heroTiles', strip = visual === 'strip' ? ['strip'] : [];
  if (kind === 'ftpTest') return [head, ...strip, 'progress', 'tiles', 'notes'];
  if (kind === 'workout') return ['progress', head, ...strip, 'tiles', 'controls', 'notes'];
  return [head, ...strip, 'tiles', 'controls', 'notes'];
}
/** The remaining time shown beside the phase in the compact header, e.g. "8:20 left". */
export const compactClock = (clock, phase) => (phase === 'warmup' || phase === 'cooldown' ? `${clock} left` : clock);

/** The one line of coaching under the readings. Only the FTP test says "stay seated"; when Chaindance shows the rider out of the saddle the text agrees with it. */
export const COACHING = Object.freeze({ seated: 'Stay seated. Keep a steady, comfortable cadence.', steady: 'Keep a steady, comfortable cadence.', sprint: 'Sprint — out of the saddle is fine.', cooldown: 'Ramp scored. Spin gently to cool down.' });
export const coachingText = (state, phase) => (state.mode === 'ftpTest' ? (phase === 'cooldown' ? COACHING.cooldown : COACHING.seated) : state.posture === Posture.standing ? COACHING.sprint : COACHING.steady);
