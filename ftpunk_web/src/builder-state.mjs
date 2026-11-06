import { issues, normalized, same } from './custom-workouts.mjs';
import { parseWorkoutText, printWorkoutText } from './workout-text.mjs';
// The workout builder's state, with its two editors (blocks and text) and the rules for switching between them. Port of
// Sources/FTPunkDomain/BuilderState.swift. In Blocks mode the blocks are the state; in Text mode the text is. Neither is converted lossily:
// switching from Blocks prints the blocks (always possible), and switching from Text parses it, staying in Text mode when it has errors.
// Pure data and rules, no DOM. The screen (ui/builder.mjs) keeps one of these and calls its methods.
export class BuilderState {
  constructor(workout, mode = 'blocks') {
    this.original = structuredClone(workout);
    this.mode = mode; this.name = workout.name; this.category = workout.category ?? null;
    this.blocks = structuredClone(workout.blocks); this.lastValidBlocks = structuredClone(workout.blocks);
    this.text = printWorkoutText(workout.blocks); this.parsed = parseWorkoutText(this.text);
    this.notice = null; // why a switch to Blocks mode did not happen
  }
  // ----- editing ---------------------------------------------------------------------------------------------------------------------
  setBlocks(value) { if (this.mode !== 'blocks') return; this.blocks = value; this.lastValidBlocks = value; this.notice = null; }
  setText(value) {
    if (this.mode !== 'text') return;
    this.text = value; this.parsed = parseWorkoutText(value); this.notice = null;
    if (this.parsed.isValid) this.lastValidBlocks = this.parsed.blocks;
  }
  // ----- switching -------------------------------------------------------------------------------------------------------------------
  /** Returns whether the mode changed. Text with errors keeps the rider in Text mode and says which line to fix. */
  switchTo(target) {
    if (target === this.mode) return true;
    if (target === 'text') { this.text = printWorkoutText(this.blocks); this.parsed = parseWorkoutText(this.text); this.mode = 'text'; this.notice = null; return true; }
    this.parsed = parseWorkoutText(this.text);
    if (!this.parsed.isValid) { const first = this.parsed.errors[0]; this.notice = first ? `Fix line ${first.line} first: ${first.message}` : null; return false; }
    this.blocks = this.parsed.blocks; this.lastValidBlocks = this.blocks; this.mode = 'blocks'; this.notice = null;
    return true;
  }
  // ----- reading ---------------------------------------------------------------------------------------------------------------------
  /** What the chart and the summary show: the blocks, or in Text mode the last text that parsed. */
  get shownBlocks() { return this.mode === 'blocks' ? this.blocks : (this.parsed.isValid ? this.parsed.blocks : this.lastValidBlocks); }
  /** The text has errors, so what the chart shows is out of date. */
  get chartIsStale() { return this.mode === 'text' && !this.parsed.isValid; }
  workout(riderID = null, date = new Date()) {
    return { id: this.original.id, riderID: riderID ?? this.original.riderID, name: normalized(this.name), ...(this.category ? { category: this.category } : {}), updatedAt: date.toISOString(), blocks: structuredClone(this.shownBlocks) };
  }
  /** Reasons Save is disabled, in the words shown under the editor. Empty means it can be saved. */
  get saveBlockers() {
    if (this.mode === 'text' && !this.parsed.isValid) return this.parsed.errors.map(e => `Line ${e.line}: ${e.message}`);
    return issues(this.workout());
  }
  get canSave() { return this.saveBlockers.length === 0; }
  /** Anything the rider changed since the editor opened (asks before closing). */
  get hasUnsavedChanges() {
    const now = this.workout(null, new Date(this.original.updatedAt));
    return now.name !== this.original.name || (now.category ?? null) !== (this.original.category ?? null) || !same(now.blocks, this.original.blocks) || (this.mode === 'text' && !this.parsed.isValid);
  }
}
