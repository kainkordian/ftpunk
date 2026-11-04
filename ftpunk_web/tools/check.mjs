import { readdir, readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';
const root = fileURLToPath(new URL('../', import.meta.url));
const sourceFiles = [];
async function visit(directory) { for (const name of await readdir(directory)) { const path = join(directory, name); if ((await stat(path)).isDirectory()) await visit(path); else if (/\.(mjs|js)$/.test(name)) sourceFiles.push(path); } }
await visit(join(root, 'src')); sourceFiles.push(join(root, 'sw.js'));
for (const file of sourceFiles) {
  execFileSync(process.execPath, ['--check', file]);
  const text = await readFile(file, 'utf8');
  for (const [, target] of text.matchAll(/from\s+['"]([^'"]+)['"]/g)) {
    if (!target.startsWith('.')) throw Error(`Runtime dependency is not self-contained: ${target}`);
    const path = resolve(dirname(file), target);
    if (!path.startsWith(root)) throw Error(`Runtime import escapes ftpunk_web: ${target}`);
    await stat(path);
  }
}
const worker = await readFile(join(root, 'sw.js'), 'utf8');
for (const file of sourceFiles.filter(f => f.endsWith('.mjs'))) {
  if (!worker.includes(`'./${file.slice(root.length)}'`)) throw Error(`Runtime module missing from offline cache: ${file}`);
}
const html = await readFile(join(root, 'index.html'), 'utf8');
for (const [, target] of html.matchAll(/(?:src|href)="([^"#]+)"/g)) await stat(join(root, target));
const manifest = JSON.parse(await readFile(join(root, 'manifest.webmanifest'), 'utf8'));
for (const icon of manifest.icons) await stat(join(root, icon.src));
console.log(`Validated ${sourceFiles.length} runtime scripts, local imports, HTML assets, and manifest icons.`);
