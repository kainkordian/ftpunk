import { validateCachedWorkout } from './workouts.mjs';
import { DB_SCHEMA, defaultRiderSettings } from './storage.mjs';
// An in-memory stand-in for LocalStore with the same calls the app makes. Preview scenarios (`?scenario=`) use it so they never touch
// the real database. Backups and restores are refused: a preview has nothing worth exporting.
export class MemoryStore {
  constructor() { this.tables = Object.fromEntries(Object.keys(DB_SCHEMA).map(name => [name, new Map()])); this.isPreview = true; }
  key(store, value) { return value[DB_SCHEMA[store].keyPath]; }
  async all(store) { return structuredClone([...this.tables[store].values()]); }
  async get(store, key) { return structuredClone(this.tables[store].get(key)); }
  async put(store, value) { this.tables[store].set(this.key(store, value), structuredClone(value)); }
  async delete(store, key) { this.tables[store].delete(key); }
  async saveSession(session) { await this.put('sessions', session); }
  async saveWorkouts(workouts) { for (const workout of workouts.map(validateCachedWorkout)) await this.put('workouts', workout); }
  async riderSettings(riderID) { return (await this.get('riderSettings', riderID)) ?? defaultRiderSettings(riderID); }
  async recover() {}
  async backup() { throw Error('Backups are not available in a preview scenario.'); }
  async restore() { throw Error('Imports are not available in a preview scenario.'); }
}
