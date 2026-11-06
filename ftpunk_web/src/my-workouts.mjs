import { uuid } from './domain.mjs';
import { definition, categoryTitle } from './catalog.mjs';
import { importWorkoutText, MAX_WORKOUT_BYTES } from './workouts.mjs';
import { tryPlan, totalSeconds, fromDefinition, fromPlan, copyName, newWorkout } from './custom-workouts.mjs';
import { BuilderState } from './builder-state.mjs';
import { exportZWO, zwoFileName } from './zwo.mjs';
import { download } from './export.mjs';
// The model side of "My workouts" (native AppModel+Builder.swift and the custom case of workoutDetail): the riders' own workouts, their detail for the
// library and pre-flight (`custom:<id>`), saving, deleting, duplicating, ZWO import and export, and the open builder. No DOM. Installed once on the
// app model by app.mjs, so the shared model class stays as it is: it adds `reload` (which also loads the custom workouts), the `custom` workout
// resolver, and replaces `importWorkoutFile` with one that also reads Zwift files.

export function installCustomWorkouts(model) {
  model.customWorkouts = []; // every rider's own workouts, newest first
  model.builder = null;      // the open builder: { state: BuilderState, isNew }
  Object.defineProperty(model, 'myCustomWorkouts', { get: () => model.customWorkouts.filter(w => w.riderID === model.profile?.id), configurable: true });
  const reload = model.reload.bind(model);
  model.reload = async () => { await reload(); model.customWorkouts = await model.store.customWorkouts(); };

  /** The same shape as the other workout details: { ref, title, category, categoryTitle, source, duration, plan, previewPlan, needsFTP, custom }. */
  model.customDetail = id => {
    const workout = model.customWorkouts.find(w => w.id === id); if (!workout) return null;
    const ftp = model.ftp, plan = tryPlan(workout, ftp);
    // Without an FTP the preview is drawn at a reference level with no FTP, so bars are neutral and no watts are shown.
    const reference = plan ?? tryPlan(workout, 100), previewPlan = reference && !plan ? { ...reference, ftpWatts: null } : reference;
    if (!previewPlan) return null;
    return { ref: `custom:${id}`, title: workout.name, category: workout.category ?? null, categoryTitle: workout.category ? categoryTitle(workout.category) : null, source: 'My workout', duration: totalSeconds(workout), plan, previewPlan, needsFTP: plan == null, custom: workout };
  };
  model.workoutResolvers.set('custom', id => model.customDetail(id));

  model.saveCustomWorkout = async workout => { const saved = await model.store.saveCustomWorkout(workout); await model.reload(); model.invalidate(); return saved; };
  model.deleteCustomWorkout = async id => { if (model.busy) return; await model.store.deleteCustomWorkout(id); await model.reload(); model.invalidate(); };

  /** A copy of a library workout, as editable blocks for the selected rider: built-in workouts as % FTP, imported ones as watts, own workouts as they are. Null when it cannot be copied. */
  model.duplicateWorkout = ref => {
    const separator = String(ref).indexOf(':'), kind = String(ref).slice(0, separator), id = String(ref).slice(separator + 1), riderID = model.profile.id;
    if (kind === 'classic') { const def = definition(id); return def ? fromDefinition(def, riderID, { name: copyName(def.name) }) : null; }
    if (kind === 'cached') { const record = model.workouts.find(w => w.id === id); return record ? fromPlan(record.plan, riderID, { name: copyName(record.plan.name) }) : null; }
    if (kind === 'custom') { const own = model.customWorkouts.find(w => w.id === id); return own ? { ...structuredClone(own), id: uuid(), riderID, name: copyName(own.name), updatedAt: new Date().toISOString() } : null; }
    return null;
  };

  // ----- the builder -----------------------------------------------------------------------------------------------------------------
  const lastMode = () => model.prefs.builderMode === 'text' ? 'text' : 'blocks';
  /** Opens the builder on a workout. `mode` null uses the editor the rider used last. Returns the route to show. */
  model.openBuilder = (workout, { isNew = false, mode = null } = {}) => { model.builder = { state: new BuilderState(workout, mode ?? lastMode()), isNew }; return '#/builder/draft'; };
  /** A blank workout, or one made from pasted text (opens in the text editor). */
  model.newWorkout = (text = null) => {
    const state = new BuilderState(newWorkout(model.profile.id));
    if (text != null) { state.switchTo('text'); state.setText(text); model.builder = { state, isNew: true }; return '#/builder/draft'; }
    return model.openBuilder(newWorkout(model.profile.id), { isNew: true });
  };
  model.editWorkout = id => { const workout = model.customWorkouts.find(w => w.id === id); return workout ? model.openBuilder(workout, { mode: 'blocks' }) : null; };
  model.duplicateAndEdit = ref => { const copy = model.duplicateWorkout(ref); return copy ? model.openBuilder(copy, { isNew: true, mode: 'blocks' }) : null; };
  model.closeBuilder = () => { model.builder = null; };

  // ----- files -----------------------------------------------------------------------------------------------------------------------
  /** Library import: a Zwift .zwo (needs the rider's FTP), FTPunk JSON or an Intervals.icu workout event. */
  model.importWorkoutFile = async file => {
    if (model.busy) return;
    const riderID = model.profile.id;
    if (file.size > MAX_WORKOUT_BYTES) throw Error('Workout files must be under 2 MB.');
    const { plan, source } = importWorkoutText(await file.text(), model.ftp);
    if (model.busy || model.profile.id !== riderID) throw Error('The rider or ride changed. Import again.');
    await model.store.saveWorkouts([{ id: uuid(), riderID, source, savedAt: new Date().toISOString(), plan }]);
    model.importReport = `Saved ${plan.name} for offline riding.`; await model.reload(); model.invalidate();
  };
  /** Downloads a resolved plan as a Zwift file (powers are fractions of the plan's FTP, or the rider's). The file stays on this device. */
  model.exportWorkoutZWO = plan => download(exportZWO(plan, model.ftp), zwoFileName(plan), 'application/xml');
}
