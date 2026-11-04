import { runSuite } from './suite.mjs';
const result = await runSuite(r => console.log(`${r.ok ? 'PASS' : 'FAIL'} ${r.name}${r.ok ? '' : `\n${r.error}`}`));
console.log(`\n${result.passed} passed; ${result.failed} failed.`);
if (result.failed) throw Error(`${result.failed} tests failed.`);
