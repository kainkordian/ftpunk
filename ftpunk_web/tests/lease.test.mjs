import { test, assert, equal } from './harness.mjs';
import { acquireRideLease } from '../src/storage.mjs';
import { AppModel } from '../src/app-model.mjs';
import { MemoryStore } from '../src/memory-store.mjs';
import { loadPreferences } from '../src/storage.mjs';

// Headless Chrome on a fresh profile was seen never answering a Web Locks request (2026-11-06): the app hung on "Loading…".

test('A trainer-control reservation that never answers times out instead of hanging', async () => {
  let callback = null;
  const silent = { request: (name, options, cb) => { callback = cb; return new Promise(() => {}); } };
  const started = performance.now();
  let message = null;
  try { await acquireRideLease(silent, { timeoutMs: 50 }); } catch (error) { message = error.message; }
  assert(message && /did not answer/.test(message), `expected a timeout, got ${message}`);
  assert(performance.now() - started < 1000, 'the timeout fires promptly');
  // A lock that arrives after the timeout is let go at once (the callback returns without holding it).
  equal(callback({ name: 'ftpunk-web-ride' }), undefined);
});

test('An unavailable lock is still reported as another tab running a test', async () => {
  const busy = { request: (name, options, cb) => Promise.resolve(cb(null)) };
  let message = null;
  try { await acquireRideLease(busy, { timeoutMs: 1000 }); } catch (error) { message = error.message; }
  assert(/Another FTPunk tab/.test(message ?? ''), `got ${message}`);
});

test('The app model uses the lease it was given, so previews never touch Web Locks', async () => {
  let calls = 0;
  const model = new AppModel({ store: new MemoryStore(), preview: true, prefs: loadPreferences({ getItem: () => null }), lease: async () => { calls++; return () => {}; } });
  await model.boot();
  assert(calls >= 1, 'boot reserved through the injected lease');
});
