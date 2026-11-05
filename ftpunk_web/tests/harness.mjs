// Tiny test harness shared by every suite. Suites register tests at import time; tests/index.html runs them.
const tests = [];
export const test = (name, body) => tests.push({ name, body });
export function assert(value, message = 'Assertion failed') { if (!value) throw Error(message); }
// Deep equality by canonical JSON: object keys are compared in sorted order, so key order never matters.
const canonical = (value, seen = new Set()) => JSON.stringify(value, (key, v) => v instanceof Set ? { set: [...v] } : v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a < b ? -1 : 1)) : v);
export function equal(a, b) { assert(canonical(a) === canonical(b), `Expected ${canonical(b)}, got ${canonical(a)}`); }
export function near(a, b, tolerance = 1e-5) { assert(Math.abs(a - b) <= tolerance, `${a} differs from ${b}`); }
export function throws(body) { let threw = false; try { body(); } catch { threw = true; } assert(threw, 'Expected rejection'); }
export async function rejects(body) { let threw = false; try { await body(); } catch { threw = true; } assert(threw, 'Expected async rejection'); }
export const fixtureText = async name => (await fetch(new URL(`./fixtures/${name}.json`, import.meta.url))).text();
export const fixture = async name => JSON.parse(await fixtureText(name));
export async function runSuite(report = () => {}) {
  const results = [];
  for (const { name, body } of tests) { try { await body(); results.push({ name, ok: true }); } catch (error) { results.push({ name, ok: false, error: error.stack ?? error.message }); } report(results.at(-1)); }
  return { passed: results.filter(r => r.ok).length, failed: results.filter(r => !r.ok).length, results };
}
